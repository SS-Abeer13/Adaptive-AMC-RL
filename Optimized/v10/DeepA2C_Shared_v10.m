function [actorNet, criticNet, learning_curve, entropy_curve] = ...
            DeepA2C_Shared_v10(simTime, num_episodes, seed, env)
% DeepA2C_Shared_v10  Shared-network n-step A2C with scheduled credit assignment
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
    % v10: hyper-parameters overridable through env.a2c (defaults = v9)
    hp = struct(); if isfield(env, 'a2c') && isstruct(env.a2c), hp = env.a2c; end
    n_step    = hpget(hp, 'n_step', 10);
    lr_actor  = hpget(hp, 'lr_actor', 5e-4);
    lr_critic = hpget(hp, 'lr_critic', 1e-3);
    ent_start = hpget(hp, 'ent_start', 0.08);   % Exploratory start for autonomous learning
    ent_end   = hpget(hp, 'ent_end', 0.005);    % Annealed floor
    rk = 'goodput'; if isfield(env, 'reward_kind'), rk = lower(env.reward_kind); end
    Pq = 1; if isfield(env, 'cqi_period'), Pq = max(1, round(env.cqi_period)); end
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
    nSingle = nBase + nSched + nExtra_v10(env);
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
    learning_curve = zeros(num_episodes, 1);
    entropy_curve  = zeros(num_episodes, 1);

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

    for ep = 1:num_episodes
        % Linear entropy decay across autonomous training episodes
        entW = ent_start + (ent_end - ent_start) * (ep - 1) / max(num_episodes - 1, 1);

        sched = sampleSched_v5(env);
        [~, sOneHot] = schedContext_v5(sched, env);
        ctx = single(repmat(sOneHot, 1, N));

        % v9: optional pure-OLLA warm-up before the learning part of the episode
        W = 0; if isfield(env, 'train_warm_ttis'), W = env.train_warm_ttis; end
        Ttot = W + simTime;
        [Strue, ~, meta] = generateChannel_v10(Ttot, env);
        obsS = cqiFeedback_v10(Strue, env, meta.delays);

        burstObsM = zeros(Ttot, N);
        for i = 1:N
            idx = max((1:Ttot).' - meta.delays(i), 1);
            burstObsM(:, i) = double(meta.burst(idx));
        end

        ageM = cqiAge_v10(Ttot, N, Pq);
        emaO = obsS(1, :); cn = 0;
        Q = trafficInit_v10(env, N, 0);
        lastIdx = zeros(1, N); pendR = zeros(1, N);
        off = zeros(1, N);
        H = harqInit_v10(N);
        nk = zeros(1, N);
        prevRef = baseCQI_v5(obsS(1,:) + off, env);
        R_emas = zeros(1, N);
        ema = 0.05;
        ep_tp = 0;
        ep_ent = 0;

        % Initialize temporal state history buffer [nSingle x N x L_seq]
        histS = zeros(nSingle, N, L_seq, 'single');

        noop = find(A == 0);
        for t = 1:Ttot
            learn = t > W;
            [Q, H, missEv] = trafficPre_v10(Q, t, env, H);
            X = struct('age', ageM(t, :), 'dev', obsS(t, :) - emaO, 'cn', cn, 'Q', Q, 't', t);
            xtra = featExtra_v10(env, X);
            [S_temporal, histS, ref] = build_state_v10(t, obsS, off, prevRef, nk, H, ...
                meta.speeds(t,:), burstObsM(t,:), meta.delays, R_emas, ctx, histS, env, nFeat, xtra);
            % v10 deadline misses: credit the user's most recent buffered decision
            if learn && strcmpi(rk, 'ontime') && any(missEv)
                for i = find(missEv)
                    if lastIdx(i) > 0, bufR(lastIdx(i)) = bufR(lastIdx(i)) - single(env.miss_pen);
                    else, pendR(i) = pendR(i) - env.miss_pen; end
                end
            end

            % Flush the buffer now that S_temporal is the successor state of
            % every buffered transition.
            if learn && nb >= flushAt
                [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = a2c_update_v10( ...
                    actorNet, criticNet, Wc, S_temporal, bufS, bufA, bufR, bufU, bufP, nb, ...
                    gamma, entW, clip_norm, lr_actor, lr_critic, toDl, ...
                    aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt);
                Wa = extract_weights(actorNet);
                Wc = extract_weights(criticNet);
                nb = 0; lastIdx(:) = 0;
            end

            % Forward actor pass
            [~, P] = forward_actor(Wa, S_temporal);
            if learn, ep_ent = ep_ent + mean(-sum(P .* log(P + 1e-12), 1)); end

            % Sample action per user
            aIdx = zeros(1, N);
            sent = zeros(1, N);
            pot  = zeros(1, N);
            isRetx = env.harq_on & H.pend;  % action has no effect on a retx
            for i = 1:N
                if learn
                    a = find(rand <= cumsum(P(:, i)), 1, 'first');
                    if isempty(a), a = nA; end
                else
                    a = noop;   % warm-up: pure OLLA
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
            pot(~Q.has) = 0;
            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            rb(~Q.has) = 0;
            [tp_now, off, H, ~, nEv, dropEv] = txStep_v10(sent, Strue(t,:), rb, off, H, env);
            [Q, okEv] = trafficPost_v10(Q, tp_now, t);
            if any(schedNow(rb)), cn = 0.6 * cn + 0.4 * mean(double(nEv(rb > 0))); else, cn = 0.97 * cn; end
            emaO = 0.98 * emaO + 0.02 * obsS(t, :);

            schedM = rb > 0;
            nk(schedM)  = 0.7 * nk(schedM) + 0.3 * double(nEv(schedM));
            nk(~schedM) = 0.95 * nk(~schedM);
            R_emas = (1 - ema) * R_emas + ema * tp_now;
            if learn, ep_tp = ep_tp + sum(tp_now); end

            % -------------------------------------------------------------
            % Scheduled Credit Assignment: store ONLY scheduled users
            % -------------------------------------------------------------
            for i = 1:N
                if learn && schedM(i)
                    % Reward = Goodput - Drop Penalty - Retransmission Penalty
                    if strcmpi(rk, 'ontime')
                        r_i = env.ontime_bonus * double(okEv(i)) + pendR(i);
                        pendR(i) = 0;
                    elseif strcmpi(rk, 'oppcost')
                        % v10b: every scheduled slot (first tx or retx) is charged the
                        % goodput the OLLA reference decision is expected to deliver on
                        % it, so a slot spent on a failed / retransmitted block costs the
                        % cell -- the per-user return now tracks cell goodput.
                        tref = tbsFromMCSandRB(max(minC, min(maxC, ref(i))) - 1, rb(i)) * 1e-3 * (1 - env.olla_target);
                        r_i = (tp_now(i) - tref) / env.reward_scale;
                    else
                        r_i = (tp_now(i) / env.reward_scale) ...
                              - env.lambda_drop * double(dropEv(i)) ...
                              - env.lambda_retx * double(nEv(i));
                    end
                    nb = nb + 1;
                    bufS(:, nb) = S_temporal(:, i);
                    bufA(nb)    = aIdx(i);
                    bufR(nb)    = single(r_i);
                    bufU(nb)    = i;
                    bufP(nb)    = single(~isRetx(i));
                    lastIdx(i)  = nb;
                end
            end
            prevRef = ref;
        end

        % End of episode (time-limit truncation): bootstrap from the
        % post-episode state (no new CQI report, but OLLA/HARQ/EMA updated).
        if nb > 0
            Xp = struct('age', ageM(Ttot, :), 'dev', obsS(Ttot, :) - emaO, 'cn', cn, 'Q', Q, 't', Ttot);
            S_post = build_state_v10(Ttot, obsS, off, prevRef, nk, H, ...
                meta.speeds(Ttot,:), burstObsM(Ttot,:), meta.delays, R_emas, ctx, histS, env, nFeat, featExtra_v10(env, Xp));
            [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = a2c_update_v10( ...
                actorNet, criticNet, Wc, S_post, bufS, bufA, bufR, bufU, bufP, nb, ...
                gamma, entW, clip_norm, lr_actor, lr_critic, toDl, ...
                aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt);
            Wa = extract_weights(actorNet);
            Wc = extract_weights(criticNet);
            nb = 0; lastIdx(:) = 0;
        end

        learning_curve(ep) = ep_tp / simTime;
        entropy_curve(ep)  = ep_ent / simTime;

        if mod(ep, 25) == 0 || ep == num_episodes
            fprintf('  Deep A2C v10 ep %3d/%d | CellTp = %5.2f Mbps | Policy Entropy = %5.3f | entW = %.3f\n', ...
                    ep, num_episodes, learning_curve(ep), entropy_curve(ep), entW);
        end
    end
end

function [S_temporal, histS, ref] = build_state_v10(t, obsS, off, prevRef, nk, H, spd, burstObs, delays, R_emas, ctx, histS, env, nFeat, xtra)
% Build the stacked (L_seq-frame) state for all users at TTI t.
    ref  = baseCQI_v5(obsS(t,:) + off, env);
    dRef = max(env.min_delta, min(env.max_delta, ref - prevRef));
    dS   = obsS(t,:) - obsS(max(t-1,1),:);
    t0   = max(t-4, 1);
    slope4 = (obsS(t,:) - obsS(t0,:)) / max(t - t0, 1);
    s_now = stateFeat_v10(env.state_tier, ref, dRef, obsS(t,:), dS, off, ...
                         slope4, nk, H, spd, burstObs, delays, R_emas, ctx, xtra);
    L_seq = size(histS, 3);
    histS(:,:,2:L_seq) = histS(:,:,1:L_seq-1);
    histS(:,:,1) = s_now;
    S_temporal = reshape(permute(histS, [1, 3, 2]), nFeat, size(histS, 2));
end

function [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = a2c_update_v10( ...
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

    [aG, cG] = dlfeval(@a2c_grads_v10, actorNet, criticNet, ...
                       toDl(bufS(:, 1:nb)), bufA(1:nb), toDl(rets), entW, bufP(1:nb));
    aG = clipGlobal(aG, clip_norm);
    cG = clipGlobal(cG, clip_norm);
    aIt = aIt + 1;
    [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
    cIt = cIt + 1;
    [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);
end

function [aGrad, cGrad] = a2c_grads_v10(actorNet, criticNet, S, Aacts, R, entW, pMask)
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

function v = hpget(hp, f, d)
    if isfield(hp, f) && ~isempty(hp.(f)), v = hp.(f); else, v = d; end
end

function tf = schedNow(rb)
    tf = rb > 0;
end
