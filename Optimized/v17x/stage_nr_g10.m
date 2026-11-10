function stage_nr_g10(ctx)
% stage_nr_g10  Operating-point check with the non-oracle residual recipe (v17x-nr-grid).
% Spec: paper/proposals/NR_G10_operating_grid_prereg.md (Amendment 5, frozen).
% Cells: G2_hi_d10, G3_lo_d18
% Recipe: residual A2C with Fixed base rule (one global calibrated offset from G10).
% Outputs:
%   Dataset/table_cells_nr.csv
%   Dataset/fill_summary_v17nr_grid.txt
%   Dataset/REPORT_nr_g10.txt
%   Dataset/stage_nr_g10.done
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env_base = R.env; env_base.scheduler = 'pf';
    
    cells = ctx.g10_cells;
    n_seeds = ternary(ctx.smoke, 2, 5);
    ep_deep = ternary(ctx.smoke, 2, 3000);
    n_eval  = ternary(ctx.smoke, 2, 300);
    T = o.simTime;
    
    cell_results = struct();
    
    for cIdx = 1:numel(cells)
        cName = cells{cIdx};
        ctx.hbf(sprintf('=== Running NR-G10 cell %s (%d/%d) ===', cName, cIdx, numel(cells)));
        
        cCfg = get_cell_cfg(cName, env_base);
        
        % Assert seed disjointness (common_rules.md R4, NR_G10 §2)
        assert(cCfg.base_seed >= 33000 && cCfg.base_seed < 35000, 'NR-G10 base seed range assertion');
        assert(cCfg.eval_trace_base >= 700000 && cCfg.eval_trace_base < 800000, 'NR-G10 eval trace range assertion');
        
        % Load frozen single-cue calibrations from G10
        calib_file = fullfile(ctx.ckptdir, 'g10', sprintf('calib_single_%s.mat', cName));
        if ~exist(calib_file, 'file')
            error('v17x:nr_g10:missingCalib', 'Missing G10 calibration file: %s', calib_file);
        end
        calib_data = load(calib_file);
        calib_s = calib_data.out;
        
        % Set up environment for non-oracle residual training
        envCal = calib_s.env;
        envCal.base_rule_kind = 'fixed';
        envCal.base_rule_name = 'Fixed';
        envCal.base_rule_force = 'fixed';
        envCal.fixed_offset = calib_s.fixed_offset;
        
        ctx.hbf(sprintf('Cell %s NR recipe: base_rule=%s, offset=%d (non-oracle)', ...
            cName, envCal.base_rule_name, envCal.fixed_offset));
        
        % Units: train_seed_<cell>_K
        train_outs = cell(1, n_seeds);
        for s = 1:n_seeds
            u_name = sprintf('train_seed_%s_%d', cName, s);
            train_outs{s} = ctx.unit(u_name, @() unit_train_cell(envCal, T, ep_deep, cCfg.base_seed, s, cName, ctx));
        end
        
        % Load bandits from G10 or train if missing
        bandit_file = fullfile(ctx.ckptdir, 'g10', sprintf('bandit_%s.mat', cName));
        if exist(bandit_file, 'file')
            bdata = load(bandit_file);
            bandit_out = bdata.out;
        else
            bandit_out = ctx.unit(['bandit_' cName], @() unit_bandit_cell(envCal, T, ep_deep, cCfg.base_seed, n_seeds, cName, ctx));
        end
        
        % Unit: eval_<cell>
        eval_out = ctx.unit(['eval_' cName], @() unit_eval_cell_nr(cName, cCfg, envCal, calib_s, train_outs, bandit_out, o, n_eval, n_seeds, ctx));
        cell_results.(cName) = eval_out;
    end
    
    % Aggregate results, write tables and summary
    write_nr_g10_outputs(ctx, cells, cell_results);
    ctx.hbf('nr_g10 done successfully');
end

% =========================================================================
function cfg = get_cell_cfg(cName, env_base)
    cfg = struct();
    cfg.name = cName;
    cfg.env = env_base;
    switch cName
        case 'G2_hi_d10'
            cfg.env.pkt_bits = 16000; cfg.env.pkt_deadline = 10;
            cfg.base_seed = 33042;
            cfg.eval_trace_base  = 720000; cfg.eval_crn_base  = 730000;
        case 'G3_lo_d18'
            cfg.env.pkt_bits = 8000; cfg.env.pkt_deadline = 18;
            cfg.base_seed = 34042;
            cfg.eval_trace_base  = 740000; cfg.eval_crn_base  = 750000;
        otherwise
            error('v17x:nr_g10:unknownCell', 'unknown cell %s', cName);
    end
end

% =========================================================================
function out = unit_train_cell(envCal, simTime, ep_deep, base_seed, s, cName, ctx)
    ctx.hbf(sprintf('train_seed_%s_%d: training Deep A2C v17 on %s (ep=%d, seed=%d)', ...
        cName, s, cName, ep_deep, base_seed + 200 + s));
    envPrim = envCal;
    envPrim.seed_idx = s;
    t0 = tic;
    [a2c, critic, lc, ent, abest, ~, bestEp, valc, trainInfo] = ...
        DeepA2C_Shared_v17(simTime, ep_deep, base_seed + 200 + s, envPrim);
    ctx.hbf(sprintf('train_seed_%s_%d: finished in %.1f s, final lc=%.2f', cName, s, toc(t0), lc(end)));
    out = struct('a2c', a2c, 'critic', critic, 'lc', lc, 'ent', ent, 'abest', abest, 'bestEp', bestEp);
end

% =========================================================================
function out = unit_bandit_cell(env, simTime, ep_deep, base_seed, n_seeds, cName, ctx)
    ctx.hbf(sprintf('bandit_%s: training bandits on same episodes', cName));
    b_glob = cell(1, n_seeds);
    b_delay = cell(1, n_seeds);
    for s = 1:n_seeds
        b_glob{s}  = Bandit_v17(simTime, ep_deep, base_seed + 100 + s, env, 'global');
        b_delay{s} = Bandit_v17(simTime, ep_deep, base_seed + 100 + s, env, 'delay');
    end
    out = struct('bandit_g', {b_glob}, 'bandit_d', {b_delay});
end

% =========================================================================
function out = unit_eval_cell_nr(cName, cCfg, envCal, calib_s, train_outs, bandit_out, o, n_eval, n_seeds, ctx)
    ctx.hbf(sprintf('eval_%s: evaluating 9 comparators on %d traces', cName, n_eval));
    T = o.simTime;
    b0 = min(envCal.burn_in, T - 1);
    
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        rng(cCfg.eval_trace_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, envCal);
        obsS = cqiFeedback_v17(Strue, envCal, meta.delays);
        meta.trace_id = j;
        rng(cCfg.eval_crn_base + j); U = rand(T, envCal.N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end
    
    cmpNames = {'Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', ...
                'Fixed', 'FixedPU (Oracle)', 'Context table', ...
                'Bandit (global)', 'Bandit (delay class)'};
    
    cmp_vals = cell(1, 9);
    
    % Deterministic comparators
    e = envCal;
    cmp_vals{1} = eval_det_traces(traces, e, 'baseline', b0);
    cmp_vals{2} = eval_det_traces(traces, e, 'olla', b0);
    e_o = e; e_o.olla_target = calib_s.olla_setting(1); e_o.olla_target_tuned = calib_s.olla_setting(1); e_o.olla_step_down = calib_s.olla_setting(2);
    cmp_vals{3} = eval_det_traces(traces, e_o, 'olla_tuned', b0);
    cmp_vals{4} = eval_det_traces(traces, e, 'multi_olla', b0);
    e_f = e; e_f.fixed_offset = calib_s.fixed_offset;
    cmp_vals{5} = eval_det_traces(traces, e_f, 'fixed', b0);
    e_pu = e; e_pu.fixed_class_tab = calib_s.fixedpu_tab; e_pu.class_tab = calib_s.fixedpu_tab;
    cmp_vals{6} = eval_det_traces(traces, e_pu, 'fixed_class', b0);
    e_ctx = e; e_ctx.ctx_tab = calib_s.ctx_tab;
    cmp_vals{7} = eval_det_traces(traces, e_ctx, 'ctxtab', b0);
    
    bg_vals = zeros(n_seeds, n_eval);
    bd_vals = zeros(n_seeds, n_eval);
    for s = 1:n_seeds
        bg_vals(s, :) = eval_bandit_traces(traces, e, bandit_out.bandit_g{s}, b0);
        bd_vals(s, :) = eval_bandit_traces(traces, e, bandit_out.bandit_d{s}, b0);
    end
    cmp_vals{8} = mean(bg_vals, 1);
    cmp_vals{9} = mean(bd_vals, 1);
    
    % RL primary scheme (mean over 5 seeds)
    rl_seeds = zeros(n_seeds, n_eval);
    pols = cell(1, n_seeds);
    for s = 1:n_seeds
        pol = train_outs{s}.a2c;
        pols{s} = pol;
        for j = 1:n_eval
            rng(77000 + 100*j + 10*8 + s);
            [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, traces(j).SINR, traces(j).obsS, e, traces(j).meta, traces(j).U);
            [~, ~, rl_seeds(s, j)] = userMetric_v17(e, tp, inf, b0);
        end
    end
    rl_prim = mean(rl_seeds, 1);
    
    % Ensemble
    rl_ens = zeros(1, n_eval);
    for j = 1:n_eval
        rng(77000 + 100*j + 10*10 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_ens', pols, traces(j).SINR, traces(j).obsS, e, traces(j).meta, traces(j).U);
        [~, ~, rl_ens(j)] = userMetric_v17(e, tp, inf, b0);
    end
    
    % Holm adjustment over 9 comparators
    stats = run_cmp_stats(rl_prim, cmp_vals, cmpNames);
    
    % Claims:
    claimA = stats.beats(2) && stats.beats(3) && stats.beats(4);
    claimB = stats.beats(5) && stats.beats(6) && stats.beats(7);
    win_all = all(stats.beats);
    
    % Find best comparator among the 9 (lowest margin)
    [min_mar, best_cmp_idx] = min(stats.pct);
    best_cmp_name = cmpNames{best_cmp_idx};
    
    % Rule R2: hierarchical seed x trace bootstrap 95% CI vs best comparator
    r2_ci = calc_hierarchical_ci(rl_seeds, cmp_vals{best_cmp_idx});
    
    ctx.hbf(sprintf('Cell %s NR eval: WIN=%d (Claim A=%d, B=%d), best cmp=%s (mar=+%.2f%%, R2=[+%.2f, +%.2f]%%)', ...
        cName, win_all, claimA, claimB, best_cmp_name, min_mar, r2_ci(1), r2_ci(2)));
    
    out = struct('cName', cName, 'stats', stats, 'cmpNames', {cmpNames}, ...
                 'cmp_vals', {cmp_vals}, 'rl_prim', rl_prim, 'rl_ens', rl_ens, ...
                 'rl_seeds', rl_seeds, 'claimA', claimA, 'claimB', claimB, ...
                 'win_all', win_all, 'best_cmp_name', best_cmp_name, ...
                 'best_cmp_idx', best_cmp_idx, 'r2_ci', r2_ci);
end

% =========================================================================
function vals = eval_det_traces(traces, e, ptype, b0)
    nT = numel(traces);
    vals = zeros(1, nT);
    for j = 1:nT
        rng(61500 + j);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6(ptype, [], traces(j).SINR, traces(j).obsS, e, traces(j).meta, traces(j).U);
        [~, ~, vals(j)] = userMetric_v17(e, tp, inf, b0);
    end
end

% =========================================================================
function vals = eval_bandit_traces(traces, e, pol, b0)
    nT = numel(traces);
    vals = zeros(1, nT);
    for j = 1:nT
        rng(61500 + j);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('bandit', pol, traces(j).SINR, traces(j).obsS, e, traces(j).meta, traces(j).U);
        [~, ~, vals(j)] = userMetric_v17(e, tp, inf, b0);
    end
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
        if all(d == 0), p(k) = 1.0; else, p(k) = signrank(a2c, b); end
    end
    [p_sorted, sort_idx] = sort(p);
    holm_p_sorted = zeros(1, K); cur_max = 0;
    for i = 1:K
        val = p_sorted(i) * (K - i + 1);
        val = min(1.0, max(val, cur_max));
        cur_max = val;
        holm_p_sorted(i) = val;
    end
    holm_p = zeros(1, K); holm_p(sort_idx) = holm_p_sorted;
    beats = (holm_p < 0.05) & (ci_lo > 0);
    st = struct('pct', pct, 'ci_lo', ci_lo, 'ci_hi', ci_hi, 'p', p, 'holm_p', holm_p, 'beats', beats);
end

% =========================================================================
function ci = calc_hierarchical_ci(rl_seeds, cmp_vals)
    [nS, nT] = size(rl_seeds);
    B = 2000;
    bm = mean(cmp_vals);
    boot_diffs = zeros(1, B);
    for b = 1:B
        s_idx = randi(nS, [1, nS]);
        t_idx = randi(nT, [1, nT]);
        sample = rl_seeds(s_idx, t_idx);
        cmp_sample = cmp_vals(t_idx);
        boot_diffs(b) = mean(sample(:)) - mean(cmp_sample);
    end
    boot_pct = 100 * boot_diffs / bm;
    ci = [prctile(boot_pct, 2.5), prctile(boot_pct, 97.5)];
end

% =========================================================================
function write_nr_g10_outputs(ctx, cells, cell_results)
    f_csv = fullfile(ctx.outdir, 'table_cells_nr.csv');
    f = fopen(f_csv, 'w');
    fprintf(f, 'cell,comparator,margin_pct,ci90_lo,ci90_hi,wilcoxon_p,holm_p,beats\n');
    for cIdx = 1:numel(cells)
        cName = cells{cIdx};
        if isfield(cell_results, cName)
            res = cell_results.(cName);
            for k = 1:numel(res.cmpNames)
                fprintf(f, '%s,%s,+%.2f,%.2f,%.2f,%.2e,%.2e,%d\n', ...
                    cName, res.cmpNames{k}, res.stats.pct(k), ...
                    res.stats.ci_lo(k), res.stats.ci_hi(k), ...
                    res.stats.p(k), res.stats.holm_p(k), res.stats.beats(k));
            end
        end
    end
    fclose(f);
    
    % Summary file
    f_sum = fullfile(ctx.outdir, 'fill_summary_v17nr_grid.txt');
    sF = fopen(f_sum, 'w');
    fprintf(sF, 'NR-G10 OPERATING GRID SUMMARY (%s)\n\n', datestr(now, 31));
    all_win = 1; win_count = 0;
    for cIdx = 1:numel(cells)
        cName = cells{cIdx};
        if isfield(cell_results, cName)
            res = cell_results.(cName);
            w = res.win_all;
            if w, win_count = win_count + 1; else, all_win = 0; end
            fprintf(sF, 'CELL|name=%s|win=%d|claimA=%d|claimB=%d|primary_ontime=%.4f|best_cmp=%s|r2_lo=%.2f|r2_hi=%.2f\n', ...
                cName, w, res.claimA, res.claimB, mean(res.rl_prim), ...
                res.best_cmp_name, res.r2_ci(1), res.r2_ci(2));
        end
    end
    
    if win_count == numel(cells)
        verdict = 'ALL';
    elseif win_count > 0
        verdict = 'MIXED';
    else
        verdict = 'NONE';
    end
    fprintf(sF, '\nVERDICT|%s\n', verdict);
    fclose(sF);
    
    stage_nr_g10_report(ctx);
    
    % Done marker
    f_done = fullfile(ctx.outdir, 'stage_nr_g10.done');
    dF = fopen(f_done, 'w'); fprintf(dF, 'DONE\n'); fclose(dF);
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
