function [actorNet, criticNet, learning_curve, entropy_curve] = ...
            DeepPPO_Shared_v15(simTime, num_episodes, seed, env)
% DeepPPO_Shared_v15  P2 (IMPLEMENTATION_PLAN_v15.md): clipped-surrogate PPO
% with GAE(lambda), replacing DeepA2C_Shared_v15's single-pass n-step A2C
% update. Reuses the same environment interaction (state features, action
% sampling incl. the P1 target-mode semi-MDP epoch, scheduling, physics) as
% DeepA2C_Shared_v15 -- only the learning rule differs -- so a trained
% actorNet is a drop-in policy for evalPolicy_v15's 'a2c'/'a2c_v15' ptype
% (same fc1/fc2/logits layer names and nFeat input width).
%
% env.ppo.* hyper-parameters (defaults match the plan):
%   n_step      rollout-size multiplier (buffer holds n_step*N*2 + N entries)
%   lr_actor, lr_critic
%   ent_start, ent_end   linear entropy-coefficient schedule
%   ent_floor            minimum realised policy entropy (nats) the schedule
%                         tries to maintain; the coefficient is boosted for
%                         the next rollout if the last one fell below it
%   clip_eps              PPO clipped-surrogate epsilon (0.2)
%   val_clip_eps           value-function clipping epsilon (0.2)
%   gae_lambda             GAE lambda (0.95)
%   n_epochs                epochs per rollout (4)
%   minibatch               minibatch size (256)
%   obs_norm, reward_norm   running mean/std normalisation (true/true)
    if ~isempty(seed), rng(seed); end
    N = env.N;
    targMode = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'target');
    if targMode, A = env.target_set; else, A = env.actions; end
    nA = numel(A);
    targEpoch = 10; if isfield(env, 'target_epoch'), targEpoch = max(1, round(env.target_epoch)); end
    maxC = env.max_CQI; minC = env.min_CQI;

    gamma = env.gamma;
    hp = struct(); if isfield(env, 'ppo') && isstruct(env.ppo), hp = env.ppo; end
    n_step      = hpget(hp, 'n_step', 20);
    lr_actor    = hpget(hp, 'lr_actor', 3e-4);
    lr_critic   = hpget(hp, 'lr_critic', 1e-3);
    ent_start   = hpget(hp, 'ent_start', 0.05);
    ent_end     = hpget(hp, 'ent_end', 0.01);
    ent_floor   = hpget(hp, 'ent_floor', 0.5);
    clip_eps    = hpget(hp, 'clip_eps', 0.2);
    val_clip_eps = hpget(hp, 'val_clip_eps', 0.2);
    gae_lambda  = hpget(hp, 'gae_lambda', 0.95);
    n_epochs    = hpget(hp, 'n_epochs', 4);
    minibatch   = hpget(hp, 'minibatch', 256);
    obsNormOn   = hpget(hp, 'obs_norm', true);
    rewNormOn   = hpget(hp, 'reward_norm', true);
    rk = 'goodput'; if isfield(env, 'reward_kind'), rk = lower(env.reward_kind); end
    Pq = 1; if isfield(env, 'cqi_period'), Pq = max(1, round(env.cqi_period)); end
    clip_norm = 5.0;
    L_seq = 3;

    nSched = numel(env.sched_list);
    if upper(env.state_tier) == 'A', nBase = 5;
    elseif upper(env.state_tier) == 'O', nBase = 10;
    else, nBase = 13;
    end
    nSingle = nBase + nSched + nExtra_v15(env);
    nFeat = nSingle * L_seq;

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

    Wa = extract_weights_ppo(actorNet);
    Wc = extract_weights_ppo(criticNet);

    aAvg = []; aAvgSq = []; aIt = 0;
    cAvg = []; cAvgSq = []; cIt = 0;
    learning_curve = zeros(num_episodes, 1);
    entropy_curve  = zeros(num_episodes, 1);

    % Running mean/std (Welford) for observation normalisation (per feature,
    % over all TTIs/users seen so far) and for reward scaling (over all
    % buffered transitions; divides only -- no mean subtraction, so reward
    % sign/structure is preserved).
    obsCount = 0; obsMean = zeros(nFeat, 1); obsM2 = zeros(nFeat, 1);
    rewCount = 0; rewMean = 0; rewM2 = 0;

    flushAt = n_step * N * 2;
    cap = flushAt + N;
    bufS = zeros(nFeat, cap, 'single');
    bufA = zeros(1, cap);
    bufR = zeros(1, cap, 'single');
    bufU = zeros(1, cap);
    bufP = zeros(1, cap, 'single');
    bufLogp = zeros(1, cap, 'single');
    bufV    = zeros(1, cap, 'single');
    nb = 0;
    entW = ent_start;      % boosted (see ent_floor) if the last rollout collapsed

    for ep = 1:num_episodes
        entSched = ent_start + (ent_end - ent_start) * (ep - 1) / max(num_episodes - 1, 1);
        entW = max(entSched, entW);   % entW may already be boosted from the previous rollout

        sched = sampleSched_v5(env);
        [~, sOneHot] = schedContext_v5(sched, env);
        ctx = single(repmat(sOneHot, 1, N));

        W = 0; if isfield(env, 'train_warm_ttis'), W = env.train_warm_ttis; end
        Ttot = W + simTime;
        [Strue, ~, meta] = generateChannel_v15(Ttot, env);
        obsS = cqiFeedback_v15(Strue, env, meta.delays);

        burstObsM = zeros(Ttot, N);
        for i = 1:N
            idx = max((1:Ttot).' - meta.delays(i), 1);
            burstObsM(:, i) = double(meta.burst(idx));
        end

        ageM = cqiAge_v15(Ttot, N, Pq);
        emaO = obsS(1, :); cn = 0;
        Q = trafficInit_v15(env, N, 0);
        lastIdx = zeros(1, N); pendR = zeros(1, N);
        off = zeros(1, N);
        H = harqInit_v15(N);
        nk = zeros(1, N);
        prevRef = baseCQI_v15(obsS(1,:) + off, env);
        R_emas = zeros(1, N);
        ema = 0.05;
        ep_tp = 0; ep_ent = 0; ep_entN = 0;
        ack8 = zeros(1, N); tsince = zeros(1, N); offEma = zeros(1, N);

        histS = zeros(nSingle, N, L_seq, 'single');

        if targMode
            defA = find(abs(A - env.olla_target_tuned) < 1e-9, 1);
            if isempty(defA), defA = 1; end
            epochA = defA * ones(1, N);
            epochR = zeros(1, N);
            epochSched = false(1, N);
            epochS0 = zeros(nFeat, N, 'single');
            epochLogp0 = zeros(1, N, 'single');
            epochV0    = zeros(1, N, 'single');
        else
            noop = find(A == 0);
        end

        for t = 1:Ttot
            learn = t > W;
            [Q, H, missEv] = trafficPre_v15(Q, t, env, H);
            X = struct('age', ageM(t, :), 'dev', obsS(t, :) - emaO, 'cn', cn, 'Q', Q, 't', t, ...
                        'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma);
            xtra = featExtra_v15(env, X);
            [S_raw, histS, ref] = build_state_ppo_v15(t, obsS, off, prevRef, nk, H, ...
                meta.speeds(t,:), burstObsM(t,:), meta.delays, R_emas, ctx, histS, env, nFeat, xtra);

            if obsNormOn
                [obsMean, obsM2, obsCount] = welford_update(obsMean, obsM2, obsCount, S_raw);
                obsStd = sqrt(max(obsM2 / max(obsCount - 1, 1), 1e-8));
                S_temporal = single(max(-5, min(5, (double(S_raw) - obsMean) ./ obsStd)));
            else
                S_temporal = S_raw;
            end

            if learn && strcmpi(rk, 'ontime') && any(missEv)
                if targMode
                    epochR(missEv) = epochR(missEv) - env.miss_pen;
                else
                    for i = find(missEv)
                        if lastIdx(i) > 0, bufR(lastIdx(i)) = bufR(lastIdx(i)) - single(env.miss_pen);
                        else, pendR(i) = pendR(i) - env.miss_pen; end
                    end
                end
            end

            % Rollout-full flush: run n_epochs x minibatch-SGD PPO updates on
            % the collected rollout, then clear the buffer and continue.
            if learn && nb >= flushAt
                [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt, lastEnt, rewMean, rewM2, rewCount] = ppo_update_v15( ...
                    actorNet, criticNet, Wc, S_temporal, bufS, bufA, bufR, bufU, bufP, bufLogp, bufV, nb, ...
                    gamma, gae_lambda, entW, clip_eps, val_clip_eps, clip_norm, n_epochs, minibatch, ...
                    lr_actor, lr_critic, toDl, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt, rewNormOn, rewMean, rewM2, rewCount);
                Wa = extract_weights_ppo(actorNet);
                Wc = extract_weights_ppo(criticNet);
                nb = 0; lastIdx(:) = 0;
                entW = entSched; if lastEnt < ent_floor, entW = entSched * 2; end  % P2: entropy floor
            end

            [~, P] = forward_actor_ppo(Wa, S_temporal);
            [curV] = forward_critic_ppo(Wc, S_temporal);
            logp_all = log(P + 1e-12);
            if learn
                epN = -sum(P .* logp_all, 1);
                ep_ent = ep_ent + mean(epN); ep_entN = ep_entN + 1;
            end

            isRetx = env.harq_on & H.pend;

            if targMode
                atDecision = mod(t - 1, targEpoch) == 0;
                if atDecision
                    if t > 1
                        pushIdx = find(epochSched | (epochR ~= 0));
                        if learn && ~isempty(pushIdx)
                            nSel = numel(pushIdx);
                            newNb = nb + (1:nSel);
                            bufS(:, newNb) = epochS0(:, pushIdx);
                            bufA(newNb)    = epochA(pushIdx);
                            bufR(newNb)    = single(epochR(pushIdx));
                            bufU(newNb)    = pushIdx;
                            bufP(newNb)    = single(1);
                            bufLogp(newNb) = epochLogp0(pushIdx);
                            bufV(newNb)    = epochV0(pushIdx);
                            nb = nb + nSel;
                        end
                    end
                    epochR(:) = 0; epochSched(:) = false;
                    epochS0 = S_temporal;
                    epochV0 = single(curV);
                    if learn
                        U_act = rand(1, N);
                        Pcum = cumsum(P, 1);
                        cmp = U_act <= Pcum;
                        [tfHit, newA] = max(cmp, [], 1);
                        newA(~tfHit) = nA;
                        epochA = newA;
                    end
                    epochLogp0 = logp_all(sub2ind(size(logp_all), epochA, 1:N));
                end
                aIdx = epochA;
                targVec = A(epochA);
                sent = ref;
            else
                if learn
                    U_act = rand(1, N);
                    Pcum = cumsum(P, 1);
                    cmp = U_act <= Pcum;
                    [tfHit, aIdx] = max(cmp, [], 1);
                    aIdx(~tfHit) = nA;
                else
                    aIdx = noop * ones(1, N);
                end
                targVec = [];
                sent = max(minC, min(maxC, ref + A(aIdx)));
            end

            rbFull = env.total_RB * ones(1, N);
            if isfield(env, 'sched_on_ref') && env.sched_on_ref
                potNew = tbsFromMCSandRB_v15(max(env.min_CQI, min(env.max_CQI, ref)) - 1, rbFull) * 1e-3;
            else
                potNew = tbsFromMCSandRB_v15(sent - 1, rbFull) * 1e-3;
            end
            pot = potNew;
            if any(isRetx)
                potRetx = tbsFromMCSandRB_v15(H.mcs, rbFull) * 1e-3;
                pot(isRetx) = potRetx(isRetx);
            end

            pot(~Q.has) = 0;
            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            rb(~Q.has) = 0;
            [tp_now, off, H, ~, nEv, dropEv] = txStep_v15(sent, Strue(t,:), rb, off, H, env, [], targVec);
            [Q, okEv] = trafficPost_v15(Q, tp_now, t);
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
                selIdx = find(schedM);
                nSel = numel(selIdx);
                if nSel > 0
                    if strcmpi(rk, 'ontime')
                        rI = env.ontime_bonus * double(okEv(selIdx));
                        if ~targMode, rI = rI + pendR(selIdx); pendR(selIdx) = 0; end
                    elseif strcmpi(rk, 'oppcost')
                        tref = tbsFromMCSandRB_v15(max(minC, min(maxC, ref(selIdx))) - 1, rb(selIdx)) * 1e-3 * (1 - env.olla_target);
                        rI = (tp_now(selIdx) - tref) / env.reward_scale;
                    elseif strcmpi(rk, 'cell')
                        % P2: cell-level reward, credited to the scheduled
                        % user(s) -- cell goodput minus a reference (OLLA)
                        % expectation. Decentralised critic (same state as
                        % the actor) for simplicity; the per-user cell-wide
                        % NACK-rate cue is still available via feat_extra.
                        cellTp = sum(tp_now);
                        cellRef = sum(tbsFromMCSandRB_v15(max(minC, min(maxC, ref)) - 1, rbFull) * 1e-3 * (1 - env.olla_target));
                        rI = ((cellTp - cellRef) / env.reward_scale) * ones(1, nSel) / max(nSel, 1);
                    else
                        rI = (tp_now(selIdx) / env.reward_scale) ...
                              - env.lambda_drop * double(dropEv(selIdx)) ...
                              - env.lambda_retx * double(nEv(selIdx));
                    end
                    if targMode
                        epochR(selIdx) = epochR(selIdx) + rI;
                        epochSched(selIdx) = true;
                    else
                        newNb = nb + (1:nSel);
                        bufS(:, newNb)   = S_temporal(:, selIdx);
                        bufA(newNb)      = aIdx(selIdx);
                        bufR(newNb)      = single(rI);
                        bufU(newNb)      = selIdx;
                        bufP(newNb)      = single(~isRetx(selIdx));
                        bufLogp(newNb)   = logp_all(sub2ind(size(logp_all), aIdx(selIdx), selIdx));
                        bufV(newNb)      = single(curV(selIdx));
                        lastIdx(selIdx)  = newNb;
                        nb = nb + nSel;
                    end
                end
            end
            prevRef = ref;
        end

        if targMode
            pushIdx = find(epochSched | (epochR ~= 0));
            if ~isempty(pushIdx)
                nSel = numel(pushIdx);
                newNb = nb + (1:nSel);
                bufS(:, newNb) = epochS0(:, pushIdx);
                bufA(newNb)    = epochA(pushIdx);
                bufR(newNb)    = single(epochR(pushIdx));
                bufU(newNb)    = pushIdx;
                bufP(newNb)    = single(1);
                bufLogp(newNb) = epochLogp0(pushIdx);
                bufV(newNb)    = epochV0(pushIdx);
                nb = nb + nSel;
            end
        end
        if nb > 0
            Xp = struct('age', ageM(Ttot, :), 'dev', obsS(Ttot, :) - emaO, 'cn', cn, 'Q', Q, 't', Ttot, ...
                        'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma);
            S_post = build_state_ppo_v15(Ttot, obsS, off, prevRef, nk, H, ...
                meta.speeds(Ttot,:), burstObsM(Ttot,:), meta.delays, R_emas, ctx, histS, env, nFeat, featExtra_v15(env, Xp));
            if obsNormOn
                obsStd = sqrt(max(obsM2 / max(obsCount - 1, 1), 1e-8));
                S_post = single(max(-5, min(5, (double(S_post) - obsMean) ./ obsStd)));
            end
            [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt, lastEnt, rewMean, rewM2, rewCount] = ppo_update_v15( ...
                actorNet, criticNet, Wc, S_post, bufS, bufA, bufR, bufU, bufP, bufLogp, bufV, nb, ...
                gamma, gae_lambda, entW, clip_eps, val_clip_eps, clip_norm, n_epochs, minibatch, ...
                lr_actor, lr_critic, toDl, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt, rewNormOn, rewMean, rewM2, rewCount);
            Wa = extract_weights_ppo(actorNet);
            Wc = extract_weights_ppo(criticNet);
            nb = 0; lastIdx(:) = 0;
            entW = entSched; if lastEnt < ent_floor, entW = entSched * 2; end
        end

        learning_curve(ep) = ep_tp / simTime;
        entropy_curve(ep)  = ep_ent / max(ep_entN, 1);

        if mod(ep, 25) == 0 || ep == num_episodes
            fprintf('  Deep PPO v15 ep %3d/%d | CellTp = %5.2f Mbps | Policy Entropy = %5.3f | entW = %.3f\n', ...
                    ep, num_episodes, learning_curve(ep), entropy_curve(ep), entW);
        end
    end
end

function [S_temporal, histS, ref] = build_state_ppo_v15(t, obsS, off, prevRef, nk, H, spd, burstObs, delays, R_emas, ctx, histS, env, nFeat, xtra)
    ref  = baseCQI_v15(obsS(t,:) + off, env);
    dRef = max(env.min_delta, min(env.max_delta, ref - prevRef));
    dS   = obsS(t,:) - obsS(max(t-1,1),:);
    t0   = max(t-4, 1);
    slope4 = (obsS(t,:) - obsS(t0,:)) / max(t - t0, 1);
    s_now = stateFeat_v15(env.state_tier, ref, dRef, obsS(t,:), dS, off, ...
                         slope4, nk, H, spd, burstObs, delays, R_emas, ctx, xtra);
    L_seq = size(histS, 3);
    histS(:,:,2:L_seq) = histS(:,:,1:L_seq-1);
    histS(:,:,1) = s_now;
    S_temporal = reshape(permute(histS, [1, 3, 2]), nFeat, size(histS, 2));
end

function [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt, lastEnt, rewMean, rewM2, rewCount] = ppo_update_v15( ...
        actorNet, criticNet, Wc, S_next, bufS, bufA, bufR, bufU, bufP, bufLogp, bufV, nb, ...
        gamma, lambda, entW, clipEps, valClipEps, clip_norm, n_epochs, minibatch, ...
        lr_actor, lr_critic, toDl, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt, rewNormOn, rewMean, rewM2, rewCount)
% ppo_update_v15  GAE(lambda) advantages per user chain (backward, bootstrap
% from V(S_next)), then n_epochs x minibatch-SGD on the PPO clipped
% surrogate + clipped value loss + entropy bonus. P2: running mean/std
% (Welford) reward normalisation -- divides by the running std only (no
% mean subtraction, so reward sign/structure is preserved) -- updated with
% this rollout's batch before being used in the GAE recursion.
    Vnext = forward_critic_ppo(Wc, S_next);  % 1 x N
    R = bufR(1:nb); U = bufU(1:nb); V = bufV(1:nb);
    if rewNormOn
        for j = 1:nb
            rewCount = rewCount + 1;
            d = double(R(j)) - rewMean;
            rewMean = rewMean + d / rewCount;
            rewM2 = rewM2 + d * (double(R(j)) - rewMean);
        end
        rewStd = sqrt(max(rewM2 / max(rewCount - 1, 1), 1e-8));
        R = single(double(R) / rewStd);
    end
    adv = zeros(1, nb, 'single');
    ret = zeros(1, nb, 'single');
    for u = unique(U)
        idx = find(U == u);
        nextA = 0; nextV = single(Vnext(u));
        for j = numel(idx):-1:1
            delta = R(idx(j)) + gamma * nextV - V(idx(j));
            adv(idx(j)) = delta + gamma * lambda * nextA;
            nextA = adv(idx(j));
            nextV = V(idx(j));
        end
    end
    ret = adv + V;

    pm = bufP(1:nb) > 0;
    advN = adv;
    if any(pm)
        a = adv(pm); sd = std(double(a));
        if sd > 1e-6, advN(pm) = (a - mean(a)) / sd; else, advN(pm) = a - mean(a); end
    end

    idxAll = 1:nb;
    lastEnt = 0; nEntBatch = 0;
    for epch = 1:n_epochs
        perm = idxAll(randperm(nb));
        for b0 = 1:minibatch:nb
            mb = perm(b0:min(b0 + minibatch - 1, nb));
            [aG, cG, entB] = dlfeval(@ppo_grads_v15, actorNet, criticNet, ...
                toDl(bufS(:, mb)), bufA(mb), toDl(advN(mb)), toDl(ret(mb)), ...
                toDl(bufLogp(mb)), toDl(bufV(mb)), entW, clipEps, valClipEps, bufP(mb));
            aG = clipGlobal_ppo(aG, clip_norm);
            cG = clipGlobal_ppo(cG, clip_norm);
            aIt = aIt + 1;
            [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
            cIt = cIt + 1;
            [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);
            lastEnt = lastEnt + double(gather(extractdata(entB))); nEntBatch = nEntBatch + 1;
        end
    end
    lastEnt = lastEnt / max(nEntBatch, 1);
end

function [aGrad, cGrad, meanEnt] = ppo_grads_v15(actorNet, criticNet, S, Aacts, advN, ret, oldLogp, oldV, entW, clipEps, valClipEps, pMask)
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

    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);
    meanEnt = mean(entropy);

    ratio = exp(logp - oldLogp);
    surr1 = ratio .* advN;
    cr = max(min(ratio, 1 + clipEps), 1 - clipEps);
    surr2 = cr .* advN;
    pm = double(pMask(:)') > 0;
    nP = max(sum(pm), 1);
    policySurr = min(surr1, surr2);
    aLoss = -sum(policySurr .* dlarray(single(pm))) / nP - entW * mean(entropy);

    V = forward(criticNet, S);
    Vclip = oldV + max(min(V - oldV, valClipEps), -valClipEps);
    vLoss1 = (V - ret).^2;
    vLoss2 = (Vclip - ret).^2;
    cLoss = mean(max(vLoss1, vLoss2));

    cGrad = dlgradient(cLoss, criticNet.Learnables, 'RetainData', true);
    aGrad = dlgradient(aLoss, actorNet.Learnables);
end

function grads = clipGlobal_ppo(grads, clipNorm)
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

function W = extract_weights_ppo(net)
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

function [logits, P] = forward_actor_ppo(W, S)
    x1 = max(0, W.w1 * S + W.b1);
    x2 = max(0, W.w2 * x1 + W.b2);
    logits = double(W.w3 * x2 + W.b3);
    logits = logits - max(logits, [], 1);
    P = exp(logits) ./ sum(exp(logits), 1);
end

function V = forward_critic_ppo(W, S)
    x1 = max(0, W.w1 * S + W.b1);
    x2 = max(0, W.w2 * x1 + W.b2);
    V = double(W.w3 * x2 + W.b3);
end

function v = hpget(hp, f, d)
    if isfield(hp, f) && ~isempty(hp.(f)), v = hp.(f); else, v = d; end
end

function [mean_, M2, count] = welford_update(mean_, M2, count, xBatch)
% Welford's online mean/variance, updated with a batch of columns (N
% samples of an nFeat x 1 vector each TTI).
    for j = 1:size(xBatch, 2)
        count = count + 1;
        x = double(xBatch(:, j));
        delta = x - mean_;
        mean_ = mean_ + delta / count;
        delta2 = x - mean_;
        M2 = M2 + delta .* delta2;
    end
end
