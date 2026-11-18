function stage_r6_fullaction(ctx)
% stage_r6_fullaction  Residual RL with the full action set (-4..+2) against
% the ACK-trained one-step learner (GBT-full-ACK).
% Spec: paper/proposals/R6_fullaction_prereg.md (Amendment 11, Freeze v13).
% Units:
%   gate_default : NR2 seed 1 repro on 20 traces, unchanged [-1 0 1] config
%   smoke        : one seed, 20 episodes, full action set, on preflight range
%   train_k (k=1..10) : RL-full training seeds
%   repro        : ctxj500 and NR2 seed 1 on traces 1-20, exact match
%   eval         : RL-full seeds 1-10 on the 500 NR2 traces, delta/clip shares
%   r6b_log, r6b_fit, r6b_equiv, r6b_eval (optional): true-SINR one-step model
%                  on the R1b exploration logs
%   export       : pertrace_r6.csv, r6_actions.csv, REPORT_r6.txt
%
% All envs are loaded from frozen files with assertions; no hard-coded
% parameters beyond the ones this freeze names explicitly (seed blocks,
% decision-draw bases, resid_actions).

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

    n_seeds   = ternary(ctx.smoke, 2, 10);
    ep_deep   = ternary(ctx.smoke, 2, 3000);
    n_eval    = ternary(ctx.smoke, 2, 500);
    n_repro   = ternary(ctx.smoke, 2, 20);
    n_calib_r6b = ternary(ctx.smoke, 2, 500);
    run_r6b   = ~strcmp(strtrim(getenv('R6B_RUN')), '0');   % default on; set R6B_RUN=0 to skip

    ctx.hbf(sprintf('r6_fullaction start: n_seeds=%d, ep_deep=%d, n_eval=%d, n_repro=%d, run_r6b=%d', ...
        n_seeds, ep_deep, n_eval, n_repro, run_r6b));

    % NR2's own base rule environment, unchanged (base_seed/offset/action set).
    envN2 = env_M1;
    envN2.base_rule_force = 'fixed';
    envN2.fixed_offset = -2;
    [envN2, ~] = selectBaseRule_v17n(envN2, 2, o.simTime);
    if ~strcmp(envN2.base_rule_kind, 'fixed') || envN2.fixed_offset ~= -2
        error('v17x:r6:base_rule', 'envN2 base rule must be fixed with offset -2');
    end
    assert(isequal(envN2.resid_actions, [-1 0 1]), 'envN2.resid_actions must be the default [-1 0 1] (gate_default config)');

    % R6a: the only change from NR2 is the residual action set.
    envFull = envN2;
    envFull.resid_actions = -2:4;
    envFull.scheme_name = 'Deep A2C v17 (full action set, non-oracle base)';
    assert(isequal(envFull.resid_actions, -2:4), 'envFull.resid_actions must be exactly -2..+4 (7 actions)');

    base_seed = 27042;

    % ---- Disjointness (R6_fullaction_prereg.md Section 2) ----
    train_rng = base_seed + 200 + (1:10);              % 27243..27252
    assert(isequal(train_rng, 27243:27252), 'R6 training seed block must be base_seed+201..+210');
    dec_rng   = 2340000 + (100*(1:500) + reshape(1:10, [], 1));
    prior_ranges = [(77000:80000), (1020000:1080000), (1030000:1030020), ...
                    (2040000:2270100), (3050000:3080500), (4100000:4603500)];
    isect = intersect(dec_rng(:)', prior_ranges);
    assert(isempty(isect), 'R6 decision-draw range 2340000+ intersects a prior draw range');
    prior_seed_ranges = [20042:24252, 25042:25262, 31042:32252, 33042:34262];
    isect2 = intersect(train_rng, prior_seed_ranges);
    assert(isempty(isect2), 'R6 training seeds intersect a prior training seed block');

    % ---- 1. Unit: gate_default ----
    ctx.unit('gate_default', @() unit_gate_default(envN2, R_M1, o, n_repro, ctx));

    % ---- 2. Unit: smoke ----
    ctx.unit('smoke', @() unit_smoke(envFull, o, ctx));

    % ---- 3. Units: train_k (k=1..n_seeds) ----
    train_outs = cell(1, n_seeds);
    for s = 1:n_seeds
        u_name = sprintf('train_%d', s);
        train_outs{s} = ctx.unit(u_name, @() unit_train(envFull, o.simTime, ep_deep, base_seed, s, ctx));
    end

    % ---- 4. Unit: repro ----
    ctx.unit('repro', @() unit_repro(envN2, o, n_repro, ctx));

    % ---- 5. Unit: eval ----
    eval_res = ctx.unit('eval', @() unit_eval(envFull, train_outs, o, n_eval, n_seeds, ctx));

    % ---- 6. Units: r6b_log, r6b_fit, r6b_equiv, r6b_eval (optional) ----
    r6b_res = struct('ran', false);
    if run_r6b
        envFixed_M1 = env_M1;
        envFixed_M1.base_rule_force = 'fixed';
        envFixed_M1.fixed_offset = -2;
        [envFixed_M1, ~] = selectBaseRule_v17n(envFixed_M1, 2, o.simTime);

        r6b_log = ctx.unit('r6b_log', @() unit_r6b_log(envFixed_M1, n_calib_r6b, o, ctx));
        r6b_fit = ctx.unit('r6b_fit', @() unit_r6b_fit(r6b_log, ctx));
        r6b_trees = ctx.unit('r6b_equiv', @() unit_r6b_equiv(r6b_fit, ctx));
        r6b_res = ctx.unit('r6b_eval', @() unit_r6b_eval(envFixed_M1, r6b_trees, n_eval, o, ctx));
        r6b_res.ran = true;
    else
        ctx.hbf('r6b: skipped (R6B_RUN=0)');
    end

    % ---- 7. Unit: export ----
    ctx.unit('export', @() unit_export(eval_res, r6b_res, n_eval, n_seeds, ctx));

    ctx.hbf('r6_fullaction done successfully');
end

% =========================================================================
function out = unit_gate_default(envN2, R_M1, o, n_repro, ctx)
    ctx.hbf(sprintf('gate_default: NR2 seed 1 unchanged-config repro on %d traces', n_repro));
    b0 = min(envN2.burn_in, o.simTime - 1);

    nr2_s1_file = fullfile(ctx.ckptdir, 'nr2', 'train_seed_1.mat');
    if ~exist(nr2_s1_file, 'file')
        nr2_s1_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'train_seed_1.mat');
    end
    eval_nr2_file = fullfile(ctx.ckptdir, 'nr2', 'eval.mat');
    if ~exist(eval_nr2_file, 'file')
        eval_nr2_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'eval.mat');
    end
    assert(exist(nr2_s1_file, 'file') == 2, 'nr2/train_seed_1.mat missing: %s', nr2_s1_file);
    assert(exist(eval_nr2_file, 'file') == 2, 'nr2/eval.mat missing: %s', eval_nr2_file);

    sd = load(nr2_s1_file); pol = sd.out.a2c;
    st = load(eval_nr2_file);

    for j = 1:n_repro
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
        rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envN2);
        obsS = cqiFeedback_v17(Strue, envN2, meta.delays);
        meta.trace_id = j;
        rng(crn_seed); U = rand(o.simTime, envN2.N);

        rng(1020000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, Strue, obsS, envN2, meta, U);
        [~, ~, p] = userMetric_v17(envN2, tp, inf, b0);
        stored = st.out.nr2_seeds(1, j);
        if abs(p - stored) ~= 0
            error('v17x:r6:gate_default', 'gate_default REPRO failed on trace %d (diff=%.3e): the code path used by every earlier stage is not bit-identical', j, abs(p - stored));
        end
    end
    ctx.hbf('gate_default: NR2 seed 1 reproduces bit-identically on the unchanged [-1 0 1] config (max_abs_diff = 0)');
    out = struct('gate_default_pass', true);
end

% =========================================================================
function out = unit_smoke(envFull, o, ctx)
    ctx.hbf('smoke: 1 seed, 20 episodes, full action set, preflight range 1030001-1030020');
    smoke_seed = 1030001;  % disjoint preflight range per Section 8
    [a2c, ~, lc, ~] = DeepA2C_Shared_v17(o.simTime, 20, smoke_seed, envFull);

    % Assert the output width, the delta=0 logit bias and that transmitted
    % offsets lie in -4..+2 (Section 2 smoke gate).
    L = a2c.Learnables;
    Wl = extractdata(L.Value{(L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Weights"});
    bl = extractdata(L.Value{(L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Bias"});
    nA = size(Wl, 1);
    assert(nA == 7, 'smoke: actor output width must be 7 (envFull.resid_actions has 7 actions), got %d', nA);

    zeroIdx = find(envFull.resid_actions == 0, 1);
    assert(~isempty(zeroIdx), 'smoke: envFull.resid_actions must contain 0');
    [~, maxBiasIdx] = max(bl);
    ctx.hbf(sprintf('smoke: output width=%d, delta=0 index=%d, largest initial bias at index=%d (bias values: %s)', ...
        nA, zeroIdx, maxBiasIdx, mat2str(bl', 4)));

    n_eval_pf = 20;
    offsets_seen = [];
    for j = 1:n_eval_pf
        rng(1030000 + j); [Strue, ~, meta] = generateChannel_v17(o.simTime, envFull);
        obsS = cqiFeedback_v17(Strue, envFull, meta.delays);
        meta.trace_id = j;
        rng(1030000 + j); U = rand(o.simTime, envFull.N);
        rng(2340000 + 100*j + 1);
        [~, ~, ~, act, ~] = evalPolicy_v17_g6('a2c_v17', a2c, Strue, obsS, envFull, meta, U);
        d = envFull.resid_actions(act(act >= 1 & act <= 7));
        offsets_seen = [offsets_seen; d(:)]; %#ok<AGROW>
    end
    tot_off = -2 + offsets_seen;  % base -2 + delta, before CQI clipping
    assert(all(tot_off >= -4 & tot_off <= 2), 'smoke: transmitted base+delta offsets must lie in -4..+2');
    ctx.hbf(sprintf('smoke: PASS (final lc=%.2f; %d decisions observed, offsets within -4..+2)', lc(end), numel(offsets_seen)));
    out = struct('smoke_pass', true, 'nA', nA);
end

% =========================================================================
function out = unit_train(envFull, simTime, ep_deep, base_seed, s, ctx)
    seed = base_seed + 200 + s;
    assert(seed >= 27243 && seed <= 27252, 'R6 train seed disjointness assertion');
    ctx.hbf(sprintf('train_%d: training RL-full (seed %d, %d episodes, 7-action)', s, seed, ep_deep));
    envPrim = envFull;
    envPrim.seed_idx = s;

    t0 = tic;
    [a2c, critic, lc, ent, abest, ~, bestEp, valc] = ...
        DeepA2C_Shared_v17(simTime, ep_deep, seed, envPrim);
    ctx.hbf(sprintf('train_%d: finished in %.1f s, final lc=%.2f', s, toc(t0), lc(end)));
    out = struct('a2c', a2c, 'critic', critic, 'lc', lc, 'ent', ent, ...
                 'abest', abest, 'bestEp', bestEp, 'valc', valc, 'seed', seed);
    try java.lang.System.gc(); catch, end
end

% =========================================================================
function out = unit_repro(envN2, o, n_repro, ctx)
    ctx.hbf(sprintf('repro: ctxj500 and NR2 seed 1 on %d traces, exact match', n_repro));
    b0 = min(envN2.burn_in, o.simTime - 1);

    eval_nr2_file = fullfile(ctx.ckptdir, 'nr2', 'eval.mat');
    if ~exist(eval_nr2_file, 'file'), eval_nr2_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'eval.mat'); end
    st_nr2 = load(eval_nr2_file);

    nr2_s1_file = fullfile(ctx.ckptdir, 'nr2', 'train_seed_1.mat');
    if ~exist(nr2_s1_file, 'file'), nr2_s1_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'train_seed_1.mat'); end
    sd1 = load(nr2_s1_file); pol_nr2_s1 = sd1.out.a2c;

    tables_file = fullfile(ctx.root, 'Dataset', 'cal500_tables.txt');
    ctxj_tab = read_ctxj_from_tables(tables_file);
    e_ctxj = envN2; e_ctxj.ctxj_tab = ctxj_tab;

    for j = 1:n_repro
        tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
        crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
        rng(tr_seed, 'twister'); [Strue, ~, meta] = generateChannel_v17(o.simTime, envN2);
        obsS = cqiFeedback_v17(Strue, envN2, meta.delays);
        meta.trace_id = j;
        rng(crn_seed, 'twister'); U = rand(o.simTime, envN2.N);

        rng(1020000 + 100*j + 10*99 + 1, 'twister');
        [tp, ~, ~, ~, inf] = evalPolicy_presub('ctxj', [], Strue, obsS, e_ctxj, meta, U);
        [~, ~, p_cj] = userMetric_v17(e_ctxj, tp, inf, b0);
        if abs(p_cj - st_nr2.out.cmp.ctxj500(j)) ~= 0
            error('v17x:r6:repro', 'ctxj500 REPRO failed on trace %d (diff=%.3e)', j, abs(p_cj - st_nr2.out.cmp.ctxj500(j)));
        end

        rng(1020000 + 100*j + 10*8 + 1, 'twister');
        [tp, ~, ~, ~, inf] = evalPolicy_presub('a2c_v17', pol_nr2_s1, Strue, obsS, envN2, meta, U);
        [~, ~, p_nr2] = userMetric_v17(envN2, tp, inf, b0);
        if abs(p_nr2 - st_nr2.out.nr2_seeds(1, j)) ~= 0
            error('v17x:r6:repro', 'NR2 seed 1 REPRO failed on trace %d (diff=%.3e)', j, abs(p_nr2 - st_nr2.out.nr2_seeds(1, j)));
        end
    end
    ctx.hbf('repro: REPRO PASS for ctxj500 and NR2 seed 1 (max_abs_diff = 0)');
    out = struct('repro_pass', true);
end

% =========================================================================
function out = unit_eval(envFull, train_outs, o, n_eval, n_seeds, ctx)
    ctx.hbf(sprintf('eval: RL-full seeds 1-%d on %d NR2 traces (decision draws rng(2340000+100j+s))', n_seeds, n_eval));
    b0 = min(envFull.burn_in, o.simTime - 1);
    N = envFull.N;

    envE = envFull; envE.r6_delta_log = true;   % opt-in: widen sch_log with delta/clip columns

    rlfull_vals = zeros(n_seeds, n_eval);
    delta_counts = zeros(n_seeds, numel(envFull.resid_actions));   % columns indexed by action, delta = resid_actions(idx)
    n_sched_new = zeros(1, n_seeds);
    n_clipped = zeros(1, n_seeds);

    for s = 1:n_seeds
        pol = train_outs{s}.a2c;
        ctx.hb(sprintf('eval: RL-full seed %d', s));
        for j = 1:n_eval
            tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
            crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
            rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envE);
            obsS = cqiFeedback_v17(Strue, envE, meta.delays);
            meta.trace_id = j;
            rng(crn_seed); U = rand(o.simTime, N);

            rng(2340000 + 100*j + s);
            [tp, ~, ~, ~, inf] = evalPolicy_presub('a2c_v17', pol, Strue, obsS, envE, meta, U);
            [~, ~, rlfull_vals(s, j)] = userMetric_v17(envE, tp, inf, b0);

            sl = inf.sch_log;  % [u, act_idx, slack, is_retx, n_busy, delta, clip]
            if ~isempty(sl)
                newtx = sl(sl(:, 4) == 0, :);  % scheduled NEW transmissions only
                if ~isempty(newtx)
                    n_sched_new(s) = n_sched_new(s) + size(newtx, 1);
                    n_clipped(s) = n_clipped(s) + sum(newtx(:, 7));
                    for ka = 1:numel(envFull.resid_actions)
                        delta_counts(s, ka) = delta_counts(s, ka) + sum(newtx(:, 2) == ka);
                    end
                end
            end
        end
        ctx.hbf(sprintf('eval: RL-full seed %d mean on-time = %.4f', s, mean(rlfull_vals(s, :))));
    end
    ctx.hbf(sprintf('eval: RL-full mean on-time (pooled %d seeds) = %.4f', n_seeds, mean(mean(rlfull_vals))));

    out = struct('rlfull_vals', rlfull_vals, 'delta_counts', delta_counts, ...
                 'n_sched_new', n_sched_new, 'n_clipped', n_clipped, ...
                 'resid_actions', envFull.resid_actions);
end

% =========================================================================
function out = unit_r6b_log(envFixed, n_calib, o, ctx)
    ctx.hbf(sprintf('r6b_log: re-running R1b exploration logging on %d G6 calibration traces (identical streams)', n_calib));

    calib_trace_base = 600000; calib_crn_base = 610000; exp_stream_base = 3050000;

    for j = 1:n_calib
        tr_seed = calib_trace_base + j;
        assert(~(tr_seed >= 500001 && tr_seed <= 570500), 'Evaluation trace seed collision!');
        assert(~(tr_seed >= 1000001 && tr_seed <= 1010500), 'Evaluation trace seed collision!');
        assert(~(tr_seed >= 720001 && tr_seed <= 750500), 'Evaluation trace seed collision!');
    end

    max_dec = n_calib * o.simTime * envFixed.N;
    X_buf = zeros(max_dec, 19, 'single');
    mcs_buf = zeros(max_dec, 1, 'int8');
    ack1_buf = zeros(max_dec, 1, 'int8');
    tr_buf = zeros(max_dec, 1, 'int32');
    exp_buf = zeros(max_dec, 1, 'int8');
    psucc_buf = zeros(max_dec, 7, 'single');
    ubits_buf = zeros(max_dec, 7, 'single');
    n_total = 0;

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

        [~, ~, ~, ~, inf] = evalPolicy_presub('log_explore_r6b', pol, Strue, obsS, envFixed, meta, U);

        log_data = inf.r1b_log;  % 48 cols: 41 (as log_explore) + 7 c_psucc
        n_dec = size(log_data, 1);
        if n_dec > 0
            idx_s = n_total + 1; idx_e = n_total + n_dec;
            tr_buf(idx_s:idx_e)      = int32(log_data(:, 1));
            X_buf(idx_s:idx_e, :)    = single(log_data(:, 4:22));
            mcs_buf(idx_s:idx_e)     = int8(log_data(:, 24));
            ack1_buf(idx_s:idx_e)    = int8(log_data(:, 25));
            exp_buf(idx_s:idx_e)     = int8(log_data(:, 41));
            ubits_buf(idx_s:idx_e,:) = single(log_data(:, 34:40));  % c_ubits (7 cols)
            psucc_buf(idx_s:idx_e,:) = single(log_data(:, 42:48)); % c_psucc (7 cols)
            n_total = idx_e;
        end
    end

    trace_id = tr_buf(1:n_total); mcs_taken = mcs_buf(1:n_total);
    ack1 = ack1_buf(1:n_total); explored = exp_buf(1:n_total);
    X_feat = X_buf(1:n_total, :);
    Y = double(ubits_buf(1:n_total, :)) .* double(psucc_buf(1:n_total, :));  % q(x,a) = psucc(a) x ubits(a)

    % Assert row-for-row identity with the stored R1b log (trace, mcs, ack1, explored).
    xfit_file = fullfile(ctx.ckptdir, 'r1b_ack', 'r1b_calib_xfit.csv');
    if ~exist(xfit_file, 'file')
        xfit_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'r1b_ack', 'r1b_calib_xfit.csv');
    end
    assert(exist(xfit_file, 'file') == 2, 'r1b_calib_xfit.csv missing: %s', xfit_file);
    T_stored = readtable(xfit_file);
    assert(height(T_stored) == n_total, 'R6b log row count (%d) differs from stored R1b log (%d)', n_total, height(T_stored));
    assert(isequal(double(trace_id), T_stored.trace), 'R6b log trace_id differs from stored R1b log');
    assert(isequal(double(mcs_taken), T_stored.mcs), 'R6b log mcs differs from stored R1b log');
    assert(isequal(double(ack1), T_stored.ack1), 'R6b log ack1 differs from stored R1b log');
    assert(isequal(double(explored), T_stored.explored), 'R6b log explored differs from stored R1b log');
    ctx.hbf(sprintf('r6b_log: %d decisions logged, row-identical to the stored R1b log (trace/mcs/ack1/explored)', n_total));

    calib_mat = fullfile(ctx.ckptdir, 'r6b', 'r6b_calib_log.mat');
    if ~exist(fileparts(calib_mat), 'dir'), mkdir(fileparts(calib_mat)); end
    save(calib_mat, 'X_feat', 'Y', 'trace_id', 'n_total', '-v7.3');
    out = struct('calib_mat', calib_mat, 'n_decisions', n_total);
end

% =========================================================================
function out = unit_r6b_fit(r6b_log, ctx)
    ctx.hbf('r6b_fit: training 7 HistGradientBoostingRegressor models via Python train_r6b_sinrexp.py');
    if isfield(ctx, 'python') && ~isempty(ctx.python)
        py_exe = ctx.python;
    elseif isfield(ctx, 'cfg') && isfield(ctx.cfg, 'python') && ~isempty(ctx.cfg.python)
        py_exe = ctx.cfg.python;
    else
        py_exe = 'D:\miniconda\python.exe';
    end

    py_script = fullfile(ctx.root, 'train_r6b_sinrexp.py');
    joblib_out = fullfile(ctx.outdir, 'r6b_model.joblib');
    trees_mat  = fullfile(ctx.ckptdir, 'r6b', 'r6b_trees.mat');
    hash_out   = fullfile(ctx.outdir, 'r6b_hash.txt');

    cmd = sprintf('"%s" "%s" "%s" "%s" "%s" "%s"', py_exe, py_script, r6b_log.calib_mat, joblib_out, trees_mat, hash_out);
    [status, cmdout] = system(cmd);
    if status ~= 0, error('v17x:r6b:fit_failed', 'Python R6b fit failed:\n%s', cmdout); end
    sha256 = strtrim(fileread(hash_out));
    ctx.hbf(sprintf('r6b_fit: R6b models SHA-256 = %s', sha256));
    out = struct('trees_mat', trees_mat, 'sha256', sha256, 'joblib', joblib_out);
end

% =========================================================================
function out = unit_r6b_equiv(r6b_fit, ctx)
    ctx.hbf('r6b_equiv: verifying tree prediction equivalence with scikit-learn (1e-9 gate)');
    S = load(r6b_fit.trees_mat);
    trees_export = S.trees_export;
    X_equiv = S.X_equiv; Y_pred_sk = S.Y_pred_sk;

    n_eq = size(X_equiv, 1);
    models = cell(1, 7);
    for a = 1:7
        if iscell(trees_export), models{a} = trees_export{a}; else, models{a} = trees_export(a); end
        trees = models{a}.trees;
        if isstruct(trees) && numel(trees) > 1
            t_cell = cell(1, numel(trees));
            for k = 1:numel(trees), t_cell{k} = trees(k); end
            models{a}.trees = t_cell;
        end
    end

    Y_pred_mat = zeros(n_eq, 7);
    for a = 1:7
        for i = 1:n_eq
            Y_pred_mat(i, a) = model_predict_local(models{a}, X_equiv(i, :));
        end
    end
    max_diff = max(abs(Y_pred_mat(:) - Y_pred_sk(:)));
    ctx.hbf(sprintf('r6b_equiv: max abs difference = %.3e', max_diff));
    if max_diff > 1e-9
        error('v17x:r6b:equiv_fail', 'R6b equivalence check failed: max abs diff %.3e > 1e-9', max_diff);
    end
    ctx.hbf('r6b_equiv: EQUIVALENCE GATE PASS (max abs diff <= 1e-9)');
    out = models;
end

% =========================================================================
function out = unit_r6b_eval(envFixed, r6b_models, n_eval, o, ctx)
    ctx.hbf(sprintf('r6b_eval: evaluating GBT-res-SINRexp and GBT-full-SINRexp on %d NR2 traces (deterministic)', n_eval));
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

        [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_res', r6b_models, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_res(j)] = userMetric_v17(envFixed, tp, inf, b0);

        [tp, ~, ~, ~, inf] = evalPolicy_presub('gbt_full', r6b_models, Strue, obsS, envFixed, meta, U);
        [~, ~, vals_full(j)] = userMetric_v17(envFixed, tp, inf, b0);
    end
    ctx.hbf(sprintf('r6b_eval: GBT-res-SINRexp=%.4f, GBT-full-SINRexp=%.4f', mean(vals_res), mean(vals_full)));
    out = struct('res', vals_res, 'full', vals_full);
end

% =========================================================================
function out = unit_export(eval_res, r6b_res, n_eval, n_seeds, ctx)
    ctx.hbf('export: writing pertrace_r6.csv, r6_actions.csv and REPORT_r6.txt');
    r6_dir = fullfile(ctx.outdir, 'presub', 'r6');
    if ~exist(r6_dir, 'dir'), mkdir(r6_dir); end

    pertrace_csv = fullfile(r6_dir, 'pertrace_r6.csv');
    fid = fopen(pertrace_csv, 'w');
    fprintf(fid, 'trace_set,scheme,seed,trace,value\n');
    for s = 1:n_seeds
        for j = 1:n_eval
            fprintf(fid, 'NR2,RL-full,%d,%d,%.6f\n', s, j, eval_res.rlfull_vals(s, j));
        end
    end
    if r6b_res.ran
        for j = 1:n_eval
            fprintf(fid, 'NR2,GBT-res-SINRexp,0,%d,%.6f\n', j, r6b_res.res(j));
            fprintf(fid, 'NR2,GBT-full-SINRexp,0,%d,%.6f\n', j, r6b_res.full(j));
        end
    end
    fclose(fid);

    actions_csv = fullfile(r6_dir, 'r6_actions.csv');
    fid = fopen(actions_csv, 'w');
    fprintf(fid, 'seed,metric,key,value\n');
    for s = 1:n_seeds
        for ka = 1:numel(eval_res.resid_actions)
            d = eval_res.resid_actions(ka);
            share = 0;
            if eval_res.n_sched_new(s) > 0
                share = eval_res.delta_counts(s, ka) / eval_res.n_sched_new(s);
            end
            fprintf(fid, '%d,delta_share,%d,%.6f\n', s, d, share);
        end
        clip_share = 0;
        if eval_res.n_sched_new(s) > 0
            clip_share = eval_res.n_clipped(s) / eval_res.n_sched_new(s);
        end
        fprintf(fid, '%d,clip_share,all,%.6f\n', s, clip_share);
    end
    fclose(fid);

    r6_eval_mat = fullfile(ctx.ckptdir, 'r6', 'r6_eval.mat');
    if ~exist(fileparts(r6_eval_mat), 'dir'), mkdir(fileparts(r6_eval_mat)); end
    save(r6_eval_mat, 'eval_res', 'r6b_res', '-v7.3');

    rep_file = fullfile(ctx.outdir, 'REPORT_r6.txt');
    fid = fopen(rep_file, 'w');
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'REPORT_r6.txt -- Residual RL, Full Action Set vs ACK-Trained One-Step Learner (Stage r6)\n');
    fprintf(fid, 'Generated: %s | MATLAB %s\n', datestr(now, 31), version);
    fprintf(fid, '================================================================================\n\n');
    fprintf(fid, 'RL-full mean on-time (pooled %d seeds, %d NR2 traces): %.4f\n', n_seeds, n_eval, mean(mean(eval_res.rlfull_vals)));
    for s = 1:n_seeds
        fprintf(fid, '  seed %2d: %.4f\n', s, mean(eval_res.rlfull_vals(s, :)));
    end
    fprintf(fid, '\nDelta shares on scheduled new transmissions (pooled seeds):\n');
    tot = sum(eval_res.n_sched_new);
    for ka = 1:numel(eval_res.resid_actions)
        d = eval_res.resid_actions(ka);
        c = sum(eval_res.delta_counts(:, ka));
        fprintf(fid, '  delta=%+d: %.4f%% (n=%d)\n', d, 100*c/max(tot,1), c);
    end
    fprintf(fid, '  CQI floor/ceiling clip share: %.4f%%\n', 100*sum(eval_res.n_clipped)/max(tot,1));
    if r6b_res.ran
        fprintf(fid, '\nR6b (descriptive): GBT-res-SINRexp=%.4f, GBT-full-SINRexp=%.4f\n', mean(r6b_res.res), mean(r6b_res.full));
    else
        fprintf(fid, '\nR6b: not run\n');
    end
    fclose(fid);

    ctx.hbf(sprintf('export: pertrace_r6.csv, r6_actions.csv and REPORT_r6.txt written to %s / %s', r6_dir, ctx.outdir));
    out = struct('pertrace_csv', pertrace_csv, 'actions_csv', actions_csv, 'report', rep_file);
end

% =========================================================================
function q = model_predict_local(model, x)
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

function tab = read_ctxj_from_tables(fpath)
    tab = zeros(3, 2, 3, 2);
    if ~exist(fpath, 'file'), return; end
    lines = strsplit(fileread(fpath), sprintf('\n'));
    for i = 1:numel(lines)
        line = strtrim(lines{i});
        tok = regexp(line, 'cell\((\d+),(\d+),(\d+),(\d+)\) = ([+-]?\d+)', 'tokens', 'once');
        if ~isempty(tok)
            b = str2double(tok{1}); d = str2double(tok{2});
            v = str2double(tok{3}); u = str2double(tok{4}) + 1;
            off = str2double(tok{5});
            tab(b, d, v, u) = off;
        end
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
