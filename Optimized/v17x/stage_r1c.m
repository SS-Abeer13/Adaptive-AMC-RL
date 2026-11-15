function stage_r1c(ctx)
% stage_r1c  Calibration-draw replication and per-cell test of ACK-trained learner.
% Spec: paper/proposals/R1c_ack_prereg.md (Amendment 10, Freeze v11/v12).
% Units:
%   load_cells          : load and hash-check cell envs, assert parameters
%   log_m1_k (k=2..4)   : epsilon-greedy logging on M1 calibration draws
%   log_g2_k (k=1..4)   : epsilon-greedy logging on G2 calibration draws
%   log_g3_k (k=1..4)   : epsilon-greedy logging on G3 calibration draws
%   fit                 : python train_r1c_ack.py on all 11 models
%   equiv               : tree prediction equivalence gate (<= 1e-9)
%   repro               : REPRO gate on traces 1-20 (NR2, G2, G3)
%   eval_nr2            : evaluate M1 fits 2-4 on NR2 evaluation traces
%   eval_g2_cellfit     : evaluate G2 cell fits 1-4 on G2 evaluation traces
%   eval_g3_cellfit     : evaluate G3 cell fits 1-4 on G3 evaluation traces
%   eval_g2_transfer    : evaluate M1 fits 1-4 transferred to G2
%   eval_g3_transfer    : evaluate M1 fits 1-4 transferred to G3
%   export              : export pertrace_r1c.csv and REPORT_r1c.txt

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
    n_eval_nr2 = ternary(ctx.smoke, 2, 500);
    n_eval_cell = ternary(ctx.smoke, 2, 300);
    n_repro = ternary(ctx.smoke, 2, 20);

    ctx.hbf(sprintf('r1c start: n_calib=%d, n_eval_nr2=%d, n_eval_cell=%d, n_repro=%d', ...
        n_calib, n_eval_nr2, n_eval_cell, n_repro));

    if isfield(ctx, 'python') && ~isempty(ctx.python)
        py_exe = ctx.python;
    elseif isfield(ctx, 'cfg') && isfield(ctx.cfg, 'python') && ~isempty(ctx.cfg.python)
        py_exe = ctx.cfg.python;
    else
        py_exe = 'D:\miniconda\python.exe';
    end

    % Assert pinned Python interpreter and required packages
    check_cmd = sprintf('"%s" -c "import numpy, scipy, sklearn, h5py, joblib; print(\''OK\'')"', py_exe);
    [py_st, py_out] = system(check_cmd);
    if py_st ~= 0 || ~contains(py_out, 'OK')
        error('v17x:r1c:python_packages_missing', ...
            'Python interpreter %s failed package assertion (numpy, scipy, sklearn, h5py, joblib):\n%s', py_exe, py_out);
    end
    ctx.hbf(sprintf('r1c python interpreter verified: %s', py_exe));

    ckpt_r1c = fullfile(ctx.ckptdir, 'r1c');
    if ~exist(ckpt_r1c, 'dir'), mkdir(ckpt_r1c); end

    % ---- 1. Unit: load_cells ----
    cells = ctx.unit('load_cells', @() unit_load_cells(ctx));

    % ---- 2. Units: log_m1_k (k=2..4) ----
    envFixed_M1 = env_M1;
    envFixed_M1.base_rule_force = 'fixed';
    envFixed_M1.fixed_offset = -2;
    [envFixed_M1, ~] = selectBaseRule_v17n(envFixed_M1, 2, o.simTime);

    m1_ranges = [
        620000, 630000, 3060000; % Fit 2
        640000, 650000, 3070000; % Fit 3
        660000, 670000, 3080000  % Fit 4
    ];

    calib_m1 = cell(1, 4);
    calib_m1{1} = fullfile(ctx.ckptdir, 'r1b_ack', 'calib_log_r1b.mat'); % R1b fit 1
    for k = 2:4
        tr_b = m1_ranges(k-1, 1);
        crn_b = m1_ranges(k-1, 2);
        exp_b = m1_ranges(k-1, 3);
        c_mat = fullfile(ckpt_r1c, sprintf('calib_log_m1_%d.mat', k));
        calib_m1{k} = c_mat;
        ctx.unit(sprintf('log_m1_%d', k), @() unit_log_explore(envFixed_M1, n_calib, o, tr_b, crn_b, exp_b, -2, c_mat, ctx));
    end

    % ---- 3. Units: log_g2_k and log_g3_k (k=1..4) ----
    calib_g2 = cell(1, 4);
    calib_g3 = cell(1, 4);
    for k = 1:4
        % G2: traces 4100000 + 1000(k-1) + j
        tr_b_g2  = 4100000 + 1000 * (k - 1);
        crn_b_g2 = 4200000 + 1000 * (k - 1);
        exp_b_g2 = 4300000 + 1000 * (k - 1);
        c_mat_g2 = fullfile(ckpt_r1c, sprintf('calib_log_g2_%d.mat', k));
        calib_g2{k} = c_mat_g2;
        ctx.unit(sprintf('log_g2_%d', k), @() unit_log_explore(cells.g2.envFixed, n_calib, o, tr_b_g2, crn_b_g2, exp_b_g2, cells.g2.base_offset, c_mat_g2, ctx));

        % G3: traces 4400000 + 1000(k-1) + j
        tr_b_g3  = 4400000 + 1000 * (k - 1);
        crn_b_g3 = 4500000 + 1000 * (k - 1);
        exp_b_g3 = 4600000 + 1000 * (k - 1);
        c_mat_g3 = fullfile(ckpt_r1c, sprintf('calib_log_g3_%d.mat', k));
        calib_g3{k} = c_mat_g3;
        ctx.unit(sprintf('log_g3_%d', k), @() unit_log_explore(cells.g3.envFixed, n_calib, o, tr_b_g3, crn_b_g3, exp_b_g3, cells.g3.base_offset, c_mat_g3, ctx));
    end

    % ---- 4. Unit: fit ----
    models = ctx.unit('fit', @() unit_fit(calib_m1, calib_g2, calib_g3, ckpt_r1c, ctx, py_exe));

    % ---- 5. Unit: equiv ----
    trees = ctx.unit('equiv', @() unit_equiv(models, ctx));

    % ---- 6. Unit: repro ----
    ctx.unit('repro', @() unit_repro(envFixed_M1, cells, n_repro, o, ctx));

    % ---- 7. Unit: eval_nr2 ----
    eval_nr2 = ctx.unit('eval_nr2', @() unit_eval_nr2(envFixed_M1, trees.m1, n_eval_nr2, o, ctx));

    % ---- 8. Units: eval_<cell>_cellfit ----
    eval_g2_cell = ctx.unit('eval_g2_cellfit', @() unit_eval_cell('g2', cells.g2.envFixed, trees.g2, n_eval_cell, o, ctx));
    eval_g3_cell = ctx.unit('eval_g3_cellfit', @() unit_eval_cell('g3', cells.g3.envFixed, trees.g3, n_eval_cell, o, ctx));

    % ---- 9. Units: eval_<cell>_transfer ----
    eval_g2_trans = ctx.unit('eval_g2_transfer', @() unit_eval_transfer('g2', cells.g2.envFixed, trees.m1, n_eval_cell, o, ctx));
    eval_g3_trans = ctx.unit('eval_g3_transfer', @() unit_eval_transfer('g3', cells.g3.envFixed, trees.m1, n_eval_cell, o, ctx));

    % ---- 10. Unit: export ----
    ctx.unit('export', @() unit_export(eval_nr2, eval_g2_cell, eval_g3_cell, eval_g2_trans, eval_g3_trans, models.sha_manifest, n_eval_nr2, n_eval_cell, ctx));

    ctx.hbf('stage_r1c done successfully');
end

% =========================================================================
function out = unit_load_cells(ctx)
    ctx.hbf('load_cells: reading frozen cell envs and asserting parameters per §4.1');
    g10_dir = fullfile(ctx.ckptdir, 'g10');
    if ~exist(g10_dir, 'dir')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'g10');
        if exist(fallback, 'dir'), g10_dir = fallback; else, error('ckpt/g10 missing'); end
    end

    f_g2 = fullfile(g10_dir, 'calib_single_G2_hi_d10.mat');
    f_g3 = fullfile(g10_dir, 'calib_single_G3_lo_d18.mat');

    assert(exist(f_g2, 'file') == 2, 'G2 calib file missing: %s', f_g2);
    assert(exist(f_g3, 'file') == 2, 'G3 calib file missing: %s', f_g3);

    s2 = load(f_g2);
    s3 = load(f_g3);

    env2 = s2.out.env;
    base2 = s2.out.fixed_offset;
    assert(env2.pkt_bits == 14000, 'G2 pkt_bits must be 14000 (Deviation D1)');
    assert(env2.pkt_deadline == 10, 'G2 pkt_deadline must be 10');
    assert(env2.pkt_period == 20, 'G2 pkt_period must be 20');
    assert(env2.N == 10, 'G2 N must be 10');
    assert(base2 == -2, 'G2 base offset must be -2');
    assert(env2.fixed_offset == -2, 'G2 env.fixed_offset must be -2');
    assert(env2.N * env2.pkt_bits / env2.pkt_period == 7000, 'G2 offered load must be 7000 bits/TTI');

    env3 = s3.out.env;
    base3 = s3.out.fixed_offset;
    assert(env3.pkt_bits == 8000, 'G3 pkt_bits must be 8000');
    assert(env3.pkt_deadline == 18, 'G3 pkt_deadline must be 18');
    assert(env3.pkt_period == 20, 'G3 pkt_period must be 20');
    assert(env3.N == 10, 'G3 N must be 10');
    assert(base3 == -3, 'G3 base offset must be -3');
    assert(env3.fixed_offset == -3, 'G3 env.fixed_offset must be -3');
    assert(env3.N * env3.pkt_bits / env3.pkt_period == 4000, 'G3 offered load must be 4000 bits/TTI');

    envFixed2 = env2;
    envFixed2.base_rule_force = 'fixed';
    envFixed2.fixed_offset = base2;
    envFixed2 = selectBaseRule_v17n(envFixed2, 2, 1000);

    envFixed3 = env3;
    envFixed3.base_rule_force = 'fixed';
    envFixed3.fixed_offset = base3;
    envFixed3 = selectBaseRule_v17n(envFixed3, 2, 1000);

    ctx.hbf('load_cells: cell environments loaded and asserted successfully');
    out = struct( ...
        'g2', struct('env', env2, 'envFixed', envFixed2, 'base_offset', base2, 'ctx_tab', s2.out.ctx_tab, 'file', f_g2), ...
        'g3', struct('env', env3, 'envFixed', envFixed3, 'base_offset', base3, 'ctx_tab', s3.out.ctx_tab, 'file', f_g3) ...
    );
end

% =========================================================================
function out = unit_log_explore(envFixed, n_calib, o, tr_base, crn_base, exp_base, base_off, calib_mat, ctx)
    ctx.hbf(sprintf('log_explore: logging %d traces (tr_base=%d, crn_base=%d, exp_base=%d, base_off=%d) -> %s', ...
        n_calib, tr_base, crn_base, exp_base, base_off, calib_mat));

    for j = 1:n_calib
        tr_seed = tr_base + j;
        crn_seed = crn_base + j;

        % Disjointness assertions per §4.2
        assert(~(tr_seed >= 500001 && tr_seed <= 570500), 'Evaluation trace seed collision!');
        assert(~(tr_seed >= 1000001 && tr_seed <= 1010500), 'Evaluation trace seed collision!');
        assert(~(tr_seed >= 720001 && tr_seed <= 750500), 'Evaluation trace seed collision!');
        assert(~(crn_seed >= 510001 && crn_seed <= 580500), 'Evaluation CRN seed collision!');
        assert(~(crn_seed >= 1010001 && crn_seed <= 1010500), 'Evaluation CRN seed collision!');
        assert(~(crn_seed >= 730001 && crn_seed <= 750500), 'Evaluation CRN seed collision!');
    end

    max_dec = n_calib * o.simTime * envFixed.N;
    X_buf = zeros(max_dec, 19, 'single');
    mcs_buf = zeros(max_dec, 1, 'int8');
    ack1_buf = zeros(max_dec, 1, 'int8');
    tr_buf = zeros(max_dec, 1, 'int32');
    exp_buf = zeros(max_dec, 1, 'int8');
    n_total = 0;

    for j = 1:n_calib
        rng(tr_base + j, 'twister');
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;

        rng(crn_base + j, 'twister');
        U = rand(o.simTime, envFixed.N);

        pol = struct();
        pol.s_exp = RandStream('twister', 'Seed', exp_base + j);
        pol.trace_id = j;
        pol.base_offset = base_off;

        [~, ~, ~, ~, inf] = evalPolicy_presub('log_explore', pol, Strue, obsS, envFixed, meta, U);

        log_data = inf.r1b_log;
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

    assert(size(X_feat, 2) == 19, 'Observable features must be exactly 19');
    assert(all(ack1 == 0 | ack1 == 1), 'ack1 must be binary {0, 1}');

    save(calib_mat, 'X_feat', 'mcs_taken', 'ack1', 'trace_id', 'explored', 'n_total', '-v7.3');
    out = struct('n_decisions', n_total, 'calib_mat', calib_mat);
end

% =========================================================================
function out = unit_fit(calib_m1, calib_g2, calib_g3, ckpt_r1c, ctx, py_exe)
    if nargin < 6 || isempty(py_exe)
        if isfield(ctx, 'python') && ~isempty(ctx.python)
            py_exe = ctx.python;
        elseif isfield(ctx, 'cfg') && isfield(ctx.cfg, 'python') && ~isempty(ctx.cfg.python)
            py_exe = ctx.cfg.python;
        else
            py_exe = 'D:\miniconda\python.exe';
        end
    end
    ctx.hbf(sprintf('fit: training all 11 models via Python (%s)', py_exe));
    py_script = fullfile(ctx.root, 'train_r1c_ack.py');

    % Manifest collection
    sha_manifest = fullfile(ctx.outdir, 'r1c_models.sha256');
    fid_mani = fopen(sha_manifest, 'w');

    % 1. M1 fit 1 (frozen from R1b)
    m1_fit1_joblib = fullfile(ctx.outdir, 'r1b_model.joblib');
    if ~exist(m1_fit1_joblib, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'r1b_model.joblib');
        if exist(fallback, 'file'), m1_fit1_joblib = fallback; end
    end
    sha1 = strtrim(fileread(fullfile(fileparts(m1_fit1_joblib), 'r1b_hash.txt')));
    fprintf(fid_mani, '%s\n', sha1);

    models_m1 = cell(1, 4);
    models_m1{1} = struct('trees_mat', fullfile(ctx.ckptdir, 'r1b_ack', 'r1b_trees.mat'), 'joblib', m1_fit1_joblib);

    % 2. M1 fits 2..4
    for k = 2:4
        c_mat = calib_m1{k};
        j_out = fullfile(ctx.outdir, sprintf('r1c_model_m1_%d.joblib', k));
        t_mat = fullfile(ckpt_r1c, sprintf('r1c_trees_m1_%d.mat', k));
        h_out = fullfile(ckpt_r1c, sprintf('r1c_hash_m1_%d.txt', k));
        x_csv = fullfile(ckpt_r1c, sprintf('r1c_xfit_m1_%d.csv', k));

        cmd = sprintf('"%s" "%s" "%s" "%s" "%s" "%s" "%s"', py_exe, py_script, c_mat, j_out, t_mat, h_out, x_csv);
        [status, cmdout] = system(cmd);
        if status ~= 0, error('v17x:r1c:fit_m1_failed', 'Python fit M1_%d failed:\n%s', k, cmdout); end
        sha_k = strtrim(fileread(h_out));
        fprintf(fid_mani, '%s\n', sha_k);
        models_m1{k} = struct('trees_mat', t_mat, 'joblib', j_out);
    end

    % 3. G2 fits 1..4
    models_g2 = cell(1, 4);
    for k = 1:4
        c_mat = calib_g2{k};
        j_out = fullfile(ctx.outdir, sprintf('r1c_model_g2_%d.joblib', k));
        t_mat = fullfile(ckpt_r1c, sprintf('r1c_trees_g2_%d.mat', k));
        h_out = fullfile(ckpt_r1c, sprintf('r1c_hash_g2_%d.txt', k));
        x_csv = fullfile(ckpt_r1c, sprintf('r1c_xfit_g2_%d.csv', k));

        cmd = sprintf('"%s" "%s" "%s" "%s" "%s" "%s" "%s"', py_exe, py_script, c_mat, j_out, t_mat, h_out, x_csv);
        [status, cmdout] = system(cmd);
        if status ~= 0, error('v17x:r1c:fit_g2_failed', 'Python fit G2_%d failed:\n%s', k, cmdout); end
        sha_k = strtrim(fileread(h_out));
        fprintf(fid_mani, '%s\n', sha_k);
        models_g2{k} = struct('trees_mat', t_mat, 'joblib', j_out);
    end

    % 4. G3 fits 1..4
    models_g3 = cell(1, 4);
    for k = 1:4
        c_mat = calib_g3{k};
        j_out = fullfile(ctx.outdir, sprintf('r1c_model_g3_%d.joblib', k));
        t_mat = fullfile(ckpt_r1c, sprintf('r1c_trees_g3_%d.mat', k));
        h_out = fullfile(ckpt_r1c, sprintf('r1c_hash_g3_%d.txt', k));
        x_csv = fullfile(ckpt_r1c, sprintf('r1c_xfit_g3_%d.csv', k));

        cmd = sprintf('"%s" "%s" "%s" "%s" "%s" "%s" "%s"', py_exe, py_script, c_mat, j_out, t_mat, h_out, x_csv);
        [status, cmdout] = system(cmd);
        if status ~= 0, error('v17x:r1c:fit_g3_failed', 'Python fit G3_%d failed:\n%s', k, cmdout); end
        sha_k = strtrim(fileread(h_out));
        fprintf(fid_mani, '%s\n', sha_k);
        models_g3{k} = struct('trees_mat', t_mat, 'joblib', j_out);
    end
    fclose(fid_mani);

    ctx.hbf(sprintf('fit: all 11 models trained and hashed into %s', sha_manifest));
    out = struct('m1', {models_m1}, 'g2', {models_g2}, 'g3', {models_g3}, 'sha_manifest', sha_manifest);
end

% =========================================================================
function out = unit_equiv(models, ctx)
    ctx.hbf('equiv: verifying tree prediction equivalence with scikit-learn for all models (1e-9 gate)');

    trees_m1 = cell(1, 4);
    for k = 1:4
        trees_m1{k} = check_model_equiv(models.m1{k}.trees_mat, sprintf('M1 fit %d', k), ctx);
    end

    trees_g2 = cell(1, 4);
    for k = 1:4
        trees_g2{k} = check_model_equiv(models.g2{k}.trees_mat, sprintf('G2 fit %d', k), ctx);
    end

    trees_g3 = cell(1, 4);
    for k = 1:4
        trees_g3{k} = check_model_equiv(models.g3{k}.trees_mat, sprintf('G3 fit %d', k), ctx);
    end

    ctx.hbf('equiv: EQUIVALENCE GATE PASS for all 12 models (max abs diff <= 1e-9)');
    out = struct('m1', {trees_m1}, 'g2', {trees_g2}, 'g3', {trees_g3});
end

function m = check_model_equiv(trees_mat, tag, ctx)
    S = load(trees_mat);
    m = S.trees_export;
    X_equiv = S.X_equiv;
    P_pred_sk = S.P_pred_sk;

    n_eq = size(X_equiv, 1);
    P_pred_mat = zeros(n_eq, 1);

    trees = m.trees;
    if isstruct(trees) && numel(trees) > 1
        t_cell = cell(1, numel(trees));
        for k = 1:numel(trees), t_cell{k} = trees(k); end
        m.trees = t_cell;
    end

    for i = 1:n_eq
        P_pred_mat(i) = gbt_predict_prob_local(m, X_equiv(i, :));
    end

    max_diff = max(abs(P_pred_mat - P_pred_sk(:)));
    if max_diff > 1e-9
        error('v17x:r1c:equiv_fail', 'Equivalence check failed for %s: diff %.3e > 1e-9', tag, max_diff);
    end
end

% =========================================================================
function out = unit_repro(envFixed_M1, cells, n_repro, o, ctx)
    ctx.hbf(sprintf('repro: checking bit-identity on first %d traces of NR2, G2, G3', n_repro));

    % 1. NR2 REPRO (Fixed-500, Context-joint-500, NR2 seed 1)
    eval_nr2_file = fullfile(ctx.ckptdir, 'nr2', 'eval.mat');
    if ~exist(eval_nr2_file, 'file')
        eval_nr2_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'eval.mat');
    end
    st_nr2 = load(eval_nr2_file);

    nr2_s1_file = fullfile(ctx.ckptdir, 'nr2', 'train_seed_1.mat');
    if ~exist(nr2_s1_file, 'file')
        nr2_s1_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'train_seed_1.mat');
    end
    sd1 = load(nr2_s1_file);
    pol_nr2_s1 = sd1.out.a2c;

    tables_file = fullfile(ctx.root, 'Dataset', 'cal500_tables.txt');
    ctxj_tab = read_ctxj_from_tables(tables_file);
    e_ctxj = envFixed_M1;
    e_ctxj.ctxj_tab = ctxj_tab;
    b0_m1 = min(envFixed_M1.burn_in, o.simTime - 1);

    for j = 1:n_repro
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed_M1);
        obsS = cqiFeedback_v17(Strue, envFixed_M1, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(o.simTime, envFixed_M1.N);

        % Fixed
        rng(1020000 + 100*j + 10*5 + 1, 'twister');
        [tp, ~, ~, ~, inf] = evalPolicy_presub('fixed', [], Strue, obsS, envFixed_M1, meta, U);
        [~, ~, p_fix] = userMetric_v17(envFixed_M1, tp, inf, b0_m1);
        assert(abs(p_fix - st_nr2.out.cmp.fixed500(j)) == 0, 'NR2 Fixed repro failed');

        % Context-joint
        rng(1020000 + 100*j + 10*99 + 1, 'twister');
        [tp, ~, ~, ~, inf] = evalPolicy_presub('ctxj', [], Strue, obsS, e_ctxj, meta, U);
        [~, ~, p_cj] = userMetric_v17(e_ctxj, tp, inf, b0_m1);
        assert(abs(p_cj - st_nr2.out.cmp.ctxj500(j)) == 0, 'NR2 Context-joint repro failed');

        % NR2 seed 1
        rng(1020000 + 100*j + 10*8 + 1, 'twister');
        [tp, ~, ~, ~, inf] = evalPolicy_presub('a2c_v17', pol_nr2_s1, Strue, obsS, envFixed_M1, meta, U);
        [~, ~, p_nr2] = userMetric_v17(envFixed_M1, tp, inf, b0_m1);
        assert(abs(p_nr2 - st_nr2.out.nr2_seeds(1, j)) == 0, 'NR2 seed 1 repro failed');
    end

    % 2. G2 REPRO (Fixed, Context table, NR-G10 seed 1)
    eval_g2_file = fullfile(ctx.ckptdir, 'nr_g10', 'eval_G2_hi_d10.mat');
    if ~exist(eval_g2_file, 'file'), eval_g2_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr_g10', 'eval_G2_hi_d10.mat'); end
    if ~exist(eval_g2_file, 'file'), eval_g2_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'g10', 'eval_G2_hi_d10.mat'); end
    st_g2 = load(eval_g2_file);

    g2_s1_file = fullfile(ctx.ckptdir, 'nr_g10', 'train_seed_G2_hi_d10_1.mat');
    if ~exist(g2_s1_file, 'file'), g2_s1_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr_g10', 'train_seed_G2_hi_d10_1.mat'); end
    if ~exist(g2_s1_file, 'file'), g2_s1_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'g10', 'train_seed_G2_hi_d10_1.mat'); end
    sd_g2_1 = load(g2_s1_file);
    pol_g2_s1 = sd_g2_1.out.a2c;

    env_g2 = cells.g2.envFixed;
    e_ctx2 = env_g2;
    e_ctx2.ctx_tab = cells.g2.ctx_tab;
    b0_g2 = min(env_g2.burn_in, o.simTime - 1);
    for j = 1:n_repro
        tr_seed = 720000 + j; crn_seed = 730000 + j;
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, env_g2);
        obsS = cqiFeedback_v17(Strue, env_g2, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(o.simTime, env_g2.N);

        % G2 Fixed
        rng(61500 + j);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('fixed', [], Strue, obsS, env_g2, meta, U);
        [~, ~, p_fix2] = userMetric_v17(env_g2, tp, inf, b0_g2);
        assert(abs(p_fix2 - st_g2.out.cmp_vals{5}(j)) == 0, 'G2 Fixed repro failed');

        % G2 Context table
        rng(61500 + j);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('ctxtab', [], Strue, obsS, e_ctx2, meta, U);
        [~, ~, p_tab2] = userMetric_v17(env_g2, tp, inf, b0_g2);
        assert(abs(p_tab2 - st_g2.out.cmp_vals{7}(j)) == 0, 'G2 Context table repro failed');

        % G2 NR-G10 seed 1
        rng(77000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('a2c_v17', pol_g2_s1, Strue, obsS, env_g2, meta, U);
        [~, ~, p_g2_s1] = userMetric_v17(env_g2, tp, inf, b0_g2);
        assert(abs(p_g2_s1 - st_g2.out.rl_seeds(1, j)) == 0, 'G2 seed 1 repro failed');
    end

    % 3. G3 REPRO (Fixed, Context table, NR-G10 seed 1)
    eval_g3_file = fullfile(ctx.ckptdir, 'nr_g10', 'eval_G3_lo_d18.mat');
    if ~exist(eval_g3_file, 'file'), eval_g3_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr_g10', 'eval_G3_lo_d18.mat'); end
    if ~exist(eval_g3_file, 'file'), eval_g3_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'g10', 'eval_G3_lo_d18.mat'); end
    st_g3 = load(eval_g3_file);

    g3_s1_file = fullfile(ctx.ckptdir, 'nr_g10', 'train_seed_G3_lo_d18_1.mat');
    if ~exist(g3_s1_file, 'file'), g3_s1_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr_g10', 'train_seed_G3_lo_d18_1.mat'); end
    if ~exist(g3_s1_file, 'file'), g3_s1_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'g10', 'train_seed_G3_lo_d18_1.mat'); end
    sd_g3_1 = load(g3_s1_file);
    pol_g3_s1 = sd_g3_1.out.a2c;

    env_g3 = cells.g3.envFixed;
    e_ctx3 = env_g3;
    e_ctx3.ctx_tab = cells.g3.ctx_tab;
    b0_g3 = min(env_g3.burn_in, o.simTime - 1);
    for j = 1:n_repro
        tr_seed = 740000 + j; crn_seed = 750000 + j;
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, env_g3);
        obsS = cqiFeedback_v17(Strue, env_g3, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(o.simTime, env_g3.N);

        % G3 Fixed
        rng(61500 + j);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('fixed', [], Strue, obsS, env_g3, meta, U);
        [~, ~, p_fix3] = userMetric_v17(env_g3, tp, inf, b0_g3);
        assert(abs(p_fix3 - st_g3.out.cmp_vals{5}(j)) == 0, 'G3 Fixed repro failed');

        % G3 Context table
        rng(61500 + j);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('ctxtab', [], Strue, obsS, e_ctx3, meta, U);
        [~, ~, p_tab3] = userMetric_v17(env_g3, tp, inf, b0_g3);
        assert(abs(p_tab3 - st_g3.out.cmp_vals{7}(j)) == 0, 'G3 Context table repro failed');

        % G3 NR-G10 seed 1
        rng(77000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('a2c_v17', pol_g3_s1, Strue, obsS, env_g3, meta, U);
        [~, ~, p_g3_s1] = userMetric_v17(env_g3, tp, inf, b0_g3);
        assert(abs(p_g3_s1 - st_g3.out.rl_seeds(1, j)) == 0, 'G3 seed 1 repro failed');
    end

    ctx.hbf('repro: REPRO PASS for NR2, G2, G3 (max_abs_diff = 0)');
    out = struct('repro_pass', true);
end

% =========================================================================
function out = unit_eval_nr2(envFixed, trees_m1, n_eval, o, ctx)
    ctx.hbf(sprintf('eval_nr2: evaluating M1 fits 2-4 on %d NR2 traces', n_eval));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    % Load M1 fit 1 from R1b
    r1b_mat = fullfile(ctx.ckptdir, 'r1b_ack', 'r1b_eval.mat');
    if ~exist(r1b_mat, 'file'), r1b_mat = fullfile(ctx.root, 'Dataset', 'ckpt', 'r1b_ack', 'r1b_eval.mat'); end
    s_r1b = load(r1b_mat);

    res_nr2 = zeros(4, n_eval);
    full_nr2 = zeros(4, n_eval);
    res_nr2(1, :)  = s_r1b.gbt_res_nr2(1:n_eval);
    full_nr2(1, :) = s_r1b.gbt_full_nr2(1:n_eval);

    for k = 2:4
        ctx.hbf(sprintf('eval_nr2: M1 fit %d...', k));
        m = trees_m1{k};
        r_k = zeros(1, n_eval);
        f_k = zeros(1, n_eval);
        for j = 1:n_eval
            tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
            crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
            rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
            obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
            meta.trace_id = j;
            rng(crn_seed, 'twister'); U = rand(o.simTime, envFixed.N);

            % res
            [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_res_ack', m, Strue, obsS, envFixed, meta, U);
            [~, ~, r_k(j)] = userMetric_v17(envFixed, tp, inf, b0);

            % full
            [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_full_ack', m, Strue, obsS, envFixed, meta, U);
            [~, ~, f_k(j)] = userMetric_v17(envFixed, tp, inf, b0);
        end
        res_nr2(k, :) = r_k;
        full_nr2(k, :) = f_k;
        ctx.hbf(sprintf('eval_nr2: M1 fit %d: res=%.4f, full=%.4f', k, mean(r_k), mean(f_k)));
    end

    out = struct('res', res_nr2, 'full', full_nr2);
end

% =========================================================================
function out = unit_eval_cell(cell_name, envFixed, trees_cell, n_eval, o, ctx)
    ctx.hbf(sprintf('eval_%s_cellfit: evaluating %s cell fits 1-4 on %d traces', cell_name, cell_name, n_eval));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    if strcmp(cell_name, 'g2')
        tr_base = 720000; crn_base = 730000;
    else
        tr_base = 740000; crn_base = 750000;
    end

    res_cell = zeros(4, n_eval);
    full_cell = zeros(4, n_eval);

    for k = 1:4
        ctx.hbf(sprintf('eval_%s_cellfit: fit %d...', cell_name, k));
        m = trees_cell{k};
        r_k = zeros(1, n_eval);
        f_k = zeros(1, n_eval);
        for j = 1:n_eval
            tr_seed = tr_base + j; crn_seed = crn_base + j;
            rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
            obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
            meta.trace_id = j;
            rng(crn_seed, 'twister'); U = rand(o.simTime, envFixed.N);

            % res
            [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_res_ack', m, Strue, obsS, envFixed, meta, U);
            [~, ~, r_k(j)] = userMetric_v17(envFixed, tp, inf, b0);

            % full
            [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_full_ack', m, Strue, obsS, envFixed, meta, U);
            [~, ~, f_k(j)] = userMetric_v17(envFixed, tp, inf, b0);
        end
        res_cell(k, :) = r_k;
        full_cell(k, :) = f_k;
        ctx.hbf(sprintf('eval_%s_cellfit: fit %d: res=%.4f, full=%.4f', cell_name, k, mean(r_k), mean(f_k)));
    end

    out = struct('res', res_cell, 'full', full_cell);
end

% =========================================================================
function out = unit_eval_transfer(cell_name, envFixed, trees_m1, n_eval, o, ctx)
    ctx.hbf(sprintf('eval_%s_transfer: evaluating M1 fits 1-4 on %s (%d traces)', cell_name, cell_name, n_eval));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    if strcmp(cell_name, 'g2')
        tr_base = 720000; crn_base = 730000;
    else
        tr_base = 740000; crn_base = 750000;
    end

    res_trans = zeros(4, n_eval);
    full_trans = zeros(4, n_eval);

    for k = 1:4
        ctx.hbf(sprintf('eval_%s_transfer: M1 fit %d...', cell_name, k));
        m = trees_m1{k};
        r_k = zeros(1, n_eval);
        f_k = zeros(1, n_eval);
        for j = 1:n_eval
            tr_seed = tr_base + j; crn_seed = crn_base + j;
            rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
            obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
            meta.trace_id = j;
            rng(crn_seed, 'twister'); U = rand(o.simTime, envFixed.N);

            % res
            [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_res_ack', m, Strue, obsS, envFixed, meta, U);
            [~, ~, r_k(j)] = userMetric_v17(envFixed, tp, inf, b0);

            % full
            [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_full_ack', m, Strue, obsS, envFixed, meta, U);
            [~, ~, f_k(j)] = userMetric_v17(envFixed, tp, inf, b0);
        end
        res_trans(k, :) = r_k;
        full_trans(k, :) = f_k;
        ctx.hbf(sprintf('eval_%s_transfer: M1 fit %d: res=%.4f, full=%.4f', cell_name, k, mean(r_k), mean(f_k)));
    end

    out = struct('res', res_trans, 'full', full_trans);
end

% =========================================================================
function out = unit_export(eval_nr2, eval_g2_cell, eval_g3_cell, eval_g2_trans, eval_g3_trans, sha_manifest, n_eval_nr2, n_eval_cell, ctx)
    ctx.hbf('export: writing pertrace_r1c.csv and REPORT_r1c.txt');
    r1c_dir = fullfile(ctx.outdir, 'presub', 'r1c');
    if ~exist(r1c_dir, 'dir'), mkdir(r1c_dir); end

    pertrace_csv = fullfile(r1c_dir, 'pertrace_r1c.csv');
    fid = fopen(pertrace_csv, 'w');
    fprintf(fid, 'trace_set,scheme,seed,trace,value\n');

    % 1. NR2 traces (M1 fits 2..4; M1 fit 1 is sourced from r1b)
    for k = 2:4
        sch_res = sprintf('GBT-res-ACK-M1fit%d', k);
        sch_full = sprintf('GBT-full-ACK-M1fit%d', k);
        for j = 1:n_eval_nr2
            fprintf(fid, 'NR2,%s,0,%d,%.6f\n', sch_res, j, eval_nr2.res(k, j));
            fprintf(fid, 'NR2,%s,0,%d,%.6f\n', sch_full, j, eval_nr2.full(k, j));
        end
    end

    % 2. G2 cell fits (fits 1..4)
    for k = 1:4
        sch_res = sprintf('GBT-res-ACK-cellfit%d', k);
        sch_full = sprintf('GBT-full-ACK-cellfit%d', k);
        for j = 1:n_eval_cell
            fprintf(fid, 'G2,%s,0,%d,%.6f\n', sch_res, j, eval_g2_cell.res(k, j));
            fprintf(fid, 'G2,%s,0,%d,%.6f\n', sch_full, j, eval_g2_cell.full(k, j));
        end
    end

    % 3. G3 cell fits (fits 1..4)
    for k = 1:4
        sch_res = sprintf('GBT-res-ACK-cellfit%d', k);
        sch_full = sprintf('GBT-full-ACK-cellfit%d', k);
        for j = 1:n_eval_cell
            fprintf(fid, 'G3,%s,0,%d,%.6f\n', sch_res, j, eval_g3_cell.res(k, j));
            fprintf(fid, 'G3,%s,0,%d,%.6f\n', sch_full, j, eval_g3_cell.full(k, j));
        end
    end

    % 4. G2 transfer (M1 fits 1..4)
    for k = 1:4
        sch_res = sprintf('GBT-res-ACK-M1fit%d', k);
        sch_full = sprintf('GBT-full-ACK-M1fit%d', k);
        for j = 1:n_eval_cell
            fprintf(fid, 'G2,%s,0,%d,%.6f\n', sch_res, j, eval_g2_trans.res(k, j));
            fprintf(fid, 'G2,%s,0,%d,%.6f\n', sch_full, j, eval_g2_trans.full(k, j));
        end
    end

    % 5. G3 transfer (M1 fits 1..4)
    for k = 1:4
        sch_res = sprintf('GBT-res-ACK-M1fit%d', k);
        sch_full = sprintf('GBT-full-ACK-M1fit%d', k);
        for j = 1:n_eval_cell
            fprintf(fid, 'G3,%s,0,%d,%.6f\n', sch_res, j, eval_g3_trans.res(k, j));
            fprintf(fid, 'G3,%s,0,%d,%.6f\n', sch_full, j, eval_g3_trans.full(k, j));
        end
    end
    fclose(fid);

    % Save MAT checkpoint
    r1c_eval_mat = fullfile(ctx.ckptdir, 'r1c', 'r1c_eval.mat');
    save(r1c_eval_mat, 'eval_nr2', 'eval_g2_cell', 'eval_g3_cell', 'eval_g2_trans', 'eval_g3_trans', '-v7.3');

    % Write REPORT_r1c.txt
    rep_file = fullfile(ctx.outdir, 'REPORT_r1c.txt');
    fid = fopen(rep_file, 'w');
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'REPORT_r1c.txt -- Calibration-Draw Replication & Per-Cell Generalization (Stage r1c)\n');
    fprintf(fid, 'Generated: %s | MATLAB %s\n', datestr(now, 31), version);
    fprintf(fid, '================================================================================\n\n');
    if exist(sha_manifest, 'file')
        fprintf(fid, 'Model SHA-256 Manifest:\n%s\n', fileread(sha_manifest));
    end
    fprintf(fid, '\nNR2 Evaluation Traces (n=%d):\n', n_eval_nr2);
    for k = 1:4
        fprintf(fid, '  M1 Fit %d: GBT-res-ACK = %.4f | GBT-full-ACK = %.4f\n', ...
            k, mean(eval_nr2.res(k, :)), mean(eval_nr2.full(k, :)));
    end
    fprintf(fid, '\nG2 Evaluation Traces (Cell Fits, n=%d):\n', n_eval_cell);
    for k = 1:4
        fprintf(fid, '  G2 Fit %d: GBT-res-ACK = %.4f | GBT-full-ACK = %.4f\n', ...
            k, mean(eval_g2_cell.res(k, :)), mean(eval_g2_cell.full(k, :)));
    end
    fprintf(fid, '\nG3 Evaluation Traces (Cell Fits, n=%d):\n', n_eval_cell);
    for k = 1:4
        fprintf(fid, '  G3 Fit %d: GBT-res-ACK = %.4f | GBT-full-ACK = %.4f\n', ...
            k, mean(eval_g3_cell.res(k, :)), mean(eval_g3_cell.full(k, :)));
    end
    fclose(fid);

    ctx.hbf(sprintf('export: pertrace_r1c.csv and REPORT_r1c.txt written to %s', r1c_dir));
    out = struct('pertrace_csv', pertrace_csv, 'report', rep_file);
end

% Local tree prediction helper
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

function tab = read_ctxj_from_tables(fpath)
    tab = zeros(3, 2, 3, 2);
    if ~exist(fpath, 'file'), return; end
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
