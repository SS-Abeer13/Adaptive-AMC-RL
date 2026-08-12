function [actorNet, criticNet, tp_per_user, bler_per_user, learning_curve] = ...
            DeepAC_AMC_Multi_GPU_v1(simTime, num_episodes, seed, reward_mode, scheduler_mode)
% Shared-network Deep A2C for N=5 users with CUDA forward compat,
% gradient clipping, NaN guard, waitbar progress, and error logging.

    if nargin < 1 || isempty(simTime),        simTime = 100;              end
    if nargin < 2 || isempty(num_episodes),   num_episodes = 100;         end
    if nargin >= 3 && ~isempty(seed),         rng(seed);                  end
    if nargin < 4 || isempty(reward_mode),    reward_mode = 'throughput'; end
    if nargin < 5 || isempty(scheduler_mode), scheduler_mode = 'pf';      end

    log_path = fullfile(fileparts(mfilename('fullpath')), 'training_log.txt');
    log_fid  = fopen(log_path, 'a');
    log = @(varargin) fprintf(log_fid, '[%s] %s\n', datestr(now,'HH:MM:SS'), sprintf(varargin{:}));
    log('Start DeepAC_Multi_GPU: simTime=%d ep=%d mode=%s sched=%s', simTime, num_episodes, reward_mode, scheduler_mode);

    N        = 5;
    bsPos    = [500, 500];
    fc       = 2e9;
    hBS      = 30;
    txPower  = 43;
    BW       = 10e6;
    total_RB = 110;

    actions     = [-2, -1, 0, 1, 2];
    num_actions = numel(actions);

    gamma     = 0.95;
    n_step    = 10;
    lr_actor  = 5e-4;          % lowered from 1e-3 for stability
    lr_critic = 1e-3;
    entropy_w = 0.05;          % raised from 0.01 to prevent policy collapse
    ema_alpha = 0.05;
    gradClipNorm = 1.0;

    max_CQI = 15; min_CQI = 1; max_delta = 5; min_delta = -5;

    % ===== GPU detect with forward-compat for Blackwell (sm_120, RTX 50xx) =====
    useGPU = false;
    try
        try
            parallel.gpu.enableCUDAForwardCompatibility(true);
            log('CUDA forward compatibility enabled');
        catch ME_fwd
            log('CUDA forward-compat not available: %s', ME_fwd.message);
        end
        if gpuDeviceCount > 0
            g = gpuDevice;
            useGPU = true;
            fprintf('GPU: %s, CC %s, %.1f GB free\n', g.Name, char(string(g.ComputeCapability)), g.AvailableMemory/2^30);
            log('GPU active: %s CC=%s mem=%.1fGB', g.Name, char(string(g.ComputeCapability)), g.AvailableMemory/2^30);
        end
    catch ME
        warning('GPU check failed (%s). CPU fallback.', ME.message);
        log('GPU failed: %s -- CPU fallback', ME.message);
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

    learning_curve = zeros(num_episodes, 1);
    tp_per_user    = zeros(simTime, N);
    bler_per_user  = zeros(simTime, N);

    buf_capacity = n_step * N;
    buf_states  = zeros(3, buf_capacity, 'single');
    buf_actions = zeros(1, buf_capacity);
    buf_rewards = zeros(1, buf_capacity, 'single');
    buf_count   = 0;

    % ===== Waitbar =====
    try
        h_wait = waitbar(0, 'Initializing Deep A2C...', 'Name', sprintf('Deep A2C (%s)', scheduler_mode));
    catch
        h_wait = [];
    end

    nan_skips = 0;
    grad_clips = 0;
    t_start = tic;

    try
        for episode = 1:num_episodes

            [S1,S2,S3,S4,S5,~,~,~,~,~] = calculateControlledSINR2(simTime, fc, hBS, txPower, BW, N, bsPos);
            SINR_values = [S1, S2, S3, S4, S5];

            cur_CQI = zeros(1, N); prev_CQI = zeros(1, N); delta_CQI = zeros(1, N);
            for i = 1:N
                idx = find(SINR_values(1, i) >= CQI_thresholds, 1, 'last');
                if isempty(idx), idx = min_CQI; end
                cur_CQI(i)  = max(min_CQI, min(max_CQI, idx));
                prev_CQI(i) = cur_CQI(i);
            end

            R_emas = zeros(1, N);
            episode_tp_sum = 0;

            for t = 1:simTime
                S = single([cur_CQI/15; delta_CQI/5; SINR_values(t,:)/30]);
                if useGPU, S_dl = dlarray(gpuArray(S), 'CB'); else, S_dl = dlarray(S, 'CB'); end
                probs = gather(extractdata(predict(actorNet, S_dl)));
                probs = max(probs, 1e-8);
                probs = probs ./ sum(probs, 1);

                action_idx = zeros(1, N); new_CQI = zeros(1, N);
                BLER_now = zeros(1, N); potential_rates = zeros(1, N);
                for i = 1:N
                    a_idx = find(rand() <= cumsum(probs(:, i)), 1, 'first');
                    if isempty(a_idx), a_idx = num_actions; end
                    action_idx(i) = a_idx;
                    new_CQI(i)  = max(min_CQI, min(max_CQI, cur_CQI(i) + actions(a_idx)));
                    mcs_i       = new_CQI(i) - 1;
                    BLER_now(i) = estimateBLER_Enhanced(SINR_values(t,i), mcs_i);
                    potential_rates(i) = (1 - BLER_now(i)) * tbsFromMCSandRB(mcs_i, total_RB) * 1e-3;
                end

                rb_alloc = schedule_users(scheduler_mode, t, N, R_emas, potential_rates, total_RB);

                tp_now = zeros(1, N);
                for i = 1:N
                    if rb_alloc(i) > 0
                        tp_now(i) = (1 - BLER_now(i)) * tbsFromMCSandRB(new_CQI(i)-1, rb_alloc(i)) * 1e-3;
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
                        actual_tbs = tbsFromMCSandRB(new_CQI(i) - 1, rb_alloc(i));
                        reward_i = computeReward(BLER_now(i), actual_tbs, reward_mode);
                    else
                        reward_i = 0;
                    end
                    buf_count = buf_count + 1;
                    buf_states(:, buf_count) = S(:, i);
                    buf_actions(buf_count)   = action_idx(i);
                    buf_rewards(buf_count)   = single(reward_i);
                end
                for i = 1:N
                    new_delta = max(min_delta, min(max_delta, new_CQI(i) - prev_CQI(i)));
                    prev_CQI(i)  = cur_CQI(i);
                    cur_CQI(i)   = new_CQI(i);
                    delta_CQI(i) = new_delta;
                end

                if buf_count >= buf_capacity || t == simTime
                    if t == simTime
                        V_boot = zeros(1, N, 'single');
                    else
                        sN = single([cur_CQI/15; delta_CQI/5; SINR_values(t+1,:)/30]);
                        if useGPU, sN_dl = dlarray(gpuArray(sN), 'CB'); else, sN_dl = dlarray(sN, 'CB'); end
                        V_boot = gather(extractdata(predict(criticNet, sN_dl)));
                    end

                    K = buf_count;
                    Tsteps  = K / N;
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

                    % NaN guard
                    if any(isnan([gather(extractdata(lossA)), gather(extractdata(lossC))]))
                        nan_skips = nan_skips + 1;
                        log('Episode %d step %d: NaN loss, skipping update', episode, t);
                    else
                        % Per-parameter gradient clipping
                        [aGrad, clippedA] = clipGrads(aGrad, gradClipNorm);
                        [cGrad, clippedC] = clipGrads(cGrad, gradClipNorm);
                        grad_clips = grad_clips + clippedA + clippedC;

                        aIter = aIter + 1;
                        [actorNet, aTrAvg, aTrAvgSq] = adamupdate(actorNet, aGrad, ...
                                                aTrAvg, aTrAvgSq, aIter, lr_actor);
                        cIter = cIter + 1;
                        [criticNet, cTrAvg, cTrAvgSq] = adamupdate(criticNet, cGrad, ...
                                                cTrAvg, cTrAvgSq, cIter, lr_critic);
                    end

                    buf_count = 0;
                end
            end

            learning_curve(episode) = episode_tp_sum / simTime;

            if ~isempty(h_wait) && isvalid(h_wait)
                waitbar(episode/num_episodes, h_wait, ...
                    sprintf('Episode %d/%d  CellTp=%.2f Mbps  (NaN-skip=%d, clips=%d)', ...
                            episode, num_episodes, learning_curve(episode), nan_skips, grad_clips));
            end
            if mod(episode, 10) == 0
                log('ep %d/%d cellTp=%.2f nan=%d clips=%d', episode, num_episodes, learning_curve(episode), nan_skips, grad_clips);
            end
        end
    catch ME
        log('ERROR: %s', ME.message);
        for k = 1:numel(ME.stack)
            log('  at %s:%d (%s)', ME.stack(k).file, ME.stack(k).line, ME.stack(k).name);
        end
        if ~isempty(h_wait) && isvalid(h_wait), delete(h_wait); end
        fclose(log_fid);
        rethrow(ME);
    end

    elapsed = toc(t_start);
    log('Done in %.1f s. NaN-skips=%d, grad-clips=%d', elapsed, nan_skips, grad_clips);
    fprintf('Deep A2C done: %.1f s, NaN-skips=%d, clips=%d\n', elapsed, nan_skips, grad_clips);
    if ~isempty(h_wait) && isvalid(h_wait), delete(h_wait); end
    fclose(log_fid);
end


function [grads, num_clipped] = clipGrads(grads, maxNorm)
    num_clipped = 0;
    for i = 1:height(grads)
        g = grads.Value{i};
        nrm = double(gather(sqrt(sum(extractdata(g(:)).^2))));
        if nrm > maxNorm
            grads.Value{i} = g * (maxNorm / max(nrm, eps));
            num_clipped = num_clipped + 1;
        end
    end
end


function [actorGrad, criticGrad, actorLoss, criticLoss] = ac_gradients(actorNet, criticNet, ...
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
    actorLossPG  = -mean(logp .* adv_detached);

    entropy  = -sum(probs .* log(probs + 1e-8), 1);
    entLoss  = -entropy_w * mean(entropy);

    actorLoss = actorLossPG + entLoss;

    criticGrad = dlgradient(criticLoss, criticNet.Learnables, 'RetainData', true);
    actorGrad  = dlgradient(actorLoss,  actorNet.Learnables);
end
