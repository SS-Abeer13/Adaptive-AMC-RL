function [actorNet, criticNet, learning_curve, entropy_curve] = ...
            DeepA2C_BC_v8(simTime, num_episodes, seed, env, bc_eps)
% DeepA2C_BC_v8  DIAGNOSTIC ONLY (fill run, 2026-10-03). Identical to
% DeepA2C_Shared_v8 except for an optional behaviour-cloning (BC) phase of
% bc_eps episodes on the FixedPU oracle's per-class actions before RL:
%   - BC episodes act with the teacher action, train the actor by
%     cross-entropy (+ soft entropy 0.03) and the critic on observed returns;
%   - after BC the entropy anneal starts at 0.01 instead of ent_start.
% Used only to ask whether RL fine-tuning improves on an oracle-initialised
% policy. Never used for headline results.
    if nargin < 5 || isempty(bc_eps), bc_eps = 0; end
% DeepA2C_Shared_v8  Shared-network n-step A2C with scheduled credit assignment
% and temporal sequence memory (v8 autonomous link adaptation).
%
% Key architectural upgrades over v7:
%   1. STRICTLY AUTONOMOUS: Zero Behavior Cloning (bc_warm_eps = 0).
%   2. PER-USER SCHEDULED CREDIT ASSIGNMENT: Unscheduled users do not pollute
%      the gradient buffer with noise; only scheduled transmissions train the policy.
%   3. TEMPORAL MEMORY: Autoregressive state stacking (depth L=3) to resolve
%      delayed POMDP partial observability and track Markov interference bursts.
%   4. EXPANDED ACTION SPACE: -6 to +4 (11 actions) for rapid burst adaptation.
%   5. MATHEMATICALLY SPECIFIED REWARD: Throughput reward with packet drop penalties.
    if ~isempty(seed), rng(seed); end
    N = env.N;
    A = env.actions;
    nA = numel(A);
    maxC = env.max_CQI; minC = env.min_CQI;
    maxD = env.max_delta; minD = env.min_delta;

    gamma = env.gamma;
    n_step = 10;
    lr_actor = 5e-4;
    lr_critic = 1e-3;
    ent_start = 0.08;   % Exploratory start for autonomous learning
    ent_end = 0.005;    % Annealed floor
    clip_norm = 5.0;
    L_seq = 3;          % Temporal sequence stacking depth

    nSched = numel(env.sched_list);
    if upper(env.state_tier) == 'A'
        nBase = 5;
    elseif upper(env.state_tier) == 'O'
        nBase = 10;   % observable Tier-B (no true speed / burst / delay)
    else
        nBase = 13;
    end
    nSingle = nBase + nSched;
    nFeat = nSingle * L_seq; % Multi-frame temporal state dimension

    % Deep Actor and Critic Networks (DLNetwork with ReLU activations)
    actorLayers = [
        featureInputLayer(nFeat, 'Name', 'in')
        fullyConnectedLayer(128, 'Name', 'fc1'); reluLayer('Name', 'r1')
        fullyConnectedLayer(96,  'Name', 'fc2'); reluLayer('Name', 'r2')
        fullyConnectedLayer(nA,  'Name', 'logits')];

    criticLayers = [
        featureInputLayer(nFeat, 'Name', 'in')
        fullyConnectedLayer(128, 'Name', 'fc1'); reluLayer('Name', 'r1')
        fullyConnectedLayer(96,  'Name', 'fc2'); reluLayer('Name', 'r2')
        fullyConnectedLayer(1,   'Name', 'value')];

    actorNet  = dlnetwork(actorLayers);
    criticNet = dlnetwork(criticLayers);
    toDl = @(x) dlarray(single(x), 'CB');

    Wa = extract_weights(actorNet);
    Wc = extract_weights(criticNet);

    aAvg = []; aAvgSq = []; aIt = 0;
    cAvg = []; cAvgSq = []; cIt = 0;
    nTot = bc_eps + num_episodes;
    learning_curve = zeros(nTot, 1);
    entropy_curve  = zeros(nTot, 1);
    entW_bc = 0.03;

    % Experience buffer for scheduled transitions.
    % AUDIT FIX (2026-09-29) -- returns / bootstrapping:
    %   The previous update used rets = r + gamma * V(S_t(:, user)) for EVERY
    %   buffered transition, where S_t was the state of the *current* TTI at
    %   flush time. So (i) a transition from TTI 1 was bootstrapped from the
    %   user's state ~200 TTIs later, (ii) the newest transition was
    %   bootstrapped from its own pre-action state, and (iii) no n-step return
    %   was ever formed (n_step only sized the buffer). Under PF/RR the buffer
    %   filled once per 200-TTI episode, so almost every target was wrong.
    % Now: each user's scheduled transitions form that user's decision
    % sequence (semi-MDP over scheduled TTIs, gamma applied per scheduled
    % decision). Returns are computed backwards per user,
    %   G_j = r_j + gamma * G_{next scheduled j of same user},
    % and the last one bootstraps from V(s_i) of the state observed AFTER
    % that transition (the next TTI's state, or a post-episode state).
    %
    % AUDIT FIX -- HARQ retransmission credit: on a retransmission TTI the
    % sampled action is ignored (the retx reuses the stored MCS), so those
    % transitions are kept in the return chain / critic target but masked
    % out of the policy-gradient term (bufP = 0).
    flushAt = n_step * N * 2;
    cap = flushAt + N;
    bufS = zeros(nFeat, cap, 'single');
    bufA = zeros(1, cap);
    bufR = zeros(1, cap, 'single');
    bufU = zeros(1, cap); % User ID tracking for individual returns
    bufP = zeros(1, cap, 'single'); % 1 = action affected the transmission
    nb = 0;

    for ep = 1:nTot
        isBC = ep <= bc_eps;
        epR  = ep - bc_eps;
        if isBC
            entW = entW_bc;
            updFn = @bc_update_v8;
        else
            if bc_eps > 0, es = 0.01; else, es = ent_start; end
            entW = es + (ent_end - es) * (epR - 1) / max(num_episodes - 1, 1);
            updFn = @a2c_update_v8;
        end

        sched = sampleSched_v5(env);
        [~, sOneHot] = schedContext_v5(sched, env);
        ctx = single(repmat(sOneHot, 1, N));

        [Strue, ~, meta] = generateChannel_v7(simTime, env);
        obsS = cqiFeedback_v8(Strue, env, meta.delays);

        burstObsM = zeros(simTime, N);
        for i = 1:N
            idx = max((1:simTime).' - meta.delays(i), 1);
            burstObsM(:, i) = double(meta.burst(idx));
        end

        aTgt = zeros(1, N);
        for i = 1:N
            [dc, vc] = userClass_v8(meta.delays(i), mean(meta.speeds(:, i)));
            [~, aTgt(i)] = min(abs(A - env.fixed_class_tab(dc, vc)));
        end

        off = zeros(1, N);
        H = harqInit_v8(N);
        nk = zeros(1, N);
        prevRef = baseCQI_v5(obsS(1,:) + off, env);
        R_emas = zeros(1, N);
        ema = 0.05;
        ep_tp = 0;
        ep_ent = 0;

        % Initialize temporal state history buffer [nSingle x N x L_seq]
        histS = zeros(nSingle, N, L_seq, 'single');

        for t = 1:simTime
            [S_temporal, histS, ref] = build_state_v8(t, obsS, off, prevRef, nk, H, ...
                meta.speeds(t,:), burstObsM(t,:), meta.delays, R_emas, ctx, histS, env, nFeat);

            % Flush the buffer now that S_temporal is the successor state of
            % every buffered transition.
            if nb >= flushAt
                [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = updFn( ...
                    actorNet, criticNet, Wc, S_temporal, bufS, bufA, bufR, bufU, bufP, nb, ...
                    gamma, entW, clip_norm, lr_actor, lr_critic, toDl, ...
                    aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt);
                Wa = extract_weights(actorNet);
                Wc = extract_weights(criticNet);
                nb = 0;
            end

            % Forward actor pass
            [~, P] = forward_actor(Wa, S_temporal);
            ep_ent = ep_ent + mean(-sum(P .* log(P + 1e-12), 1));

            % Sample action per user
            aIdx = zeros(1, N);
            sent = zeros(1, N);
            pot  = zeros(1, N);
            isRetx = env.harq_on & H.pend;  % action has no effect on a retx
            for i = 1:N
                if isBC
                    a = aTgt(i);
                else
                    a = find(rand <= cumsum(P(:, i)), 1, 'first');
                    if isempty(a), a = nA; end
                end
                aIdx(i) = a;
                sent(i) = max(minC, min(maxC, ref(i) + A(a)));
                if isRetx(i)
                    pot(i) = tbsFromMCSandRB(H.mcs(i), env.total_RB) * 1e-3;
                else
                    if isfield(env, 'sched_on_ref') && env.sched_on_ref
                    % FILL FIX option: scheduler ranks users by the OLLA reference rate,
                    % not by the link-adaptation decision (removes scheduler gaming)
                    pot(i) = tbsFromMCSandRB(max(env.min_CQI, min(env.max_CQI, ref(i))) - 1, env.total_RB) * 1e-3;
                else
                    pot(i) = tbsFromMCSandRB(sent(i)-1, env.total_RB) * 1e-3;
                end
                end
            end

            % Physical transmission step
            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            [tp_now, off, H, ~, nEv, dropEv] = txStep_v8(sent, Strue(t,:), rb, off, H, env);

            schedM = rb > 0;
            nk(schedM)  = 0.7 * nk(schedM) + 0.3 * double(nEv(schedM));
            nk(~schedM) = 0.95 * nk(~schedM);
            R_emas = (1 - ema) * R_emas + ema * tp_now;
            ep_tp  = ep_tp + sum(tp_now);

            % -------------------------------------------------------------
            % Scheduled Credit Assignment: store ONLY scheduled users
            % -------------------------------------------------------------
            for i = 1:N
                if schedM(i)
                    % Reward = Goodput - Drop Penalty - Retransmission Penalty
                    r_i = (tp_now(i) / env.reward_scale) ...
                          - env.lambda_drop * double(dropEv(i)) ...
                          - env.lambda_retx * double(nEv(i));
                    nb = nb + 1;
                    bufS(:, nb) = S_temporal(:, i);
                    bufA(nb)    = aIdx(i);
                    bufR(nb)    = single(r_i);
                    bufU(nb)    = i;
                    bufP(nb)    = single(~isRetx(i));
                end
            end
            prevRef = ref;
        end

        % End of episode (time-limit truncation): bootstrap from the
        % post-episode state (no new CQI report, but OLLA/HARQ/EMA updated).
        if nb > 0
            S_post = build_state_v8(simTime, obsS, off, prevRef, nk, H, ...
                meta.speeds(simTime,:), burstObsM(simTime,:), meta.delays, R_emas, ctx, histS, env, nFeat);
            [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = updFn( ...
                actorNet, criticNet, Wc, S_post, bufS, bufA, bufR, bufU, bufP, nb, ...
                gamma, entW, clip_norm, lr_actor, lr_critic, toDl, ...
                aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt);
            Wa = extract_weights(actorNet);
            Wc = extract_weights(criticNet);
            nb = 0;
        end

        learning_curve(ep) = ep_tp / simTime;
        entropy_curve(ep)  = ep_ent / simTime;

        if mod(ep, 25) == 0 || ep == nTot
            fprintf('  [BC=%d] Deep A2C v8 ep %3d/%d | CellTp = %5.2f Mbps | Policy Entropy = %5.3f | entW = %.3f\n', ...
                    isBC, ep, nTot, learning_curve(ep), entropy_curve(ep), entW);
        end
    end
end

function [S_temporal, histS, ref] = build_state_v8(t, obsS, off, prevRef, nk, H, spd, burstObs, delays, R_emas, ctx, histS, env, nFeat)
% Build the stacked (L_seq-frame) state for all users at TTI t.
    ref  = baseCQI_v5(obsS(t,:) + off, env);
    dRef = max(env.min_delta, min(env.max_delta, ref - prevRef));
    dS   = obsS(t,:) - obsS(max(t-1,1),:);
    t0   = max(t-4, 1);
    slope4 = (obsS(t,:) - obsS(t0,:)) / max(t - t0, 1);
    s_now = stateFeat_v8(env.state_tier, ref, dRef, obsS(t,:), dS, off, ...
                         slope4, nk, H, spd, burstObs, delays, R_emas, ctx);
    L_seq = size(histS, 3);
    histS(:,:,2:L_seq) = histS(:,:,1:L_seq-1);
    histS(:,:,1) = s_now;
    S_temporal = reshape(permute(histS, [1, 3, 2]), nFeat, size(histS, 2));
end

function [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = a2c_update_v8( ...
        actorNet, criticNet, Wc, S_next, bufS, bufA, bufR, bufU, bufP, nb, ...
        gamma, entW, clip_norm, lr_actor, lr_critic, toDl, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt)
% Per-user n-step returns over each user's scheduled transitions, with the
% final transition of each user bootstrapped from that user's successor state.
    Vnext = forward_critic(Wc, S_next);          % 1 x N
    rets = zeros(1, nb, 'single');
    R = bufR(1:nb);
    U = bufU(1:nb);
    for u = unique(U)
        idx = find(U == u);
        G = single(Vnext(u));
        for j = numel(idx):-1:1
            G = R(idx(j)) + single(gamma) * G;
            rets(idx(j)) = G;
        end
    end

    [aG, cG] = dlfeval(@a2c_grads_v8, actorNet, criticNet, ...
                       toDl(bufS(:, 1:nb)), bufA(1:nb), toDl(rets), entW, bufP(1:nb));
    aG = clipGlobal(aG, clip_norm);
    cG = clipGlobal(cG, clip_norm);
    aIt = aIt + 1;
    [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
    cIt = cIt + 1;
    [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);
end

function [aGrad, cGrad] = a2c_grads_v8(actorNet, criticNet, S, Aacts, R, entW, pMask)
    V = forward(criticNet, S);
    adv = R - V;
    cLoss = mean(adv.^2);

    logits = forward(actorNet, S);
    m = max(logits, [], 1);
    logZ = m + log(sum(exp(logits - m), 1));
    logp_all = logits - logZ;
    B = size(S, 2);
    An = size(logits, 1);
    mask = zeros(An, B, 'single');
    mask(sub2ind([An, B], Aacts(1:B), 1:B)) = 1;
    mask = dlarray(mask);
    logp = sum(logp_all .* mask, 1);

    % Advantage normalisation over the policy-relevant (first-transmission)
    % samples only; retransmission samples get zero policy weight.
    advD = double(gather(extractdata(adv)));
    pm = double(pMask(:)') > 0;
    advN = zeros(size(advD));
    if any(pm)
        a = advD(pm);
        sd = std(a);
        if sd > 1e-6, advN(pm) = (a - mean(a)) / sd; else, advN(pm) = a - mean(a); end
    end
    advD = dlarray(cast(advN, 'like', extractdata(logits)));
    nP = max(sum(pm), 1);

    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);
    aLoss = -sum(logp .* advD) / nP - entW * mean(entropy);

    cGrad = dlgradient(cLoss, criticNet.Learnables, 'RetainData', true);
    aGrad = dlgradient(aLoss, actorNet.Learnables);
end

function [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = bc_update_v8( ...
        actorNet, criticNet, Wc, S_next, bufS, bufA, bufR, bufU, bufP, nb, ...
        gamma, entW, clip_norm, lr_actor, lr_critic, toDl, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt)
% BC update: actor cross-entropy on teacher actions (first transmissions
% only), critic regression on the cloned rollout's per-user returns.
    Vnext = forward_critic(Wc, S_next);
    rets = zeros(1, nb, 'single');
    R = bufR(1:nb);
    U = bufU(1:nb);
    for u = unique(U)
        idx = find(U == u);
        G = single(Vnext(u));
        for j = numel(idx):-1:1
            G = R(idx(j)) + single(gamma) * G;
            rets(idx(j)) = G;
        end
    end
    [aG, cG] = dlfeval(@bc_grads_v8, actorNet, criticNet, ...
                       toDl(bufS(:, 1:nb)), bufA(1:nb), toDl(rets), entW, bufP(1:nb));
    aG = clipGlobal(aG, clip_norm);
    cG = clipGlobal(cG, clip_norm);
    aIt = aIt + 1;
    [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
    cIt = cIt + 1;
    [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);
end

function [aGrad, cGrad] = bc_grads_v8(actorNet, criticNet, S, Aacts, R, entW, pMask)
    V = forward(criticNet, S);
    cLoss = mean((R - V).^2);
    logits = forward(actorNet, S);
    m = max(logits, [], 1);
    logZ = m + log(sum(exp(logits - m), 1));
    logp_all = logits - logZ;
    B = size(S, 2);
    An = size(logits, 1);
    mask = zeros(An, B, 'single');
    mask(sub2ind([An, B], Aacts(1:B), 1:B)) = 1;
    pm = single(double(pMask(:)') > 0);
    mask = mask .* pm;
    mask = dlarray(mask);
    nP = max(sum(pm), 1);
    ce = -sum(sum(logp_all .* mask, 1)) / nP;
    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);
    aLoss = ce - entW * mean(entropy);
    cGrad = dlgradient(cLoss, criticNet.Learnables, 'RetainData', true);
    aGrad = dlgradient(aLoss, actorNet.Learnables);
end

function grads = clipGlobal(grads, clipNorm)
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

function W = extract_weights(net)
    L = net.Learnables;
    W.w1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Weights"});
    W.b1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Bias"});
    W.w2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Weights"});
    W.b2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Bias"});
    isL3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Weights";
    W.w3 = extractdata(L.Value{isL3});
    isB3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Bias";
    W.b3 = extractdata(L.Value{isB3});
end

function [logits, P] = forward_actor(W, S)
    x1 = max(0, W.w1 * S + W.b1);
    x2 = max(0, W.w2 * x1 + W.b2);
    logits = double(W.w3 * x2 + W.b3);
    logits = logits - max(logits, [], 1);
    P = exp(logits) ./ sum(exp(logits), 1);
end

function V = forward_critic(W, S)
    x1 = max(0, W.w1 * S + W.b1);
    x2 = max(0, W.w2 * x1 + W.b2);
    V = double(W.w3 * x2 + W.b3);
end
