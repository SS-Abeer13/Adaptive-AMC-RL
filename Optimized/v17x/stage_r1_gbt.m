function stage_r1_gbt(ctx)
% stage_r1_gbt  One-step supervised learner (GBT) comparator.
% Spec: paper/proposals/R_presub_prereg.md §3 and §12 (Amendment 8, Freeze v9).
% Units:
%   log_calib
%   fit
%   equiv
%   repro
%   eval_NR2
%   eval_M1
%   export
% Outputs:
%   Dataset/gbt_models.joblib
%   Dataset/r1_gbt_hash.txt
%   Dataset/ckpt/r1_gbt/r1_gbt_eval.mat
%   Dataset/REPORT_r1_gbt.txt
%   Dataset/stage_r1_gbt.done

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

    ctx.hbf(sprintf('r1_gbt start: n_calib=%d, n_eval=%d, n_repro=%d', n_calib, n_eval, n_repro));

    envFixed = env_M1;
    envFixed.base_rule_force = 'fixed';
    envFixed.fixed_offset = -2;
    [envFixed, ~] = selectBaseRule_v17n(envFixed, 2, o.simTime);

    ckpt_r1 = fullfile(ctx.ckptdir, 'r1_gbt');
    if ~exist(ckpt_r1, 'dir'), mkdir(ckpt_r1); end

    % ---- 1. Unit: log_calib ----
    calib_mat = fullfile(ckpt_r1, 'calib_log.mat');
    ctx.unit('log_calib', @() unit_log_calib(envFixed, n_calib, o, calib_mat, ctx));

    % ---- 2. Unit: fit ----
    joblib_out = fullfile(ctx.outdir, 'gbt_models.joblib');
    trees_mat  = fullfile(ckpt_r1, 'gbt_trees.mat');
    hash_out   = fullfile(ctx.outdir, 'r1_gbt_hash.txt');
    ctx.unit('fit', @() unit_fit(calib_mat, joblib_out, trees_mat, hash_out, ctx));

    % ---- 3. Unit: equiv ----
    trees_data = ctx.unit('equiv', @() unit_equiv(trees_mat, ctx));

    % ---- 4. Unit: repro ----
    ctx.unit('repro', @() unit_repro(envFixed, n_repro, o, ctx));

    % ---- 5. Unit: eval_NR2 ----
    eval_nr2 = ctx.unit('eval_NR2', @() unit_eval_nr2(envFixed, trees_data, n_eval, o, ctx));

    % ---- 6. Unit: eval_M1 ----
    eval_m1 = ctx.unit('eval_M1', @() unit_eval_m1(envFixed, trees_data, n_eval, o, ctx));

    % ---- 7. Unit: export ----
    ctx.unit('export', @() unit_export(eval_nr2, eval_m1, n_eval, hash_out, ctx));

    ctx.hbf('r1_gbt done successfully');
end

% =========================================================================
function out = unit_log_calib(envFixed, n_calib, o, calib_mat, ctx)
    ctx.hbf(sprintf('log_calib: logging calibration decisions from %d traces', n_calib));

    calib_trace_base = 600000;
    calib_crn_base   = 610000;
    for j = 1:n_calib
        tr_seed = calib_trace_base + j;
        crn_seed = calib_crn_base + j;
        assert(~(tr_seed >= 500001 && tr_seed <= 570500), 'Evaluation trace seed in calibration!');
        assert(~(tr_seed >= 1000001 && tr_seed <= 1000500), 'Evaluation trace seed in calibration!');
        assert(~(tr_seed >= 720000 && tr_seed <= 750500), 'Evaluation trace seed in calibration!');
        assert(~(crn_seed >= 510001 && crn_seed <= 580500), 'Evaluation CRN seed in calibration!');
        assert(~(crn_seed >= 1010001 && crn_seed <= 1010500), 'Evaluation CRN seed in calibration!');
    end

    max_dec = n_calib * o.simTime * envFixed.N;
    X_buf = zeros(max_dec, 19, 'single');
    Y_buf = zeros(max_dec, 7, 'single');
    n_total = 0;

    for j = 1:n_calib
        rng(calib_trace_base + j);
        [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = calib_trace_base + j;
        rng(calib_crn_base + j);
        U = rand(o.simTime, envFixed.N);

        rng(77000 + 100*j + 10*5 + 1);
        [~, ~, ~, ~, inf] = evalPolicy_v17_hr('fixed', [], Strue, obsS, envFixed, meta, U);

        hr_log = inf.hr_log;
        COLS = inf.hr_cols;
        n_dec = size(hr_log, 1);
        if n_dec > 0
            c_obs1 = find(strcmp(COLS, 'obs_1'));
            c_obs19 = find(strcmp(COLS, 'obs_19'));
            c_ubits_start = find(strcmp(COLS, 'ubits_m4'));
            c_psucc_start = find(strcmp(COLS, 'psucc_m4'));

            obs19 = hr_log(:, c_obs1:c_obs19);
            ubits = hr_log(:, c_ubits_start:c_ubits_start+6);
            psucc = hr_log(:, c_psucc_start:c_psucc_start+6);

            q_vals = psucc .* ubits;

            idx_s = n_total + 1;
            idx_e = n_total + n_dec;
            X_buf(idx_s:idx_e, :) = single(obs19);
            Y_buf(idx_s:idx_e, :) = single(q_vals);
            n_total = idx_e;
        end
    end

    X = X_buf(1:n_total, :);
    Y = Y_buf(1:n_total, :);
    ctx.hbf(sprintf('log_calib: %d decisions logged. Saving to %s', n_total, calib_mat));
    save(calib_mat, 'X', 'Y', 'n_total', '-v7.3');
    out = struct('n_decisions', n_total, 'calib_mat', calib_mat);
end

% =========================================================================
function out = unit_fit(calib_mat, joblib_out, trees_mat, hash_out, ctx)
    ctx.hbf('fit: calling python train_r1_gbt.py...');
    py_script = fullfile(ctx.root, 'train_r1_gbt.py');
    cmd = sprintf('python "%s" "%s" "%s" "%s" "%s"', py_script, calib_mat, joblib_out, trees_mat, hash_out);
    [status, cmdout] = system(cmd);
    if status ~= 0
        error('v17x:r1_gbt:fit_failed', 'Python GBT training failed:\n%s', cmdout);
    end
    ctx.hbf(sprintf('fit: python GBT training successful:\n%s', strtrim(cmdout)));

    if ~exist(joblib_out, 'file') || ~exist(hash_out, 'file') || ~exist(trees_mat, 'file')
        error('v17x:r1_gbt:missing_artifacts', 'Expected GBT artifacts missing after fit');
    end
    sha256 = strtrim(fileread(hash_out));
    ctx.hbf(sprintf('fit: GBT models SHA-256 = %s', sha256));
    out = struct('sha256', sha256, 'joblib', joblib_out);
end

% =========================================================================
function out = unit_equiv(trees_mat, ctx)
    ctx.hbf('equiv: verifying tree prediction equivalence with scikit-learn (1e-9 gate)');
    S = load(trees_mat);
    trees_export = S.trees_export;
    X_equiv = S.X_equiv;
    Y_pred_sk = S.Y_pred_sk;

    n_eq = size(X_equiv, 1);
    Y_pred_mat = zeros(n_eq, 7);

    models = cell(1, 7);
    for a = 1:7
        if iscell(trees_export)
            models{a} = trees_export{a};
        else
            models{a} = trees_export(a);
        end
    end

    for a = 1:7
        m = models{a};
        trees = m.trees;
        if isstruct(trees) && numel(trees) > 1
            t_cell = cell(1, numel(trees));
            for k = 1:numel(trees), t_cell{k} = trees(k); end
            m.trees = t_cell;
            models{a} = m;
        end
        for i = 1:n_eq
            Y_pred_mat(i, a) = model_predict(m, X_equiv(i, :));
        end
    end

    diff_mat = abs(Y_pred_mat - Y_pred_sk);
    max_diff = max(diff_mat(:));
    ctx.hbf(sprintf('equiv: max abs difference between MATLAB and scikit-learn = %.3e', max_diff));
    if max_diff > 1e-9
        error('v17x:r1_gbt:equiv_fail', 'GBT equivalence check failed: max abs diff %.3e > 1e-9', max_diff);
    end
    ctx.hbf('equiv: EQUIVALENCE GATE PASS (max abs diff <= 1e-9)');
    out = models;
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
            error('v17x:r1:repro', 'REPRO failed on NR2 Fixed-500 trace %d: diff=%.3e', j, abs(p - stored_f));
        end
    end

    eval_g6c_file = fullfile(ctx.ckptdir, 'g6c', 'eval.mat');
    if ~exist(eval_g6c_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'g6c', 'eval.mat');
        if exist(fallback, 'file'), eval_g6c_file = fallback; else, error('g6c/eval.mat missing'); end
    end
    st_g6c = load(eval_g6c_file);

    for j = 1:n_repro
        rng(500000 + j); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;
        rng(510000 + j); U = rand(o.simTime, envFixed.N);
        rng(77000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('fixed', [], Strue, obsS, envFixed, meta, U);
        [~, ~, p] = userMetric_v17(envFixed, tp, inf, b0);
        stored_f = st_g6c.out.prim_fixed500(j);
        if abs(p - stored_f) ~= 0
            error('v17x:r1:repro', 'REPRO failed on M1 Fixed-500 trace %d: diff=%.3e', j, abs(p - stored_f));
        end
    end

    ctx.hbf('repro: bit-identity verified on NR2 and M1 traces (max_abs_diff = 0)');
    out = struct('repro_pass', true);
end

% =========================================================================
function out = unit_eval_nr2(envFixed, models, n_eval, o, ctx)
    ctx.hbf(sprintf('eval_NR2: evaluating GBT-res and GBT-full on %d NR2 traces', n_eval));
    b0 = min(envFixed.burn_in, o.simTime - 1);

    vals_res = zeros(1, n_eval);
    vals_full = zeros(1, n_eval);

    for j = 1:n_eval
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
        rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;
        rng(crn_seed); U = rand(o.simTime, envFixed.N);

        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_res', models, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_res(j)] = userMetric_v17(envFixed, tp, inf, b0);

        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_full', models, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_full(j)] = userMetric_v17(envFixed, tp, inf, b0);
    end

    ctx.hbf(sprintf('eval_NR2: GBT-res mean ontime=%.4f, GBT-full mean ontime=%.4f', ...
        mean(vals_res), mean(vals_full)));
    out = struct('gbt_res', vals_res, 'gbt_full', vals_full);
end

% =========================================================================
function out = unit_eval_m1(envFixed, models, n_eval, o, ctx)
    ctx.hbf(sprintf('eval_M1: evaluating GBT-res, GBT-full, and NR2 policies on %d M1 traces', n_eval));
    b0 = min(envFixed.burn_in, o.simTime - 1);
    n_seeds = ternary(ctx.smoke, 2, 10);

    vals_res = zeros(1, n_eval);
    vals_full = zeros(1, n_eval);
    nr2_m1_seeds = zeros(n_seeds, n_eval);

    nr2_pols = cell(1, n_seeds);
    for s = 1:n_seeds
        ckpt_s = fullfile(ctx.ckptdir, 'nr2', sprintf('train_seed_%d.mat', s));
        if ~exist(ckpt_s, 'file')
            fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', sprintf('train_seed_%d.mat', s));
            if exist(fallback, 'file'), ckpt_s = fallback; else, error('train_seed_%d.mat missing', s); end
        end
        sd = load(ckpt_s);
        nr2_pols{s} = sd.out.a2c;
    end

    for j = 1:n_eval
        rng(500000 + j); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFixed);
        obsS = cqiFeedback_v17(Strue, envFixed, meta.delays);
        meta.trace_id = j;
        rng(510000 + j); U = rand(o.simTime, envFixed.N);

        rng(77000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_res', models, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_res(j)] = userMetric_v17(envFixed, tp, inf, b0);

        rng(77000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_full', models, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_full(j)] = userMetric_v17(envFixed, tp, inf, b0);

        for s = 1:n_seeds
            rng(77000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', nr2_pols{s}, Strue, obsS, envFixed, meta, U);
            [~, ~, nr2_m1_seeds(s, j)] = userMetric_v17(envFixed, tp, inf, b0);
        end
    end

    ctx.hbf(sprintf('eval_M1: GBT-res=%.4f, GBT-full=%.4f, NR2 (mean over %d seeds)=%.4f', ...
        mean(vals_res), mean(vals_full), n_seeds, mean(mean(nr2_m1_seeds))));
    out = struct('gbt_res', vals_res, 'gbt_full', vals_full, 'nr2_m1_seeds', nr2_m1_seeds);
end

% =========================================================================
function out = unit_export(eval_nr2, eval_m1, n_eval, hash_out, ctx)
    ctx.hbf('export: exporting r1_gbt_eval.mat and REPORT_r1_gbt.txt');
    ckpt_r1 = fullfile(ctx.ckptdir, 'r1_gbt');
    r1_eval_mat = fullfile(ckpt_r1, 'r1_gbt_eval.mat');

    gbt_res_nr2  = eval_nr2.gbt_res;
    gbt_full_nr2 = eval_nr2.gbt_full;
    gbt_res_m1   = eval_m1.gbt_res;
    gbt_full_m1  = eval_m1.gbt_full;
    nr2_m1_seeds = eval_m1.nr2_m1_seeds;

    save(r1_eval_mat, 'gbt_res_nr2', 'gbt_full_nr2', 'gbt_res_m1', 'gbt_full_m1', 'nr2_m1_seeds', '-v7.3');

    sha256 = '';
    if exist(hash_out, 'file'), sha256 = strtrim(fileread(hash_out)); end

    rep_file = fullfile(ctx.outdir, 'REPORT_r1_gbt.txt');
    fid = fopen(rep_file, 'w');
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'REPORT_r1_gbt.txt -- One-Step Supervised Learner (Stage r1_gbt)\n');
    fprintf(fid, 'Generated: %s | MATLAB %s\n', datestr(now, 31), version);
    fprintf(fid, '================================================================================\n\n');
    fprintf(fid, 'GBT model hash: %s\n', sha256);
    fprintf(fid, 'Evaluation traces: n_eval=%d\n\n', n_eval);
    fprintf(fid, 'NR2 traces:\n');
    fprintf(fid, '  GBT-res  mean on-time: %.4f\n', mean(gbt_res_nr2));
    fprintf(fid, '  GBT-full mean on-time: %.4f\n\n', mean(gbt_full_nr2));
    fprintf(fid, 'M1 traces (secondary):\n');
    fprintf(fid, '  GBT-res  mean on-time: %.4f\n', mean(gbt_res_m1));
    fprintf(fid, '  GBT-full mean on-time: %.4f\n', mean(gbt_full_m1));
    fprintf(fid, '  NR2 (re-evaluated, %d seeds) mean on-time: %.4f\n', size(nr2_m1_seeds, 1), mean(mean(nr2_m1_seeds)));
    fclose(fid);

    out = struct('r1_eval_mat', r1_eval_mat, 'report', rep_file);
end

% =========================================================================
function q = model_predict(model, x)
    q = model.baseline;
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
        q = q + t.val(idx);
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
