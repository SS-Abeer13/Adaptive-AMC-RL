function [actorNet, criticNet, dac_throughputs, dac_bler, dac_se, learning_curve_dac] = ...
            DeepAC_AMC_Simulation_GPU_v1(simTime, num_episodes, seed, reward_mode)
% GPU-accelerated Deep A2C for single-user AMC.
% - dlnetwork parameters in single precision on the GPU.
% - n-step rollout buffered as a single batch update.
% - Falls back to CPU/double if no compatible GPU.

    if nargin < 1 || isempty(simTime),      simTime = 1000;             end
    if nargin < 2 || isempty(num_episodes), num_episodes = 300;         end
    if nargin >= 3 && ~isempty(seed),       rng(seed);                  end
    if nargin < 4 || isempty(reward_mode),  reward_mode = 'throughput'; end

    cellRadius = 500; fc = 2e9; hBS = 30; hUE = 1.5; txPower = 43; BW = 10e6;

    actions     = [-2, -1, 0, 1, 2];
    num_actions = numel(actions);

    gamma     = 0.95;
    n_step    = 10;
    lr_actor  = 1e-3;
    lr_critic = 1e-3;
    entropy_w = 0.01;

    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;

    useGPU = false;
    try
        if gpuDeviceCount > 0
            g = gpuDevice;
            if double(string(g.ComputeCapability)) >= 6.0
                useGPU = true;
                fprintf('GPU active: %s, %.1f GB available\n', g.Name, g.AvailableMemory/2^30);
            end
        end
    catch ME
        warning('GPU check failed (%s). Falling back to CPU.', ME.message);
    end

    actorLayers = [
        featureInputLayer(3, 'Name', 'in')
        fullyConnectedLayer(64, 'Name', 'fc1')
        reluLayer('Name', 'relu1')
        fullyConnectedLayer(64, 'Name', 'fc2')
        reluLayer('Name', 'relu2')
        fullyConnectedLayer(num_actions, 'Name', 'logits')
        softmaxLayer('Name', 'softmax')
    ];
    criticLayers = [
        featureInputLayer(3, 'Name', 'in')
        fullyConnectedLayer(64, 'Name', 'fc1')
        reluLayer('Name', 'relu1')
        fullyConnectedLayer(64, 'Name', 'fc2')
        reluLayer('Name', 'relu2')
        fullyConnectedLayer(1, 'Name', 'value')
    ];
    actorNet  = dlnetwork(actorLayers);
    criticNet = dlnetwork(criticLayers);

    if useGPU
        actorNet  = dlupdate(@(x) gpuArray(single(x)), actorNet);
        criticNet = dlupdate(@(x) gpuArray(single(x)), criticNet);
    end

    aTrAvg = []; aTrAvgSq = []; aIter = 0;
    cTrAvg = []; cTrAvgSq = []; cIter = 0;

    CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, 10.3, ...
                      11.7, 14.1, 16.3, 18.7, 21.0, 22.7];

    learning_curve_dac = zeros(num_episodes, 1);
    dac_throughputs    = zeros(simTime, 1);
    dac_bler           = zeros(simTime, 1);
    dac_se             = zeros(simTime, 1);

    for episode = 1:num_episodes

        [SINR_values, ~] = calculateControlledSINR2(simTime, cellRadius, fc, ...
                                                    hBS, hUE, txPower, BW);

        current_CQI = find(SINR_values(1) >= CQI_thresholds, 1, 'last');
        current_CQI = max(min_CQI, min(max_CQI, current_CQI));
        prev_CQI    = current_CQI;
        delta_CQI   = 0;
        episode_tp  = 0;

        buf_states  = zeros(3, n_step, 'single');
        buf_actions = zeros(1, n_step);
        buf_rewards = zeros(1, n_step, 'single');
        step_in_buf = 0;

        for t = 1:simTime
            current_SINR = SINR_values(t);

            s_vec = single([current_CQI/15; delta_CQI/5; current_SINR/30]);
            if useGPU
                s_dl = dlarray(gpuArray(s_vec), 'CB');
            else
                s_dl = dlarray(s_vec, 'CB');
            end

            probs = gather(extractdata(predict(actorNet, s_dl)));
            probs = max(probs, 1e-8);
            probs = probs / sum(probs);

            action_idx = find(rand() <= cumsum(probs), 1, 'first');
            if isempty(action_idx), action_idx = num_actions; end
            action = actions(action_idx);

            new_CQI = max(min_CQI, min(max_CQI, current_CQI + action));

            dac_MCS = new_CQI - 1;
            [dac_TBS, ~, ~] = selectTBSFromSINR(current_SINR);
            BLER_t   = estimateBLER_Enhanced(current_SINR, dac_MCS);
            tp_Mbps  = (1 - BLER_t) * dac_TBS * 1e-3;
            se_bphz  = tp_Mbps * 1e6 / BW;

            if episode == num_episodes
                dac_throughputs(t) = tp_Mbps;
                dac_bler(t)        = BLER_t;
                dac_se(t)          = se_bphz;
            end
            episode_tp = episode_tp + tp_Mbps;

            reward_t = computeReward(BLER_t, dac_TBS, reward_mode);

            step_in_buf = step_in_buf + 1;
            buf_states(:, step_in_buf)  = s_vec;
            buf_actions(step_in_buf)    = action_idx;
            buf_rewards(step_in_buf)    = single(reward_t);

            new_delta   = max(min_delta, min(max_delta, new_CQI - prev_CQI));
            prev_CQI    = current_CQI;
            current_CQI = new_CQI;
            delta_CQI   = new_delta;

            if step_in_buf == n_step || t == simTime

                if t == simTime
                    V_boot = single(0);
                else
                    next_SINR = SINR_values(t+1);
                    sN = single([current_CQI/15; delta_CQI/5; next_SINR/30]);
                    if useGPU
                        sN_dl = dlarray(gpuArray(sN), 'CB');
                    else
                        sN_dl = dlarray(sN, 'CB');
                    end
                    V_boot = gather(extractdata(predict(criticNet, sN_dl)));
                end

                K = step_in_buf;
                returns = zeros(1, K, 'single');
                R = V_boot;
                for k = K:-1:1
                    R = buf_rewards(k) + gamma * R;
                    returns(k) = R;
                end

                if useGPU
                    S_batch = dlarray(gpuArray(buf_states(:,1:K)), 'CB');
                    R_batch = dlarray(gpuArray(returns), 'CB');
                else
                    S_batch = dlarray(buf_states(:,1:K), 'CB');
                    R_batch = dlarray(returns, 'CB');
                end
                A_batch = buf_actions(1:K);

                [aGrad, cGrad] = dlfeval(@ac_gradients, actorNet, criticNet, ...
                                         S_batch, A_batch, R_batch, entropy_w);

                aIter = aIter + 1;
                [actorNet, aTrAvg, aTrAvgSq] = adamupdate(actorNet, aGrad, ...
                                            aTrAvg, aTrAvgSq, aIter, lr_actor);
                cIter = cIter + 1;
                [criticNet, cTrAvg, cTrAvgSq] = adamupdate(criticNet, cGrad, ...
                                            cTrAvg, cTrAvgSq, cIter, lr_critic);

                step_in_buf = 0;
            end
        end

        learning_curve_dac(episode) = episode_tp / simTime;
        if mod(episode, 25) == 0
            fprintf('  ep %3d / %d   meanTp=%.2f Mbps\n', episode, num_episodes, learning_curve_dac(episode));
        end
    end
end


function [actorGrad, criticGrad] = ac_gradients(actorNet, criticNet, ...
                                                 states, actions, returns, entropy_w)
    V = forward(criticNet, states);
    advantage = returns - V;
    criticLoss = mean(advantage .^ 2);

    probs = forward(actorNet, states);

    B = size(states, 2);
    A = size(probs, 1);
    mask = zeros(A, B, 'like', extractdata(probs));
    for b = 1:B
        mask(actions(b), b) = 1;
    end
    mask = dlarray(mask);

    selected = sum(probs .* mask, 1);
    logp     = log(selected + 1e-8);

    adv_detached = dlarray(extractdata(advantage));
    actorLoss    = -mean(logp .* adv_detached);

    entropy = -sum(probs .* log(probs + 1e-8), 1);
    entLoss = -entropy_w * mean(entropy);

    totalActorLoss = actorLoss + entLoss;

    criticGrad = dlgradient(criticLoss, criticNet.Learnables, 'RetainData', true);
    actorGrad  = dlgradient(totalActorLoss, actorNet.Learnables);
end
