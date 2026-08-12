function [actorNet, criticNet, tp_per_user, bler_per_user, learning_curve] = ...
            DeepAC_AMC_Multi_GPU_v4(simTime, num_episodes, seed, reward_mode, scheduler_mode, N)
% v4 Deep A2C: baseline-relative CQI design + shared actor/critic across all N users.
% Action a in {-2..+2} is now an OFFSET from baseline_CQI derived from current SINR,
% not from agent's previous output. So action 0 -> identical to baseline.
% Works for arbitrary N; scales linearly with sample efficiency via parameter sharing.

    if nargin < 1 || isempty(simTime),        simTime = 100;              end
    if nargin < 2 || isempty(num_episodes),   num_episodes = 200;         end
    if nargin >= 3 && ~isempty(seed),         rng(seed);                  end
    if nargin < 4 || isempty(reward_mode),    reward_mode = 'throughput'; end
    if nargin < 5 || isempty(scheduler_mode), scheduler_mode = 'pf';      end
    if nargin < 6 || isempty(N),              N = 50;                     end

    log_path = fullfile(fileparts(mfilename('fullpath')), 'training_log_v4.txt');
    log_fid  = fopen(log_path, 'a');
    log = @(varargin) fprintf(log_fid, '[%s] %s\n', datestr(now,'HH:MM:SS'), sprintf(varargin{:}));
    log('Start DeepAC_v4: simTime=%d ep=%d N=%d mode=%s sched=%s', simTime, num_episodes, N, reward_mode, scheduler_mode);

    bsPos    = [500, 500];
    fc       = 2e9; hBS = 30; txPower = 43; BW = 10e6;
    total_RB = 110;

    actions     = [-2, -1, 0, 1, 2];
    num_actions = numel(actions);
    no_op_idx   = find(actions == 0);

    gamma     = 0.95;
    n_step    = 10;
    lr_actor  = 5e-4;
    lr_critic = 1e-3;
    entropy_w = 0.03;
    ema_alpha = 0.05;
    gradClipNorm     = 1.0;
    lambda_potential = 0.1;
    warmup_episodes  = 30;

    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;

    useGPU = false;
    try
        try, parallel.gpu.enableCUDAForwardCompatibility(true); catch, end
        if gpuDeviceCount > 0
            g = gpuDevice;
            useGPU = true;
            fprintf('GPU: %s, CC %s, %.1f GB free\n', g.Name, char(string(g.ComputeCapability)), g.AvailableMemory/2^30);
            log('GPU active: %s', g.Name);
        end
    catch ME
        warning('GPU check failed: %s. CPU fallback.', ME.message);
        log('GPU failed: %s -- CPU fallback', ME.message);
    end

    actor_bias_init = single([-0.5; -0.25; 1.0; -0.25; -0.5]);    % softer than v3
    actorLayers = [
        featureInputLayer(3, 'Name', 'in')
        fullyConnectedLayer(64, 'Name', 'fc1')
        reluLayer('Name', 'relu1')
        fullyConnectedLayer(64, 'Name', 'fc2')
        reluLayer('Name', 'relu2')
        fullyConnectedLayer(num_actions, 'Name', 'logits', 'Bias', actor_bias_init)
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

    learning_curve = zeros(num_episodes, 1);
    tp_per_user    = zeros(simTime, N);
    bler_per_user  = zeros(simTime, N);

    buf_capacity = n_step * N;
    buf_states  = zeros(3, buf_capacity, 'single');
    buf_actions = zeros(1, buf_capacity);
    buf_rewards = zeros(1, buf_capacity, 'single');
    buf_count   = 0;

    try, h_wait = waitbar(0, 'Deep A2C v4', 'Name', sprintf('Deep A2C v4 (N=%d, %s)', N, scheduler_mode));
    catch, h_wait = []; end

    nan_skips = 0; grad_clips = 0;
    t_start = tic;

    try
        for episode = 1:num_episodes
            [SINR_values, ~] = calculateControlledSINR_N(simTime, fc, hBS, txPower, BW, N, bsPos);

            R_emas       = zeros(1, N);
            prev_base_CQI = zeros(1, N);
            for i = 1:N
                idx = find(SINR_values(1, i) >= CQI_thresholds, 1, 'last');
                if isempty(idx), idx = min_CQI; end
                prev_base_CQI(i) = max(min_CQI, min(max_CQI, idx));
            end
            episode_tp_sum = 0;

            for t = 1:simTime
                % FIX (v4): derive baseline CQI from current SINR each TTI
                base_CQI = zeros(1, N);
                for i = 1:N
                    idx = find(SINR_values(t, i) >= CQI_thresholds, 1, 'last');
                    if isempty(idx), idx = min_CQI; end
                    base_CQI(i) = max(min_CQI, min(max_CQI, idx));
                end
                delta_CQI = max(min_delta, min(max_delta, base_CQI - prev_base_CQI));

                % Batched state across all N users
                S = single([base_CQI/15; delta_CQI/5; SINR_values(t,:)/30]);
                if useGPU, S_dl = dlarray(gpuArray(S), 'CB'); else, S_dl = dlarray(S, 'CB'); end
                probs = gather(extractdata(predict(actorNet, S_dl)));

                if episode <= warmup_episodes
                    blend = (warmup_episodes - episode + 1) / warmup_episodes * 0.3;
                    probs = (1 - blend) * probs + blend * (1 / num_actions);
                end
                probs = max(probs, 1e-8);
                probs = probs ./ sum(probs, 1);

                action_idx = zeros(1, N); sent_CQI = zeros(1, N);
                BLER_now = zeros(1, N);
                potential_rates = zeros(1, N); potential_TBS = zeros(1, N);
                for i = 1:N
                    a_idx = find(rand() <= cumsum(probs(:, i)), 1, 'first');
                    if isempty(a_idx), a_idx = num_actions; end
                    action_idx(i) = a_idx;

                    % FIX (v4): action = offset from BASELINE CQI, not from agent history
                    sent_CQI(i) = max(min_CQI, min(max_CQI, base_CQI(i) + actions(a_idx)));
                    mcs_i       = sent_CQI(i) - 1;
                    BLER_now(i) = estimateBLER_Enhanced(SINR_values(t,i), mcs_i);
                    potential_TBS(i)   = tbsFromMCSandRB(mcs_i, total_RB);
                    potential_rates(i) = (1 - BLER_now(i)) * potential_TBS(i) * 1e-3;
                end

                rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential_rates, total_RB);

                tp_now = zeros(1, N);
                for i = 1:N
                    if rb_alloc(i) > 0
                        tp_now(i) = (1 - BLER_now(i)) * tbsFromMCSandRB(sent_CQI(i)-1, rb_alloc(i)) * 1e-3;
                    end
                end
                R_emas = (1 - ema_alpha) * R_emas + ema_alpha * tp_now;
                episode_tp_sum = episode_tp_sum + sum(tp_now);

                if episode == num_episodes
                    tp_per_user(t, :)   = tp_now;
                    bler_per_user(t, :) = BLER_now;
                end

                for i = 1:N
                    if rb_alloc(i) > 0
                        actual_tbs = tbsFromMCSandRB(sent_CQI(i) - 1, rb_alloc(i));
                        reward_i = computeReward(BLER_now(i), actual_tbs, reward_mode);
                    else
                        reward_i = lambda_potential * computeReward(BLER_now(i), potential_TBS(i), reward_mode);
                    end
                    buf_count = buf_count + 1;
                    buf_states(:, buf_count) = S(:, i);
                    buf_actions(buf_count)   = action_idx(i);
                    buf_rewards(buf_count)   = single(reward_i);
                end
                prev_base_CQI = base_CQI;

                if buf_count >= buf_capacity || t == simTime
                    if t == simTime
                        V_boot = zeros(1, N, 'single');
                    else
                        base_CQI_next = zeros(1, N);
                        for i = 1:N
                            idx = find(SINR_values(t+1, i) >= CQI_thresholds, 1, 'last');
                            if isempty(idx), idx = min_CQI; end
                            base_CQI_next(i) = max(min_CQI, min(max_CQI, idx));
                        end
                        delta_CQI_next = max(min_delta, min(max_delta, base_CQI_next - prev_base_CQI));
                        sN = single([base_CQI_next/15; delta_CQI_next/5; SINR_values(t+1,:)/30]);
                        if useGPU, sN_dl = dlarray(gpuArray(sN), 'CB'); else, sN_dl = dlarray(sN, 'CB'); end
                        V_boot = gather(extractdata(predict(criticNet, sN_dl)));
                    end

                    K = buf_count; Tsteps = K / N;
                    returns = zeros(1, K, 'single');
                    for i = 1:N
                        R = V_boot(i);
                        for tt = Tsteps:-1:1
                            idx = (tt-1)*N + i;
                            R = buf_rewards(idx) + gamma * R;
                            returns(idx) = R;
                        end
                    end

                    if useGPU
                        S_batch = dlarray(gpuArray(buf_states(:,1:K)), 'CB');
                        R_batch = dlarray(gpuArray(returns), 'CB');
                    else
                        S_batch = dlarray(buf_states(:,1:K), 'CB');
                        R_batch = dlarray(returns, 'CB');
                    end
                    A_batch = buf_actions(1:K);

                    [aGrad, cGrad, lossA, lossC] = dlfeval(@ac_gradients, actorNet, criticNet, ...
                                             S_batch, A_batch, R_batch, entropy_w);

                    if any(isnan([gather(extractdata(lossA)), gather(extractdata(lossC))]))
                        nan_skips = nan_skips + 1;
                    else
                        [aGrad, ca] = clipGrads(aGrad, gradClipNorm);
                        [cGrad, cc] = clipGrads(cGrad, gradClipNorm);
                        grad_clips = grad_clips + ca + cc;
                        aIter = aIter + 1;
                        [actorNet, aTrAvg, aTrAvgSq] = adamupdate(actorNet, aGrad, aTrAvg, aTrAvgSq, aIter, lr_actor);
                        cIter = cIter + 1;
                        [criticNet, cTrAvg, cTrAvgSq] = adamupdate(criticNet, cGrad, cTrAvg, cTrAvgSq, cIter, lr_critic);
                    end

                    buf_count = 0;
                end
            end

            learning_curve(episode) = episode_tp_sum / simTime;
            if ~isempty(h_wait) && isvalid(h_wait)
                waitbar(episode/num_episodes, h_wait, ...
                    sprintf('Deep v4 N=%d ep %d/%d  CellTp=%.1f Mbps  (nan=%d clips=%d)', ...
                            N, episode, num_episodes, learning_curve(episode), nan_skips, grad_clips));
            end
            if mod(episode, 10) == 0
                log('ep %d/%d N=%d cellTp=%.2f nan=%d clips=%d', episode, num_episodes, N, learning_curve(episode), nan_skips, grad_clips);
            end
        end
    catch ME
        log('ERROR: %s', ME.message);
        for k = 1:numel(ME.stack), log('  at %s:%d (%s)', ME.stack(k).file, ME.stack(k).line, ME.stack(k).name); end
        if ~isempty(h_wait) && isvalid(h_wait), delete(h_wait); end
        fclose(log_fid);
        rethrow(ME);
    end

    elapsed = toc(t_start);
    log('Done in %.1f s', elapsed);
    fprintf('Deep A2C v4 done: %.1f s, NaN-skips=%d, clips=%d\n', elapsed, nan_skips, grad_clips);
    if ~isempty(h_wait) && isvalid(h_wait), delete(h_wait); end
    fclose(log_fid);
end


function [grads, n_clipped] = clipGrads(grads, maxNorm)
    n_clipped = 0;
    for i = 1:height(grads)
        g = grads.Value{i};
        nrm = double(gather(sqrt(sum(extractdata(g(:)).^2))));
        if nrm > maxNorm
            grads.Value{i} = g * (maxNorm / max(nrm, eps));
            n_clipped = n_clipped + 1;
        end
    end
end


function [actorGrad, criticGrad, actorLoss, criticLoss] = ac_gradients(actorNet, criticNet, states, actions, returns, entropy_w)
    V = forward(criticNet, states);
    advantage = returns - V;
    criticLoss = mean(advantage .^ 2);
    probs = forward(actorNet, states);
    B = size(states, 2); A = size(probs, 1);
    mask = zeros(A, B, 'like', extractdata(probs));
    for b = 1:B, mask(actions(b), b) = 1; end
    mask = dlarray(mask);
    selected = sum(probs .* mask, 1);
    logp     = log(selected + 1e-8);
    adv_detached = dlarray(extractdata(advantage));
    actorLossPG  = -mean(logp .* adv_detached);
    entropy = -sum(probs .* log(probs + 1e-8), 1);
    entLoss = -entropy_w * mean(entropy);
    actorLoss = actorLossPG + entLoss;
    criticGrad = dlgradient(criticLoss, criticNet.Learnables, 'RetainData', true);
    actorGrad  = dlgradient(actorLoss,  actorNet.Learnables);
end
