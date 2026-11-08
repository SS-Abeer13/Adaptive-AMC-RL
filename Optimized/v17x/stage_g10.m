function stage_g10(ctx)
% stage_g10  Operating-point check at two neighbouring cells with per-cell recalibration (v17c-grid).
% Spec: paper/proposals/G10_operating_grid_prereg.md
% Cells: G2_hi_d10, G3_lo_d18
% Outputs:
%   Dataset/fill_summary_v17c.txt
%   Dataset/base_rule_by_cell.csv
%   Dataset/table_cells.csv
%   Dataset/REPORT_g10.txt
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
    n_calib = ternary(ctx.smoke, 2, 200);
    T = o.simTime;
    
    cell_results = struct();
    base_rule_log = cell(numel(cells), 5);
    
    for cIdx = 1:numel(cells)
        cName = cells{cIdx};
        ctx.hbf(sprintf('=== Running G10 cell %s (%d/%d) ===', cName, cIdx, numel(cells)));
        
        cCfg = get_cell_cfg(cName, env_base);
        
        % Assert seed disjointness (common_rules.md R4, G10 §2)
        assert(cCfg.calib_trace_base >= 900000, 'G10 calib trace range assertion');
        assert(cCfg.eval_trace_base >= 700000 && cCfg.eval_trace_base < 800000, 'G10 eval trace range assertion');
        
        % 1. Unit: feas_<cell>
        feas_res = ctx.unit(['feas_' cName], @() unit_feas(cCfg, o, ctx));
        cCfg.env = feas_res.env;
        
        if ~feas_res.is_feasible
            ctx.hbf(sprintf('Cell %s is infeasible! Skipping cell.', cName));
            continue;
        end
        
        % Pre-generate calibration traces (200 traces)
        C_traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
        for j = 1:n_calib
            rng(cCfg.calib_trace_base + j);
            [Strue, ~, meta] = generateChannel_v17(T, cCfg.env);
            obsS = cqiFeedback_v17(Strue, cCfg.env, meta.delays);
            meta.trace_id = 10000 + j;
            rng(cCfg.calib_crn_base + j); Uc = rand(T, cCfg.env.N);
            C_traces(j).SINR = Strue; C_traces(j).obsS = obsS; C_traces(j).meta = meta; C_traces(j).U = Uc;
        end
        
        % 2. Unit: calib_single_<cell>
        calib_s = ctx.unit(['calib_single_' cName], @() unit_calib_single(cName, C_traces, cCfg, o, ctx));
        comp_tab = calib_s.comp_tab;
        envCal = calib_s.env;
        base_rule_log(cIdx, :) = {cName, envCal.base_rule_kind, envCal.base_rule_name, envCal.fixed_offset, calib_s.base_rule_is_oracle};
        
        % 3. Counting pass & combined search: calib_comb_<cell>_start_k_sweep_s
        ctxj_tab = run_cell_combined_search(cName, C_traces, comp_tab, calib_s, envCal, ctx);
        
        % 4. Units: train_seed_<cell>_K
        train_outs = cell(1, n_seeds);
        for s = 1:n_seeds
            u_name = sprintf('train_seed_%s_%d', cName, s);
            train_outs{s} = ctx.unit(u_name, @() unit_train_cell(envCal, T, ep_deep, cCfg.base_seed, s, cName, ctx));
        end
        
        % 5. Unit: bandit_<cell>
        bandit_out = ctx.unit(['bandit_' cName], @() unit_bandit_cell(envCal, T, ep_deep, cCfg.base_seed, n_seeds, cName, ctx));
        
        % 6. Unit: eval_<cell>
        eval_out = ctx.unit(['eval_' cName], @() unit_eval_cell(cName, cCfg, envCal, calib_s, ctxj_tab, train_outs, bandit_out, o, n_eval, n_seeds, ctx));
        cell_results.(cName) = eval_out;
    end
    
    % ---- 7. Aggregate results, write tables and summary ----
    write_g10_outputs(ctx, cells, cell_results, base_rule_log);
    ctx.hbf('g10 done successfully');
end

% =========================================================================
function cfg = get_cell_cfg(cName, env_base)
    cfg = struct();
    cfg.name = cName;
    cfg.env = env_base;
    switch cName
        case 'G2_hi_d10'
            cfg.env.pkt_bits = 16000; cfg.env.pkt_deadline = 10;
            cfg.base_seed = 31042;
            cfg.eval_trace_base  = 720000; cfg.eval_crn_base  = 730000;
            cfg.calib_trace_base = 901000; cfg.calib_crn_base = 911000;
        case 'G3_lo_d18'
            cfg.env.pkt_bits = 8000; cfg.env.pkt_deadline = 18;
            cfg.base_seed = 32042;
            cfg.eval_trace_base  = 740000; cfg.eval_crn_base  = 750000;
            cfg.calib_trace_base = 902000; cfg.calib_crn_base = 912000;
        otherwise
            error('v17x:g10:unknownCell', 'unknown cell %s', cName);
    end
end

% =========================================================================
function out = unit_feas(cCfg, o, ctx)
    ctx.hbf(sprintf('feas: checking feasibility for cell %s (target on-time in [0.50, 0.97])', cCfg.name));
    env = cCfg.env;
    nCal = ternary(ctx.smoke, 2, 20);
    T = o.simTime;
    
    % Test initial feasibility
    [ok, sc] = test_feasibility(env, nCal, cCfg.calib_trace_base, cCfg.calib_crn_base, T);
    ctx.hbf(sprintf('Cell %s initial on-time = %.4f (feasible: %d)', cCfg.name, sc, ok));
    
    if ~ok && ~ctx.smoke
        % Step packet size towards 12,000
        if env.pkt_bits == 16000
            env.pkt_bits = 14000;
        elseif env.pkt_bits == 8000
            env.pkt_bits = 10000;
        end
        [ok, sc] = test_feasibility(env, nCal, cCfg.calib_trace_base, cCfg.calib_crn_base, T);
        ctx.hbf(sprintf('Cell %s after step: pkt_bits=%d, on-time=%.4f (feasible: %d)', ...
            cCfg.name, env.pkt_bits, sc, ok));
    end
    out = struct('is_feasible', ok, 'env', env, 'feas_score', sc);
end

% =========================================================================
function [ok, sc] = test_feasibility(env, nCal, seed_base, crn_base, T)
    envE = env; envE.fixed_offset = 0;
    b0 = min(envE.burn_in, T - 1);
    totN = 0; totD = 0;
    for j = 1:nCal
        rng(seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, envE);
        obsS = cqiFeedback_v17(Strue, envE, meta.delays);
        meta.trace_id = 10000 + j;
        rng(crn_base + j); Uc = rand(T, envE.N);
        rng(61000 + j);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed', [], Strue, obsS, envE, meta, Uc);
        [nu, de] = userMetric_v17(envE, tp, inf, b0);
        totN = totN + sum(nu); totD = totD + sum(de);
    end
    sc = totN / max(totD, 1);
    ok = (sc >= 0.50 && sc <= 0.97);
end

% =========================================================================
function out = unit_calib_single(cName, traces, cCfg, o, ctx)
    ctx.hbf(sprintf('calib_single_%s: re-calibrating all comparators on 200 calibration traces', cName));
    env = cCfg.env;
    nT = numel(traces);
    b0 = min(env.burn_in, o.simTime - 1);
    
    % 1. Fixed & FixedPU separable
    cands = -5:3;
    nC = numel(cands);
    totN = zeros(1, nC); totD = zeros(1, nC);
    acc = zeros(2, 3, nC); cnt = zeros(2, 3, nC);
    
    for j = 1:nT
        if mod(j, 50) == 0 || j == nT
            ctx.hb(sprintf('calib_single_%s: Fixed/PU trace %d/%d', cName, j, nT));
        end
        for c = 1:nC
            e = env; e.fixed_offset = cands(c);
            rng(61000 + 100*traces(j).meta.trace_id + c);
            [tpc, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed', [], traces(j).SINR, traces(j).obsS, e, traces(j).meta, traces(j).U);
            [num, den] = userMetric_v17(e, tpc, inf, b0);
            totN(c) = totN(c) + sum(num); totD(c) = totD(c) + sum(den);
            for i = 1:env.N
                [dc, vc] = userClass_v17(traces(j).meta.delays(i), mean(traces(j).meta.speeds(:, i)));
                acc(dc, vc, c) = acc(dc, vc, c) + num(i);
                cnt(dc, vc, c) = cnt(dc, vc, c) + den(i);
            end
        end
    end
    sc = totN ./ max(totD, 1);
    [f_score, bi] = max(sc);
    fixed_offset = cands(bi);
    env.fixed_offset = fixed_offset;
    
    fixedpu_sep_tab = zeros(2, 3);
    for d = 1:2
        for v = 1:3
            csc = squeeze(acc(d, v, :)) ./ max(squeeze(cnt(d, v, :)), 1);
            [~, cbi] = max(csc);
            fixedpu_sep_tab(d, v) = cands(cbi);
        end
    end
    
    % Joint refinement of FixedPU
    cur_pu = fixedpu_sep_tab;
    e = env; e.fixed_class_tab = cur_pu; e.class_tab = cur_pu;
    cur_pu_score = score_tab(traces, e, 'fixed_class');
    for s = 1:ternary(ctx.smoke, 1, 3)
        improved = false;
        for d = 1:2
            for v = 1:3
                for c = 1:nC
                    if cands(c) == cur_pu(d, v), continue; end
                    t2 = cur_pu; t2(d, v) = cands(c);
                    e = env; e.fixed_class_tab = t2; e.class_tab = t2;
                    sc_cand = score_tab(traces, e, 'fixed_class');
                    if sc_cand > cur_pu_score + 1e-6
                        cur_pu_score = sc_cand;
                        cur_pu = t2;
                        improved = true;
                    end
                end
            end
        end
        if ~improved, break; end
    end
    fixedpu_tab = cur_pu;
    fixedpu_score = cur_pu_score;
    env.fixed_class_tab = fixedpu_tab;
    env.class_tab = fixedpu_tab;
    
    % Base rule selection (auto-selected between Fixed and FixedPU)
    if fixedpu_score > f_score + 1e-12
        env.base_rule_kind = 'fixed_class';
        env.base_rule_name = 'FixedPU (Oracle)';
        is_oracle = 1;
    else
        env.base_rule_kind = 'fixed';
        env.base_rule_name = 'Fixed';
        is_oracle = 0;
    end
    ctx.hbf(sprintf('Cell %s base rule: %s (kind=%s, is_oracle=%d)', ...
        cName, env.base_rule_name, env.base_rule_kind, is_oracle));
    
    % Context table (exhaustive 343)
    [all_ctx, n_ctx] = ndgrid(-4:2, -4:2, -4:2);
    ctx_tabs = [all_ctx(:), n_ctx(:), all_ctx(:)]; % shorthand
    [G1, G2, G3] = ndgrid(-4:2, -4:2, -4:2);
    ctx_tabs = [G1(:), G2(:), G3(:)];
    if ctx.smoke, ctx_tabs = ctx_tabs(1:2, :); end
    
    best_ctx_sc = -Inf; best_ctx_tab = [];
    for k = 1:size(ctx_tabs, 1)
        e = env; e.ctx_tab = ctx_tabs(k, :);
        csc = score_tab(traces, e, 'ctxtab');
        if csc > best_ctx_sc + 1e-12
            best_ctx_sc = csc;
            best_ctx_tab = ctx_tabs(k, :);
        end
        if mod(k, 10) == 0 || k == size(ctx_tabs, 1)
            ctx.hb(sprintf('calib_single_%s: Context tab %d/%d (best=%.4f)', ...
                cName, k, size(ctx_tabs, 1), best_ctx_sc));
        end
    end
    env.ctx_tab = best_ctx_tab;
    
    % OLLA tuned (30 settings)
    olla_targets = [0.01, 0.02, 0.03, 0.05, 0.07, 0.10, 0.15, 0.20, 0.30, 0.50];
    olla_steps = [0.25, 0.5, 1.0];
    [OT, OS] = ndgrid(olla_targets, olla_steps);
    olla_settings = [OT(:), OS(:)];
    if ctx.smoke, olla_settings = olla_settings(1:2, :); end
    best_olla_sc = -Inf; best_olla_set = [];
    for k = 1:size(olla_settings, 1)
        e = env; e.olla_target = olla_settings(k, 1); e.olla_target_tuned = olla_settings(k, 1); e.olla_step_down = olla_settings(k, 2);
        osc = score_tab(traces, e, 'olla_tuned');
        if osc > best_olla_sc + 1e-12
            best_olla_sc = osc;
            best_olla_set = olla_settings(k, :);
        end
        if mod(k, 5) == 0 || k == size(olla_settings, 1)
            ctx.hb(sprintf('calib_single_%s: OLLA setting %d/%d (best=%.4f)', ...
                cName, k, size(olla_settings, 1), best_olla_sc));
        end
    end
    env.olla_target_tuned = best_olla_set(1);
    
    % Composite table: min(2, max(-4, P(d,v) + X(b) - F))
    comp_tab = zeros(3, 2, 3, 2);
    for b = 1:3
        for d = 1:2
            for v = 1:3
                for u = 1:2
                    comp_tab(b, d, v, u) = min(2, max(-4, fixedpu_tab(d, v) + best_ctx_tab(b) - fixed_offset));
                end
            end
        end
    end
    e = env; e.ctxj_tab = comp_tab;
    comp_score = score_tab(traces, e, 'ctxj');
    
    % Write composite_table_<cell>.csv
    csvComp = fullfile(ctx.outdir, sprintf('composite_table_%s.csv', cName));
    f = fopen(csvComp, 'w');
    fprintf(f, 'slack_bin,delay_class,speed_class,busy_bin,offset\n');
    for b = 1:3, for d = 1:2, for v = 1:3, for u = 1:2
        fprintf(f, '%d,%d,%d,%d,%d\n', b, d, v, u - 1, comp_tab(b, d, v, u));
    end, end, end, end
    fclose(f);
    
    out = struct('env', env, 'comp_tab', comp_tab, 'comp_score', comp_score, ...
                 'fixed_offset', fixed_offset, 'fixed_score', f_score, ...
                 'fixedpu_tab', fixedpu_tab, 'fixedpu_score', fixedpu_score, ...
                 'ctx_tab', best_ctx_tab, 'ctx_score', best_ctx_sc, ...
                 'olla_setting', best_olla_set, 'olla_score', best_olla_sc, ...
                 'base_rule_is_oracle', is_oracle);
end

% =========================================================================
function ctxj_tab = run_cell_combined_search(cName, traces, comp_tab, calib_s, envCal, ctx)
    ctx.hbf(sprintf('Running combined search for cell %s (threshold N=80)', cName));
    nT = numel(traces);
    
    % Counting pass
    cell_counts = zeros(3, 2, 3, 2);
    for j = 1:nT
        e = envCal; e.ctxj_tab = comp_tab;
        rng(61500 + j);
        [~, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxj', [], traces(j).SINR, traces(j).obsS, e, traces(j).meta, traces(j).U);
        log = inf.sch_log; meta = traces(j).meta;
        for row = 1:size(log, 1)
            if log(row, 4) == 1, continue; end
            u = log(row, 1); sl = log(row, 3);
            if sl <= 2, b = 1; elseif sl <= 5, b = 2; else, b = 3; end
            if meta.delays(u) <= 4, d = 1; else, d = 2; end
            sp = mean(meta.speeds(:, u));
            if sp < 10, v = 1; elseif sp <= 20, v = 2; else, v = 3; end
            busy = log(row, 5);
            if busy == 0, u_bin = 1; else, u_bin = 2; end
            cell_counts(b, d, v, u_bin) = cell_counts(b, d, v, u_bin) + 1;
        end
    end
    
    thresh = ternary(ctx.smoke, 0, 80);
    is_sparse = (cell_counts < thresh);
    
    % Write ctxj_cells_<cell>.csv
    csvCells = fullfile(ctx.outdir, sprintf('ctxj_cells_%s.csv', cName));
    f = fopen(csvCells, 'w');
    fprintf(f, 'slack_bin,delay_class,speed_class,busy_bin,decision_count,is_sparse,composite_offset\n');
    for b = 1:3, for d = 1:2, for v = 1:3, for u = 1:2
        fprintf(f, '%d,%d,%d,%d,%d,%d,%d\n', b, d, v, u - 1, cell_counts(b, d, v, u), is_sparse(b, d, v, u), comp_tab(b, d, v, u));
    end, end, end, end
    fclose(f);
    
    % Coordinate ascent: 4 starts, cap 6 sweeps
    n_starts = ternary(ctx.smoke, 2, 4);
    max_sweeps = ternary(ctx.smoke, 1, 6);
    cands = -4:2;
    best_sc = -Inf; best_tab = [];
    
    for k = 0:(n_starts - 1)
        if k == 0
            init_tab = comp_tab;
        else
            rng(90017 + k, 'twister');
            init_tab = comp_tab;
            rand_offsets = cands(randi(numel(cands), 3, 2, 3, 2));
            init_tab(~is_sparse) = rand_offsets(~is_sparse);
        end
        cur_tab = init_tab;
        e = envCal; e.ctxj_tab = cur_tab;
        cur_sc = score_tab(traces, e, 'ctxj');
        
        for s = 1:max_sweeps
            u_name = sprintf('calib_comb_%s_start_%d_sweep_%d', cName, k, s);
            sweep_res = ctx.unit(u_name, @() run_one_sweep_g10(traces, cur_tab, cur_sc, is_sparse, cands, envCal, ctx));
            cur_tab = sweep_res.tab;
            cur_sc  = sweep_res.score;
            if ~sweep_res.improved, break; end
        end
        if cur_sc > best_sc + 1e-12 || k == 0
            best_sc = cur_sc;
            best_tab = cur_tab;
        end
    end
    ctxj_tab = best_tab;
    ctx.hbf(sprintf('Cell %s combined search completed: score=%.5f', cName, best_sc));
end

% =========================================================================
function out = run_one_sweep_g10(traces, cur_tab, cur_score, is_sparse, cands, envE, ctx)
    tab = cur_tab; score = cur_score; improved = false;
    for b = 1:3, for d = 1:2, for v = 1:3, for u = 1:2
        if is_sparse(b, d, v, u), continue; end
        cur_off = tab(b, d, v, u);
        best_cand_off = cur_off; best_cand_score = score;
        for c = 1:numel(cands)
            cand_off = cands(c);
            if cand_off == cur_off, continue; end
            t2 = tab; t2(b, d, v, u) = cand_off;
            e = envE; e.ctxj_tab = t2;
            sc = score_tab(traces, e, 'ctxj');
            if sc > best_cand_score + 1e-6
                best_cand_score = sc; best_cand_off = cand_off;
            end
        end
        if best_cand_score > score + 1e-6
            improved = true; score = best_cand_score; tab(b, d, v, u) = best_cand_off;
        end
        ctx.hb(sprintf('calib_comb: cell (%d,%d,%d,%d) score=%.4f', b, d, v, u, score));
    end, end, end, end
    out = struct('tab', tab, 'score', score, 'improved', improved);
end

% =========================================================================
function out = unit_train_cell(env, simTime, ep_deep, base_seed, s, cName, ctx)
    ctx.hbf(sprintf('train_seed_%s_%d: training A2C (%d episodes)', cName, s, ep_deep));
    envPrim = env;
    envPrim.scheme_name = 'Deep A2C v17 (cell)';
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
function out = unit_eval_cell(cName, cCfg, envCal, calib_s, ctxj_tab, train_outs, bandit_out, o, n_eval, n_seeds, ctx)
    ctx.hbf(sprintf('eval_%s: evaluating 10 comparators on %d traces', cName, n_eval));
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
                'Bandit (global)', 'Bandit (delay class)', 'Context-joint'};
    
    cmp_vals = cell(1, 10);
    
    % Deterministic comparators
    e = envCal;
    % 1: Baseline
    cmp_vals{1} = eval_det_traces(traces, e, 'baseline', b0);
    % 2: OLLA
    cmp_vals{2} = eval_det_traces(traces, e, 'olla', b0);
    % 3: OLLA tuned
    e_o = e; e_o.olla_target = calib_s.olla_setting(1); e_o.olla_target_tuned = calib_s.olla_setting(1); e_o.olla_step_down = calib_s.olla_setting(2);
    cmp_vals{3} = eval_det_traces(traces, e_o, 'olla_tuned', b0);
    % 4: Multi-OLLA
    cmp_vals{4} = eval_det_traces(traces, e, 'multi_olla', b0);
    % 5: Fixed
    e_f = e; e_f.fixed_offset = calib_s.fixed_offset;
    cmp_vals{5} = eval_det_traces(traces, e_f, 'fixed', b0);
    % 6: FixedPU
    e_pu = e; e_pu.fixed_class_tab = calib_s.fixedpu_tab; e_pu.class_tab = calib_s.fixedpu_tab;
    cmp_vals{6} = eval_det_traces(traces, e_pu, 'fixed_class', b0);
    % 7: Context table
    e_ctx = e; e_ctx.ctx_tab = calib_s.ctx_tab;
    cmp_vals{7} = eval_det_traces(traces, e_ctx, 'ctxtab', b0);
    % 8: Bandit global
    bg_vals = zeros(n_seeds, n_eval);
    bd_vals = zeros(n_seeds, n_eval);
    for s = 1:n_seeds
        bg_vals(s, :) = eval_bandit_traces(traces, e, bandit_out.bandit_g{s}, b0);
        bd_vals(s, :) = eval_bandit_traces(traces, e, bandit_out.bandit_d{s}, b0);
    end
    cmp_vals{8} = mean(bg_vals, 1);
    cmp_vals{9} = mean(bd_vals, 1);
    % 10: Context-joint
    e_cj = e; e_cj.ctxj_tab = ctxj_tab;
    cmp_vals{10} = eval_det_traces(traces, e_cj, 'ctxj', b0);
    
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
    
    % Holm adjustment over 10 comparators
    stats = run_cmp_stats(rl_prim, cmp_vals, cmpNames);
    
    % Claims:
    claimA = stats.beats(2) && stats.beats(3) && stats.beats(4);
    claimB = stats.beats(5) && stats.beats(6) && stats.beats(7);
    claimJP = stats.beats(10);
    win_all = all(stats.beats);
    
    ctx.hbf(sprintf('Cell %s eval results: WIN=%d (Claim A=%d, B=%d, JP=%d)', ...
        cName, win_all, claimA, claimB, claimJP));
    
    out = struct('cName', cName, 'stats', stats, 'cmpNames', {cmpNames}, ...
                 'cmp_vals', {cmp_vals}, 'rl_prim', rl_prim, 'rl_ens', rl_ens, ...
                 'claimA', claimA, 'claimB', claimB, 'claimJP', claimJP, 'win_all', win_all);
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
function v = score_tab(traces, e, ptype)
    n = 0; d = 0;
    b0 = min(e.burn_in, size(traces(1).SINR, 1) - 1);
    for jj = 1:numel(traces)
        rng(61500 + jj);
        [tpc, ~, ~, ~, inf] = evalPolicy_v17_g6(ptype, [], traces(jj).SINR, traces(jj).obsS, e, traces(jj).meta, traces(jj).U);
        [nu, de] = userMetric_v17(e, tpc, inf, b0);
        n = n + sum(nu); d = d + sum(de);
    end
    v = n / max(d, 1);
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
function write_g10_outputs(ctx, cells, cell_results, base_rule_log)
    % 1. Write base_rule_by_cell.csv
    f_base = fullfile(ctx.outdir, 'base_rule_by_cell.csv');
    f = fopen(f_base, 'w');
    fprintf(f, 'cell,base_rule_kind,base_rule_name,fixed_offset,is_class_oracle\n');
    for i = 1:size(base_rule_log, 1)
        if ~isempty(base_rule_log{i, 1})
            fprintf(f, '%s,%s,%s,%d,%d\n', ...
                base_rule_log{i, 1}, base_rule_log{i, 2}, base_rule_log{i, 3}, ...
                base_rule_log{i, 4}, base_rule_log{i, 5});
        end
    end
    fclose(f);
    
    % 2. Write table_cells.csv
    f_cells = fullfile(ctx.outdir, 'table_cells.csv');
    f = fopen(f_cells, 'w');
    fprintf(f, 'cell,comparator,margin_pct,ci90_lo,ci90_hi,wilcoxon_p,holm_p,beats\n');
    for cIdx = 1:numel(cells)
        cName = cells{cIdx};
        if isfield(cell_results, cName)
            res = cell_results.(cName);
            for k = 1:10
                fprintf(f, '%s,%s,%+.2f,%.2f,%.2f,%.2e,%.2e,%d\n', ...
                    cName, res.cmpNames{k}, res.stats.pct(k), res.stats.ci_lo(k), ...
                    res.stats.ci_hi(k), res.stats.p(k), res.stats.holm_p(k), res.stats.beats(k));
            end
        end
    end
    fclose(f);
    
    % 3. Write fill_summary_v17c.txt
    f_sum = fullfile(ctx.outdir, 'fill_summary_v17c.txt');
    f = fopen(f_sum, 'w');
    fprintf(f, 'G10 OPERATING GRID SUMMARY (%s, MATLAB %s)\n\n', datestr(now, 31), version);
    
    n_wins = 0; n_tested = 0;
    for cIdx = 1:numel(cells)
        cName = cells{cIdx};
        if isfield(cell_results, cName)
            res = cell_results.(cName);
            n_tested = n_tested + 1;
            if res.win_all, n_wins = n_wins + 1; end
            fprintf(f, 'CELL|name=%s|win=%d|claimA=%d|claimB=%d|claimJP=%d|primary_ontime=%.4f\n', ...
                cName, res.win_all, res.claimA, res.claimB, res.claimJP, mean(res.rl_prim));
        end
    end
    
    % Pre-registered wording per G10 §4
    if n_wins == 2 && n_tested == 2
        verdict = 'Both cells WIN (2 of 2)';
        wording = 'The gain held at both tested neighbouring operating points: residual A2C beat every comparator, including rules re-calibrated for that cell. Two further grid corners were not tested.';
    elseif n_wins == 1
        verdict = 'One cell WINs (1 of 2)';
        wording = 'The gain is operating-point dependent: residual A2C beat every comparator at one cell but not at the other. Two further grid corners were not tested.';
    else
        verdict = 'No tested cell WINs';
        wording = 'The result was observed at the M1 operating point only; at the two tested neighbouring points it was not reproduced. Two further grid corners were not tested.';
    end
    
    fprintf(f, '\nVERDICT|%s\n', verdict);
    fprintf(f, 'WORDING|%s\n', wording);
    fclose(f);
    
    % Copy tables to paper/
    try
        copyfile(f_base, fullfile(fileparts(ctx.root), 'paper', 'base_rule_by_cell.csv'));
        copyfile(f_cells, fullfile(fileparts(ctx.root), 'paper', 'table_cells.csv'));
    catch
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
