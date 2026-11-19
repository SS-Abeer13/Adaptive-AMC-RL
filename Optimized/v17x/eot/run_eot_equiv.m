function run_eot_equiv()
% run_eot_equiv  Bit-identity gate for EOT variant on calibration traces 60001-60020.
% Compares frozen evaluators vs EOT 'asrun' evaluator across:
%   M1 env: Baseline, OLLA, Fixed, FixedPU, Context, Context-joint-500,
%           M1 seed 1, NR2 seed 1, R6a seed 1, GBT-res-ACK fit 1, GBT-full-ACK fit 1.
%   M2 env: Baseline, OLLA, Fixed, M2 seed 1.
% Outputs lines to Dataset/eot/eot_equiv.txt:
%   EQUIV|<case>|<scheme>|bit_identical=1

    here = fileparts(mfilename('fullpath'));
    v17x_dir = fileparts(here);
    v17_dir = fullfile(fileparts(v17x_dir), 'v17');
    addpath(here);
    addpath(fullfile(v17x_dir, 'g6'));
    addpath(fullfile(v17x_dir, 'nr1'));
    addpath(v17x_dir);
    addpath(v17_dir);
    v17_setup;

    out_dir = fullfile(v17x_dir, 'Dataset', 'eot');
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    equiv_file = fullfile(out_dir, 'eot_equiv.txt');
    fid = fopen(equiv_file, 'w');
    if fid < 0, error('Cannot open %s for writing', equiv_file); end
    cleanup = onCleanup(@() fclose(fid));

    % ---- Load M1 setup & policies ----
    tag_m1 = 'M1_dl_rtt8';
    ov = C.(tag_m1); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data_m1 = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag_m1)));
    R_M1 = data_m1.results;
    env_m1 = R_M1.env;
    env_m1.scheduler = 'pf';
    o.simTime = 200; % calibration trace length

    % Fixed offset from cal500_single.txt or default
    f_off = -2;
    comp_ckpt = fullfile(v17x_dir, 'Dataset', 'ckpt', 'g6a', 'composite_table.mat');
    if exist(comp_ckpt, 'file')
        S_comp = load(comp_ckpt);
        pu_tab = S_comp.out.fixedpu_tab;
        ctx_tab = S_comp.out.ctx_tab;
    else
        pu_tab = env_m1.class_tab;
        ctx_tab = env_m1.ctx_tab;
    end
    ctxj_tab_file = fullfile(v17x_dir, 'Dataset', 'cal500_tables.txt');
    if exist(ctxj_tab_file, 'file')
        ctxj_tab = read_ctxj_from_tables(ctxj_tab_file);
    else
        ctxj_tab = env_m1.ctx_tab;
    end

    e_f = env_m1; e_f.fixed_offset = f_off;
    e_pu = env_m1; e_pu.fixed_class_tab = pu_tab; e_pu.class_tab = pu_tab;
    e_ctx = env_m1; e_ctx.ctx_tab = ctx_tab;
    e_ctxj = env_m1; e_ctxj.ctxj_tab = ctxj_tab;

    % Base rule environment for NR2: Fixed with frozen offset -2
    envN2 = env_m1;
    envN2.base_rule_force = 'fixed';
    envN2.fixed_offset = -2;
    envN2 = selectBaseRule_v17n(envN2, 2, o.simTime);

    % Full action environment for R6a
    envFull = envN2;
    envFull.resid_actions = -2:4;
    envFull.scheme_name = 'Deep A2C v17 (full action set, non-oracle base)';

    % Policies
    pol_m1_s1 = R_M1.policies.A2C{1};

    nr2_s1_mat = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr2', 'train_seed_1.mat'));
    pol_nr2_s1 = nr2_s1_mat.out.a2c;

    r6a_s1_mat = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r6_fullaction', 'train_1.mat'));
    pol_r6a_s1 = r6a_s1_mat.out.a2c;

    r1b_equiv = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'r1b_ack', 'equiv.mat'));
    r1b_model = r1b_equiv.out;

    % ---- Load M2 setup & policies ----
    tag_m2 = 'M2_dl_rtt0';
    ov2 = C.(tag_m2); o2 = base; fn2 = fieldnames(ov2);
    for k = 1:numel(fn2), o2.(fn2{k}) = ov2.(fn2{k}); end
    data_m2 = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag_m2)));
    R_M2 = data_m2.results;
    env_m2 = R_M2.env;
    env_m2.scheduler = 'pf';

    pol_m2_s1 = R_M2.policies.A2C{1};

    % Calibration traces 60001..60020
    nTraces = 20;
    fprintf('Generating %d calibration traces (60001-60020)...\n', nTraces);
    traces_m1 = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    traces_m2 = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:nTraces
        tr_seed = 60000 + j;
        crn_seed = 62000 + j;

        % M1 trace
        rng(tr_seed, 'twister');
        [Strue1, ~, meta1] = generateChannel_v17(o.simTime, env_m1);
        obsS1 = cqiFeedback_v17(Strue1, env_m1, meta1.delays);
        meta1.trace_id = tr_seed;
        rng(crn_seed, 'twister');
        U1 = rand(o.simTime, env_m1.N);
        traces_m1(j).SINR = Strue1; traces_m1(j).obsS = obsS1; traces_m1(j).meta = meta1; traces_m1(j).U = U1;

        % M2 trace
        rng(tr_seed, 'twister');
        [Strue2, ~, meta2] = generateChannel_v17(o.simTime, env_m2);
        obsS2 = cqiFeedback_v17(Strue2, env_m2, meta2.delays);
        meta2.trace_id = tr_seed;
        rng(crn_seed, 'twister');
        U2 = rand(o.simTime, env_m2.N);
        traces_m2(j).SINR = Strue2; traces_m2(j).obsS = obsS2; traces_m2(j).meta = meta2; traces_m2(j).U = U2;
    end

    % =========================================================================
    % M1 Evaluations
    % =========================================================================
    fprintf('\n--- Evaluating M1 schemes ---\n');
    m1_schemes = {
        'Baseline',          'baseline',     [],         env_m1, @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'OLLA',              'olla',         [],         env_m1, @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'Fixed',             'fixed',        [],         e_f,    @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'FixedPU',           'fixed_class',  [],         e_pu,   @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'Context',           'ctxtab',       [],         e_ctx,  @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'Context-joint-500', 'ctxj',         [],         e_ctxj, @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'M1 seed 1',         'a2c_v17',      pol_m1_s1,  env_m1, @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'NR2 seed 1',        'a2c_v17',      pol_nr2_s1, envN2,   @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'R6a seed 1',        'a2c_v17',      pol_r6a_s1, envFull, @evalPolicy_presub, @evalPolicy_presub_eot;
        'GBT-res-ACK fit 1', 'gbt_res_ack',  r1b_model,  e_f,    @evalPolicy_presub, @evalPolicy_presub_eot;
        'GBT-full-ACK fit 1','gbt_full_ack', r1b_model,  e_f,    @evalPolicy_presub, @evalPolicy_presub_eot;
    };

    for s = 1:size(m1_schemes, 1)
        name = m1_schemes{s, 1};
        ptype = m1_schemes{s, 2};
        pol = m1_schemes{s, 3};
        e_scheme = m1_schemes{s, 4};
        f_frozen = m1_schemes{s, 5};
        f_eot = m1_schemes{s, 6};

        fprintf('  Checking M1 | %s... ', name);
        e_scheme_eot = e_scheme;
        e_scheme_eot.eot_mode = 'asrun';

        for j = 1:nTraces
            % Frozen
            [tp_frz, bler_frz, cqi_err_frz, act_frz, inf_frz] = f_frozen(ptype, pol, traces_m1(j).SINR, traces_m1(j).obsS, e_scheme, traces_m1(j).meta, traces_m1(j).U);
            % EOT asrun
            [tp_eot, bler_eot, cqi_err_eot, act_eot, inf_eot] = f_eot(ptype, pol, traces_m1(j).SINR, traces_m1(j).obsS, e_scheme_eot, traces_m1(j).meta, traces_m1(j).U);

            % Bit-identity asserts
            assert(isequal(tp_frz, tp_eot), 'tp mismatch trace %d for %s', j, name);
            nan_frz = isnan(bler_frz); nan_eot = isnan(bler_eot);
            assert(isequal(nan_frz, nan_eot), 'bler NaN pattern mismatch trace %d for %s', j, name);
            if any(~nan_frz(:))
                assert(max(abs(bler_frz(~nan_frz) - bler_eot(~nan_eot))) == 0, 'bler mismatch trace %d for %s', j, name);
            end
            assert(isequal(cqi_err_frz, cqi_err_eot), 'cqi_err mismatch trace %d for %s', j, name);
            assert(isequal(act_frz, act_eot), 'act mismatch trace %d for %s', j, name);
            assert(isequal(inf_frz.okU, inf_eot.okU), 'okU mismatch trace %d for %s', j, name);
            assert(isequal(inf_frz.resU, inf_eot.resU), 'resU mismatch trace %d for %s', j, name);
        end
        fprintf('BIT-IDENTICAL (20/20 traces)\n');
        line = sprintf('EQUIV|M1|%s|bit_identical=1', name);
        fprintf(fid, '%s\n', line);
    end

    % =========================================================================
    % M2 Evaluations (RTT 0)
    % =========================================================================
    fprintf('\n--- Evaluating M2 schemes (RTT 0) ---\n');
    e_f2 = env_m2; e_f2.fixed_offset = -2;
    m2_schemes = {
        'Baseline',          'baseline',     [],         env_m2, @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'OLLA',              'olla',         [],         env_m2, @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'Fixed',             'fixed',        [],         e_f2,   @evalPolicy_v17_g6, @evalPolicy_g6_eot;
        'M2 seed 1',         'a2c_v17',      pol_m2_s1,  env_m2, @evalPolicy_v17_g6, @evalPolicy_g6_eot;
    };

    for s = 1:size(m2_schemes, 1)
        name = m2_schemes{s, 1};
        ptype = m2_schemes{s, 2};
        pol = m2_schemes{s, 3};
        e_scheme = m2_schemes{s, 4};
        f_frozen = m2_schemes{s, 5};
        f_eot = m2_schemes{s, 6};

        fprintf('  Checking M2 | %s... ', name);
        e_scheme_eot = e_scheme;
        e_scheme_eot.eot_mode = 'asrun';

        for j = 1:nTraces
            [tp_frz, bler_frz, cqi_err_frz, act_frz, inf_frz] = f_frozen(ptype, pol, traces_m2(j).SINR, traces_m2(j).obsS, e_scheme, traces_m2(j).meta, traces_m2(j).U);
            [tp_eot, bler_eot, cqi_err_eot, act_eot, inf_eot] = f_eot(ptype, pol, traces_m2(j).SINR, traces_m2(j).obsS, e_scheme_eot, traces_m2(j).meta, traces_m2(j).U);

            assert(isequal(tp_frz, tp_eot), 'tp mismatch trace %d for M2 %s', j, name);
            nan_frz = isnan(bler_frz); nan_eot = isnan(bler_eot);
            assert(isequal(nan_frz, nan_eot), 'bler NaN pattern mismatch trace %d for M2 %s', j, name);
            if any(~nan_frz(:))
                assert(max(abs(bler_frz(~nan_frz) - bler_eot(~nan_eot))) == 0, 'bler mismatch trace %d for M2 %s', j, name);
            end
            assert(isequal(cqi_err_frz, cqi_err_eot), 'cqi_err mismatch trace %d for M2 %s', j, name);
            assert(isequal(act_frz, act_eot), 'act mismatch trace %d for M2 %s', j, name);
            assert(isequal(inf_frz.okU, inf_eot.okU), 'okU mismatch trace %d for M2 %s', j, name);
            assert(isequal(inf_frz.resU, inf_eot.resU), 'resU mismatch trace %d for M2 %s', j, name);
        end
        fprintf('BIT-IDENTICAL (20/20 traces)\n');
        line = sprintf('EQUIV|M2|%s|bit_identical=1', name);
        fprintf(fid, '%s\n', line);
    end

    fprintf('\nAll EQUIV checks passed! eot_equiv.txt written successfully.\n');
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
