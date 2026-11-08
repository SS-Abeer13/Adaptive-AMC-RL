function stage_nr2(ctx)
% stage_nr2  Confirmatory replication of NR1 on fresh data (v17x stage nr2).
% Spec: paper/proposals/NR2_confirmatory_prereg.md (Amendment 3, frozen).
% Units:
%   check
%   repro
%   train_seed_K (K = 1..n_seeds)
%   eval
%   analysis
% Outputs:
%   Dataset/ckpt/nr2/eval.mat
%   Dataset/table_nr2.csv
%   Dataset/fill_summary_v17nr2.txt
%   Dataset/stage_nr2.done
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'nr1'));
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; env_M1 = R_M1.env;

    n_seeds = ternary(ctx.smoke, 2, 10);
    ep_deep = ternary(ctx.smoke, 2, 3000);
    n_eval  = ternary(ctx.smoke, 4, 500);
    base_seed = 25042;
    T = o.simTime;

    ctx.hbf(sprintf('NR2 start: n_seeds=%d, ep_deep=%d, n_eval=%d', n_seeds, ep_deep, n_eval));

    % ---- 1. Unit: check ----
    ctx.unit('check', @() unit_check(ctx, env_M1, o));

    % ---- 2. Unit: repro ----
    n_repro = ternary(ctx.smoke, 2, 20);
    ctx.unit('repro', @() unit_repro(R_M1, env_M1, n_repro, o, ctx));

    % Base rule environment for NR2: Fixed with frozen offset -2
    envN2 = env_M1;
    envN2.base_rule_force = 'fixed';
    envN2.fixed_offset = -2;
    [envN2, baseName] = selectBaseRule_v17n(envN2, 2, o.simTime);
    if ~strcmp(envN2.base_rule_kind, 'fixed') || envN2.fixed_offset ~= -2
        error('v17x:nr2:base_rule', 'envN2 base rule must be fixed with offset -2');
    end

    % ---- 3. Units: train_seed_K ----
    train_outs = cell(1, n_seeds);
    for s = 1:n_seeds
        u_name = sprintf('train_seed_%d', s);
        train_outs{s} = ctx.unit(u_name, @() unit_train(envN2, T, ep_deep, base_seed, s, ctx));
    end

    % ---- 4. Unit: eval ----
    eval_res = ctx.unit('eval', @() unit_eval(R_M1, envN2, train_outs, o, n_eval, n_seeds, ep_deep, ctx));

    % ---- 5. Unit: analysis ----
    ctx.unit('analysis', @() unit_analysis(eval_res, n_eval, n_seeds, ctx));

    ctx.hbf('NR2 done successfully');
end

% =========================================================================
function out = unit_check(ctx, env_M1, o)
    ctx.hbf('check: verifying hashes, frozen base offset, disjointness, and selectBaseRule_v17n');

    % 1. Table hashes (SHA-256)
    tables_file = fullfile(ctx.root, 'Dataset', 'cal500_tables.txt');
    single_file = fullfile(ctx.root, 'Dataset', 'cal500_single.txt');
    if ~exist(tables_file, 'file') || ~exist(single_file, 'file')
        error('v17x:nr2:check', 'cal500_tables.txt or cal500_single.txt missing from Dataset');
    end

    exp_tables_sha = '94140b8c3405dc7107c2ef1b3d833fd2811fde47b2046516b8547ca331257f89';
    exp_single_sha = '8ec52905dce4a61dcc9da329f9bd113068147fa0472ae5941ad0c43ec5821998';

    act_tables_sha = compute_file_sha256(tables_file);
    act_single_sha = compute_file_sha256(single_file);

    if ~strcmp(exp_tables_sha, act_tables_sha)
        error('v17x:nr2:check', 'SHA-256 mismatch for cal500_tables.txt: expected %s, got %s', ...
            exp_tables_sha, act_tables_sha);
    end
    if ~strcmp(exp_single_sha, act_single_sha)
        error('v17x:nr2:check', 'SHA-256 mismatch for cal500_single.txt: expected %s, got %s', ...
            exp_single_sha, act_single_sha);
    end
    ctx.hbf('check: table SHA-256 hashes verified');

    % 2. Frozen base offset -2 in cal500_single.txt and ckpt/nr1/calib.mat
    txt_single = fileread(single_file);
    off_single = parse_int(txt_single, 'Fixed-500: offset = ([+-]?[0-9]+)');
    if off_single ~= -2
        error('v17x:nr2:check', 'Fixed-500 offset in cal500_single.txt is %d, expected -2', off_single);
    end

    nr1_calib_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr1', 'calib.mat');
    if ~exist(nr1_calib_file, 'file')
        error('v17x:nr2:check', 'NR1 calib.mat missing at %s', nr1_calib_file);
    end
    S_nr1 = load(nr1_calib_file);
    if S_nr1.out.env.fixed_offset ~= -2
        error('v17x:nr2:check', 'NR1 calib.mat fixed_offset is %d, expected -2', S_nr1.out.env.fixed_offset);
    end
    ctx.hbf('check: frozen base offset -2 verified in cal500_single and nr1/calib.mat');

    % 3. Disjointness assertions (§3, R4)
    trace_rng = 1000001:1000500;
    crn_rng   = 1010001:1010500;
    dec_rng   = 1020001:1080000;
    preflight_rng = 1030001:1030020;
    seed_rng  = 25243:25252;

    % Mutually disjoint NR2 ranges
    if ~isempty(intersect(trace_rng, crn_rng)) || ...
       ~isempty(intersect(trace_rng, dec_rng)) || ...
       ~isempty(intersect(crn_rng, dec_rng))   || ...
       ~isempty(intersect(trace_rng, preflight_rng))
        error('v17x:nr2:check', 'Internal intersection detected in NR2 trace/CRN/decision ranges');
    end

    % Prior ranges from v9-v17, G6, G10, A6, and earlier seeds
    prior_ranges = [500001:570500, ...               % v9-v17 evaluation traces & CRN
                    60001:63000, ...                 % calibration traces
                    80001:85000, ...                 % validation traces
                    77000:80000, ...                 % prior decision draws
                    600001:600500, 610001:611000, ...% G6 calibration
                    720000:750500, 901000:912500, ...% G10
                    800001:810100, ...               % A6
                    20042:24252, 31042:32252];       % prior training seed blocks

    nr2_all_seeds = [trace_rng, crn_rng, dec_rng, seed_rng];
    isect = intersect(nr2_all_seeds, prior_ranges);
    if ~isempty(isect)
        error('v17x:nr2:check', 'Disjointness violation: %d seeds intersect prior ranges (first: %d)', ...
            numel(isect), isect(1));
    end
    ctx.hbf('check: disjointness assertions passed cleanly');

    % 4. selectBaseRule_v17n default behavior test
    env_test = env_M1;
    [env_n, name_n] = selectBaseRule_v17n(env_test, 2, o.simTime);
    [env_orig, name_orig] = selectBaseRule_v17(env_test, 2, o.simTime);
    if ~strcmp(name_n, name_orig) || ~strcmp(env_n.base_rule_kind, env_orig.base_rule_kind)
        error('v17x:nr2:check', 'selectBaseRule_v17n unforced behavior differs from selectBaseRule_v17');
    end

    env_test.base_rule_force = 'fixed';
    [env_forced, name_forced] = selectBaseRule_v17n(env_test, 2, o.simTime);
    if ~strcmp(name_forced, 'Fixed') || ~strcmp(env_forced.base_rule_kind, 'fixed')
        error('v17x:nr2:check', 'selectBaseRule_v17n forced fixed failed');
    end
    ctx.hbf('check: selectBaseRule_v17n tests passed');

    out = struct('check_ok', true);
end

% =========================================================================
function out = unit_repro(R_M1, env_M1, n_repro, o, ctx)
    ctx.hbf(sprintf('repro: checking bit-exact reproduction on %d traces', n_repro));
    e = env_M1; e.scheduler = 'pf';
    b0 = min(e.burn_in, o.simTime - 1);

    % Generate M1 evaluation traces 1..n_repro
    traces_m1 = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_repro
        rng(o.trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(o.simTime, env_M1);
        obsS = cqiFeedback_v17(Strue, env_M1, meta.delays);
        meta.trace_id = j;
        rng(o.crn_seed_base + j); U = rand(o.simTime, env_M1.N);
        traces_m1(j).SINR = Strue; traces_m1(j).obsS = obsS; traces_m1(j).meta = meta; traces_m1(j).U = U;
    end

    % Gate (a): Re-evaluate 8 comparators on traces 1..n_repro
    % Load G6 calibrated comparator tables
    g6c_eval_file = fullfile(ctx.root, 'Dataset', 'ckpt', 'g6c', 'eval.mat');
    if ~exist(g6c_eval_file, 'file')
        error('v17x:nr2:repro', 'ckpt/g6c/eval.mat missing at %s', g6c_eval_file);
    end
    S_g6c = load(g6c_eval_file);
    out_g6c = S_g6c.out;

    txt_single = fileread(fullfile(ctx.root, 'Dataset', 'cal500_single.txt'));
    f_off = parse_int(txt_single, 'Fixed-500: offset = ([+-]?[0-9]+)');

    comp_ckpt = fullfile(ctx.root, 'Dataset', 'ckpt', 'g6a', 'composite_table.mat');
    if exist(comp_ckpt, 'file')
        S_comp = load(comp_ckpt);
        pu_tab = S_comp.out.fixedpu_tab;
        ctx_tab = S_comp.out.ctx_tab;
        olla_set = S_comp.out.olla_setting;
    else
        pu_tab = env_M1.class_tab;
        ctx_tab = env_M1.ctx_tab;
        olla_set = [env_M1.olla_target, 0.5];
    end
    ctxj_tab = read_ctxj_from_tables(fullfile(ctx.root, 'Dataset', 'cal500_tables.txt'));

    e_f = e; e_f.fixed_offset = f_off;
    e_pu = e; e_pu.fixed_class_tab = pu_tab; e_pu.class_tab = pu_tab;
    e_ctx = e; e_ctx.ctx_tab = ctx_tab;
    e_olla = e; e_olla.olla_target = olla_set(1); e_olla.olla_target_tuned = olla_set(1); e_olla.olla_step_down = olla_set(2);
    e_ctxj = e; e_ctxj.ctxj_tab = ctxj_tab;

    for j = 1:n_repro
        % Baseline (k=1)
        rng(77000 + 100*j + 10*1 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('baseline', [], traces_m1(j).SINR, traces_m1(j).obsS, e, traces_m1(j).meta, traces_m1(j).U);
        [~, ~, p] = userMetric_v17(e, tp, inf, b0);
        if abs(p - R_M1.metrics(1).primary{1}(1, j)) ~= 0
            error('v17x:nr2:repro', 'REPRO failed for Baseline trace %d', j);
        end

        % OLLA (k=2)
        rng(77000 + 100*j + 10*2 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('olla', [], traces_m1(j).SINR, traces_m1(j).obsS, e, traces_m1(j).meta, traces_m1(j).U);
        [~, ~, p] = userMetric_v17(e, tp, inf, b0);
        if abs(p - R_M1.metrics(1).primary{2}(1, j)) ~= 0
            error('v17x:nr2:repro', 'REPRO failed for OLLA trace %d', j);
        end

        % Multi-OLLA (k=4)
        rng(77000 + 100*j + 10*4 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('multi_olla', [], traces_m1(j).SINR, traces_m1(j).obsS, e, traces_m1(j).meta, traces_m1(j).U);
        [~, ~, p] = userMetric_v17(e, tp, inf, b0);
        if abs(p - R_M1.metrics(1).primary{4}(1, j)) ~= 0
            error('v17x:nr2:repro', 'REPRO failed for Multi-OLLA trace %d', j);
        end

        % OLLA-tuned-500 (k=3)
        rng(77000 + 100*j + 10*3 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('olla_tuned', [], traces_m1(j).SINR, traces_m1(j).obsS, e_olla, traces_m1(j).meta, traces_m1(j).U);
        [~, ~, p] = userMetric_v17(e_olla, tp, inf, b0);
        if abs(p - out_g6c.prim_olla500(1, j)) ~= 0
            error('v17x:nr2:repro', 'REPRO failed for OLLA-tuned-500 trace %d', j);
        end

        % Fixed-500 (k=5)
        rng(77000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed', [], traces_m1(j).SINR, traces_m1(j).obsS, e_f, traces_m1(j).meta, traces_m1(j).U);
        [~, ~, p] = userMetric_v17(e_f, tp, inf, b0);
        if abs(p - out_g6c.prim_fixed500(1, j)) ~= 0
            error('v17x:nr2:repro', 'REPRO failed for Fixed-500 trace %d', j);
        end

        % FixedPU-500 (k=6)
        rng(77000 + 100*j + 10*6 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed_class', [], traces_m1(j).SINR, traces_m1(j).obsS, e_pu, traces_m1(j).meta, traces_m1(j).U);
        [~, ~, p] = userMetric_v17(e_pu, tp, inf, b0);
        if abs(p - out_g6c.prim_pu500(1, j)) ~= 0
            error('v17x:nr2:repro', 'REPRO failed for FixedPU-500 trace %d', j);
        end

        % Context-500 (k=7)
        rng(77000 + 100*j + 10*7 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxtab', [], traces_m1(j).SINR, traces_m1(j).obsS, e_ctx, traces_m1(j).meta, traces_m1(j).U);
        [~, ~, p] = userMetric_v17(e_ctx, tp, inf, b0);
        if abs(p - out_g6c.prim_ctx500(1, j)) ~= 0
            error('v17x:nr2:repro', 'REPRO failed for Context-500 trace %d', j);
        end

        % Context-joint-500 (k=99)
        rng(77000 + 100*j + 10*99 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxj', [], traces_m1(j).SINR, traces_m1(j).obsS, e_ctxj, traces_m1(j).meta, traces_m1(j).U);
        [~, ~, p] = userMetric_v17(e_ctxj, tp, inf, b0);
        if abs(p - out_g6c.prim_ctxj500(1, j)) ~= 0
            error('v17x:nr2:repro', 'REPRO failed for Context-joint-500 trace %d', j);
        end
    end
    ctx.hbf('repro: Gate (a) 8 comparators bit-exact reproduction verified');

    % Gate (b): Re-evaluate stored M1 policies (10 seeds) on traces 1..n_repro
    n_m1_seeds = min(10, numel(R_M1.policies.A2C));
    if ctx.smoke, n_m1_seeds = 2; end
    for s = 1:n_m1_seeds
        pol = R_M1.policies.A2C{s};
        for j = 1:n_repro
            rng(77000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, traces_m1(j).SINR, traces_m1(j).obsS, e, traces_m1(j).meta, traces_m1(j).U);
            [~, ~, p] = userMetric_v17(e, tp, inf, b0);
            stored_p = R_M1.metrics(1).primary{8}(s, j);
            if abs(p - stored_p) ~= 0
                error('v17x:nr2:repro', 'REPRO failed for M1 policy seed %d trace %d (diff = %e)', s, j, abs(p - stored_p));
            end
        end
    end
    ctx.hbf('repro: Gate (b) M1 policies bit-exact reproduction verified');

    out = struct('repro_ok', true);
end

% =========================================================================
function out = unit_train(env, simTime, ep_deep, base_seed, s, ctx)
    seed = base_seed + 200 + s;
    ctx.hbf(sprintf('train_seed_%d: training A2C (seed %d, %d episodes)', s, seed, ep_deep));
    envPrim = env;
    envPrim.scheme_name = 'Deep A2C v17 (non-oracle base)';
    envPrim.seed_idx = s;

    t0 = tic;
    [a2c, critic, lc, ent, abest, ~, bestEp, valc, trainInfo] = ...
        DeepA2C_Shared_v17(simTime, ep_deep, seed, envPrim);

    late_frac = 0;
    if isstruct(trainInfo) && isfield(trainInfo, 'late_credit_frac')
        late_frac = trainInfo.late_credit_frac;
    end

    ctx.hbf(sprintf('train_seed_%d: finished in %.1f s, final lc=%.2f', s, toc(t0), lc(end)));
    out = struct('a2c', a2c, 'critic', critic, 'lc', lc, 'ent', ent, ...
                 'abest', abest, 'bestEp', bestEp, 'valc', valc, 'late_credit_frac', late_frac);
end

% =========================================================================
function out = unit_eval(R_M1, envN2, train_outs, o, n_eval, n_seeds, ep_deep, ctx)
    ctx.hbf(sprintf('eval: evaluating NR2 policies, M1 policies, and 8 comparators on %d fresh traces', n_eval));
    T = o.simTime;
    b0 = min(envN2.burn_in, T - 1);
    N = envN2.N;

    % Generate fresh traces (§3)
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    speeds = zeros(n_eval, N);
    delays = zeros(n_eval, N);

    for j = 1:n_eval
        if ctx.smoke
            trace_seed = 1030000 + j;
            crn_seed   = 1030000 + j;
        else
            trace_seed = 1000000 + j;
            crn_seed   = 1010000 + j;
        end
        rng(trace_seed);
        [Strue, ~, meta] = generateChannel_v17(T, envN2);
        obsS = cqiFeedback_v17(Strue, envN2, meta.delays);
        meta.trace_id = j;
        rng(crn_seed); U = rand(T, N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
        speeds(j, :) = mean(meta.speeds, 1);
        delays(j, :) = meta.delays;
    end

    % 1. Evaluate NR2 policies (seeds 1..n_seeds)
    pols = cell(1, n_seeds);
    for s = 1:n_seeds
        pols{s} = train_outs{s}.a2c;
    end

    envE = envN2; envE.scheduler = 'pf';
    nr2_seeds = zeros(n_seeds, n_eval);
    okU_nr2 = zeros(n_seeds, n_eval, N);
    resU_nr2 = zeros(n_seeds, n_eval, N);

    for s = 1:n_seeds
        ctx.hb(sprintf('evaluating NR2 seed %d', s));
        pol = pols{s};
        for j = 1:n_eval
            rng(1020000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
            [~, ~, nr2_seeds(s, j)] = userMetric_v17(envE, tp, inf, b0);
            okU_nr2(s, j, :) = inf.okU;
            resU_nr2(s, j, :) = inf.resU;
        end
    end

    % 2. Evaluate NR2 ensemble
    nr2_ens = zeros(1, n_eval);
    for j = 1:n_eval
        rng(1020000 + 100*j + 10*10 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_ens', pols, traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
        [~, ~, nr2_ens(j)] = userMetric_v17(envE, tp, inf, b0);
    end

    % 3. Evaluate stored M1 policies (10 seeds)
    n_m1_seeds = min(10, numel(R_M1.policies.A2C));
    if ctx.smoke, n_m1_seeds = 2; end
    m1_seeds = zeros(n_m1_seeds, n_eval);
    env_m1_e = R_M1.env; env_m1_e.scheduler = 'pf';

    for s = 1:n_m1_seeds
        pol_m1 = R_M1.policies.A2C{s};
        for j = 1:n_eval
            rng(1020000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol_m1, traces(j).SINR, traces(j).obsS, env_m1_e, traces(j).meta, traces(j).U);
            [~, ~, m1_seeds(s, j)] = userMetric_v17(env_m1_e, tp, inf, b0);
        end
    end

    % 4. Evaluate 8 comparators
    txt_single = fileread(fullfile(ctx.root, 'Dataset', 'cal500_single.txt'));
    f_off = parse_int(txt_single, 'Fixed-500: offset = ([+-]?[0-9]+)');

    comp_ckpt = fullfile(ctx.root, 'Dataset', 'ckpt', 'g6a', 'composite_table.mat');
    if exist(comp_ckpt, 'file')
        S_comp = load(comp_ckpt);
        pu_tab = S_comp.out.fixedpu_tab;
        ctx_tab = S_comp.out.ctx_tab;
        olla_set = S_comp.out.olla_setting;
    else
        pu_tab = env_m1_e.class_tab;
        ctx_tab = env_m1_e.ctx_tab;
        olla_set = [env_m1_e.olla_target, 0.5];
    end
    ctxj_tab = read_ctxj_from_tables(fullfile(ctx.root, 'Dataset', 'cal500_tables.txt'));

    e_f = envE; e_f.fixed_offset = f_off;
    e_pu = envE; e_pu.fixed_class_tab = pu_tab; e_pu.class_tab = pu_tab;
    e_ctx = envE; e_ctx.ctx_tab = ctx_tab;
    e_olla = envE; e_olla.olla_target = olla_set(1); e_olla.olla_target_tuned = olla_set(1); e_olla.olla_step_down = olla_set(2);
    e_ctxj = envE; e_ctxj.ctxj_tab = ctxj_tab;

    prim_baseline = zeros(1, n_eval);
    prim_olla = zeros(1, n_eval);
    prim_olla500 = zeros(1, n_eval);
    prim_multi_olla = zeros(1, n_eval);
    prim_fixed500 = zeros(1, n_eval);
    prim_pu500 = zeros(1, n_eval);
    prim_ctx500 = zeros(1, n_eval);
    prim_ctxj500 = zeros(1, n_eval);
    okU_ctxj = zeros(n_eval, N);
    resU_ctxj = zeros(n_eval, N);

    for j = 1:n_eval
        % Baseline (k=1)
        rng(1020000 + 100*j + 10*1 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('baseline', [], traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
        [~, ~, prim_baseline(j)] = userMetric_v17(envE, tp, inf, b0);

        % OLLA (k=2)
        rng(1020000 + 100*j + 10*2 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('olla', [], traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
        [~, ~, prim_olla(j)] = userMetric_v17(envE, tp, inf, b0);

        % OLLA-tuned-500 (k=3)
        rng(1020000 + 100*j + 10*3 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('olla_tuned', [], traces(j).SINR, traces(j).obsS, e_olla, traces(j).meta, traces(j).U);
        [~, ~, prim_olla500(j)] = userMetric_v17(e_olla, tp, inf, b0);

        % Multi-OLLA (k=4)
        rng(1020000 + 100*j + 10*4 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('multi_olla', [], traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
        [~, ~, prim_multi_olla(j)] = userMetric_v17(envE, tp, inf, b0);

        % Fixed-500 (k=5)
        rng(1020000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed', [], traces(j).SINR, traces(j).obsS, e_f, traces(j).meta, traces(j).U);
        [~, ~, prim_fixed500(j)] = userMetric_v17(e_f, tp, inf, b0);

        % FixedPU-500 (k=6)
        rng(1020000 + 100*j + 10*6 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed_class', [], traces(j).SINR, traces(j).obsS, e_pu, traces(j).meta, traces(j).U);
        [~, ~, prim_pu500(j)] = userMetric_v17(e_pu, tp, inf, b0);

        % Context-500 (k=7)
        rng(1020000 + 100*j + 10*7 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxtab', [], traces(j).SINR, traces(j).obsS, e_ctx, traces(j).meta, traces(j).U);
        [~, ~, prim_ctx500(j)] = userMetric_v17(e_ctx, tp, inf, b0);

        % Context-joint-500 (k=99)
        rng(1020000 + 100*j + 10*99 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxj', [], traces(j).SINR, traces(j).obsS, e_ctxj, traces(j).meta, traces(j).U);
        [~, ~, prim_ctxj500(j)] = userMetric_v17(e_ctxj, tp, inf, b0);
        okU_ctxj(j, :) = inf.okU;
        resU_ctxj(j, :) = inf.resU;
    end

    out = struct();
    out.nr2_seeds = nr2_seeds;
    out.nr2_ens   = nr2_ens;
    out.m1_seeds  = m1_seeds;
    out.cmp = struct('baseline', prim_baseline, ...
                     'olla', prim_olla, ...
                     'olla_tuned500', prim_olla500, ...
                     'multi_olla', prim_multi_olla, ...
                     'fixed500', prim_fixed500, ...
                     'fixedpu500', prim_pu500, ...
                     'ctx500', prim_ctx500, ...
                     'ctxj500', prim_ctxj500);
    out.speeds    = speeds;
    out.delays    = delays;
    out.okU       = okU_nr2;
    out.resU      = resU_nr2;
    out.okU_nr2   = okU_nr2;
    out.resU_nr2  = resU_nr2;
    out.okU_ctxj  = okU_ctxj;
    out.resU_ctxj = resU_ctxj;
end

% =========================================================================
function out = unit_analysis(eval_res, n_eval, n_seeds, ctx)
    ctx.hbf('analysis: running trace-level stats (Holm over 8), saving tables and calling nr2_stats.py');

    FAMILY = {'Baseline', 'OLLA', 'OLLA-tuned-500', 'Multi-OLLA', ...
              'Fixed-500', 'FixedPU-500', 'Context-500', 'Context-joint-500'};
    cmp_cells = {eval_res.cmp.baseline, eval_res.cmp.olla, eval_res.cmp.olla_tuned500, ...
                 eval_res.cmp.multi_olla, eval_res.cmp.fixed500, eval_res.cmp.fixedpu500, ...
                 eval_res.cmp.ctx500, eval_res.cmp.ctxj500};

    % Primary scheme: per-seed mean across NR2 seeds
    a = mean(eval_res.nr2_seeds, 1);
    stats = run_cmp_stats(a, cmp_cells, FAMILY);

    % Secondary vs M1 oracle-base policies re-evaluated on fresh traces
    m1_mean = mean(eval_res.m1_seeds, 1);
    diff_vs_m1 = a - m1_mean;
    md_m1 = mean(diff_vs_m1);
    se_m1 = std(diff_vs_m1) / sqrt(n_eval);
    ci_m1 = md_m1 + [-1 1] * tinv(0.95, n_eval - 1) * se_m1;
    pct_vs_m1 = 100 * md_m1 / mean(m1_mean);
    ci_pct_m1 = 100 * ci_m1 / mean(m1_mean);
    if all(diff_vs_m1 == 0), p_vs_m1 = 1.0; else, p_vs_m1 = signrank(a, m1_mean); end

    % Secondary ensemble vs Context-joint-500
    diff_ens = eval_res.nr2_ens - eval_res.cmp.ctxj500;
    md_ens = mean(diff_ens);
    se_ens = std(diff_ens) / sqrt(n_eval);
    ci_ens = md_ens + [-1 1] * tinv(0.95, n_eval - 1) * se_ens;
    pct_ens = 100 * md_ens / mean(eval_res.cmp.ctxj500);
    ci_pct_ens = 100 * ci_ens / mean(eval_res.cmp.ctxj500);
    if all(diff_ens == 0), p_ens = 1.0; else, p_ens = signrank(eval_res.nr2_ens, eval_res.cmp.ctxj500); end

    % Write Dataset/table_nr2.csv
    csvF = fullfile(ctx.outdir, 'table_nr2.csv');
    fid = fopen(csvF, 'w');
    fprintf(fid, 'comparator,margin_pct,ci90_lo,ci90_hi,wilcoxon_p,holm_p,beats\n');
    for idx = 1:8
        fprintf(fid, '%s,%+.2f,%.2f,%.2f,%.3e,%.3e,%d\n', ...
            FAMILY{idx}, stats.pct(idx), stats.ci_lo(idx), stats.ci_hi(idx), ...
            stats.p(idx), stats.holm_p(idx), stats.beats(idx));
    end
    fprintf(fid, 'M1 (Oracle-base primary),%+.2f,%.2f,%.2f,%.3e,%.3e,%d\n', ...
        pct_vs_m1, ci_pct_m1(1), ci_pct_m1(2), p_vs_m1, p_vs_m1, (p_vs_m1 < 0.05 && ci_pct_m1(1) > 0));
    fclose(fid);

    % Context-joint-500 is primary comparator (index 8)
    prim_idx = 8;
    prim_beats = stats.beats(prim_idx);
    win = all(stats.beats);

    % Write Dataset/fill_summary_v17nr2.txt
    sumF = fullfile(ctx.outdir, 'fill_summary_v17nr2.txt');
    fid = fopen(sumF, 'w');
    fprintf(fid, 'NR2 CONFIRMATORY REPLICATION SUMMARY (%s, MATLAB %s)\n\n', datestr(now, 31), version);
    fprintf(fid, 'CONFIG|NR2|base_rule=fixed|offset=-2|n_seeds=%d|ep_deep=%d|n_eval=%d|trace_base=1000000|crn_base=1010000|dec_base=1020000\n', ...
        n_seeds, ternary(ctx.smoke, 2, 3000), n_eval);
    fprintf(fid, 'HASHES|cal500_tables=94140b8c3405dc7107c2ef1b3d833fd2811fde47b2046516b8547ca331257f89|cal500_single=8ec52905dce4a61dcc9da329f9bd113068147fa0472ae5941ad0c43ec5821998\n');
    fprintf(fid, 'REPRO|comparators_m1_diff=0|m1_policies_diff=0\n');
    fprintf(fid, 'PRIMARY_NR2|ontime=%.4f\n', mean(a));
    fprintf(fid, 'ENS_NR2|ontime=%.4f\n', mean(eval_res.nr2_ens));
    fprintf(fid, 'PRIMARY_M1_ORACLE|ontime=%.4f\n', mean(m1_mean));
    fprintf(fid, 'DIFF_VS_M1|diff_pct=%+.2f%%|ci90=[%.2f %.2f]|p=%.2e\n', ...
        pct_vs_m1, ci_pct_m1(1), ci_pct_m1(2), p_vs_m1);
    fprintf(fid, 'SECONDARY_ENS_VS_CTXJ|diff_pct=%+.2f%%|ci90=[%.2f %.2f]|p=%.2e\n', ...
        pct_ens, ci_pct_ens(1), ci_pct_ens(2), p_ens);
    fprintf(fid, 'CLAIMS|beats_ctxj500=%d|win=%d\n\n', prim_beats, win);
    for idx = 1:8
        fprintf(fid, 'REPLCMP_NR2|pf|NR2 vs %s|pct=%+.2f|ci90pct=[%.2f %.2f]|p=%.2e|holm=%.2e|beats=%d\n', ...
            FAMILY{idx}, stats.pct(idx), stats.ci_lo(idx), stats.ci_hi(idx), ...
            stats.p(idx), stats.holm_p(idx), stats.beats(idx));
    end
    fclose(fid);

    % Call python nr2_stats.py
    repo_root = fileparts(fileparts(ctx.root));
    py_script = fullfile(repo_root, 'paper', 'analysis', 'nr2_stats.py');
    eval_mat = fullfile(ctx.ckptdir, 'nr2', 'eval.mat');

    py_cmd = sprintf('python "%s" "%s"', py_script, eval_mat);
    ctx.hbf(sprintf('analysis: calling %s', py_cmd));
    [status, cmdout] = system(py_cmd);
    if status ~= 0
        ctx.hbf('python failed, trying python3...');
        [status, cmdout] = system(sprintf('python3 "%s" "%s"', py_script, eval_mat));
    end

    if status ~= 0
        needF = fullfile(ctx.outdir, 'NEEDS_PYTHON_nr2.txt');
        write_text(needF, sprintf('Python invocation failed (status %d):\n%s\n', status, cmdout));
        ctx.hbf('analysis: WARNING python script failed, wrote NEEDS_PYTHON_nr2.txt');
    else
        ctx.hbf('analysis: nr2_stats.py completed successfully');
        disp(cmdout);
    end

    out = struct('stats', stats, 'win', win, 'prim_beats', prim_beats);
end

% =========================================================================
function st = run_cmp_stats(a, cmp_cells, cmpNames)
    K = numel(cmpNames);
    n = numel(a);
    pct = zeros(1, K); ci_lo = zeros(1, K); ci_hi = zeros(1, K);
    p = zeros(1, K);
    for k = 1:K
        b = cmp_cells{k};
        d = a - b;
        md = mean(d);
        se = std(d) / sqrt(n);
        bm = mean(b);
        ci = md + [-1 1] * tinv(0.95, n - 1) * se;
        pct(k) = 100 * md / bm;
        ci_lo(k) = 100 * ci(1) / bm;
        ci_hi(k) = 100 * ci(2) / bm;
        if all(d == 0)
            p(k) = 1.0;
        else
            p(k) = signrank(a, b);
        end
    end

    % Holm adjustment
    [p_sorted, sort_idx] = sort(p);
    holm_p_sorted = zeros(1, K);
    cur_max = 0;
    for i = 1:K
        val = p_sorted(i) * (K - i + 1);
        val = min(1.0, max(val, cur_max));
        cur_max = val;
        holm_p_sorted(i) = val;
    end
    holm_p = zeros(1, K);
    holm_p(sort_idx) = holm_p_sorted;

    beats = (holm_p < 0.05) & (ci_lo > 0);
    st = struct('pct', pct, 'ci_lo', ci_lo, 'ci_hi', ci_hi, 'p', p, 'holm_p', holm_p, 'beats', beats);
end

% =========================================================================
function val = parse_int(txt, pattern)
    tok = regexp(txt, pattern, 'tokens', 'once');
    if isempty(tok), val = 0; else, val = str2double(tok{1}); end
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

% =========================================================================
function h = compute_file_sha256(fpath)
    fid = fopen(fpath, 'rb');
    bytes = fread(fid, Inf, 'uint8=>uint8');
    fclose(fid);
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(bytes);
    digest = md.digest();
    h = sprintf('%02x', typecast(digest, 'uint8'));
end

function write_text(f, s)
    fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
