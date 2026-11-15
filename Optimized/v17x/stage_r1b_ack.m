function stage_r1b_ack(ctx)
% stage_r1b_ack  One-step supervised learner trained on observed ACK/NACK only.
% Spec: paper/proposals/R1b_ack_prereg.md (Amendment 9, Freeze v10).
% Units:
%   log_explore : exploration logging on calibration traces (rng(3050000 + j))
%   fit         : Python train_r1b_ack.py (gbt_a classifier, SHA-256 hash, 5-fold cross-fit)
%   equiv       : tree prediction equivalence gate with scikit-learn (<= 1e-9)
%   repro       : REPRO gate on 20 traces (Fixed-500, Context-joint-500, NR2 seed 1; diff = 0)
%   eval_NR2    : evaluate GBT-res-ACK and GBT-full-ACK on NR2 evaluation traces
%   eval_M1     : evaluate GBT-res-ACK and GBT-full-ACK on M1 evaluation traces
%   export      : export pertrace_r1b.csv, r1b_deploy_acks.csv, REPORT_r1b_ack.txt

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

    ctx.hbf(sprintf('r1b_ack start: n_calib=%d, n_eval=%d, n_repro=%d', n_calib, n_eval, n_repro));

    envFixed = env_M1;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    [envFixed, ~] = selectBaseRule_v17n(envFixed, 2, o.simTime);

    ckpt_r1b = fullfile(ctx.ckptdir, 'r1b_ack');
    if ~exist(ckpt_r1b, 'dir'), mkdir(ckpt_r1b); end

    % ---- 1. Unit: log_explore ----
    calib_mat = fullfile(ckpt_r1b, 'calib_log_r1b.mat');
    ctx.unit('log_explore', @() unit_log_explore(envFixed, n_calib, o, calib_mat, ctx));

    % ---- 2. Unit: fit ----
    joblib_out = fullfile(ctx.outdir, 'r1b_model.joblib');
    trees_mat  = fullfile(ckpt_r1b, 'r1b_trees.mat');
    hash_out   = fullfile(ctx.outdir, 'r1b_hash.txt');
    xfit_csv   = fullfile(ckpt_r1b, 'r1b_calib_xfit.csv');
    ctx.unit('fit', @() unit_fit(calib_mat, joblib_out, trees_mat, hash_out, xfit_csv, ctx));

    % ---- 3. Unit: equiv ----
    trees_data = ctx.unit('equiv', @() unit_equiv(trees_mat, ctx));

    % ---- 4. Unit: repro ----
    ctx.unit('repro', @() unit_repro(envFixed, n_repro, o, ctx));

    % ---- 5. Unit: eval_NR2 ----
    eval_nr2 = ctx.unit('eval_NR2', @() unit_eval_nr2(envFixed, trees_data, n_eval, o, ctx));

    % ---- 6. Unit: eval_M1 ----
    eval_m1 = ctx.unit('eval_M1', @() unit_eval_m1(envFixed, trees_data, n_eval, o, ctx));

    % ---- 7. Unit: export ----
    ctx.unit('export', @() unit_export(eval_nr2, eval_m1, xfit_csv, hash_out, n_eval, ctx));

    ctx.hbf('r1b_ack done successfully');
end

% =========================================================================
function out = unit_log_explore(envFixed, n_calib, o, calib_mat, ctx)
    ctx.hbf(sprintf('log_explore: logging epsilon-greedy exploration from %d calibration traces', n_calib));

    calib_trace_base = 600000;
    calib_crn_base   = 610000;
    exp_stream_base  = 3050000;

    for j = 1:n_calib
        tr_seed = calib_trace_base + j;
        crn_seed = calib_crn_base + j;
        exp_seed = exp_stream_base + j;

        % Assertions per R1b pre-registration §3
        assert(~(tr_seed >= 500001 && tr_seed <= 570500), 'Evaluation trace seed in calibration!');
        assert(~(tr_seed >= 1000001 && tr_seed <= 1000500), 'Evaluation trace seed in calibration!');
        assert(~(tr_seed >= 720000 && tr_seed <= 750500), 'Evaluation trace seed in calibration!');
        assert(~(crn_seed >= 510001 && crn_seed <= 580500), 'Evaluation CRN seed in calibration!');
        assert(~(crn_seed >= 1010001 && crn_seed <= 1010500), 'Evaluation CRN seed in calibration!');
        assert(exp_seed >= 3050001 && exp_seed <= 3050500, 'Exploration seed out of range!');
    end

    max_dec = n_calib * o.simTime * envFixed.N;
    X_buf = zeros(max_dec, 19, 'single');
    mcs_buf = zeros(max_dec, 1, 'int8');
    ack1_buf = zeros(max_dec, 1, 'int8');
    tr_buf = zeros(max_dec, 1, 'int32');
    exp_buf = zeros(max_dec, 1, 'int8');
    n_total = 0;

    b0 = min(envFixed.burn_in, o.simTime - 1);

    for j = 1:n_calib
        rng(calib_trace_base + j, 'twister');
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;

        rng(calib_crn_base + j, 'twister');
        U = rand(o.simTime, envFixed.N);

        pol = struct();
        pol.s_exp = RandStream('twister', 'Seed', exp_stream_base + j);
        pol.trace_id = j;
        pol.base_offset = -2;

        [~, ~, ~, ~, inf] = evalPolicy_presub('log_explore', pol, Strue, obsS, envFixed, meta, U);

        log_data = inf.r1b_log; % [trace_id, t, u, obs1..19, off_taken, tx_mcs, ack1, ubits_taken, c_mcs(7), c_ubits(7), explored]
        n_dec = size(log_data, 1);
        if n_dec > 0
            idx_s = n_total + 1;
            idx_e = n_total + n_dec;

            tr_buf(idx_s:idx_e)   = int32(log_data(:, 1));
            X_buf(idx_s:idx_e, :) = single(log_data(:, 4:22));
            mcs_buf(idx_s:idx_e)  = int8(log_data(:, 24));
            ack1_buf(idx_s:idx_e) = int8(log_data(:, 25));
            exp_buf(idx_s:idx_e)  = int8(log_data(:, 41));

            n_total = idx_e;
        end
    end

    X_feat    = X_buf(1:n_total, :);
    mcs_taken = mcs_buf(1:n_total);
    ack1      = ack1_buf(1:n_total);
    trace_id  = tr_buf(1:n_total);
    explored  = exp_buf(1:n_total);

    % Assert no forbidden truth columns
    assert(size(X_feat, 2) == 19, 'Observable features must be exactly 19');
    assert(all(ack1 == 0 | ack1 == 1), 'ack1 must be binary {0, 1}');

    ctx.hbf(sprintf('log_explore: %d decisions logged (explored=%d, base=%d). Saving to %s', ...
        n_total, sum(explored == 1), sum(explored == 0), calib_mat));
    save(calib_mat, 'X_feat', 'mcs_taken', 'ack1', 'trace_id', 'explored', 'n_total', '-v7.3');
    out = struct('n_decisions', n_total, 'calib_mat', calib_mat);
end

% =========================================================================
function out = unit_fit(calib_mat, joblib_out, trees_mat, hash_out, xfit_csv, ctx)
    ctx.hbf('fit: calling python train_r1b_ack.py...');
    py_script = fullfile(ctx.root, 'train_r1b_ack.py');
    cmd = sprintf('python "%s" "%s" "%s" "%s" "%s" "%s"', ...
        py_script, calib_mat, joblib_out, trees_mat, hash_out, xfit_csv);
    [status, cmdout] = system(cmd);
    if status ~= 0
        error('v17x:r1b_ack:fit_failed', 'Python training failed:\n%s', cmdout);
    end
    ctx.hbf(sprintf('fit: python training successful:\n%s', strtrim(cmdout)));

    if ~exist(joblib_out, 'file') || ~exist(hash_out, 'file') || ~exist(trees_mat, 'file') || ~exist(xfit_csv, 'file')
        error('v17x:r1b_ack:missing_artifacts', 'Expected artifacts missing after fit');
    end
    sha256 = strtrim(fileread(hash_out));
    ctx.hbf(sprintf('fit: deployed model SHA-256 = %s', sha256));
    out = struct('sha256', sha256, 'joblib', joblib_out);
end

% =========================================================================
function out = unit_equiv(trees_mat, ctx)
    ctx.hbf('equiv: verifying tree prediction equivalence with scikit-learn (1e-9 gate)');
    S = load(trees_mat);
    m = S.trees_export;
    X_equiv = S.X_equiv;
    P_pred_sk = S.P_pred_sk;

    n_eq = size(X_equiv, 1);
    P_pred_mat = zeros(n_eq, 1);

    % Handle cell vs struct packaging
    trees = m.trees;
    if isstruct(trees) && numel(trees) > 1
        t_cell = cell(1, numel(trees));
        for k = 1:numel(trees), t_cell{k} = trees(k); end
        m.trees = t_cell;
    end

    for i = 1:n_eq
        P_pred_mat(i) = gbt_predict_prob_local(m, X_equiv(i, :));
    end

    diff_vec = abs(P_pred_mat - P_pred_sk(:));
    max_diff = max(diff_vec);
    ctx.hbf(sprintf('equiv: max abs difference between MATLAB and scikit-learn = %.3e', max_diff));
    if max_diff > 1e-9
        error('v17x:r1b_ack:equiv_fail', 'Equivalence check failed: max abs diff %.3e > 1e-9', max_diff);
    end
    ctx.hbf('equiv: EQUIVALENCE GATE PASS (max abs diff <= 1e-9)');
    out = m;
end

% =========================================================================
function out = unit_repro(envFixed, n_repro, o, ctx)
    ctx.hbf(sprintf('repro: checking bit-identity on first %d traces of NR2', n_repro));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    eval_nr2_file = fullfile(ctx.ckptdir, 'nr2', 'eval.mat');
    if ~exist(eval_nr2_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'eval.mat');
        if exist(fallback, 'file'), eval_nr2_file = fallback; else, error('nr2/eval.mat missing'); end
    end
    st_nr2 = load(eval_nr2_file);

    % Check NR2 seed 1 policy
    nr2_s1_file = fullfile(ctx.ckptdir, 'nr2', 'train_seed_1.mat');
    if ~exist(nr2_s1_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'train_seed_1.mat');
        if exist(fallback, 'file'), nr2_s1_file = fallback; else, error('nr2/train_seed_1.mat missing'); end
    end
    sd1 = load(nr2_s1_file);
    pol_nr2_s1 = sd1.out.a2c;

    % Setup Context-joint environment with table
    tables_file = fullfile(ctx.root, 'Dataset', 'cal500_tables.txt');
    ctxj_tab = read_ctxj_from_tables(tables_file);
    e_ctxj = envFixed;
    e_ctxj.ctxj_tab = ctxj_tab;

    for j = 1:n_repro
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);

        rng(tr_seed);
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;

        rng(crn_seed);
        U = rand(o.simTime, envFixed.N);

        % Fixed-500
        rng(1020000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('fixed', [], Strue, obsS, envFixed, meta, U);
        [~, ~, p_fix] = userMetric_v17(envFixed, tp, inf, b0);
        stored_f = st_nr2.out.cmp.fixed500(j);
        if abs(p_fix - stored_f) ~= 0
            error('v17x:r1b:repro', 'REPRO failed on Fixed-500 trace %d: diff=%.3e', j, abs(p_fix - stored_f));
        end

        % Context-joint-500
        rng(1020000 + 100*j + 10*99 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('ctxj', [], Strue, obsS, e_ctxj, meta, U);
        [~, ~, p_cj] = userMetric_v17(e_ctxj, tp, inf, b0);
        stored_cj = st_nr2.out.cmp.ctxj500(j);
        if abs(p_cj - stored_cj) ~= 0
            error('v17x:r1b:repro', 'REPRO failed on Context-joint trace %d: diff=%.3e', j, abs(p_cj - stored_cj));
        end

        % NR2 seed 1
        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('a2c_v17', pol_nr2_s1, Strue, obsS, envFixed, meta, U);
        [~, ~, p_nr2] = userMetric_v17(envFixed, tp, inf, b0);
        stored_nr2 = st_nr2.out.nr2_seeds(1, j);
        if abs(p_nr2 - stored_nr2) ~= 0
            error('v17x:r1b:repro', 'REPRO failed on NR2 seed 1 trace %d: diff=%.3e', j, abs(p_nr2 - stored_nr2));
        end
    end

    ctx.hbf('repro: REPRO PASS (Fixed-500, Context-joint-500, NR2 seed 1 max_abs_diff = 0)');
    out = struct('repro_pass', true);
end

% =========================================================================
function out = unit_eval_nr2(envFixed, model, n_eval, o, ctx)
    ctx.hbf(sprintf('eval_NR2: evaluating GBT-res-ACK and GBT-full-ACK on %d NR2 traces', n_eval));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    vals_res = zeros(1, n_eval);
    vals_full = zeros(1, n_eval);

    deploy_res_cell = cell(1, n_eval);
    deploy_full_cell = cell(1, n_eval);

    for j = 1:n_eval
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);

        rng(tr_seed, 'twister');
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;

        rng(crn_seed, 'twister');
        U = rand(o.simTime, envFixed.N);

        % GBT-res-ACK
        [tp_res, ~, ~, ~, inf_res] = evalPolicy_presub('gbt_res_ack', model, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_res(j)] = userMetric_v17(envFixed, tp_res, inf_res, b0);
        deploy_res_cell{j} = inf_res.r1b_deploy;

        % GBT-full-ACK
        [tp_full, ~, ~, ~, inf_full] = evalPolicy_presub('gbt_full_ack', model, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_full(j)] = userMetric_v17(envFixed, tp_full, inf_full, b0);
        deploy_full_cell{j} = inf_full.r1b_deploy;
    end

    deploy_res = cat(1, deploy_res_cell{:});
    deploy_full = cat(1, deploy_full_cell{:});

    ctx.hbf(sprintf('eval_NR2: GBT-res-ACK mean ontime=%.4f, GBT-full-ACK mean ontime=%.4f', ...
        mean(vals_res), mean(vals_full)));

    out = struct( ...
        'gbt_res', vals_res, ...
        'gbt_full', vals_full, ...
        'deploy_res', deploy_res, ...
        'deploy_full', deploy_full ...
    );
end

% =========================================================================
function out = unit_eval_m1(envFixed, model, n_eval, o, ctx)
    ctx.hbf(sprintf('eval_M1: evaluating GBT-res-ACK and GBT-full-ACK on %d M1 traces', n_eval));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    vals_res_m1 = zeros(1, n_eval);
    vals_full_m1 = zeros(1, n_eval);

    for j = 1:n_eval
        tr_seed = 500000 + j;
        crn_seed = 510000 + j;

        rng(tr_seed, 'twister');
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;

        rng(crn_seed, 'twister');
        U = rand(o.simTime, envFixed.N);

        % GBT-res-ACK
        [tp_res, ~, ~, ~, inf_res] = evalPolicy_presub('gbt_res_ack', model, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_res_m1(j)] = userMetric_v17(envFixed, tp_res, inf_res, b0);

        % GBT-full-ACK
        [tp_full, ~, ~, ~, inf_full] = evalPolicy_presub('gbt_full_ack', model, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_full_m1(j)] = userMetric_v17(envFixed, tp_full, inf_full, b0);
    end

    ctx.hbf(sprintf('eval_M1: GBT-res-ACK=%.4f, GBT-full-ACK=%.4f', ...
        mean(vals_res_m1), mean(vals_full_m1)));

    out = struct('gbt_res_m1', vals_res_m1, 'gbt_full_m1', vals_full_m1);
end

% =========================================================================
function out = unit_export(eval_nr2, eval_m1, xfit_csv, hash_out, n_eval, ctx)
    ctx.hbf('export: exporting pertrace_r1b.csv, r1b_deploy_acks.csv, and REPORT_r1b_ack.txt');

    r1b_dir = fullfile(ctx.outdir, 'presub', 'r1b');
    if ~exist(r1b_dir, 'dir'), mkdir(r1b_dir); end

    % 1. Copy cross-fitted calibration diagnostics
    target_xfit = fullfile(r1b_dir, 'r1b_calib_xfit.csv');
    copyfile(xfit_csv, target_xfit);

    % 2. Export pertrace_r1b.csv
    pertrace_csv = fullfile(r1b_dir, 'pertrace_r1b.csv');
    fid = fopen(pertrace_csv, 'w');
    fprintf(fid, 'trace_set,scheme,seed,trace,value\n');
    for j = 1:n_eval
        fprintf(fid, 'NR2,GBT-res-ACK,0,%d,%.6f\n', j, eval_nr2.gbt_res(j));
    end
    for j = 1:n_eval
        fprintf(fid, 'NR2,GBT-full-ACK,0,%d,%.6f\n', j, eval_nr2.gbt_full(j));
    end
    for j = 1:n_eval
        fprintf(fid, 'M1,GBT-res-ACK,0,%d,%.6f\n', j, eval_m1.gbt_res_m1(j));
    end
    for j = 1:n_eval
        fprintf(fid, 'M1,GBT-full-ACK,0,%d,%.6f\n', j, eval_m1.gbt_full_m1(j));
    end
    fclose(fid);

    % 3. Export r1b_deploy_acks.csv
    deploy_csv = fullfile(r1b_dir, 'r1b_deploy_acks.csv');
    fid = fopen(deploy_csv, 'w');
    fprintf(fid, 'scheme,trace,mcs,p_hat,ack1\n');
    % Deploy res
    d_res = eval_nr2.deploy_res;
    for i = 1:size(d_res, 1)
        fprintf(fid, 'GBT-res-ACK,%d,%d,%.6f,%d\n', int32(d_res(i, 1)), int32(d_res(i, 2)), d_res(i, 3), int32(d_res(i, 4)));
    end
    % Deploy full
    d_full = eval_nr2.deploy_full;
    for i = 1:size(d_full, 1)
        fprintf(fid, 'GBT-full-ACK,%d,%d,%.6f,%d\n', int32(d_full(i, 1)), int32(d_full(i, 2)), d_full(i, 3), int32(d_full(i, 4)));
    end
    fclose(fid);

    % 4. Save evaluation MAT checkpoint
    r1b_eval_mat = fullfile(ctx.ckptdir, 'r1b_ack', 'r1b_eval.mat');
    gbt_res_nr2  = eval_nr2.gbt_res;
    gbt_full_nr2 = eval_nr2.gbt_full;
    gbt_res_m1   = eval_m1.gbt_res_m1;
    gbt_full_m1  = eval_m1.gbt_full_m1;
    save(r1b_eval_mat, 'gbt_res_nr2', 'gbt_full_nr2', 'gbt_res_m1', 'gbt_full_m1', '-v7.3');

    sha256 = '';
    if exist(hash_out, 'file'), sha256 = strtrim(fileread(hash_out)); end

    % 5. Write REPORT_r1b_ack.txt
    rep_file = fullfile(ctx.outdir, 'REPORT_r1b_ack.txt');
    fid = fopen(rep_file, 'w');
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'REPORT_r1b_ack.txt -- ACK-Trained Supervised Learner (Stage r1b_ack)\n');
    fprintf(fid, 'Generated: %s | MATLAB %s\n', datestr(now, 31), version);
    fprintf(fid, '================================================================================\n\n');
    fprintf(fid, 'Deployed model SHA-256: %s\n', sha256);
    fprintf(fid, 'Evaluation traces: n_eval=%d\n\n', n_eval);
    fprintf(fid, 'NR2 traces:\n');
    fprintf(fid, '  GBT-res-ACK  mean on-time: %.4f\n', mean(gbt_res_nr2));
    fprintf(fid, '  GBT-full-ACK mean on-time: %.4f\n\n', mean(gbt_full_nr2));
    fprintf(fid, 'M1 traces (secondary):\n');
    fprintf(fid, '  GBT-res-ACK  mean on-time: %.4f\n', mean(gbt_res_m1));
    fprintf(fid, '  GBT-full-ACK mean on-time: %.4f\n', mean(gbt_full_m1));
    fclose(fid);

    out = struct('pertrace_csv', pertrace_csv, 'deploy_csv', deploy_csv, 'report', rep_file);
end

% =========================================================================
function p = gbt_predict_prob_local(model, x)
    raw = model.baseline;
    trees = model.trees;
    n_t = numel(trees);
    for k = 1:n_t
        t = trees{k};
        idx = 1;
        while ~t.is_leaf(idx)
            if x(t.feat(idx)) <= t.th(idx)
                idx = t.left(idx);
            else
                idx = t.right(idx);
            end
        end
        raw = raw + t.val(idx);
    end
    p = 1.0 / (1.0 + exp(-raw));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
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
            off = str2double(tok{5});
            tab(b, d, v, u) = off;
        end
    end
end
