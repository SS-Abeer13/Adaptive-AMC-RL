function stage_nr1(ctx)
% stage_nr1  Residual on a non-oracle Fixed base under realistic HARQ (v17n).
% Spec: paper/proposals/NR1_nonoracle_residual_prereg.md
% Units:
%   calib
%   train_seed_K (K = 1..n_seeds)
%   eval
% Outputs:
%   Dataset/fill_summary_v17n.txt
%   table_nr1.csv
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'nr1'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; env_M1 = R_M1.env;
    
    n_seeds = ternary(ctx.smoke, 2, 10);
    ep_deep = ternary(ctx.smoke, 2, 3000);
    n_eval  = ternary(ctx.smoke, 2, 500);
    base_seed = 24042;
    T = o.simTime;
    
    ctx.hbf(sprintf('NR1 start: n_seeds=%d, ep_deep=%d, n_eval=%d', n_seeds, ep_deep, n_eval));
    
    % ---- 1. Unit: calib ----
    calib_res = ctx.unit('calib', @() unit_calib(env_M1, o, ctx));
    envN1 = calib_res.env;
    
    % ---- 2. Units: train_seed_K ----
    train_outs = cell(1, n_seeds);
    for s = 1:n_seeds
        u_name = sprintf('train_seed_%d', s);
        train_outs{s} = ctx.unit(u_name, @() unit_train(envN1, T, ep_deep, base_seed, s, ctx));
    end
    
    % ---- 3. Unit: eval ----
    ctx.unit('eval', @() unit_eval(R_M1, envN1, train_outs, o, n_eval, n_seeds, ep_deep, ctx));
    
    ctx.hbf('NR1 done successfully');
end

% =========================================================================
function out = unit_calib(env_M1, o, ctx)
    ctx.hbf('calib: verifying calibration reproduces M1 exactly, then forcing base_rule_force=fixed');
    env = env_M1;
    nCalib = ternary(ctx.smoke, 2, 20);
    
    if ~ctx.smoke
        % In full run, assert that calibrated tables equal M1's stored tables
        cal_env = calibrateFixedClass_v17(env, nCalib, o.simTime);
        cal_env = calibrateCtx_v17(cal_env, cal_env.n_calib_ctx, o.simTime);
        if cal_env.fixed_offset ~= env_M1.fixed_offset
            error('v17x:nr1:calib', 'calibrated fixed_offset (%d) differs from M1 (%d)', cal_env.fixed_offset, env_M1.fixed_offset);
        end
        if ~isequal(cal_env.fixed_class_tab, env_M1.fixed_class_tab)
            error('v17x:nr1:calib', 'calibrated fixed_class_tab differs from M1');
        end
        if ~isequal(cal_env.ctx_tab, env_M1.ctx_tab)
            error('v17x:nr1:calib', 'calibrated ctx_tab differs from M1');
        end
        ctx.hbf('calib: M1 calibration tables reproduced exactly');
    end
    
    env.base_rule_force = 'fixed';
    [env, baseName] = selectBaseRule_v17n(env, nCalib, o.simTime);
    if ~strcmp(env.base_rule_kind, 'fixed')
        error('v17x:nr1:calib', 'base_rule_kind is not fixed (got %s)', env.base_rule_kind);
    end
    ctx.hbf(sprintf('calib: forced base rule selected: %s (kind=%s, offset=%+d)', ...
        baseName, env.base_rule_kind, env.fixed_offset));
    out = struct('env', env);
end

% =========================================================================
function out = unit_train(env, simTime, ep_deep, base_seed, s, ctx)
    ctx.hbf(sprintf('train_seed_%d: training A2C (seed %d, %d episodes)', s, base_seed + 200 + s, ep_deep));
    envPrim = env;
    envPrim.scheme_name = 'Deep A2C v17 (non-oracle base)';
    envPrim.seed_idx = s;
    
    t0 = tic;
    [a2c, critic, lc, ent, abest, ~, bestEp, valc, trainInfo] = ...
        DeepA2C_Shared_v17(simTime, ep_deep, base_seed + 200 + s, envPrim);
    
    late_frac = 0;
    if isstruct(trainInfo) && isfield(trainInfo, 'late_credit_frac')
        late_frac = trainInfo.late_credit_frac;
    end
    
    ctx.hbf(sprintf('train_seed_%d: finished in %.1f s, final lc=%.2f', s, toc(t0), lc(end)));
    out = struct('a2c', a2c, 'critic', critic, 'lc', lc, 'ent', ent, ...
                 'abest', abest, 'bestEp', bestEp, 'valc', valc, 'late_credit_frac', late_frac);
end

% =========================================================================
function out = unit_eval(R_M1, envN1, train_outs, o, n_eval, n_seeds, ep_deep, ctx)
    ctx.hbf('eval: evaluating NR1 policies on M1 evaluation traces');
    T = o.simTime;
    b0 = min(envN1.burn_in, T - 1);
    
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        rng(o.trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, envN1);
        obsS = cqiFeedback_v17(Strue, envN1, meta.delays);
        meta.trace_id = j;
        rng(o.crn_seed_base + j); U = rand(T, envN1.N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end
    
    pols = cell(1, n_seeds);
    for s = 1:n_seeds
        pols{s} = train_outs{s}.a2c;
    end
    
    envE = envN1; envE.scheduler = 'pf';
    
    % Evaluate 10 NR1 seeds
    prim_seeds = zeros(n_seeds, n_eval);
    for s = 1:n_seeds
        ctx.hb(sprintf('evaluating NR1 seed %d', s));
        pol = pols{s};
        for j = 1:n_eval
            rng(77000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_v17('a2c_v17', pol, traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
            [~, ~, prim_seeds(s, j)] = userMetric_v17(envE, tp, inf, b0);
        end
    end
    
    % Ensemble
    prim_ens = zeros(1, n_eval);
    for j = 1:n_eval
        rng(77000 + 100*j + 10*10 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('a2c_ens', pols, traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
        [~, ~, prim_ens(j)] = userMetric_v17(envE, tp, inf, b0);
    end
    
    nr1_prim = mean(prim_seeds, 1);
    
    % Stored M1 comparators
    cmpNames = {'Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', ...
                'Fixed', 'FixedPU (Oracle)', 'Context table', ...
                'Bandit (global)', 'Bandit (delay class)'};
    cold_indices = [1, 2, 3, 4, 5, 6, 7, 13, 14];
    m1_cmp = cell(1, 9);
    for idx = 1:9
        k = cold_indices(idx);
        m1_cmp{idx} = mean(R_M1.metrics(1).primary{k}(:, 1:n_eval), 1, 'omitnan');
    end
    m1_a2c = mean(R_M1.metrics(1).primary{8}(:, 1:n_eval), 1, 'omitnan');
    
    % Statistical tests: Holm over 9 comparators
    stats = run_cmp_stats(nr1_prim, m1_cmp, cmpNames);
    
    % Paired test: NR1 vs M1 oracle-base primary policy
    diff_vs_m1 = nr1_prim - m1_a2c;
    md_m1 = mean(diff_vs_m1);
    se_m1 = std(diff_vs_m1) / sqrt(n_eval);
    ci_m1 = md_m1 + [-1 1] * tinv(0.95, n_eval - 1) * se_m1;
    pct_vs_m1 = 100 * md_m1 / mean(m1_a2c);
    ci_pct_m1 = 100 * ci_m1 / mean(m1_a2c);
    if all(diff_vs_m1 == 0), p_vs_m1 = 1.0; else, p_vs_m1 = signrank(nr1_prim, m1_a2c); end
    
    % Claims:
    % Claim A: beats OLLA family (indices 2, 3, 4)
    claimA = stats.beats(2) && stats.beats(3) && stats.beats(4);
    % Claim B: beats calibrated rules (indices 5, 6, 7)
    claimB = stats.beats(5) && stats.beats(6) && stats.beats(7);
    % WIN: beats all 9
    nr1_win = all(stats.beats);
    
    % Verdict string per §4
    if nr1_win
        verdict = 'NR1 WIN';
    elseif claimA
        verdict = 'NR1 Claim A only';
    else
        verdict = 'NR1 fails';
    end
    
    % Write table_nr1.csv
    csvF = fullfile(ctx.outdir, 'table_nr1.csv');
    f = fopen(csvF, 'w');
    fprintf(f, 'comparator,nr1_margin_pct,ci90_lo,ci90_hi,wilcoxon_p,holm_p,beats\n');
    for idx = 1:9
        fprintf(f, '%s,%+.2f,%.2f,%.2f,%.2e,%.2e,%d\n', ...
            cmpNames{idx}, stats.pct(idx), stats.ci_lo(idx), stats.ci_hi(idx), ...
            stats.p(idx), stats.holm_p(idx), stats.beats(idx));
    end
    fprintf(f, 'M1 (Oracle-base primary),%+.2f,%.2f,%.2f,%.2e,%.2e,%d\n', ...
        pct_vs_m1, ci_pct_m1(1), ci_pct_m1(2), p_vs_m1, p_vs_m1, (p_vs_m1 < 0.05 && ci_pct_m1(1) > 0));
    fclose(f);
    
    % Also copy to paper/table_nr1.csv
    try
        copyfile(csvF, fullfile(fileparts(ctx.root), 'paper', 'table_nr1.csv'));
    catch
    end
    
    % Write fill_summary_v17n.txt
    txtF = fullfile(ctx.outdir, 'fill_summary_v17n.txt');
    f = fopen(txtF, 'w');
    fprintf(f, 'NR1 NON-ORACLE RESIDUAL SUMMARY (%s, MATLAB %s)\n\n', datestr(now, 31), version);
    fprintf(f, 'CONFIG|NR1|base_rule=fixed|offset=%+d|n_seeds=%d|ep_deep=%d|n_eval=%d\n', ...
        envN1.fixed_offset, n_seeds, ep_deep, n_eval);
    fprintf(f, 'PRIMARY_NR1|ontime=%.4f\n', mean(nr1_prim));
    fprintf(f, 'ENS_NR1|ontime=%.4f\n', mean(prim_ens));
    fprintf(f, 'PRIMARY_M1_ORACLE|ontime=%.4f\n', mean(m1_a2c));
    fprintf(f, 'DIFF_VS_M1|diff_pct=%+.2f%%|ci90=[%.2f %.2f]|p=%.2e\n', ...
        pct_vs_m1, ci_pct_m1(1), ci_pct_m1(2), p_vs_m1);
    fprintf(f, 'CLAIMS|claimA=%d|claimB=%d|win=%d|verdict=%s\n\n', claimA, claimB, nr1_win, verdict);
    for idx = 1:9
        fprintf(f, 'REPLCMP_NR1|pf|NR1 vs %s|pct=%+.2f|ci90pct=[%.2f %.2f]|p=%.2e|holm=%.2e|beats=%d\n', ...
            cmpNames{idx}, stats.pct(idx), stats.ci_lo(idx), stats.ci_hi(idx), ...
            stats.p(idx), stats.holm_p(idx), stats.beats(idx));
    end
    fclose(f);
    
    ctx.hbf(sprintf('NR1 results: %s (Claim A=%d, Claim B=%d, WIN=%d, diff vs M1=%+.2f%%)', ...
        verdict, claimA, claimB, nr1_win, pct_vs_m1));
    out = struct('stats', stats, 'verdict', verdict, 'nr1_prim', nr1_prim);
end

% =========================================================================
function st = run_cmp_stats(a2c, cmp_cells, cmpNames)
    K = numel(cmpNames);
    n = numel(a2c);
    pct = zeros(1, K); ci_lo = zeros(1, K); ci_hi = zeros(1, K);
    p = zeros(1, K);
    for k = 1:K
        b = cmp_cells{k};
        d = a2c - b;
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
            p(k) = signrank(a2c, b);
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

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
