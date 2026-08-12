function [actorNet, criticNet, learning_curve, entropy_curve] = ...
            DeepA2C_Shared_v7(simTime, num_episodes, seed, env)
% DeepA2C_Shared_v7  Shared-network n-step A2C (v7 environment).
% If env.bc_warm_eps > 0, the first bc_warm_eps episodes behavior-clone
% the FixedPU comparator before RL fine-tuning begins.
    if ~isempty(seed), rng(seed); end
    N = env.N; A = env.actions; nA = numel(A);
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;

    gamma = env.gamma; n_step = 10;
    lr_actor = 5e-4; lr_critic = 1e-3;
    ent_start = 0.05; ent_end = 0.001; clip_norm = 5.0;

    nSched = numel(env.sched_list);
    if upper(env.state_tier) == 'A', nBase = 5; else, nBase = 11; end
    nFeat = nBase + nSched;

    actorLayers = [
        featureInputLayer(nFeat, 'Name', 'in')
        fullyConnectedLayer(96, 'Name', 'fc1'); reluLayer('Name','r1')
        fullyConnectedLayer(96, 'Name', 'fc2'); reluLayer('Name','r2')
        fullyConnectedLayer(nA, 'Name', 'logits')];
    criticLayers = [
        featureInputLayer(nFeat, 'Name', 'in')
        fullyConnectedLayer(96, 'Name', 'fc1'); reluLayer('Name','r1')
        fullyConnectedLayer(96, 'Name', 'fc2'); reluLayer('Name','r2')
        fullyConnectedLayer(1, 'Name', 'value')];
    actorNet  = dlnetwork(actorLayers);
    criticNet = dlnetwork(criticLayers);
    toDl = @(x) dlarray(single(x), 'CB');

    aAvg=[]; aAvgSq=[]; aIt=0; cAvg=[]; cAvgSq=[]; cIt=0;
    learning_curve = zeros(num_episodes,1); entropy_curve = zeros(num_episodes,1);

    cap = n_step * N;
    bufS = zeros(nFeat, cap, 'single'); bufA = zeros(1, cap); bufR = zeros(1, cap, 'single');
    nb = 0;

    bcEps = 0;
    if isfield(env, 'bc_warm_eps') && ~isempty(env.bc_warm_eps)
        bcEps = round(env.bc_warm_eps);
    end
    % entW_bc kept soft (not 0) so the BC clone doesn't saturate the
    % logits; post-BC entropy anneal starts low (see 'es' below) so
    % fine-tuning doesn't re-randomize the clone.
    entW_bc = 0.03;

    for ep = 1:(bcEps + num_episodes)
        isBC = ep <= bcEps;
        epR  = ep - bcEps;
        if isBC
            entW = entW_bc;
        else
            if bcEps > 0, es = 0.01; else, es = ent_start; end
            entW = es + (ent_end-es)*(epR-1)/max(num_episodes-1,1);
        end
        sched = sampleSched_v5(env);
        [~, sOneHot] = schedContext_v5(sched, env);
        ctx = single(repmat(sOneHot, 1, N));
        [Strue, ~, meta] = generateChannel_v7(simTime, env);
        obsS = cqiFeedback_v7(Strue, env, meta.delays);

        burstObsM = zeros(simTime, N);
        for i = 1:N
            idx = max((1:simTime).' - meta.delays(i), 1);
            burstObsM(:, i) = double(meta.burst(idx));
        end

        aTgt = zeros(1, N);
        if isBC
            for i = 1:N
                [dc, vc] = userClass_v7(meta.delays(i), mean(meta.speeds(:,i)));
                [~, aTgt(i)] = min(abs(A - env.fixed_class_tab(dc, vc)));
            end
        end

        off = zeros(1, N); H = harqInit_v7(N); nk = zeros(1, N);
        prevRef = baseCQI_v5(obsS(1,:) + off, env);
        R_emas = zeros(1,N); ema = 0.05; ep_tp = 0; ep_ent = 0;

        for t = 1:simTime
            ref  = baseCQI_v5(obsS(t,:) + off, env);
            dRef = max(minD, min(maxD, ref - prevRef));
            dS   = obsS(t,:) - obsS(max(t-1,1),:);
            t0 = max(t-4, 1);
            slope4 = (obsS(t,:) - obsS(t0,:)) / max(t - t0, 1);
            S = stateFeat_v7(env.state_tier, ref, dRef, obsS(t,:), dS, off, ...
                             slope4, nk, H, meta.speeds(t,:), burstObsM(t,:), ctx);

            logits = extractdata(predict(actorNet, toDl(S)));
            logits = double(logits) - max(logits, [], 1);
            P = exp(logits) ./ sum(exp(logits), 1);
            ep_ent = ep_ent + mean(-sum(P.*log(P+1e-12), 1));

            aIdx = zeros(1,N); sent = zeros(1,N); pot = zeros(1,N);
            for i = 1:N
                if isBC
                    a = aTgt(i);
                else
                    a = find(rand <= cumsum(P(:,i)), 1, 'first');
                    if isempty(a), a = nA; end
                end
                aIdx(i) = a;
                sent(i) = max(minC, min(maxC, ref(i) + A(a)));
                if env.harq_on && H.pend(i)
                    pot(i) = tbsFromMCSandRB(H.mcs(i), env.total_RB) * 1e-3;
                else
                    pot(i) = tbsFromMCSandRB(sent(i)-1, env.total_RB) * 1e-3;
                end
            end

            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            [tp_now, off, H, ~, nEv] = txStep_v7(sent, Strue(t,:), rb, off, H, env);
            schedM = rb > 0;
            nk(schedM) = 0.7*nk(schedM) + 0.3*double(nEv(schedM));
            nk(~schedM) = 0.95*nk(~schedM);
            R_emas = (1-ema)*R_emas + ema*tp_now; ep_tp = ep_tp + sum(tp_now);
            r_cell = sum(tp_now) / env.reward_scale;

            for i = 1:N
                nb = nb + 1; bufS(:,nb) = S(:,i); bufA(nb) = aIdx(i); bufR(nb) = single(r_cell);
            end
            prevRef = ref;

            if nb >= cap || t == simTime
                tn = min(t+1, simTime);
                refN  = baseCQI_v5(obsS(tn,:) + off, env);
                dRefN = max(minD, min(maxD, refN - ref));
                dSN = obsS(tn,:) - obsS(max(tn-1,1),:);
                t0n = max(tn-4, 1);
                slope4N = (obsS(tn,:) - obsS(t0n,:)) / max(tn - t0n, 1);
                sN = stateFeat_v7(env.state_tier, refN, dRefN, obsS(tn,:), dSN, off, ...
                                  slope4N, nk, H, meta.speeds(tn,:), burstObsM(tn,:), ctx);
                Vb = extractdata(predict(criticNet, toDl(sN)));

                K = nb; Ts = K/N; rets = zeros(1,K,'single');
                for i = 1:N
                    R = Vb(i);
                    for tt = Ts:-1:1
                        idx = (tt-1)*N + i; R = bufR(idx) + gamma*R; rets(idx) = R;
                    end
                end

                if isBC
                    [aG, cG] = dlfeval(@bc_grads, actorNet, criticNet, ...
                                       toDl(bufS(:,1:K)), bufA(1:K), toDl(rets), entW);
                else
                    [aG, cG] = dlfeval(@a2c_grads, actorNet, criticNet, ...
                                       toDl(bufS(:,1:K)), bufA(1:K), toDl(rets), entW);
                end
                aG = clipGlobal(aG, clip_norm); cG = clipGlobal(cG, clip_norm);
                aIt = aIt+1; [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
                cIt = cIt+1; [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);
                nb = 0;
            end
        end
        if isBC
            if mod(ep, 25) == 0
                fprintf('  A2C v7 BC ep %3d/%d  cellTp=%.2f  H=%.3f\n', ...
                        ep, bcEps, ep_tp/simTime, ep_ent/simTime);
            end
        else
            learning_curve(epR) = ep_tp / simTime; entropy_curve(epR) = ep_ent / simTime;
            if mod(epR, 25) == 0
                fprintf('  A2C v7 ep %3d/%d  cellTp=%.2f  H=%.3f  entW=%.3f\n', ...
                        epR, num_episodes, learning_curve(epR), entropy_curve(epR), entW);
            end
        end
    end
end


function [aGrad, cGrad] = a2c_grads(actorNet, criticNet, S, Aacts, R, entW)
    V = forward(criticNet, S);
    adv = R - V;
    cLoss = mean(adv.^2);

    logits = forward(actorNet, S);
    m = max(logits, [], 1);
    logZ = m + log(sum(exp(logits - m), 1));
    logp_all = logits - logZ;
    B = size(S,2); An = size(logits,1);
    mask = zeros(An, B, 'like', extractdata(logits));
    for b = 1:B, mask(Aacts(b), b) = 1; end
    mask = dlarray(mask);
    logp = sum(logp_all .* mask, 1);

    advD = double(gather(extractdata(adv)));
    sd = std(advD);
    if sd > 1e-6, advD = (advD - mean(advD))/sd; else, advD = advD - mean(advD); end
    advD = dlarray(cast(advD, 'like', extractdata(logits)));

    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);
    aLoss = -mean(logp .* advD) - entW*mean(entropy);

    cGrad = dlgradient(cLoss, criticNet.Learnables, 'RetainData', true);
    aGrad = dlgradient(aLoss, actorNet.Learnables);
end


function [aGrad, cGrad] = bc_grads(actorNet, criticNet, S, Atgt, R, entW)
% bc_grads  Actor: cross-entropy on FixedPU's actions. Critic: MSE on
% the cloned rollout's observed n-step returns.
    V = forward(criticNet, S);
    cLoss = mean((R - V).^2);

    logits = forward(actorNet, S);
    m = max(logits, [], 1);
    logZ = m + log(sum(exp(logits - m), 1));
    logp_all = logits - logZ;
    B = size(S,2); An = size(logits,1);
    mask = zeros(An, B, 'like', extractdata(logits));
    for b = 1:B, mask(Atgt(b), b) = 1; end
    mask = dlarray(mask);
    ce = -mean(sum(logp_all .* mask, 1));

    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);
    aLoss = ce - entW*mean(entropy);

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
