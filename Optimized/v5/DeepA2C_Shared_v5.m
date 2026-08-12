function [actorNet, criticNet, learning_curve, entropy_curve] = ...
            DeepA2C_Shared_v5(simTime, num_episodes, seed, env)
% DeepA2C_Shared_v5  Shared-network n-step A2C, baseline-relative encoding.
%
% Merges the two v4 lines:
%   * action = OFFSET from baseline CQI (case2_3 v4): offset 0 == baseline,
%     so the agent starts near baseline and learns only the correction needed
%     to compensate the delayed/noisy CQI -> real headroom over the baseline.
%   * training fixes (optimized/v4): rewards normalized by env.reward_scale;
%     per-batch advantage standardization; GLOBAL gradient-norm clip (5.0);
%     time-limit-aware V(s_T) bootstrap; entropy annealed 0.05 -> 0.001;
%     log-softmax loss. No bias init, no warmup blend, no imitation bonus
%     (those caused the v3 collapse and v4 oscillation).
%
% One network is shared across all N users (centralized training,
% decentralized execution); pooling N users' transitions is the deep agent's
% sample-efficiency advantage over per-user tables.
%
% State features (4): [base_CQI/15; d_base/5; obs_SINR/30; obs_SINR_trend/5].

    if ~isempty(seed), rng(seed); end
    N = env.N; A = env.actions; nA = numel(A);
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;

    gamma = env.gamma; n_step = 10;
    lr_actor = 5e-4; lr_critic = 1e-3;
    ent_start = 0.05; ent_end = 0.001; clip_norm = 5.0;

    nSched = numel(env.sched_list);
    nFeat  = 4 + nSched;          % 4 base features + observable regime one-hot

    actorLayers = [
        featureInputLayer(nFeat, 'Name', 'in')
        fullyConnectedLayer(64, 'Name', 'fc1'); reluLayer('Name','r1')
        fullyConnectedLayer(64, 'Name', 'fc2'); reluLayer('Name','r2')
        fullyConnectedLayer(nA, 'Name', 'logits')];
    criticLayers = [
        featureInputLayer(nFeat, 'Name', 'in')
        fullyConnectedLayer(64, 'Name', 'fc1'); reluLayer('Name','r1')
        fullyConnectedLayer(64, 'Name', 'fc2'); reluLayer('Name','r2')
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
    catch, useGPU = false; end
    toDl = @(x) dlarray(cond_gpu(single(x), useGPU), 'CB');

    aAvg=[]; aAvgSq=[]; aIt=0; cAvg=[]; cAvgSq=[]; cIt=0;
    learning_curve = zeros(num_episodes,1); entropy_curve = zeros(num_episodes,1);

    cap = n_step * N;
    bufS = zeros(nFeat, cap, 'single'); bufA = zeros(1, cap); bufR = zeros(1, cap, 'single');
    nb = 0;

    for ep = 1:num_episodes
        entW = ent_start + (ent_end-ent_start)*(ep-1)/max(num_episodes-1,1);
        sched = sampleSched_v5(env);
        [~, sOneHot] = schedContext_v5(sched, env);   % observable regime
        ctx = single(repmat(sOneHot, 1, N));
        [Strue, ~, ~] = generateChannel_v5(simTime, env);
        [obsS, ~] = cqiFeedback_v5(Strue, env);
        prevBase = baseCQI_v5(obsS(1, :), env);
        R_emas = zeros(1,N); ema = 0.05; ep_tp = 0; ep_ent = 0;

        for t = 1:simTime
            base = baseCQI_v5(obsS(t, :), env);
            dB   = max(minD, min(maxD, base - prevBase));
            dS   = obsS(t,:) - obsS(max(t-1,1),:);
            S = single([base/15; dB/5; obsS(t,:)/30; dS/5; ctx]);

            logits = gather(extractdata(predict(actorNet, toDl(S))));
            logits = double(logits) - max(logits, [], 1);
            P = exp(logits) ./ sum(exp(logits), 1);
            ep_ent = ep_ent + mean(-sum(P.*log(P+1e-12), 1));

            aIdx = zeros(1,N); sent = zeros(1,N); bler = zeros(1,N); pot = zeros(1,N);
            for i = 1:N
                a = find(rand <= cumsum(P(:,i)), 1, 'first');
                if isempty(a), a = nA; end
                aIdx(i) = a;
                sent(i) = max(minC, min(maxC, base(i) + A(a)));
                bler(i) = estimateBLER_v5(Strue(t,i), sent(i)-1);
                pot(i)  = (1-bler(i))*tbsFromMCSandRB(sent(i)-1, env.total_RB)*1e-3;
            end

            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            tp_now = zeros(1,N);
            for i = 1:N
                if rb(i) > 0, tp_now(i) = (1-bler(i))*tbsFromMCSandRB(sent(i)-1, rb(i))*1e-3; end
            end
            R_emas = (1-ema)*R_emas + ema*tp_now; ep_tp = ep_tp + sum(tp_now);

            for i = 1:N
                if rb(i) > 0, r = computeReward_v5(bler(i), tbsFromMCSandRB(sent(i)-1, rb(i)), env);
                else, r = 0; end
                nb = nb + 1; bufS(:,nb) = S(:,i); bufA(nb) = aIdx(i); bufR(nb) = single(r);
            end
            prevBase = base;

            if nb >= cap || t == simTime
                tn = min(t+1, simTime);
                baseN = baseCQI_v5(obsS(tn,:), env);
                dBN = max(minD, min(maxD, baseN - base));
                dSN = obsS(tn,:) - obsS(max(tn-1,1),:);
                sN = single([baseN/15; dBN/5; obsS(tn,:)/30; dSN/5; ctx]);
                Vb = gather(extractdata(predict(criticNet, toDl(sN))));   % bootstrap V(s')

                K = nb; Ts = K/N; rets = zeros(1,K,'single');
                for i = 1:N
                    R = Vb(i);
                    for tt = Ts:-1:1
                        idx = (tt-1)*N + i; R = bufR(idx) + gamma*R; rets(idx) = R;
                    end
                end

                [aG, cG] = dlfeval(@a2c_grads, actorNet, criticNet, ...
                                   toDl(bufS(:,1:K)), bufA(1:K), toDl(rets), entW);
                aG = clipGlobal(aG, clip_norm); cG = clipGlobal(cG, clip_norm);
                aIt = aIt+1; [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
                cIt = cIt+1; [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);
                nb = 0;
            end
        end
        learning_curve(ep) = ep_tp / simTime; entropy_curve(ep) = ep_ent / simTime;
        if mod(ep, 25) == 0
            fprintf('  A2C v5 ep %3d/%d  cellTp=%.2f  H=%.3f  entW=%.3f\n', ...
                    ep, num_episodes, learning_curve(ep), entropy_curve(ep), entW);
        end
    end
end


function x = cond_gpu(x, useGPU), if useGPU, x = gpuArray(x); end, end


function [aGrad, cGrad] = a2c_grads(actorNet, criticNet, S, Aacts, R, entW)
    V = forward(criticNet, S);
    adv = R - V;
    cLoss = mean(adv.^2);

    logits = forward(actorNet, S);
    m = max(logits, [], 1);
    logZ = m + log(sum(exp(logits - m), 1));
    logp_all = logits - logZ;                       % log-softmax

    B = size(S,2); An = size(logits,1);
    mask = zeros(An, B, 'like', extractdata(logits));
    for b = 1:B, mask(Aacts(b), b) = 1; end
    mask = dlarray(mask);
    logp = sum(logp_all .* mask, 1);

    advD = double(gather(extractdata(adv)));        % detach + standardize
    sd = std(advD);
    if sd > 1e-6, advD = (advD - mean(advD))/sd; else, advD = advD - mean(advD); end
    advD = dlarray(cast(advD, 'like', extractdata(logits)));

    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);
    aLoss = -mean(logp .* advD) - entW*mean(entropy);

    cGrad = dlgradient(cLoss, criticNet.Learnables, 'RetainData', true);
    aGrad = dlgradient(aLoss, actorNet.Learnables);
end


function grads = clipGlobal(grads, maxNorm)
    total = 0;
    for i = 1:height(grads)
        gg = double(gather(extractdata(grads.Value{i}))); total = total + sum(gg(:).^2);
    end
    nrm = sqrt(total);
    if nrm > maxNorm
        sc = maxNorm/nrm;
        for i = 1:height(grads), grads.Value{i} = grads.Value{i}*sc; end
    end
end
