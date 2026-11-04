function [actorNet, criticNet, learning_curve, entropy_curve] = ...
            DeepGRU_Shared_v11(simTime, num_episodes, seed, env)
% DeepGRU_Shared_v11  P4 (IMPLEMENTATION_PLAN_v11.md): a GRU(64) recurrent
% policy replacing the L_seq=3 frame-stacking memory used by
% DeepA2C_Shared_v11/DeepPPO_Shared_v11, trained with 16-step truncated
% BPTT. Scope cut agreed before implementation (see README_v11.md P4):
% offset action space (not P1's target-BLER action) and a single-pass A2C
% update per 16-TTI chunk (not P2's PPO), because both of those features
% assume the per-TTI/per-scheduled-transition sample independence that a
% recurrent policy's sequential chunks break. P4 here isolates the thing
% it actually tests: does persistent recurrent memory (vs. a 3-frame
% window) help on the stale-CQI / cell-cue cases.
%
% Hidden state is carried per user across the WHOLE episode during
% rollout (plain numeric GRU step, hand-coded from the network's own
% extracted weights -- verified gate order reset/update/new against
% dlnetwork's own forward() -- for speed: a dlarray forward() per TTI was
% ~30ms/call, far too slow at N=10 x T=200 x many episodes). Training
% replays each 16-TTI chunk through the real dlnetwork (GRU + FC) via
% dlfeval, starting from the chunk's own (detached) initial hidden state,
% so gradients flow through exactly that chunk -- standard truncated BPTT.
    if ~isempty(seed), rng(seed); end
    N = env.N;
    A = env.actions;
    nA = numel(A);
    maxC = env.max_CQI; minC = env.min_CQI;
    noop = find(A == 0);

    gamma = env.gamma;
    hp = struct(); if isfield(env, 'gru') && isstruct(env.gru), hp = env.gru; end
    chunkLen  = hpget(hp, 'chunk_len', 16);
    nH        = hpget(hp, 'hidden', 64);
    lr_actor  = hpget(hp, 'lr_actor', 3e-4);
    lr_critic = hpget(hp, 'lr_critic', 1e-3);
    ent_start = hpget(hp, 'ent_start', 0.05);
    ent_end   = hpget(hp, 'ent_end', 0.01);
    clip_norm = 5.0;
    rk = 'goodput'; if isfield(env, 'reward_kind'), rk = lower(env.reward_kind); end
    Pq = 1; if isfield(env, 'cqi_period'), Pq = max(1, round(env.cqi_period)); end

    nSched = numel(env.sched_list);
    if upper(env.state_tier) == 'A', nBase = 5;
    elseif upper(env.state_tier) == 'O', nBase = 10;
    else, nBase = 13;
    end
    nSingle = nBase + nSched + nExtra_v11(env);  % no L_seq stacking -- GRU is the memory

    actorLayers = [
        sequenceInputLayer(nSingle, 'Name', 'in')
        gruLayer(nH, 'OutputMode', 'sequence', 'Name', 'gru')
        fullyConnectedLayer(nA, 'Name', 'fc')];
    criticLayers = [
        sequenceInputLayer(nSingle, 'Name', 'in')
        gruLayer(nH, 'OutputMode', 'sequence', 'Name', 'gru')
        fullyConnectedLayer(1, 'Name', 'fc')];
    actorNet  = dlnetwork(actorLayers);
    criticNet = dlnetwork(criticLayers);
    toDl = @(x) dlarray(single(x));

    Wa = extract_weights_gru(actorNet);
    Wc = extract_weights_gru(criticNet);

    aAvg = []; aAvgSq = []; aIt = 0;
    cAvg = []; cAvgSq = []; cIt = 0;
    learning_curve = zeros(num_episodes, 1);
    entropy_curve  = zeros(num_episodes, 1);

    for ep = 1:num_episodes
        entW = ent_start + (ent_end - ent_start) * (ep - 1) / max(num_episodes - 1, 1);

        sched = sampleSched_v5(env);
        [~, sOneHot] = schedContext_v5(sched, env);
        ctx = single(repmat(sOneHot, 1, N));

        W = 0; if isfield(env, 'train_warm_ttis'), W = env.train_warm_ttis; end
        Ttot = W + simTime;
        [Strue, ~, meta] = generateChannel_v11(Ttot, env);
        obsS = cqiFeedback_v11(Strue, env, meta.delays);

        burstObsM = zeros(Ttot, N);
        for i = 1:N
            idx = max((1:Ttot).' - meta.delays(i), 1);
            burstObsM(:, i) = double(meta.burst(idx));
        end

        ageM = cqiAge_v11(Ttot, N, Pq);
        emaO = obsS(1, :); cn = 0;
        Q = trafficInit_v11(env, N, 0);
        off = zeros(1, N);
        H = harqInit_v11(N);
        nk = zeros(1, N);
        prevRef = baseCQI_v11(obsS(1,:) + off, env);
        R_emas = zeros(1, N);
        ema = 0.05;
        ep_tp = 0; ep_ent = 0;
        ack8 = zeros(1, N); tsince = zeros(1, N); offEma = zeros(1, N);

        h_a = zeros(nH, N, 'single'); h_c = zeros(nH, N, 'single');  % rollout hidden state, carried all episode

        xChunk = zeros(nSingle, N, chunkLen, 'single');
        aChunk = zeros(N, chunkLen);
        rChunk = zeros(N, chunkLen, 'single');
        mChunk = zeros(N, chunkLen, 'single');
        h_a0 = h_a; h_c0 = h_c;   % hidden state at the START of the current chunk
        L = 0;                     % TTIs accumulated in the current chunk

        for t = 1:Ttot
            learn = t > W;
            [Q, H, missEv] = trafficPre_v11(Q, t, env, H); %#ok<ASGLU> (no 'ontime' reward in P4's offset-mode scope)
            X = struct('age', ageM(t, :), 'dev', obsS(t, :) - emaO, 'cn', cn, 'Q', Q, 't', t, ...
                       'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma);
            ref  = baseCQI_v11(obsS(t,:) + off, env);
            x_now = single(stateFeat_gru_v11(env.state_tier, ref, obsS(t,:), off, nk, H, ...
                meta.speeds(t,:), burstObsM(t,:), meta.delays, R_emas, ctx, featExtra_v11(env, X)));

            % Rollout flush: every chunkLen TTIs, replay the chunk through
            % the real dlnetwork (truncated BPTT) and update the weights.
            if learn && L >= chunkLen
                [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = gru_chunk_update_v11( ...
                    actorNet, criticNet, Wc, nH, x_now, h_a0, h_c0, h_c, xChunk, aChunk, rChunk, mChunk, L, ...
                    gamma, entW, clip_norm, lr_actor, lr_critic, toDl, ...
                    aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt);
                Wa = extract_weights_gru(actorNet);
                Wc = extract_weights_gru(criticNet);
                h_a0 = h_a; h_c0 = h_c;
                L = 0;
            end

            [logits, P, h_a] = gru_step(Wa, x_now, h_a, nH);
            if learn, ep_ent = ep_ent + mean(-sum(P .* log(P + 1e-12), 1)); end
            [~, h_c] = gru_step_value(Wc, x_now, h_c, nH);

            isRetx = env.harq_on & H.pend;
            if learn
                U_act = rand(1, N);
                Pcum = cumsum(P, 1);
                cmp = U_act <= Pcum;
                [tfHit, aIdx] = max(cmp, [], 1);
                aIdx(~tfHit) = nA;
            else
                aIdx = noop * ones(1, N);
            end
            sent = max(minC, min(maxC, ref + A(aIdx)));

            rbFull = env.total_RB * ones(1, N);
            if isfield(env, 'sched_on_ref') && env.sched_on_ref
                potNew = tbsFromMCSandRB_v11(max(env.min_CQI, min(env.max_CQI, ref)) - 1, rbFull) * 1e-3;
            else
                potNew = tbsFromMCSandRB_v11(sent - 1, rbFull) * 1e-3;
            end
            pot = potNew;
            if any(isRetx)
                potRetx = tbsFromMCSandRB_v11(H.mcs, rbFull) * 1e-3;
                pot(isRetx) = potRetx(isRetx);
            end

            pot(~Q.has) = 0;
            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            rb(~Q.has) = 0;
            [tp_now, off, H, ~, nEv, dropEv] = txStep_v11(sent, Strue(t,:), rb, off, H, env);
            Q = trafficPost_v11(Q, tp_now, t);
            if any(rb > 0), cn = 0.6 * cn + 0.4 * mean(double(nEv(rb > 0))); else, cn = 0.97 * cn; end
            emaO = 0.98 * emaO + 0.02 * obsS(t, :);

            schedM = rb > 0;
            nk(schedM)  = 0.7 * nk(schedM) + 0.3 * double(nEv(schedM));
            nk(~schedM) = 0.95 * nk(~schedM);
            R_emas = (1 - ema) * R_emas + ema * tp_now;
            ack8(schedM) = 0.8 * ack8(schedM) + 0.2 * double(~nEv(schedM));
            tsince(schedM) = 0; tsince(~schedM) = tsince(~schedM) + 1;
            offEma = 0.9 * offEma + 0.1 * off;
            if learn, ep_tp = ep_tp + sum(tp_now); end

            if learn
                L = L + 1;
                xChunk(:, :, L) = x_now;
                aChunk(:, L) = aIdx(:);
                rI = zeros(1, N);
                sel = schedM;
                if any(sel)
                    % BUG FIX (22 Oct 2026): this branch was hardcoded to
                    % the plain goodput formula regardless of rk, so
                    % env.reward_kind = 'oppcost' silently had no effect on
                    % GRU training (R3_cellcue_opp's GRU result was
                    % bit-identical to R3_cellcue's before this fix).
                    if strcmpi(rk, 'oppcost')
                        % v10b's fix for the offset-mode goodput-reward
                        % defect: every scheduled slot is charged the
                        % goodput the OLLA reference decision is expected
                        % to deliver on it (see DeepA2C_Shared_v11).
                        tref = tbsFromMCSandRB_v11(max(minC, min(maxC, ref(sel))) - 1, rb(sel)) * 1e-3 * (1 - env.olla_target);
                        rI(sel) = (tp_now(sel) - tref) / env.reward_scale;
                    else
                        rI(sel) = (tp_now(sel) / env.reward_scale) ...
                                  - env.lambda_drop * double(dropEv(sel)) ...
                                  - env.lambda_retx * double(nEv(sel));
                    end
                end
                rChunk(:, L) = rI(:);
                mChunk(:, L) = double(schedM(:) & ~isRetx(:));
            end
            prevRef = ref;
        end

        if L > 0
            [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = gru_chunk_update_v11( ...
                actorNet, criticNet, Wc, nH, x_now, h_a0, h_c0, h_c, xChunk, aChunk, rChunk, mChunk, L, ...
                gamma, entW, clip_norm, lr_actor, lr_critic, toDl, ...
                aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt);
            Wa = extract_weights_gru(actorNet); %#ok<NASGU>
            Wc = extract_weights_gru(criticNet); %#ok<NASGU>
        end

        learning_curve(ep) = ep_tp / simTime;
        entropy_curve(ep)  = ep_ent / simTime;

        if mod(ep, 25) == 0 || ep == num_episodes
            fprintf('  Deep GRU v11 ep %3d/%d | CellTp = %5.2f Mbps | Policy Entropy = %5.3f | entW = %.3f\n', ...
                    ep, num_episodes, learning_curve(ep), entropy_curve(ep), entW);
        end
    end
end

function S = stateFeat_gru_v11(tier, ref, obs, off, nk, H, spd, burstObs, delays, r_ema, ctx, xtra)
% Single-frame state (no dS/slope4/dRef temporal deltas -- the GRU's own
% hidden state is the memory; stateFeat_v11 needs those for L_seq=1 too,
% so pass zeros for the now-redundant finite-difference inputs).
    N = numel(ref);
    S = stateFeat_v11(tier, ref, zeros(1, N), obs, zeros(1, N), off, zeros(1, N), nk, H, spd, burstObs, delays, r_ema, ctx, xtra);
end

function [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = gru_chunk_update_v11( ...
        actorNet, criticNet, Wc, nH, x_boot, h_a0, h_c0, h_c_end, xChunk, aChunk, rChunk, mChunk, L, ...
        gamma, entW, clip_norm, lr_actor, lr_critic, toDl, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt)
% gru_chunk_update_v11  Truncated-BPTT A2C update over one L-TTI chunk.
% Returns (Monte-Carlo within the chunk, bootstrapped once from the
% post-chunk state) computed from plain numeric rewards/hand-coded
% critic step -- independent of the differentiable forward below, which
% only needs to reproduce V at each step for the advantage baseline and
% value-regression target.
    N = size(xChunk, 2);
    [Vboot, ~] = gru_step_value(Wc, x_boot, h_c_end, nH);  % 1 x N, detached bootstrap
    G = zeros(N, L, 'single');
    Gnext = Vboot(:);
    for l = L:-1:1
        Gnext = rChunk(:, l) + gamma * Gnext;
        G(:, l) = Gnext;
    end

    X = dlarray(single(xChunk(:, :, 1:L)), 'CBT');
    [aG, cG] = dlfeval(@gru_grads_v11, actorNet, criticNet, X, ...
        toDl(h_a0), toDl(h_c0), aChunk(:, 1:L), G, toDl(mChunk(:, 1:L)), entW);
    aG = clipGlobal_gru(aG, clip_norm);
    cG = clipGlobal_gru(cG, clip_norm);
    aIt = aIt + 1;
    [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
    cIt = cIt + 1;
    [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);
end

function [aGrad, cGrad] = gru_grads_v11(actorNet, criticNet, X, h_a0, h_c0, Aacts, G, mask, entW)
    actorNet.State.Value{1} = h_a0;
    criticNet.State.Value{1} = h_c0;
    logits = forward(actorNet, X);   % nA x N x L
    V = forward(criticNet, X);        % 1 x N x L

    [nAact, N, L] = size(logits);
    m = max(logits, [], 1);
    logZ = m + log(sum(exp(logits - m), 1));
    logp_all = logits - logZ;        % nA x N x L
    idxLin = sub2ind([nAact, N, L], Aacts(:)', repmat(1:N, 1, L), repelem(1:L, N));
    logp = reshape(logp_all(idxLin), N, L);

    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);          % 1 x N x L
    entropy = reshape(entropy, N, L);

    Vsq = reshape(V, N, L);
    adv = G - Vsq;
    advD = double(gather(extractdata(adv)));
    mD = double(gather(extractdata(mask))) > 0;
    advN = zeros(size(advD));
    if any(mD(:))
        a = advD(mD); sd = std(a);
        if sd > 1e-6, advN(mD) = (a - mean(a)) / sd; else, advN(mD) = a - mean(a); end
    end
    advN = dlarray(cast(advN, 'like', extractdata(logp)));
    nP = max(sum(mD(:)), 1);

    aLoss = -sum(sum(logp .* advN .* mask)) / nP - entW * mean(entropy, 'all');
    cLoss = mean((Vsq - G).^2, 'all');

    cGrad = dlgradient(cLoss, criticNet.Learnables, 'RetainData', true);
    aGrad = dlgradient(aLoss, actorNet.Learnables);
end

function grads = clipGlobal_gru(grads, clipNorm)
    totalSq = 0;
    for k = 1:height(grads)
        v = grads.Value{k};
        if ~isempty(v), totalSq = totalSq + sum(extractdata(v(:)).^2); end
    end
    normG = sqrt(totalSq);
    if normG > clipNorm
        scale = clipNorm / (normG + 1e-12);
        for k = 1:height(grads)
            if ~isempty(grads.Value{k})
                grads.Value{k} = grads.Value{k} * scale;
            end
        end
    end
end

function W = extract_weights_gru(net)
    L = net.Learnables;
    W.Wi = extractdata(L.Value{L.Layer == "gru" & L.Parameter == "InputWeights"});
    W.Wh = extractdata(L.Value{L.Layer == "gru" & L.Parameter == "RecurrentWeights"});
    W.b  = extractdata(L.Value{L.Layer == "gru" & L.Parameter == "Bias"});
    W.Wfc = extractdata(L.Value{L.Layer == "fc" & L.Parameter == "Weights"});
    W.bfc = extractdata(L.Value{L.Layer == "fc" & L.Parameter == "Bias"});
end

function [logits, P, hNew] = gru_step(W, x, h0, nH)
% Hand-coded GRU + FC step (gate order verified: reset, update, new --
% matches MATLAB's gruLayer/dlnetwork forward() exactly). Vectorised over
% the batch (N users) via plain double/single matrix ops -- this is the
% ROLLOUT path, called every TTI, so it must stay off the dlarray/
% autodiff machinery (see file header: ~30ms/call there vs. this).
    idx = @(k) (k-1)*nH+1 : k*nH;
    r = sigmoid_gru(W.Wi(idx(1),:)*x + W.Wh(idx(1),:)*h0 + W.b(idx(1)));
    z = sigmoid_gru(W.Wi(idx(2),:)*x + W.Wh(idx(2),:)*h0 + W.b(idx(2)));
    n = tanh(W.Wi(idx(3),:)*x + r .* (W.Wh(idx(3),:)*h0) + W.b(idx(3)));
    hNew = (1 - z) .* n + z .* h0;
    logits = double(W.Wfc * hNew + W.bfc);
    logits = logits - max(logits, [], 1);
    P = exp(logits) ./ sum(exp(logits), 1);
end

function [V, hNew] = gru_step_value(W, x, h0, nH)
    idx = @(k) (k-1)*nH+1 : k*nH;
    r = sigmoid_gru(W.Wi(idx(1),:)*x + W.Wh(idx(1),:)*h0 + W.b(idx(1)));
    z = sigmoid_gru(W.Wi(idx(2),:)*x + W.Wh(idx(2),:)*h0 + W.b(idx(2)));
    n = tanh(W.Wi(idx(3),:)*x + r .* (W.Wh(idx(3),:)*h0) + W.b(idx(3)));
    hNew = (1 - z) .* n + z .* h0;
    V = double(W.Wfc * hNew + W.bfc);
end

function y = sigmoid_gru(x)
    y = 1 ./ (1 + exp(-x));
end

function v = hpget(hp, f, d)
    if isfield(hp, f) && ~isempty(hp.(f)), v = hp.(f); else, v = d; end
end
