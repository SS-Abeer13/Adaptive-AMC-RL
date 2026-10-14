function [actorNet, criticNet, learning_curve, entropy_curve] = ...
            DeepA2C_Shared_v8(simTime, num_episodes, seed, env)
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
    learning_curve = zeros(num_episodes, 1);
    entropy_curve  = zeros(num_episodes, 1);

    % Experience buffer for scheduled transitions
    cap = n_step * N * 2;
    bufS = zeros(nFeat, cap, 'single');
    bufA = zeros(1, cap);
    bufR = zeros(1, cap, 'single');
    bufU = zeros(1, cap); % User ID tracking for individual returns
    nb = 0;

    for ep = 1:num_episodes
        % Linear entropy decay across autonomous training episodes
        entW = ent_start + (ent_end - ent_start) * (ep - 1) / max(num_episodes - 1, 1);

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
            ref  = baseCQI_v5(obsS(t,:) + off, env);
            dRef = max(minD, min(maxD, ref - prevRef));
            dS   = obsS(t,:) - obsS(max(t-1,1),:);
            t0   = max(t-4, 1);
            slope4 = (obsS(t,:) - obsS(t0,:)) / max(t - t0, 1);

            % Current instantaneous feature vector
            s_now = stateFeat_v8(env.state_tier, ref, dRef, obsS(t,:), dS, off, ...
                                 slope4, nk, H, meta.speeds(t,:), burstObsM(t,:), ...
                                 meta.delays, R_emas, ctx);

            % Update sliding temporal history
            histS(:,:,2:L_seq) = histS(:,:,1:L_seq-1);
            histS(:,:,1) = s_now;

            % Flatten temporal sequence into nFeat x N
            S_temporal = reshape(permute(histS, [1, 3, 2]), nFeat, N);

            % Forward actor pass
            [logits, P] = forward_actor(Wa, S_temporal);
            ep_ent = ep_ent + mean(-sum(P .* log(P + 1e-12), 1));

            % Sample action per user
            aIdx = zeros(1, N);
            sent = zeros(1, N);
            pot  = zeros(1, N);
            for i = 1:N
                a = find(rand <= cumsum(P(:, i)), 1, 'first');
                if isempty(a), a = nA; end
                aIdx(i) = a;
                sent(i) = max(minC, min(maxC, ref(i) + A(a)));
                if env.harq_on && H.pend(i)
                    pot(i) = tbsFromMCSandRB(H.mcs(i), env.total_RB) * 1e-3;
                else
                    pot(i) = tbsFromMCSandRB(sent(i)-1, env.total_RB) * 1e-3;
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
            % Scheduled Credit Assignment: Update ONLY Scheduled Users
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
                end
            end
            prevRef = ref;

            % Update networks when buffer reaches capacity or at episode end
            if nb >= cap || (t == simTime && nb > 0)
                % Forward critic for bootstrap value
                Vb = forward_critic(Wc, S_temporal);

                % Compute discounted returns (vectorized)
                rets = bufR(1:nb) + gamma * single(Vb(bufU(1:nb)));

                % Compute policy and value gradients
                [aG, cG] = dlfeval(@a2c_grads_v8, actorNet, criticNet, ...
                                   toDl(bufS(:, 1:nb)), bufA(1:nb), toDl(rets), entW);

                % Gradient clipping & Adam parameter update
                aG = clipGlobal(aG, clip_norm);
                cG = clipGlobal(cG, clip_norm);
                aIt = aIt + 1;
                [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
                cIt = cIt + 1;
                [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);

                % Update extracted weights
                Wa = extract_weights(actorNet);
                Wc = extract_weights(criticNet);
                nb = 0;
            end
        end

        learning_curve(ep) = ep_tp / simTime;
        entropy_curve(ep)  = ep_ent / simTime;

        if mod(ep, 25) == 0 || ep == num_episodes
            fprintf('  Deep A2C v8 ep %3d/%d | CellTp = %5.2f Mbps | Policy Entropy = %5.3f | entW = %.3f\n', ...
                    ep, num_episodes, learning_curve(ep), entropy_curve(ep), entW);
        end
    end
end

function [aGrad, cGrad] = a2c_grads_v8(actorNet, criticNet, S, Aacts, R, entW)
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

    advD = double(gather(extractdata(adv)));
    sd = std(advD);
    if sd > 1e-6
        advD = (advD - mean(advD)) / sd;
    else
        advD = advD - mean(advD);
    end
    advD = dlarray(cast(advD, 'like', extractdata(logits)));

    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);
    aLoss = -mean(logp .* advD) - entW * mean(entropy);

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
