function stage_r2_rule(ctx)
% stage_r2_rule  Hand-designed and calibrated state rules.
% Spec: paper/proposals/R_presub_prereg.md §4 and §12 (Amendment 8, Freeze v9).
% Units:
%   grid_chunk_1..4 (calibration traces only)
%   select (writes and hashes r2_thresholds.txt)
%   repro
%   eval_NR2
%   eval_M1
%   export
% Outputs:
%   Dataset/r2_thresholds.txt
%   Dataset/r2_thresholds.sha256
%   Dataset/ckpt/r2_rule/r2_rule_eval.mat
%   Dataset/REPORT_r2_rule.txt
%   Dataset/stage_r2_rule.done

    addpath(ctx.v17);
    addpath(fullfile(ctx.v17, 'headroom'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    addpath(ctx.root);
    v17_setup;

    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(ctx.v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; env_M1 = R_M1.env;

    n_calib = ternary(ctx.smoke, 2, 500);
    n_eval  = ternary(ctx.smoke, 2, 500);
    n_repro = ternary(ctx.smoke, 2, 20);

    ctx.hbf(sprintf('r2_rule start: n_calib=%d, n_eval=%d, n_repro=%d', n_calib, n_eval, n_repro));

    envFixed = env_M1;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    [envFixed, ~] = selectBaseRule_v17n(envFixed, 2, o.simTime);

    ckpt_r2 = fullfile(ctx.ckptdir, 'r2_rule');
    if ~exist(ckpt_r2, 'dir'), mkdir(ckpt_r2); end

    grid_pts = generate_grid();
    n_grid = numel(grid_pts);
    n_chunks = 4;
    chunk_size = ceil(n_grid / n_chunks);

    % ---- 1. Units: grid_chunk_K ----
    chunk_results = cell(1, n_chunks);
    for c = 1:n_chunks
        idx_s = (c - 1) * chunk_size + 1;
        idx_e = min(c * chunk_size, n_grid);
        u_name = sprintf('grid_chunk_%d', c);
        sub_grid = grid_pts(idx_s:idx_e);
        chunk_results{c} = ctx.unit(u_name, @() unit_grid_chunk(envFixed, sub_grid, idx_s, idx_e, n_calib, o, ctx));
    end

    % ---- 2. Unit: select ----
    thresh_file = fullfile(ctx.outdir, 'r2_thresholds.txt');
    hash_file   = fullfile(ctx.outdir, 'r2_thresholds.sha256');
    chosen_th = ctx.unit('select', @() unit_select(chunk_results, grid_pts, thresh_file, hash_file, ctx));

    % ---- 3. Unit: repro ----
    ctx.unit('repro', @() unit_repro(envFixed, n_repro, o, ctx));

    % ---- 4. Unit: eval_NR2 ----
    eval_nr2 = ctx.unit('eval_NR2', @() unit_eval_nr2(envFixed, chosen_th, n_eval, o, ctx));

    % ---- 5. Unit: eval_M1 ----
    eval_m1 = ctx.unit('eval_M1', @() unit_eval_m1(envFixed, chosen_th, n_eval, o, ctx));

    % ---- 6. Unit: export ----
    ctx.unit('export', @() unit_export(eval_nr2, eval_m1, chosen_th, hash_file, n_eval, ctx));

    ctx.hbf('r2_rule done successfully');
end

% =========================================================================
function grid_pts = generate_grid()
    B_vals = [1, 2, 3, 0];
    S_vals = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0];
    th_vals = [0.5, 1.0, 1.5, 2.0, 0];

    grid_pts = [];
    cnt = 0;
    for b = B_vals
        for s = S_vals
            for t = th_vals
                cnt = cnt + 1;
                pt = struct('B', b, 'S', s, 'theta', t, 'id', cnt);
                grid_pts = [grid_pts; pt]; %#ok<AGROW>
            end
        end
    end
end

% =========================================================================
function out = unit_grid_chunk(envFixed, sub_grid, idx_s, idx_e, n_calib, o, ctx)
    ctx.hbf(sprintf('grid_chunk: evaluating grid points %d..%d on %d calib traces', idx_s, idx_e, n_calib));
    b0 = min(envFixed.burn_in, o.simTime - 1);
    calib_trace_base = 600000;
    calib_crn_base   = 610000;

    traces = struct('Strue', cell(1, n_calib), 'obsS', cell(1, n_calib), ...
                    'meta', cell(1, n_calib), 'U', cell(1, n_calib));
    for j = 1:n_calib
        rng(calib_trace_base + j);
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = calib_trace_base + j;
        rng(calib_crn_base + j);
        U = rand(o.simTime, envFixed.N);
        traces(j).Strue = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end

    n_pts = numel(sub_grid);
    obj_vals = zeros(1, n_pts);

    for p = 1:n_pts
        th = sub_grid(p);
        tot_ok = 0;
        tot_res = 0;
        for j = 1:n_calib
            rng(77000 + 100*j + 10*5 + 1);
            [tp, ~, ~, ~, inf] = evalPolicy_presub('rule_cal', th, traces(j).Strue, traces(j).obsS, envFixed, traces(j).meta, traces(j).U);
            tot_ok = tot_ok + sum(inf.okU);
            tot_res = tot_res + sum(inf.resU);
        end
        obj_vals(p) = tot_ok / max(tot_res, 1);
    end

    out = struct('sub_grid', sub_grid, 'obj_vals', obj_vals);
end

% =========================================================================
function chosen_th = unit_select(chunk_results, grid_pts, thresh_file, hash_file, ctx)
    ctx.hbf('select: finding optimal threshold combination and exporting r2_thresholds.txt');
    n_pts = numel(grid_pts);
    all_obj = zeros(1, n_pts);
    cur = 1;
    for c = 1:numel(chunk_results)
        vals = chunk_results{c}.obj_vals;
        len = numel(vals);
        all_obj(cur:cur+len-1) = vals;
        cur = cur + len;
    end

    max_obj = max(all_obj);
    cand_indices = find(abs(all_obj - max_obj) <= 1e-12);

    best_idx = cand_indices(1);
    best_active = 999;
    best_tuple = [Inf, Inf, Inf];

    for idx = cand_indices
        pt = grid_pts(idx);
        n_act = (pt.B > 0) + (pt.S > 0) + (pt.theta > 0);
        B_sort = ternary(pt.B > 0, pt.B, Inf);
        S_sort = ternary(pt.S > 0, pt.S, Inf);
        th_sort = ternary(pt.theta > 0, pt.theta, Inf);
        tuple = [B_sort, S_sort, th_sort];

        if n_act < best_active
            best_active = n_act;
            best_tuple = tuple;
            best_idx = idx;
        elseif n_act == best_active
            if is_lex_smaller(tuple, best_tuple)
                best_tuple = tuple;
                best_idx = idx;
            end
        end
    end

    chosen_th = grid_pts(best_idx);
    b_str = ternary(chosen_th.B > 0, sprintf('%d', chosen_th.B), 'off');
    s_str = ternary(chosen_th.S > 0, sprintf('%.1f', chosen_th.S), 'off');
    t_str = ternary(chosen_th.theta > 0, sprintf('%.1f', chosen_th.theta), 'off');
    ctx.hbf(sprintf('select: optimal thresholds: B=%s, S=%s, theta=%s (objective=%.4f)', ...
        b_str, s_str, t_str, max_obj));

    fid = fopen(thresh_file, 'w');
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'r2_thresholds.txt -- Calibrated State Rule Thresholds (Stage r2_rule)\n');
    fprintf(fid, 'Generated: %s | MATLAB %s\n', datestr(now, 31), version);
    fprintf(fid, '================================================================================\n\n');
    fprintf(fid, 'OPTIMAL_THRESHOLDS: B=%s | S=%s | theta=%s | objective=%.6f\n\n', ...
        b_str, s_str, t_str, max_obj);
    fprintf(fid, '%-6s | %-6s | %-8s | %-8s | %-12s | %-12s\n', ...
        'GridID', 'B', 'S', 'theta', 'ActiveClauses', 'Objective');
    fprintf(fid, '--------------------------------------------------------------------------------\n');
    for p = 1:n_pts
        pt = grid_pts(p);
        bs = ternary(pt.B > 0, sprintf('%d', pt.B), 'off');
        ss = ternary(pt.S > 0, sprintf('%.1f', pt.S), 'off');
        ts = ternary(pt.theta > 0, sprintf('%.1f', pt.theta), 'off');
        act_c = (pt.B > 0) + (pt.S > 0) + (pt.theta > 0);
        fprintf(fid, '%-6d | %-6s | %-8s | %-8s | %-12d | %-12.6f\n', ...
            p, bs, ss, ts, act_c, all_obj(p));
    end
    fclose(fid);
    ctx.hbf(sprintf('select: %s written', thresh_file));

    cmd = sprintf('powershell -Command "(Get-FileHash -Algorithm SHA256 ''%s'').Hash.ToLower()"', thresh_file);
    [st, sha_out] = system(cmd);
    if st == 0
        sha256 = strtrim(sha_out);
        fid_h = fopen(hash_file, 'w');
        fprintf(fid_h, '%s  r2_thresholds.txt\n', sha256);
        fclose(fid_h);
        ctx.hbf(sprintf('select: SHA-256 hash: %s', sha256));
    end
end

% =========================================================================
function out = unit_repro(envFixed, n_repro, o, ctx)
    ctx.hbf(sprintf('repro: checking bit-identity on first %d traces of NR2 and M1', n_repro));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    eval_nr2_file = fullfile(ctx.ckptdir, 'nr2', 'eval.mat');
    if ~exist(eval_nr2_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'eval.mat');
        if exist(fallback, 'file'), eval_nr2_file = fallback; else, error('nr2/eval.mat missing'); end
    end
    st_nr2 = load(eval_nr2_file);

    for j = 1:n_repro
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
        rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;
        rng(crn_seed); U = rand(o.simTime, envFixed.N);
        rng(1020000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('fixed', [], Strue, obsS, envFixed, meta, U);
        [~, ~, p] = userMetric_v17(envFixed, tp, inf, b0);
        stored_f = st_nr2.out.cmp.fixed500(j);
        if abs(p - stored_f) ~= 0
            error('v17x:r2:repro', 'REPRO failed on NR2 Fixed-500 trace %d: diff=%.3e', j, abs(p - stored_f));
        end
    end

    ctx.hbf('repro: bit-identity verified (max_abs_diff = 0)');
    out = struct('repro_pass', true);
end

% =========================================================================
function out = unit_eval_nr2(envFixed, chosen_th, n_eval, o, ctx)
    ctx.hbf(sprintf('eval_NR2: evaluating Rule and Rule-cal on %d NR2 traces', n_eval));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    vals_rule = zeros(1, n_eval);
    vals_cal  = zeros(1, n_eval);

    for j = 1:n_eval
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
        rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;
        rng(crn_seed); U = rand(o.simTime, envFixed.N);

        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('rule', [], Strue, obsS, envFixed, meta, U);
        [~, ~, vals_rule(j)] = userMetric_v17(envFixed, tp, inf, b0);

        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('rule_cal', chosen_th, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_cal(j)] = userMetric_v17(envFixed, tp, inf, b0);
    end

    ctx.hbf(sprintf('eval_NR2: Rule mean ontime=%.4f, Rule-cal mean ontime=%.4f', ...
        mean(vals_rule), mean(vals_cal)));
    out = struct('rule', vals_rule, 'rule_cal', vals_cal);
end

% =========================================================================
function out = unit_eval_m1(envFixed, chosen_th, n_eval, o, ctx)
    ctx.hbf(sprintf('eval_M1: evaluating Rule and Rule-cal on %d M1 traces', n_eval));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    vals_rule = zeros(1, n_eval);
    vals_cal  = zeros(1, n_eval);

    for j = 1:n_eval
        rng(500000 + j); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;
        rng(510000 + j); U = rand(o.simTime, envFixed.N);

        rng(77000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('rule', [], Strue, obsS, envFixed, meta, U);
        [~, ~, vals_rule(j)] = userMetric_v17(envFixed, tp, inf, b0);

        rng(77000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('rule_cal', chosen_th, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_cal(j)] = userMetric_v17(envFixed, tp, inf, b0);
    end

    ctx.hbf(sprintf('eval_M1: Rule mean ontime=%.4f, Rule-cal mean ontime=%.4f', ...
        mean(vals_rule), mean(vals_cal)));
    out = struct('rule', vals_rule, 'rule_cal', vals_cal);
end

% =========================================================================
function out = unit_export(eval_nr2, eval_m1, chosen_th, hash_file, n_eval, ctx)
    ctx.hbf('export: exporting r2_rule_eval.mat and REPORT_r2_rule.txt');
    ckpt_r2 = fullfile(ctx.ckptdir, 'r2_rule');
    r2_eval_mat = fullfile(ckpt_r2, 'r2_rule_eval.mat');

    rule_nr2     = eval_nr2.rule;
    rule_cal_nr2 = eval_nr2.rule_cal;
    rule_m1      = eval_m1.rule;
    rule_cal_m1  = eval_m1.rule_cal;

    save(r2_eval_mat, 'rule_nr2', 'rule_cal_nr2', 'rule_m1', 'rule_cal_m1', 'chosen_th', '-v7.3');

    sha256 = '';
    if exist(hash_file, 'file'), sha256 = strtrim(fileread(hash_file)); end

    rep_file = fullfile(ctx.outdir, 'REPORT_r2_rule.txt');
    fid = fopen(rep_file, 'w');
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'REPORT_r2_rule.txt -- Hand-Designed and Calibrated State Rules (Stage r2_rule)\n');
    fprintf(fid, 'Generated: %s | MATLAB %s\n', datestr(now, 31), version);
    fprintf(fid, '================================================================================\n\n');
    fprintf(fid, 'Threshold hash: %s\n', sha256);
    fprintf(fid, 'Evaluation traces: n_eval=%d\n\n', n_eval);
    fprintf(fid, 'NR2 traces:\n');
    fprintf(fid, '  Rule     mean on-time: %.4f\n', mean(rule_nr2));
    fprintf(fid, '  Rule-cal mean on-time: %.4f\n\n', mean(rule_cal_nr2));
    fprintf(fid, 'M1 traces (secondary):\n');
    fprintf(fid, '  Rule     mean on-time: %.4f\n', mean(rule_m1));
    fprintf(fid, '  Rule-cal mean on-time: %.4f\n', mean(rule_cal_m1));
    fclose(fid);

    out = struct('r2_eval_mat', r2_eval_mat, 'report', rep_file);
end

% =========================================================================
function smaller = is_lex_smaller(a, b)
    smaller = false;
    for k = 1:numel(a)
        if a(k) < b(k)
            smaller = true; return;
        elseif a(k) > b(k)
            smaller = false; return;
        end
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
