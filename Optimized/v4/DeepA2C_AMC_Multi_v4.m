function [actorNet, criticNet, learning_curve, entropy_curve] = ...
            DeepA2C_AMC_Multi_v4(simTime, num_episodes, seed, env)
% DeepA2C_AMC_Multi_v4  Shared-network n-step A2C on the unified v4 MDP.
%
% Training fixes vs v3 (audit section 2):
%   - Rewards normalized by env.reward_scale -> no optimizer saturation
%   - Advantages standardized per batch
%   - GLOBAL gradient-norm clipping (norm over all learnables), max 5.0
%   - Time-limit-aware bootstrap: V(s_T) from the critic at episode end
%     (Pardo et al. 2018), never a hard 0 at a non-terminal horizon
%   - Entropy coefficient annealed 0.05 -> 0.001 (greedy eval is consistent)
%   - No warm-up blending (off-policy bias), no bias init, no imitation bonus
%   - Actor outputs LOGITS; log-probs via log-softmax (numerically stable)
%
% The network is shared across users: centralized training, decentralized
% execution. One policy generalizes over the joint (CQI, dCQI, SINR) space
% instead of fragmenting experience into per-user tables.

    if ~isempty(seed), rng(seed); end
    N = env.N;
    actions = env.actions; num_actions = numel(actions);
    maxC = env.max_CQI; minC = env.min_CQI;
    maxD = env.max_delta; minD = env.min_delta;

    gamma      = env.gamma;
    n_step     = 10;
    lr_actor   = 5e-4;
    lr_critic  = 1e-3;
    ent_start  = 0.05;
    ent_end    = 0.001;
    clip_norm  = 5.0;

    % ---------- networks (actor emits logits; softmax applied manually)
    % v4.1: 4 input features -- (CQI, dCQI, obs SINR, obs SINR trend). The
    % trend is the same observable the tabular agents get as a 3-bin state
    % dimension; here it stays continuous (function-approximation advantage).
    actorLayers = [
        featureInputLayer(4, 'Name', 'in')
        fullyConnectedLayer(64, 'Name', 'fc1')
        reluLayer('Name', 'r1')
        fullyConnectedLayer(64, 'Name', 'fc2')
        reluLayer('Name', 'r2')
        fullyConnectedLayer(num_actions, 'Name', 'logits')];
    criticLayers = [
        featureInputLayer(4, 'Name', 'in')
        fullyConnectedLayer(64, 'Name', 'fc1')
        reluLayer('Name', 'r1')
        fullyConnectedLayer(64, 'Name', 'fc2')
        reluLayer('Name', 'r2')
        fullyConnectedLayer(1, 'Name', 'value')];
    actorNet  = dlnetwork(actorLayers);
    criticNet = dlnetwork(criticLayers);

    useGPU = false;
    try
        if gpuDeviceCount > 0
            gpuDevice; useGPU = true;
            actorNet  = dlupdate(@(x) gpuArray(single(x)), actorNet);
            criticNet = dlupdate(@(x) gpuArray(single(x)), criticNet);
        end
    catch
        useGPU = false;
    end
    toDl = @(x) dlarray(cond_gpu(single(x), useGPU), 'CB');

    aAvg = []; aAvgSq = []; aIt = 0;
    cAvg = []; cAvgSq = []; cIt = 0;

    learning_curve = zeros(num_episodes, 1);
    entropy_curve  = zeros(num_episodes, 1);

    cap = n_step * N;
    bufS = zeros(4, cap, 'single');
    bufA = zeros(1, cap);
    bufR = zeros(1, cap, 'single');
    nb   = 0;

    for ep = 1:num_episodes
        entW = ent_start + (ent_end - ent_start) * (ep - 1) / max(num_episodes - 1, 1);

        [SINR_true, ~, ~] = generateChannel_v4(simTime, env);
        [obs_SINR, obs_CQI] = cqiFeedback_v4(SINR_true, env);

        cur = obs_CQI(1, :); prev = cur; d = zeros(1, N);
        R_emas = zeros(1, N); ema_a = 0.05;
        ep_tp = 0; ep_ent = 0;

        for t = 1:simTime
            dS = obs_SINR(t, :) - obs_SINR(max(t-1, 1), :);
            S = single([cur/15; d/5; obs_SINR(t, :)/30; dS/5]);
            logits = gather(extractdata(predict(actorNet, toDl(S))));
            logits = double(logits) - max(logits, [], 1);
            P = exp(logits) ./ sum(exp(logits), 1);

            ep_ent = ep_ent + mean(-sum(P .* log(P + 1e-12), 1));

            a_idx = zeros(1,N); new_CQI = zeros(1,N);
            bler = zeros(1,N); pot = zeros(1,N);
            for i = 1:N
                a = find(rand <= cumsum(P(:, i)), 1, 'first');
                if isempty(a), a = num_actions; end
                a_idx(i) = a;
                new_CQI(i) = max(minC, min(maxC, cur(i) + actions(a)));
                mcs = new_CQI(i) - 1;
                bler(i) = estimateBLER_v4(SINR_true(t, i), mcs);
                pot(i)  = (1 - bler(i)) * tbsFromMCSandRB(mcs, env.total_RB) * 1e-3;
            end

            rb = schedule_users_v4(env.scheduler, t, N, R_emas, pot, env.total_RB);

            tp_now = zeros(1, N);
            for i = 1:N
                if rb(i) > 0
                    tp_now(i) = (1 - bler(i)) * ...
                                tbsFromMCSandRB(new_CQI(i)-1, rb(i)) * 1e-3;
                end
            end
            R_emas = (1 - ema_a) * R_emas + ema_a * tp_now;
            ep_tp = ep_tp + sum(tp_now);

            for i = 1:N
                if rb(i) > 0
                    r = computeReward_v4(bler(i), tbsFromMCSandRB(new_CQI(i)-1, rb(i)), env);
                else
                    r = 0;
                end
                nb = nb + 1;
                bufS(:, nb) = S(:, i);
                bufA(nb)    = a_idx(i);
                bufR(nb)    = single(r);
            end
            for i = 1:N
                nd = max(minD, min(maxD, new_CQI(i) - prev(i)));
                prev(i) = cur(i); cur(i) = new_CQI(i); d(i) = nd;
            end

            if nb >= cap || t == simTime
                % Time-limit-aware bootstrap: ALWAYS V(s'), even at t==simTime
                tn = min(t + 1, simTime);
                dSn = obs_SINR(tn, :) - obs_SINR(max(tn-1, 1), :);
                sN = single([cur/15; d/5; obs_SINR(tn, :)/30; dSn/5]);
                Vb = gather(extractdata(predict(criticNet, toDl(sN))));

                K = nb; Ts = K / N;
                rets = zeros(1, K, 'single');
                for i = 1:N
                    R = Vb(i);
                    for tt = Ts:-1:1
                        idx = (tt-1)*N + i;
                        R = bufR(idx) + gamma * R;
                        rets(idx) = R;
                    end
                end

                [aG, cG] = dlfeval(@a2c_grads, actorNet, criticNet, ...
                                   toDl(bufS(:, 1:K)), bufA(1:K), ...
                                   toDl(rets), entW);

                aG = clipGlobal(aG, clip_norm);
                cG = clipGlobal(cG, clip_norm);

                aIt = aIt + 1;
                [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
                cIt = cIt + 1;
                [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);

                nb = 0;
            end
        end

        learning_curve(ep) = ep_tp / simTime;
        entropy_curve(ep)  = ep_ent / simTime;
        if mod(ep, 25) == 0
            fprintf('  A2C v4 ep %3d/%d  cellTp=%.2f Mbps  H=%.3f  entW=%.3f\n', ...
                    ep, num_episodes, learning_curve(ep), entropy_curve(ep), entW);
        end
    end
end


function x = cond_gpu(x, useGPU)
    if useGPU, x = gpuArray(x); end
end


function [aGrad, cGrad] = a2c_grads(actorNet, criticNet, S, A, R, entW)
    V = forward(criticNet, S);
    adv = R - V;
    cLoss = mean(adv .^ 2);

    logits = forward(actorNet, S);
    m = max(logits, [], 1);
    logZ = m + log(sum(exp(logits - m), 1));
    logp_all = logits - logZ;                    % log-softmax, stable

    B = size(S, 2); Anum = size(logits, 1);
    mask = zeros(Anum, B, 'like', extractdata(logits));
    for b = 1:B, mask(A(b), b) = 1; end
    mask = dlarray(mask);
    logp = sum(logp_all .* mask, 1);

    % Detach + standardize advantages
    advD = double(gather(extractdata(adv)));
    sd = std(advD);
    if sd > 1e-6, advD = (advD - mean(advD)) / sd;
    else,         advD = advD - mean(advD);
    end
    advD = dlarray(cast(advD, 'like', extractdata(logits)));

    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);
    aLoss = -mean(logp .* advD) - entW * mean(entropy);

    cGrad = dlgradient(cLoss, criticNet.Learnables, 'RetainData', true);
    aGrad = dlgradient(aLoss, actorNet.Learnables);
end


function grads = clipGlobal(grads, maxNorm)
% Clip by the GLOBAL norm across all learnables (preserves direction).
    total = 0;
    for i = 1:height(grads)
        g = double(gather(extractdata(grads.Value{i})));
        total = total + sum(g(:).^2);
    end
    nrm = sqrt(total);
    if nrm > maxNorm
        sc = maxNorm / nrm;
        for i = 1:height(grads)
            grads.Value{i} = grads.Value{i} * sc;
        end
    end
end
