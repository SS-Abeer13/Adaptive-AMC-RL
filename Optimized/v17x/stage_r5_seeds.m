function stage_r5_seeds(ctx)
% stage_r5_seeds  Additional training seeds for NR2 (seeds 11..20) and NR-G10 (seeds 6..10).
% Spec: paper/proposals/R_presub_prereg.md §8 and §12 (Amendment 8, Freeze v9).
% Units:
%   train_nr2_11..20
%   train_G2_6..10
%   train_G3_6..10
%   eval
%   export
% Outputs:
%   Dataset/ckpt/r5_seeds/r5_seeds_eval.mat
%   Dataset/presub/pertrace.csv
%   Dataset/REPORT_r5_seeds.txt
%   Dataset/stage_r5_seeds.done

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

    n_nr2_extra = ternary(ctx.smoke, 2, 10);
    n_g10_extra = ternary(ctx.smoke, 2, 5);
    ep_deep     = ternary(ctx.smoke, 2, 3000);
    n_eval_nr2  = ternary(ctx.smoke, 2, 500);
    n_eval_g10  = ternary(ctx.smoke, 2, 300);

    ctx.hbf(sprintf('r5_seeds start: n_nr2_extra=%d, n_g10_extra=%d, ep_deep=%d', ...
        n_nr2_extra, n_g10_extra, ep_deep));

    ckpt_r5 = fullfile(ctx.ckptdir, 'r5_seeds');
    if ~exist(ckpt_r5, 'dir'), mkdir(ckpt_r5); end

    envN2 = env_M1;
    envN2.base_rule_force = 'fixed';
    envN2.fixed_offset = -2;
    [envN2, ~] = selectBaseRule_v17n(envN2, 2, o.simTime);
    envN2.scheme_name = 'Deep A2C v17 (non-oracle base)';

    % ---- 1. Units: train_nr2_11..20 ----
    nr2_extra_outs = cell(1, n_nr2_extra);
    nr2_base_seed = 25042;
    for sp = 1:n_nr2_extra
        s_idx = 10 + sp;
        train_seed = nr2_base_seed + 210 + sp;
        assert(train_seed >= 25253 && train_seed <= 25262, 'NR2 fresh seed disjointness assertion');
        u_name = sprintf('train_nr2_%d', s_idx);
        nr2_extra_outs{sp} = ctx.unit(u_name, @() unit_train_seed(envN2, o.simTime, ep_deep, train_seed, s_idx, ctx));
    end

    % ---- 2. Units: train_G2_6..10 and train_G3_6..10 ----
    cells = {'G2_hi_d10', 'G3_lo_d18'};
    cell_extra_outs = struct();

    for cIdx = 1:numel(cells)
        cName = cells{cIdx};
        cCfg = get_cell_cfg(cName, env_M1);

        calib_file = fullfile(ctx.ckptdir, 'g10', sprintf('calib_single_%s.mat', cName));
        if ~exist(calib_file, 'file')
            fallback_c = fullfile(ctx.root, 'Dataset', 'ckpt', 'g10', sprintf('calib_single_%s.mat', cName));
            if exist(fallback_c, 'file'), calib_file = fallback_c; else, error('calib_single_%s.mat missing', cName); end
        end
        calib_s = load(calib_file);
        calib_s = calib_s.out;

        envCal = calib_s.env;
        envCal.base_rule_kind = 'fixed';
        envCal.base_rule_name = 'Fixed';
        envCal.base_rule_force = 'fixed';
        envCal.fixed_offset = calib_s.fixed_offset;
        envCal.scheme_name = sprintf('Deep A2C v17 (%s non-oracle)', cName);

        outs = cell(1, n_g10_extra);
        for sp = 1:n_g10_extra
            s_idx = 5 + sp;
            train_seed = cCfg.base_seed + 205 + sp;
            if strcmp(cName, 'G2_hi_d10')
                assert(train_seed >= 33248 && train_seed <= 33252, 'G2 fresh seed disjointness assertion');
            else
                assert(train_seed >= 34248 && train_seed <= 34252, 'G3 fresh seed disjointness assertion');
            end
            u_name = sprintf('train_%s_%d', cName, s_idx);
            outs{sp} = ctx.unit(u_name, @() unit_train_seed(envCal, o.simTime, ep_deep, train_seed, s_idx, ctx));
        end
        cell_extra_outs.(cName) = outs;
    end

    % ---- 3. Unit: eval ----
    eval_res = ctx.unit('eval', @() unit_eval_fresh(envN2, nr2_extra_outs, cell_extra_outs, ...
        n_nr2_extra, n_g10_extra, n_eval_nr2, n_eval_g10, o, ctx));

    % ---- 4. Unit: export ----
    ctx.unit('export', @() unit_export_master(eval_res, n_nr2_extra, n_g10_extra, n_eval_nr2, n_eval_g10, ctx));

    ctx.hbf('r5_seeds done successfully');
end

% =========================================================================
function out = unit_train_seed(env, simTime, ep_deep, seed, s_idx, ctx)
    ctx.hbf(sprintf('train_seed: training seed %d (index %d, %d episodes)', seed, s_idx, ep_deep));
    t0 = tic;
    [a2c, critic, lc, ent, abest, ~, bestEp, valc] = ...
        DeepA2C_Shared_v17(simTime, ep_deep, seed, env);
    ctx.hbf(sprintf('train_seed: finished in %.1f s, final lc=%.2f', toc(t0), lc(end)));
    out = struct('a2c', a2c, 'critic', critic, 'lc', lc, 'ent', ent, 'abest', abest, 'bestEp', bestEp, 'seed', seed);
    try java.lang.System.gc(); catch, end
end

% =========================================================================
function cfg = get_cell_cfg(cName, env_base)
    cfg = struct('name', cName, 'env', env_base);
    switch cName
        case 'G2_hi_d10'
            cfg.env.pkt_bits = 16000; cfg.env.pkt_deadline = 10;
            cfg.base_seed = 33042;
            cfg.eval_trace_base = 720000; cfg.eval_crn_base = 730000;
        case 'G3_lo_d18'
            cfg.env.pkt_bits = 8000; cfg.env.pkt_deadline = 18;
            cfg.base_seed = 34042;
            cfg.eval_trace_base = 740000; cfg.eval_crn_base = 750000;
        otherwise
            error('v17x:r5:unknownCell', 'unknown cell %s', cName);
    end
end

% =========================================================================
function out = unit_eval_fresh(envN2, nr2_extra_outs, cell_extra_outs, n_nr2_extra, n_g10_extra, n_eval_nr2, n_eval_g10, o, ctx)
    ctx.hbf('eval: evaluating fresh seeds on respective traces');
    b0_m1 = min(envN2.burn_in, o.simTime - 1);

    % 1. Evaluate NR2 fresh seeds (11..20) on NR2 traces
    nr2_fresh_vals = zeros(n_nr2_extra, n_eval_nr2);
    for sp = 1:n_nr2_extra
        pol = nr2_extra_outs{sp}.a2c;
        for j = 1:n_eval_nr2
            tr_seed = ternary(ctx.smoke, 1030000 + j, 1000000 + j);
            crn_seed = ternary(ctx.smoke, 1030000 + j, 1010000 + j);
            rng(tr_seed); [Strue, ~, meta] = generateChannel_v17(o.simTime, envN2);
            obsS = cqiFeedback_v17(Strue, envN2, meta.delays);
            meta.trace_id = j;
            rng(crn_seed); U = rand(o.simTime, envN2.N);

            rng(2040000 + 100*j + sp);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, Strue, obsS, envN2, meta, U);
            [~, ~, nr2_fresh_vals(sp, j)] = userMetric_v17(envN2, tp, inf, b0_m1);
        end
    end
    ctx.hbf(sprintf('eval: NR2 fresh %d seeds mean on-time: %.4f', n_nr2_extra, mean(mean(nr2_fresh_vals))));

    % 2. Evaluate G2 fresh seeds (6..10) on G2 traces
    g2_cfg = get_cell_cfg('G2_hi_d10', envN2);
    envG2 = g2_cfg.env;
    envG2.base_rule_kind = 'fixed'; envG2.base_rule_name = 'Fixed'; envG2.base_rule_force = 'fixed';
    calib_g2_file = fullfile(ctx.ckptdir, 'g10', 'calib_single_G2_hi_d10.mat');
    if ~exist(calib_g2_file, 'file')
        fallback_g2 = fullfile(ctx.root, 'Dataset', 'ckpt', 'g10', 'calib_single_G2_hi_d10.mat');
        if exist(fallback_g2, 'file'), calib_g2_file = fallback_g2; else, error('calib_single_G2_hi_d10.mat missing'); end
    end
    calib_g2 = load(calib_g2_file);
    envG2.fixed_offset = calib_g2.out.fixed_offset;
    b0_g2 = min(envG2.burn_in, o.simTime - 1);

    g2_fresh_vals = zeros(n_g10_extra, n_eval_g10);
    g2_outs = cell_extra_outs.G2_hi_d10;
    for sp = 1:n_g10_extra
        pol = g2_outs{sp}.a2c;
        for j = 1:n_eval_g10
            rng(720000 + j); [Strue, ~, meta] = generateChannel_v17(o.simTime, envG2);
            obsS = cqiFeedback_v17(Strue, envG2, meta.delays);
            meta.trace_id = j;
            rng(730000 + j); U = rand(o.simTime, envG2.N);

            rng(2140000 + 100*j + sp);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, Strue, obsS, envG2, meta, U);
            [~, ~, g2_fresh_vals(sp, j)] = userMetric_v17(envG2, tp, inf, b0_g2);
        end
    end
    ctx.hbf(sprintf('eval: G2 fresh %d seeds mean on-time: %.4f', n_g10_extra, mean(mean(g2_fresh_vals))));

    % 3. Evaluate G3 fresh seeds (6..10) on G3 traces
    g3_cfg = get_cell_cfg('G3_lo_d18', envN2);
    envG3 = g3_cfg.env;
    envG3.base_rule_kind = 'fixed'; envG3.base_rule_name = 'Fixed'; envG3.base_rule_force = 'fixed';
    calib_g3_file = fullfile(ctx.ckptdir, 'g10', 'calib_single_G3_lo_d18.mat');
    if ~exist(calib_g3_file, 'file')
        fallback_g3 = fullfile(ctx.root, 'Dataset', 'ckpt', 'g10', 'calib_single_G3_lo_d18.mat');
        if exist(fallback_g3, 'file'), calib_g3_file = fallback_g3; else, error('calib_single_G3_lo_d18.mat missing'); end
    end
    calib_g3 = load(calib_g3_file);
    envG3.fixed_offset = calib_g3.out.fixed_offset;
    b0_g3 = min(envG3.burn_in, o.simTime - 1);

    g3_fresh_vals = zeros(n_g10_extra, n_eval_g10);
    g3_outs = cell_extra_outs.G3_lo_d18;
    for sp = 1:n_g10_extra
        pol = g3_outs{sp}.a2c;
        for j = 1:n_eval_g10
            rng(740000 + j); [Strue, ~, meta] = generateChannel_v17(o.simTime, envG3);
            obsS = cqiFeedback_v17(Strue, envG3, meta.delays);
            meta.trace_id = j;
            rng(750000 + j); U = rand(o.simTime, envG3.N);

            rng(2240000 + 100*j + sp);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, Strue, obsS, envG3, meta, U);
            [~, ~, g3_fresh_vals(sp, j)] = userMetric_v17(envG3, tp, inf, b0_g3);
        end
    end
    ctx.hbf(sprintf('eval: G3 fresh %d seeds mean on-time: %.4f', n_g10_extra, mean(mean(g3_fresh_vals))));

    out = struct('nr2_fresh_vals', nr2_fresh_vals, 'g2_fresh_vals', g2_fresh_vals, 'g3_fresh_vals', g3_fresh_vals);
end

% =========================================================================
function out = unit_export_master(eval_res, n_nr2_extra, n_g10_extra, n_eval_nr2, n_eval_g10, ctx)
    ctx.hbf('export: assembling and writing master pertrace.csv for presub_stats.py');
    presub_dir = fullfile(ctx.outdir, 'presub');
    if ~exist(presub_dir, 'dir'), mkdir(presub_dir); end

    pertrace_csv = fullfile(presub_dir, 'pertrace.csv');
    fid = fopen(pertrace_csv, 'w');
    fprintf(fid, 'trace_set,scheme,seed,trace,value\n');

    % 1. Trace set: NR2
    nr2_eval_file = fullfile(ctx.ckptdir, 'nr2', 'eval.mat');
    if ~exist(nr2_eval_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr2', 'eval.mat');
        if exist(fallback, 'file'), nr2_eval_file = fallback; else, error('nr2/eval.mat missing'); end
    end
    st_nr2 = load(nr2_eval_file);
    st_nr2_seeds = st_nr2.out.nr2_seeds;
    for s = 1:min(10, size(st_nr2_seeds, 1))
        for t = 1:n_eval_nr2
            fprintf(fid, 'NR2,NR2,%d,%d,%.6f\n', s, t, st_nr2_seeds(s, t));
        end
    end

    for sp = 1:n_nr2_extra
        s_idx = 10 + sp;
        for t = 1:n_eval_nr2
            fprintf(fid, 'NR2,NR2,%d,%d,%.6f\n', s_idx, t, eval_res.nr2_fresh_vals(sp, t));
        end
    end

    cmp = st_nr2.out.cmp;
    fam_keys = {'baseline', 'olla', 'olla_tuned500', 'multi_olla', 'fixed500', 'fixedpu500', 'ctx500', 'ctxj500'};
    for k = 1:numel(fam_keys)
        fkey = fam_keys{k};
        vec = cmp.(fkey);
        for t = 1:n_eval_nr2
            fprintf(fid, 'NR2,%s,0,%d,%.6f\n', fkey, t, vec(t));
        end
    end

    r3_diag_file = fullfile(ctx.ckptdir, 'r3_diag.mat');
    if exist(r3_diag_file, 'file')
        r3_d = load(r3_diag_file);
        for t = 1:n_eval_nr2
            fprintf(fid, 'NR2,olla_warm200,0,%d,%.6f\n', t, r3_d.warm_vals(t));
        end
    end

    r1_eval_file = fullfile(ctx.ckptdir, 'r1_gbt', 'r1_gbt_eval.mat');
    if exist(r1_eval_file, 'file')
        r1_e = load(r1_eval_file);
        for t = 1:n_eval_nr2
            fprintf(fid, 'NR2,GBT-res,0,%d,%.6f\n', t, r1_e.gbt_res_nr2(t));
            fprintf(fid, 'NR2,GBT-full,0,%d,%.6f\n', t, r1_e.gbt_full_nr2(t));
        end
    end

    r2_eval_file = fullfile(ctx.ckptdir, 'r2_rule', 'r2_rule_eval.mat');
    if exist(r2_eval_file, 'file')
        r2_e = load(r2_eval_file);
        for t = 1:n_eval_nr2
            fprintf(fid, 'NR2,Rule,0,%d,%.6f\n', t, r2_e.rule_nr2(t));
            fprintf(fid, 'NR2,Rule-cal,0,%d,%.6f\n', t, r2_e.rule_cal_nr2(t));
        end
    end

    % 2. Trace set: M1
    tag = 'M1_dl_rtt8';
    data_m1 = load(fullfile(ctx.v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data_m1.results;
    m1_seeds_vals = R_M1.metrics(1).primary{8};
    for s = 1:min(10, size(m1_seeds_vals, 1))
        for t = 1:n_eval_nr2
            fprintf(fid, 'M1,M1,%d,%d,%.6f\n', s, t, m1_seeds_vals(s, t));
        end
    end

    if exist(r1_eval_file, 'file')
        r1_e = load(r1_eval_file);
        for s = 1:size(r1_e.nr2_m1_seeds, 1)
            for t = 1:n_eval_nr2
                fprintf(fid, 'M1,NR2,%d,%d,%.6f\n', s, t, r1_e.nr2_m1_seeds(s, t));
            end
        end
        for t = 1:n_eval_nr2
            fprintf(fid, 'M1,GBT-res,0,%d,%.6f\n', t, r1_e.gbt_res_m1(t));
            fprintf(fid, 'M1,GBT-full,0,%d,%.6f\n', t, r1_e.gbt_full_m1(t));
        end
    end

    if exist(r2_eval_file, 'file')
        r2_e = load(r2_eval_file);
        for t = 1:n_eval_nr2
            fprintf(fid, 'M1,Rule,0,%d,%.6f\n', t, r2_e.rule_m1(t));
            fprintf(fid, 'M1,Rule-cal,0,%d,%.6f\n', t, r2_e.rule_cal_m1(t));
        end
    end

    g6c_eval_file = fullfile(ctx.ckptdir, 'g6c', 'eval.mat');
    if ~exist(g6c_eval_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'g6c', 'eval.mat');
        if exist(fallback, 'file'), g6c_eval_file = fallback; else, error('g6c/eval.mat missing'); end
    end
    st_g6c = load(g6c_eval_file);
    for t = 1:n_eval_nr2
        fprintf(fid, 'M1,ctxj500,0,%d,%.6f\n', t, st_g6c.out.prim_ctxj500(t));
        fprintf(fid, 'M1,fixed500,0,%d,%.6f\n', t, st_g6c.out.prim_fixed500(t));
        fprintf(fid, 'M1,ctx500,0,%d,%.6f\n', t, st_g6c.out.prim_ctx500(t));
        fprintf(fid, 'M1,olla_tuned500,0,%d,%.6f\n', t, st_g6c.out.prim_olla500(t));
        fprintf(fid, 'M1,fixedpu500,0,%d,%.6f\n', t, st_g6c.out.prim_pu500(t));
        fprintf(fid, 'M1,baseline,0,%d,%.6f\n', t, R_M1.metrics(1).primary{1}(t));
        fprintf(fid, 'M1,olla,0,%d,%.6f\n', t, R_M1.metrics(1).primary{2}(t));
        fprintf(fid, 'M1,multi_olla,0,%d,%.6f\n', t, R_M1.metrics(1).primary{4}(t));
    end

    % 3. Trace set: G2
    g2_eval_file = fullfile(ctx.ckptdir, 'nr_g10', 'eval_G2_hi_d10.mat');
    if ~exist(g2_eval_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr_g10', 'eval_G2_hi_d10.mat');
        if exist(fallback, 'file'), g2_eval_file = fallback; else, error('eval_G2_hi_d10.mat missing'); end
    end
    st_g2 = load(g2_eval_file);
    g2_seeds_stored = st_g2.out.rl_seeds;
    if size(g2_seeds_stored, 1) > size(g2_seeds_stored, 2)
        g2_seeds_stored = g2_seeds_stored.';
    end
    for s = 1:min(5, size(g2_seeds_stored, 1))
        for t = 1:n_eval_g10
            fprintf(fid, 'G2,NRG10,%d,%d,%.6f\n', s, t, g2_seeds_stored(s, t));
        end
    end
    for sp = 1:n_g10_extra
        s_idx = 5 + sp;
        for t = 1:n_eval_g10
            fprintf(fid, 'G2,NRG10,%d,%d,%.6f\n', s_idx, t, eval_res.g2_fresh_vals(sp, t));
        end
    end
    for k = 1:numel(st_g2.out.cmpNames)
        cName = st_g2.out.cmpNames{k};
        cVec = st_g2.out.cmp_vals{k};
        for t = 1:n_eval_g10
            fprintf(fid, 'G2,%s,0,%d,%.6f\n', cName, t, cVec(t));
        end
    end

    % 4. Trace set: G3
    g3_eval_file = fullfile(ctx.ckptdir, 'nr_g10', 'eval_G3_lo_d18.mat');
    if ~exist(g3_eval_file, 'file')
        fallback = fullfile(ctx.root, 'Dataset', 'ckpt', 'nr_g10', 'eval_G3_lo_d18.mat');
        if exist(fallback, 'file'), g3_eval_file = fallback; else, error('eval_G3_lo_d18.mat missing'); end
    end
    st_g3 = load(g3_eval_file);
    g3_seeds_stored = st_g3.out.rl_seeds;
    if size(g3_seeds_stored, 1) > size(g3_seeds_stored, 2)
        g3_seeds_stored = g3_seeds_stored.';
    end
    for s = 1:min(5, size(g3_seeds_stored, 1))
        for t = 1:n_eval_g10
            fprintf(fid, 'G3,NRG10,%d,%d,%.6f\n', s, t, g3_seeds_stored(s, t));
        end
    end
    for sp = 1:n_g10_extra
        s_idx = 5 + sp;
        for t = 1:n_eval_g10
            fprintf(fid, 'G3,NRG10,%d,%d,%.6f\n', s_idx, t, eval_res.g3_fresh_vals(sp, t));
        end
    end
    for k = 1:numel(st_g3.out.cmpNames)
        cName = st_g3.out.cmpNames{k};
        cVec = st_g3.out.cmp_vals{k};
        for t = 1:n_eval_g10
            fprintf(fid, 'G3,%s,0,%d,%.6f\n', cName, t, cVec(t));
        end
    end

    fclose(fid);
    ctx.hbf(sprintf('export: %s written successfully', pertrace_csv));

    r5_eval_mat = fullfile(ctx.ckptdir, 'r5_seeds', 'r5_seeds_eval.mat');
    nr2_fresh = eval_res.nr2_fresh_vals;
    g2_fresh  = eval_res.g2_fresh_vals;
    g3_fresh  = eval_res.g3_fresh_vals;
    save(r5_eval_mat, 'nr2_fresh', 'g2_fresh', 'g3_fresh', '-v7.3');

    rep_file = fullfile(ctx.outdir, 'REPORT_r5_seeds.txt');
    fid = fopen(rep_file, 'w');
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'REPORT_r5_seeds.txt -- Additional Training Seeds (Stage r5_seeds)\n');
    fprintf(fid, 'Generated: %s | MATLAB %s\n', datestr(now, 31), version);
    fprintf(fid, '================================================================================\n\n');
    fprintf(fid, 'NR2 fresh %d seeds mean on-time: %.4f\n', n_nr2_extra, mean(mean(nr2_fresh)));
    fprintf(fid, 'G2 fresh %d seeds mean on-time:  %.4f\n', n_g10_extra, mean(mean(g2_fresh)));
    fprintf(fid, 'G3 fresh %d seeds mean on-time:  %.4f\n\n', n_g10_extra, mean(mean(g3_fresh)));
    fprintf(fid, 'Master pertrace.csv written to: %s\n', pertrace_csv);
    fclose(fid);

    out = struct('pertrace_csv', pertrace_csv, 'r5_eval_mat', r5_eval_mat);
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
