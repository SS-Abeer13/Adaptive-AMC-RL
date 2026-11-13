function stage_r3_nr2diag(ctx)
% stage_r3_nr2diag  NR2 diagnostics: speed breakdown, warm-up, fairness, action shares.
% Spec: paper/proposals/R_presub_prereg.md §6 and §12 (Amendment 8, Freeze v9).
% Units:
%   repro
%   instr_seed_K (K = 1..n_seeds)
%   warm_olla
%   export
% Outputs:
%   Dataset/presub/peruser.csv
%   Dataset/presub/actions.csv
%   Dataset/REPORT_r3_nr2diag.txt
%   Dataset/stage_r3_nr2diag.done

    addpath(ctx.v17);
    addpath(fullfile(ctx.v17, 'headroom'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    v17_setup;

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(ctx.v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; env_M1 = R_M1.env;

    n_seeds = ternary(ctx.smoke, 2, 10);
    n_eval  = ternary(ctx.smoke, 2, 500);
    n_repro = ternary(ctx.smoke, 2, 20);

    ctx.hbf(sprintf('r3_nr2diag start: n_seeds=%d, n_eval=%d, n_repro=%d', n_seeds, n_eval, n_repro));

    % Set up NR2 environment (Fixed base rule, offset -2)
    envN2 = env_M1;
    envN2.base_rule_force = 'fixed';
    envN2.fixed_offset = -2;
    [envN2, ~] = selectBaseRule_v17n(envN2, 2, o.simTime);

    % Load stored NR2 eval.mat
    eval_mat_file = fullfile(ctx.ckptdir, 'nr2', 'eval.mat');
    if ~exist(eval_mat_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'eval.mat');
        if exist(fallback, 'file'), eval_mat_file = fallback; else, error('ckpt/nr2/eval.mat missing'); end
    end
    stored_eval = load(eval_mat_file);
    st_out = stored_eval.out;

    % Load calibration files for comparators
    tables_file = fullfile(ctx.root, 'Dataset', 'cal500_tables.txt');
    if ~exist(tables_file, 'file')
        error('cal500_tables.txt missing');
    end

    % Fixed-500
    e_f = envN2; e_f.fixed_offset = -2;

    % Context-500 from composite_table.mat
    comp_ckpt = fullfile(ctx.root, 'Dataset', 'ckpt', 'g6a', 'composite_table.mat');
    if exist(comp_ckpt, 'file')
        S_comp = load(comp_ckpt);
        ctx_tab = S_comp.out.ctx_tab;
    else
        ctx_tab = envN2.ctx_tab;
    end
    e_ctx = envN2; e_ctx.ctx_tab = ctx_tab;

    % Context-joint-500
    e_ctxj = envN2; e_ctxj.ctxj_tab = read_ctxj_from_tables(tables_file);

    % ---- 1. Unit: repro ----
    ctx.unit('repro', @() unit_repro(envN2, e_f, e_ctxj, st_out, n_repro, o, ctx));

    % ---- 2. Units: instr_seed_K ----
    seed_data = cell(1, n_seeds);
    for s = 1:n_seeds
        u_name = sprintf('instr_seed_%d', s);
        seed_data{s} = ctx.unit(u_name, @() unit_instr_seed(envN2, st_out, s, n_eval, o, ctx));
    end

    % ---- 3. Unit: warm_olla ----
    warm_data = ctx.unit('warm_olla', @() unit_warm_olla(envN2, e_ctx, e_ctxj, st_out, n_eval, o, ctx));

    % ---- 4. Unit: export ----
    ctx.unit('export', @() unit_export(seed_data, warm_data, n_seeds, n_eval, ctx));

    ctx.hbf('r3_nr2diag done successfully');
end

% =========================================================================
function out = unit_repro(envN2, e_f, e_ctxj, st_out, n_repro, o, ctx)
    ctx.hbf(sprintf('repro: checking bit-identity on first %d NR2 traces', n_repro));
    b0 = min(envN2.burn_in, o.simTime - 1);

    ckpt1 = fullfile(ctx.ckptdir, 'nr2', 'train_seed_1.mat');
    if ~exist(ckpt1, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'train_seed_1.mat');
        if exist(fallback, 'file'), ckpt1 = fallback; else, error('train_seed_1.mat missing'); end
    end
    s1 = load(ckpt1); pol1 = s1.out.a2c;

    for j = 1:n_repro
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
        rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envN2);
        obsS = cqiFeedback_v17(Strue, envN2, meta.delays);
        meta.trace_id = j;
        rng(crn_seed); U = rand(o.simTime, envN2.N);

        % NR2 seed 1
        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol1, Strue, obsS, envN2, meta, U);
        [~, ~, p] = userMetric_v17(envN2, tp, inf, b0);
        stored_val = st_out.nr2_seeds(1, j);
        if abs(p - stored_val) ~= 0
            error('v17x:r3:repro', 'REPRO failed for NR2 seed 1 trace %d: diff=%.3e', j, abs(p - stored_val));
        end

        % Fixed-500
        rng(1020000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed', [], Strue, obsS, e_f, meta, U);
        [~, ~, p] = userMetric_v17(e_f, tp, inf, b0);
        stored_f = st_out.cmp.fixed500(j);
        if abs(p - stored_f) ~= 0
            error('v17x:r3:repro', 'REPRO failed for Fixed-500 trace %d: diff=%.3e', j, abs(p - stored_f));
        end

        % Context-joint-500
        rng(1020000 + 100*j + 10*99 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxj', [], Strue, obsS, e_ctxj, meta, U);
        [~, ~, p] = userMetric_v17(e_ctxj, tp, inf, b0);
        stored_cj = st_out.cmp.ctxj500(j);
        if abs(p - stored_cj) ~= 0
            error('v17x:r3:repro', 'REPRO failed for Context-joint-500 trace %d: diff=%.3e', j, abs(p - stored_cj));
        end
    end
    ctx.hbf('repro: bit-identity verified (max_abs_diff = 0)');
    out = struct('repro_pass', true, 'n_repro', n_repro);
end

% =========================================================================
function out = unit_instr_seed(envN2, st_out, s, n_eval, o, ctx)
    ctx.hbf(sprintf('instr_seed_%d: instrumented eval on %d traces', s, n_eval));
    b0 = min(envN2.burn_in, o.simTime - 1);
    N = envN2.N;

    ckpt_file = fullfile(ctx.ckptdir, 'nr2', sprintf('train_seed_%d.mat', s));
    if ~exist(ckpt_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', sprintf('train_seed_%d.mat', s));
        if exist(fallback, 'file'), ckpt_file = fallback; else, error('train_seed_%d.mat missing', s); end
    end
    s_data = load(ckpt_file); pol = s_data.out.a2c;

    okU_s = zeros(n_eval, N);
    resU_s = zeros(n_eval, N);
    speeds_s = zeros(n_eval, N);

    max_acts = n_eval * o.simTime * N;
    act_seed   = s * ones(max_acts, 1, 'int32');
    act_trace  = zeros(max_acts, 1, 'int32');
    act_busy   = zeros(max_acts, 1, 'int32');
    act_slack  = zeros(max_acts, 1, 'single');
    act_haspkt = zeros(max_acts, 1, 'int32');
    act_speed  = zeros(max_acts, 1, 'single');
    act_burst  = zeros(max_acts, 1, 'int32');
    act_action = zeros(max_acts, 1, 'int32');
    act_count  = 0;

    for j = 1:n_eval
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
        rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envN2);
        obsS = cqiFeedback_v17(Strue, envN2, meta.delays);
        meta.trace_id = j;
        rng(crn_seed); U = rand(o.simTime, envN2.N);

        rng(1020000 + 100*j + 10*8 + s);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_hr('a2c_v17', pol, Strue, obsS, envN2, meta, U);
        [~, ~, p] = userMetric_v17(envN2, tp, inf, b0);

        stored_val = st_out.nr2_seeds(s, j);
        if abs(p - stored_val) ~= 0
            error('v17x:r3:eval_mismatch', 'Mismatch on seed %d trace %d: got %.6f, stored %.6f', s, j, p, stored_val);
        end

        okU_s(j, :) = inf.okU;
        resU_s(j, :) = inf.resU;
        speeds_s(j, :) = mean(meta.speeds, 1);

        hr_log = inf.hr_log;
        COLS = inf.hr_cols;
        c_t    = find(strcmp(COLS, 't'));
        c_u    = find(strcmp(COLS, 'u'));
        c_obs11= find(strcmp(COLS, 'obs_11'));
        c_obs12= find(strcmp(COLS, 'obs_12'));
        c_obs14= find(strcmp(COLS, 'obs_14'));
        c_act  = find(strcmp(COLS, 'action_taken'));

        n_dec = size(hr_log, 1);
        if n_dec > 0
            idx_start = act_count + 1;
            idx_end   = act_count + n_dec;

            t_vec = round(hr_log(:, c_t));
            u_vec = round(hr_log(:, c_u));

            act_trace(idx_start:idx_end) = int32(j);
            act_busy(idx_start:idx_end)  = int32(round(hr_log(:, c_obs14) * 8));
            act_slack(idx_start:idx_end) = single(hr_log(:, c_obs11));
            act_haspkt(idx_start:idx_end)= int32(round(hr_log(:, c_obs12)));

            sp_sub = zeros(n_dec, 1, 'single');
            br_sub = zeros(n_dec, 1, 'int32');
            for k = 1:n_dec
                sp_sub(k) = single(meta.speeds(t_vec(k), u_vec(k)));
                br_sub(k) = int32(meta.burst(t_vec(k)));
            end
            act_speed(idx_start:idx_end) = sp_sub;
            act_burst(idx_start:idx_end) = br_sub;
            act_action(idx_start:idx_end)= int32(round(hr_log(:, c_act)));

            act_count = idx_end;
        end
    end

    out = struct( ...
        'seed', s, ...
        'okU', okU_s, ...
        'resU', resU_s, ...
        'speeds', speeds_s, ...
        'act_seed',   act_seed(1:act_count), ...
        'act_trace',  act_trace(1:act_count), ...
        'act_busy',   act_busy(1:act_count), ...
        'act_slack',  act_slack(1:act_count), ...
        'act_haspkt', act_haspkt(1:act_count), ...
        'act_speed',  act_speed(1:act_count), ...
        'act_burst',  act_burst(1:act_count), ...
        'act_action', act_action(1:act_count) ...
    );
end

% =========================================================================
function out = unit_warm_olla(envN2, e_ctx, e_ctxj, st_out, n_eval, o, ctx)
    ctx.hbf(sprintf('warm_olla: running warm OLLA and comparators on %d traces', n_eval));
    b0 = min(envN2.burn_in, o.simTime - 1);
    N = envN2.N;

    envWarm = envN2;
    envWarm.olla_warm_ttis = 200;

    warm_olla_vals = zeros(1, n_eval);
    okU_ctx = zeros(n_eval, N);
    resU_ctx = zeros(n_eval, N);
    speeds_eval = zeros(n_eval, N);

    for j = 1:n_eval
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
        rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envN2);
        obsS = cqiFeedback_v17(Strue, envN2, meta.delays);
        meta.trace_id = j;
        rng(crn_seed); U = rand(o.simTime, envN2.N);
        speeds_eval(j, :) = mean(meta.speeds, 1);

        % 1. Warm OLLA (k=2)
        rng(1020000 + 100*j + 10*2 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('olla', [], Strue, obsS, envWarm, meta, U);
        [~, ~, warm_olla_vals(j)] = userMetric_v17(envWarm, tp, inf, b0);

        % 2. Context-500 (k=7) per-user metrics
        rng(1020000 + 100*j + 10*7 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxtab', [], Strue, obsS, e_ctx, meta, U);
        [~, ~, p] = userMetric_v17(e_ctx, tp, inf, b0);
        stored_c = st_out.cmp.ctx500(j);
        if abs(p - stored_c) ~= 0
            error('v17x:r3:ctx500_mismatch', 'Context-500 mismatch on trace %d: diff=%.3e', j, abs(p - stored_c));
        end
        okU_ctx(j, :) = inf.okU;
        resU_ctx(j, :) = inf.resU;
    end

    okU_ctxj = st_out.okU_ctxj;
    resU_ctxj = st_out.resU_ctxj;
    if size(okU_ctxj, 1) == N && size(okU_ctxj, 2) >= n_eval
        okU_ctxj = okU_ctxj(:, 1:n_eval).';
        resU_ctxj = resU_ctxj(:, 1:n_eval).';
    else
        okU_ctxj = okU_ctxj(1:n_eval, :);
        resU_ctxj = resU_ctxj(1:n_eval, :);
    end

    out = struct( ...
        'warm_olla_vals', warm_olla_vals, ...
        'okU_ctx', okU_ctx, ...
        'resU_ctx', resU_ctx, ...
        'okU_ctxj', okU_ctxj, ...
        'resU_ctxj', resU_ctxj, ...
        'speeds', speeds_eval ...
    );
end

% =========================================================================
function out = unit_export(seed_data, warm_data, n_seeds, n_eval, ctx)
    ctx.hbf('export: exporting peruser.csv, actions.csv, and REPORT_r3_nr2diag.txt');
    presub_dir = fullfile(ctx.outdir, 'presub');
    if ~exist(presub_dir, 'dir'), mkdir(presub_dir); end

    peruser_csv = fullfile(presub_dir, 'peruser.csv');
    fid = fopen(peruser_csv, 'w');
    fprintf(fid, 'scheme,seed,trace,user,ok,res,speed_mps\n');
    N = size(warm_data.speeds, 2);

    for s = 1:n_seeds
        sd = seed_data{s};
        for j = 1:n_eval
            for u = 1:N
                fprintf(fid, 'NR2,%d,%d,%d,%.1f,%.1f,%.4f\n', ...
                    s, j, u, sd.okU(j, u), sd.resU(j, u), sd.speeds(j, u));
            end
        end
    end

    for j = 1:n_eval
        for u = 1:N
            fprintf(fid, 'ctxj500,0,%d,%d,%.1f,%.1f,%.4f\n', ...
                j, u, warm_data.okU_ctxj(j, u), warm_data.resU_ctxj(j, u), warm_data.speeds(j, u));
        end
    end

    for j = 1:n_eval
        for u = 1:N
            fprintf(fid, 'ctx500,0,%d,%d,%.1f,%.1f,%.4f\n', ...
                j, u, warm_data.okU_ctx(j, u), warm_data.resU_ctx(j, u), warm_data.speeds(j, u));
        end
    end
    fclose(fid);
    ctx.hbf(sprintf('peruser.csv written (%s)', peruser_csv));

    actions_csv = fullfile(presub_dir, 'actions.csv');
    fid = fopen(actions_csv, 'w');
    fprintf(fid, 'seed,trace,busy,slack_frac,has_packet,speed_mps,burst,action\n');
    total_acts = 0;
    for s = 1:n_seeds
        sd = seed_data{s};
        n_a = numel(sd.act_seed);
        for i = 1:n_a
            fprintf(fid, '%d,%d,%d,%.4f,%d,%.4f,%d,%d\n', ...
                sd.act_seed(i), sd.act_trace(i), sd.act_busy(i), sd.act_slack(i), ...
                sd.act_haspkt(i), sd.act_speed(i), sd.act_burst(i), sd.act_action(i));
        end
        total_acts = total_acts + n_a;
    end
    fclose(fid);
    ctx.hbf(sprintf('actions.csv written (%d decisions, %s)', total_acts, actions_csv));

    r3_mat = fullfile(ctx.ckptdir, 'r3_diag.mat');
    warm_vals = warm_data.warm_olla_vals;
    save(r3_mat, 'warm_vals', 'total_acts', '-v7.3');

    rep_file = fullfile(ctx.outdir, 'REPORT_r3_nr2diag.txt');
    fid = fopen(rep_file, 'w');
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'REPORT_r3_nr2diag.txt -- NR2 Diagnostics (Stage r3_nr2diag)\n');
    fprintf(fid, 'Generated: %s | MATLAB %s\n', datestr(now, 31), version);
    fprintf(fid, '================================================================================\n\n');
    fprintf(fid, 'Configuration: n_seeds=%d, n_eval=%d\n', n_seeds, n_eval);
    fprintf(fid, 'Total scheduled new transmission decisions logged: %d\n', total_acts);
    fprintf(fid, 'Warm OLLA (200 TTIs) mean on-time: %.4f\n', mean(warm_vals));
    fprintf(fid, 'peruser.csv: %s\n', peruser_csv);
    fprintf(fid, 'actions.csv: %s\n', actions_csv);
    fclose(fid);

    out = struct('peruser_csv', peruser_csv, 'actions_csv', actions_csv, 'total_acts', total_acts);
end

% =========================================================================
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
            off = str2double(tok{5});
            tab(b, d, v, u) = off;
        end
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
