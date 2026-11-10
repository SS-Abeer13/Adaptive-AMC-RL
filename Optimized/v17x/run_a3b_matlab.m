function run_a3b_matlab()
% run_a3b_matlab  Benchmark inference latency in MATLAB for A3b.
% Times state construction + forward pass + action selection for all scheduled users.
% Also exports actor networks to ONNX and weights for Python onnxruntime / NumPy.

    here = fileparts(mfilename('fullpath'));
    v17_dir = fullfile(fileparts(here), 'v17');
    addpath(v17_dir);
    addpath(fullfile(here, 'g6'));
    v17_setup;
    
    outdir = fullfile(here, 'Dataset');
    if ~exist(outdir, 'dir'), mkdir(outdir); end
    
    fprintf('=== Loading Models and Calibrations ===\n');
    % 1. NR2 seed 1
    s_nr2 = load(fullfile(outdir, 'ckpt', 'nr2', 'train_seed_1.mat'));
    net_nr2 = s_nr2.out.a2c;
    L_nr2 = net_nr2.Learnables;
    Wa_nr2.w1 = extractdata(L_nr2.Value{L_nr2.Layer == "fc1" & L_nr2.Parameter == "Weights"});
    Wa_nr2.b1 = extractdata(L_nr2.Value{L_nr2.Layer == "fc1" & L_nr2.Parameter == "Bias"});
    Wa_nr2.w2 = extractdata(L_nr2.Value{L_nr2.Layer == "fc2" & L_nr2.Parameter == "Weights"});
    Wa_nr2.b2 = extractdata(L_nr2.Value{L_nr2.Layer == "fc2" & L_nr2.Parameter == "Bias"});
    isL3 = (L_nr2.Layer == "logits" | L_nr2.Layer == "value") & L_nr2.Parameter == "Weights";
    Wa_nr2.w3 = extractdata(L_nr2.Value{isL3});
    isB3 = (L_nr2.Layer == "logits" | L_nr2.Layer == "value") & L_nr2.Parameter == "Bias";
    Wa_nr2.b3 = extractdata(L_nr2.Value{isB3});
    
    % 2. M1 seed 1
    s_m1 = load(fullfile(v17_dir, 'Dataset', 'results_v17_M1_dl_rtt8.mat'));
    net_m1 = s_m1.results.policies.A2C{1};
    L_m1 = net_m1.Learnables;
    Wa_m1.w1 = extractdata(L_m1.Value{L_m1.Layer == "fc1" & L_m1.Parameter == "Weights"});
    Wa_m1.b1 = extractdata(L_m1.Value{L_m1.Layer == "fc1" & L_m1.Parameter == "Bias"});
    Wa_m1.w2 = extractdata(L_m1.Value{L_m1.Layer == "fc2" & L_m1.Parameter == "Weights"});
    Wa_m1.b2 = extractdata(L_m1.Value{L_m1.Layer == "fc2" & L_m1.Parameter == "Bias"});
    isL3 = (L_m1.Layer == "logits" | L_m1.Layer == "value") & L_m1.Parameter == "Weights";
    Wa_m1.w3 = extractdata(L_m1.Value{isL3});
    isB3 = (L_m1.Layer == "logits" | L_m1.Layer == "value") & L_m1.Parameter == "Bias";
    Wa_m1.b3 = extractdata(L_m1.Value{isB3});
    
    % 3. Context-joint-500
    ctxj_tab = read_ctxj_from_tables(fullfile(outdir, 'cal500_tables.txt'));
    
    % 4. Environment template
    env = s_m1.results.env;
    env.resid_actions = [-1, 0, 1];
    env.fixed_offset = -2; % NR2 non-oracle base offset
    
    fprintf('=== Exporting ONNX Models and Weights ===\n');
    onnx_nr2_path = fullfile(outdir, 'actor_nr2.onnx');
    onnx_m1_path = fullfile(outdir, 'actor_m1.onnx');
    exportONNXNetwork(net_nr2, onnx_nr2_path);
    exportONNXNetwork(net_m1, onnx_m1_path);
    fprintf('ONNX exported: %s and %s\n', onnx_nr2_path, onnx_m1_path);
    
    % Export test vectors for bit/float comparison
    rng(42);
    X_test = randn(57, 1000, 'single');
    logits_nr2_test = Wa_nr2.w3 * max(0, Wa_nr2.w2 * max(0, Wa_nr2.w1 * X_test + Wa_nr2.b1) + Wa_nr2.b2) + Wa_nr2.b3;
    logits_m1_test = Wa_m1.w3 * max(0, Wa_m1.w2 * max(0, Wa_m1.w1 * X_test + Wa_m1.b1) + Wa_m1.b2) + Wa_m1.b3;
    
    mat_export_path = fullfile(outdir, 'a3b_export.mat');
    save(mat_export_path, 'Wa_nr2', 'Wa_m1', 'X_test', 'logits_nr2_test', 'logits_m1_test', '-v7');
    fprintf('Weights and test vectors exported: %s\n', mat_export_path);
    
    % System / Platform info
    [~, cpu_raw] = system('wmic cpu get name');
    cpu_lines = splitlines(strtrim(cpu_raw));
    cpu_model = strtrim(cpu_lines{end});
    matlab_ver = version;
    threads = maxNumCompThreads;
    
    fprintf('Platform: %s | MATLAB %s | %d threads\n', cpu_model, matlab_ver, threads);
    
    % Benchmark Configuration
    n_users_list = [10, 50, 100];
    n_warm = 1000;
    n_ttis = 100000;
    
    schemes = {'NR2', 'M1', 'Fixed', 'Context-joint-500', 'OLLA'};
    modes = {'batched', 'per_user'};
    
    results = struct();
    res_idx = 0;
    
    fprintf('\n=== Starting MATLAB Latency Benchmark (100k TTIs, warm-up 1k excluded) ===\n');
    
    for u_idx = 1:numel(n_users_list)
        N = n_users_list(u_idx);
        fprintf('\n--- Benchmarking N = %d users ---\n', N);
        
        % Pre-generate input state structures for N users
        rng(1000 + N);
        ref = single(randi([0, 15], 1, N));
        prevRef = ref;
        obs_SINR = randn(1, N, 'single');
        prev_obs = obs_SINR;
        obs_4 = obs_SINR;
        off = zeros(1, N, 'single');
        nk = rand(1, N, 'single');
        H = struct('pend', rand(1, N) > 0.5, 'nret', single(randi([0, 3], 1, N)), ...
                   'proc_busy', rand(N, 8) > 0.7, 'proc_isRetx', zeros(N, 8), ...
                   'proc_bits', randi([1000, 8000], N, 8), 'nproc', 8);
        speeds = rand(1, N, 'single') * 30;
        burstObs = rand(1, N, 'single');
        delays = single(randi([1, 8], 1, N));
        r_ema = rand(1, N, 'single');
        sOneHot = zeros(numel(env.sched_list), 1, 'single'); sOneHot(1) = 1;
        ctx = repmat(sOneHot, 1, N);
        
        Q = trafficInit_v17(env, N);
        Q.has = true(1, N);
        Q.rem = single(randi([1000, 16000], 1, N));
        Q.dl = single(randi([1, 10], 1, N));
        
        X_feat = struct('age', single(randi([1, 5], 1, N)), ...
                        'dev', randn(1, N, 'single'), ...
                        'cn', single(0.1), ...
                        'Q', Q, 't', single(1), ...
                        'ack8', zeros(1, N, 'single'), ...
                        'tsince', zeros(1, N, 'single'), ...
                        'offtrend', zeros(1, N, 'single'), ...
                        'H', H);
                    
        du = 0.5 * 0.1 / 0.9;
        dd = 0.5;
        lim = 10;
        ack = rand(1, N) > 0.1;
        
        % Fixed offset
        f_off = -2;
        
        for s_idx = 1:numel(schemes)
            sch = schemes{s_idx};
            for m_idx = 1:numel(modes)
                mode = modes{m_idx};
                
                fprintf('Running %-18s [%-8s, N=%3d] ... ', sch, mode, N);
                
                % Timed run
                times = zeros(n_ttis, 1);
                
                switch sch
                    case 'NR2'
                        times = bench_actor(Wa_nr2, 'O', f_off, env, N, mode, n_warm, n_ttis, ...
                            ref, prevRef, obs_SINR, prev_obs, obs_4, off, nk, H, speeds, burstObs, delays, r_ema, ctx, X_feat);
                    case 'M1'
                        times = bench_actor(Wa_m1, 'O', 0, env, N, mode, n_warm, n_ttis, ...
                            ref, prevRef, obs_SINR, prev_obs, obs_4, off, nk, H, speeds, burstObs, delays, r_ema, ctx, X_feat);
                    case 'Fixed'
                        times = bench_fixed(f_off, N, mode, n_warm, n_ttis, ref);
                    case 'Context-joint-500'
                        times = bench_ctxj(ctxj_tab, N, mode, n_warm, n_ttis, ref, Q.dl, delays, speeds, H.proc_busy);
                    case 'OLLA'
                        times = bench_olla(du, dd, lim, N, mode, n_warm, n_ttis, off, ack, obs_SINR, env);
                end
                
                med_us = median(times);
                p99_us = prctile(times, 99);
                p999_us = prctile(times, 99.9);
                max_us = max(times);
                
                fprintf('median: %6.2f us | p99: %6.2f us | p99.9: %6.2f us | max: %6.2f us\n', ...
                    med_us, p99_us, p999_us, max_us);
                
                res_idx = res_idx + 1;
                results(res_idx).scheme = sch;
                results(res_idx).runtime = 'MATLAB';
                results(res_idx).mode = mode;
                results(res_idx).users = N;
                results(res_idx).median_us = med_us;
                results(res_idx).p99_us = p99_us;
                results(res_idx).p99_9_us = p999_us;
                results(res_idx).max_us = max_us;
            end
        end
    end
    
    save(fullfile(outdir, 'a3b_matlab_results.mat'), 'results', 'cpu_model', 'matlab_ver', 'threads');
    fprintf('\nMATLAB benchmark complete! Saved to %s\n', fullfile(outdir, 'a3b_matlab_results.mat'));
end

% =========================================================================
% Benchmarking subroutines
% =========================================================================

function times = bench_actor(Wa, tier, base_off, env, N, mode, n_warm, n_ttis, ...
    ref, prevRef, obs_SINR, prev_obs, obs_4, off, nk, H, speeds, burstObs, delays, r_ema, ctx, X_feat)

    histS = zeros(19, N, 3, 'single');
    delta_act = single([-1, 0, 1]);
    minD = single(-3); maxD = single(3);
    
    if strcmp(mode, 'batched')
        % Warmup
        for it = 1:n_warm
            dRef = max(minD, min(maxD, ref - prevRef));
            dS   = obs_SINR - prev_obs;
            slope4 = (obs_SINR - obs_4) * 0.25;
            xtra = featExtra_v17(env, X_feat);
            s_now = stateFeat_v17(tier, ref, dRef, obs_SINR, dS, off, slope4, nk, H, speeds, burstObs, delays, r_ema, ctx, xtra);
            histS(:, :, 2:3) = histS(:, :, 1:2);
            histS(:, :, 1) = s_now;
            S_temp = reshape(permute(histS, [1, 3, 2]), 57, N);
            out = Wa.w3 * max(0, Wa.w2 * max(0, Wa.w1 * S_temp + Wa.b1) + Wa.b2) + Wa.b3;
            [~, a] = max(out, [], 1);
            cqi = max(0, min(15, ref + base_off + delta_act(a))); %#ok<NASGU>
        end
        
        times = zeros(n_ttis, 1);
        for it = 1:n_ttis
            t0 = tic;
            dRef = max(minD, min(maxD, ref - prevRef));
            dS   = obs_SINR - prev_obs;
            slope4 = (obs_SINR - obs_4) * 0.25;
            xtra = featExtra_v17(env, X_feat);
            s_now = stateFeat_v17(tier, ref, dRef, obs_SINR, dS, off, slope4, nk, H, speeds, burstObs, delays, r_ema, ctx, xtra);
            histS(:, :, 2:3) = histS(:, :, 1:2);
            histS(:, :, 1) = s_now;
            S_temp = reshape(permute(histS, [1, 3, 2]), 57, N);
            out = Wa.w3 * max(0, Wa.w2 * max(0, Wa.w1 * S_temp + Wa.b1) + Wa.b2) + Wa.b3;
            [~, a] = max(out, [], 1);
            cqi = max(0, min(15, ref + base_off + delta_act(a))); %#ok<NASGU>
            times(it) = toc(t0) * 1e6;
        end
    else
        % Per-user loop
        cqi = zeros(1, N, 'single');
        % Warmup
        for it = 1:n_warm
            xtra_all = featExtra_v17(env, X_feat);
            for i = 1:N
                dRef_i = max(minD, min(maxD, ref(i) - prevRef(i)));
                dS_i   = obs_SINR(i) - prev_obs(i);
                slope4_i = (obs_SINR(i) - obs_4(i)) * 0.25;
                s_now_i = stateFeat_v17(tier, ref(i), dRef_i, obs_SINR(i), dS_i, off(i), ...
                    slope4_i, nk(i), struct('pend', H.pend(i), 'nret', H.nret(i)), ...
                    speeds(i), burstObs(i), delays(i), r_ema(i), ctx(:, i), xtra_all(:, i));
                histS(:, i, 2:3) = histS(:, i, 1:2);
                histS(:, i, 1) = s_now_i;
                S_temp_i = reshape(histS(:, i, :), 57, 1);
                out_i = Wa.w3 * max(0, Wa.w2 * max(0, Wa.w1 * S_temp_i + Wa.b1) + Wa.b2) + Wa.b3;
                [~, a_i] = max(out_i);
                cqi(i) = max(0, min(15, ref(i) + base_off + delta_act(a_i)));
            end
        end
        
        times = zeros(n_ttis, 1);
        for it = 1:n_ttis
            t0 = tic;
            xtra_all = featExtra_v17(env, X_feat);
            for i = 1:N
                dRef_i = max(minD, min(maxD, ref(i) - prevRef(i)));
                dS_i   = obs_SINR(i) - prev_obs(i);
                slope4_i = (obs_SINR(i) - obs_4(i)) * 0.25;
                s_now_i = stateFeat_v17(tier, ref(i), dRef_i, obs_SINR(i), dS_i, off(i), ...
                    slope4_i, nk(i), struct('pend', H.pend(i), 'nret', H.nret(i)), ...
                    speeds(i), burstObs(i), delays(i), r_ema(i), ctx(:, i), xtra_all(:, i));
                histS(:, i, 2:3) = histS(:, i, 1:2);
                histS(:, i, 1) = s_now_i;
                S_temp_i = reshape(histS(:, i, :), 57, 1);
                out_i = Wa.w3 * max(0, Wa.w2 * max(0, Wa.w1 * S_temp_i + Wa.b1) + Wa.b2) + Wa.b3;
                [~, a_i] = max(out_i);
                cqi(i) = max(0, min(15, ref(i) + base_off + delta_act(a_i)));
            end
            times(it) = toc(t0) * 1e6;
        end
    end
end

function times = bench_fixed(f_off, N, mode, n_warm, n_ttis, ref)
    if strcmp(mode, 'batched')
        for it = 1:n_warm
            cqi = max(0, min(15, ref + f_off)); %#ok<NASGU>
        end
        times = zeros(n_ttis, 1);
        for it = 1:n_ttis
            t0 = tic;
            cqi = max(0, min(15, ref + f_off)); %#ok<NASGU>
            times(it) = toc(t0) * 1e6;
        end
    else
        cqi = zeros(1, N, 'single');
        for it = 1:n_warm
            for i = 1:N
                cqi(i) = max(0, min(15, ref(i) + f_off));
            end
        end
        times = zeros(n_ttis, 1);
        for it = 1:n_ttis
            t0 = tic;
            for i = 1:N
                cqi(i) = max(0, min(15, ref(i) + f_off));
            end
            times(it) = toc(t0) * 1e6;
        end
    end
end

function times = bench_ctxj(ctxj_tab, N, mode, n_warm, n_ttis, ref, Q_dl, delays, speeds, proc_busy)
    t = 1;
    busy_cnt = sum(proc_busy, 2)';
    sl = Q_dl - t + 1;
    
    if strcmp(mode, 'batched')
        for it = 1:n_warm
            b = 1 + (sl > 2) + (sl > 5);
            d = 1 + (delays > 4);
            v = 1 + (speeds >= 10) + (speeds > 20);
            u = 1 + (busy_cnt > 0);
            idx = b + 3*(d-1) + 6*(v-1) + 18*(u-1);
            ctxjOff = ctxj_tab(idx);
            cqi = max(0, min(15, ref + ctxjOff)); %#ok<NASGU>
        end
        times = zeros(n_ttis, 1);
        for it = 1:n_ttis
            t0 = tic;
            b = 1 + (sl > 2) + (sl > 5);
            d = 1 + (delays > 4);
            v = 1 + (speeds >= 10) + (speeds > 20);
            u = 1 + (busy_cnt > 0);
            idx = b + 3*(d-1) + 6*(v-1) + 18*(u-1);
            ctxjOff = ctxj_tab(idx);
            cqi = max(0, min(15, ref + ctxjOff)); %#ok<NASGU>
            times(it) = toc(t0) * 1e6;
        end
    else
        cqi = zeros(1, N, 'single');
        for it = 1:n_warm
            for i = 1:N
                sl_i = sl(i);
                if sl_i <= 2, b_i = 1; elseif sl_i <= 5, b_i = 2; else, b_i = 3; end
                if delays(i) <= 4, d_i = 1; else, d_i = 2; end
                sp_i = speeds(i);
                if sp_i < 10, v_i = 1; elseif sp_i <= 20, v_i = 2; else, v_i = 3; end
                if busy_cnt(i) == 0, u_i = 1; else, u_i = 2; end
                ctxjOff_i = ctxj_tab(b_i, d_i, v_i, u_i);
                cqi(i) = max(0, min(15, ref(i) + ctxjOff_i));
            end
        end
        times = zeros(n_ttis, 1);
        for it = 1:n_ttis
            t0 = tic;
            for i = 1:N
                sl_i = sl(i);
                if sl_i <= 2, b_i = 1; elseif sl_i <= 5, b_i = 2; else, b_i = 3; end
                if delays(i) <= 4, d_i = 1; else, d_i = 2; end
                sp_i = speeds(i);
                if sp_i < 10, v_i = 1; elseif sp_i <= 20, v_i = 2; else, v_i = 3; end
                if busy_cnt(i) == 0, u_i = 1; else, u_i = 2; end
                ctxjOff_i = ctxj_tab(b_i, d_i, v_i, u_i);
                cqi(i) = max(0, min(15, ref(i) + ctxjOff_i));
            end
            times(it) = toc(t0) * 1e6;
        end
    end
end

function times = bench_olla(du, dd, lim, N, mode, n_warm, n_ttis, off_init, ack, obs_SINR, env)
    off = off_init;
    if strcmp(mode, 'batched')
        for it = 1:n_warm
            off = off + du .* ack - dd .* (1 - ack);
            off = max(-lim, min(lim, off));
            cqi = baseCQI_v17(obs_SINR + off, env); %#ok<NASGU>
        end
        times = zeros(n_ttis, 1);
        for it = 1:n_ttis
            t0 = tic;
            off = off + du .* ack - dd .* (1 - ack);
            off = max(-lim, min(lim, off));
            cqi = baseCQI_v17(obs_SINR + off, env); %#ok<NASGU>
            times(it) = toc(t0) * 1e6;
        end
    else
        cqi = zeros(1, N, 'single');
        for it = 1:n_warm
            for i = 1:N
                off(i) = off(i) + du * ack(i) - dd * (1 - ack(i));
                off(i) = max(-lim, min(lim, off(i)));
                cqi(i) = baseCQI_v17(obs_SINR(i) + off(i), env);
            end
        end
        times = zeros(n_ttis, 1);
        for it = 1:n_ttis
            t0 = tic;
            for i = 1:N
                off(i) = off(i) + du * ack(i) - dd * (1 - ack(i));
                off(i) = max(-lim, min(lim, off(i)));
                cqi(i) = baseCQI_v17(obs_SINR(i) + off(i), env);
            end
            times(it) = toc(t0) * 1e6;
        end
    end
end

function tab = read_ctxj_from_tables(fpath)
    tab = zeros(3, 2, 3, 2);
    lines = strsplit(fileread(fpath), sprintf('\n'));
    for i = 1:numel(lines)
        line = strtrim(lines{i});
        tok = regexp(line, 'cell\((\d+),(\d+),(\d+),(\d+)\) = ([+-]?\d+)', 'tokens', 'once');
        if ~isempty(tok)
            b = str2double(tok{1});
            d = str2double(tok{2});
            v = str2double(tok{3});
            u = str2double(tok{4}) + 1;
            off_val = str2double(tok{5});
            tab(b, d, v, u) = off_val;
        end
    end
end
