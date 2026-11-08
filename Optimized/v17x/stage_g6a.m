function stage_g6a(ctx)
% stage_g6a  G6 Step 1: Single-cue re-calibration on 500 calibration traces.
% Units:
%   sep_grid_chunkK
%   fixedpu_joint_sweepS
%   ctx_exh_chunkK
%   olla_set_K
%   composite_table
% Outputs:
%   Dataset/cal500_single.txt
%   Dataset/composite_table.csv
%   Dataset/REPORT_g6a.txt (via stage_g6a_report)
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    
    nCalib = ternary(ctx.smoke, 2, 500);
    T = o.simTime;
    
    % Assert seed disjointness (common_rules.md R4, G6 §2.1)
    calib_seed_base = 600000;
    calib_crn_base  = 610000;
    assert(calib_seed_base >= 600000 && calib_seed_base + nCalib <= 600500, 'G6 calib trace seed range assertion');
    assert(calib_crn_base >= 610000, 'G6 calib CRN range assertion');
    
    ctx.hbf(sprintf('g6a start: %d calibration traces', nCalib));
    
    % Pre-generate calibration traces
    C_traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:nCalib
        rng(calib_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, envE);
        obsS = cqiFeedback_v17(Strue, envE, meta.delays);
        meta.trace_id = 10000 + j;
        rng(calib_crn_base + j); Uc = rand(T, envE.N);
        C_traces(j).SINR = Strue; C_traces(j).obsS = obsS; C_traces(j).meta = meta; C_traces(j).U = Uc;
    end
    
    % ---- 1. Fixed & FixedPU Separable Grid (9 offsets: -5..+3) ----
    cands = -5:3;
    chunk_size = ternary(ctx.smoke, 2, 25);
    n_chunks = ceil(nCalib / chunk_size);
    sep_chunks = cell(1, n_chunks);
    for c = 1:n_chunks
        u_name = sprintf('sep_grid_chunk%d', c);
        t_start = (c - 1) * chunk_size + 1;
        t_end   = min(c * chunk_size, nCalib);
        sep_chunks{c} = ctx.unit(u_name, @() eval_sep_chunk(C_traces(t_start:t_end), cands, envE, ctx));
    end
    
    % Merge separable grid
    [fixed_500_offset, fixed_500_score, fixedpu_sep_tab, fixedpu_sep_score] = ...
        merge_sep_grid(sep_chunks, cands, envE, C_traces, ctx);
    
    % ---- 2. FixedPU Joint Refinement (coordinate ascent <= 3 sweeps) ----
    cur_fixedpu = fixedpu_sep_tab;
    cur_fixedpu_score = fixedpu_sep_score;
    for s = 1:3
        u_name = sprintf('fixedpu_joint_sweep%d', s);
        sweep_out = ctx.unit(u_name, @() eval_fixedpu_joint_sweep(C_traces, cur_fixedpu, cur_fixedpu_score, cands, envE, s, ctx));
        if sweep_out.improved
            cur_fixedpu = sweep_out.best_tab;
            cur_fixedpu_score = sweep_out.best_score;
        else
            break;
        end
        if ctx.smoke, break; end
    end
    fixedpu_500_tab = cur_fixedpu;
    fixedpu_500_score = cur_fixedpu_score;
    ctx.hbf(sprintf('FixedPU-500: sep_score=%.4f, final_score=%.4f', fixedpu_sep_score, fixedpu_500_score));
    
    % ---- 3. Context-500 Exhaustive (7^3 = 343 tables, offsets -4..+2) ----
    ctx_cands = -4:2;
    [all_ctx_tabs, n_ctx] = generate_ctx_tables(ctx_cands);
    if ctx.smoke, n_ctx = 2; all_ctx_tabs = all_ctx_tabs(1:2, :); end
    
    ctx_chunk_size = ternary(ctx.smoke, 2, 49);
    n_ctx_chunks = ceil(n_ctx / ctx_chunk_size);
    ctx_chunk_outs = cell(1, n_ctx_chunks);
    for c = 1:n_ctx_chunks
        u_name = sprintf('ctx_exh_chunk%d', c);
        idx_start = (c - 1) * ctx_chunk_size + 1;
        idx_end   = min(c * ctx_chunk_size, n_ctx);
        ctx_chunk_outs{c} = ctx.unit(u_name, @() eval_ctx_chunk(C_traces, all_ctx_tabs(idx_start:idx_end, :), envE, ctx));
    end
    
    % Merge context chunks
    [ctx_500_tab, ctx_500_score] = merge_ctx_chunks(ctx_chunk_outs, ctx);
    ctx.hbf(sprintf('Context-500: best tab=[%s], score=%.4f', num2str(ctx_500_tab), ctx_500_score));
    
    % ---- 4. OLLA-tuned-500 (30 settings: 10 targets x 3 down-steps) ----
    olla_targets = [0.01, 0.02, 0.03, 0.05, 0.07, 0.10, 0.15, 0.20, 0.30, 0.50];
    olla_steps   = [0.25, 0.5, 1.0];
    [all_olla_settings, n_olla] = generate_olla_settings(olla_targets, olla_steps);
    if ctx.smoke, n_olla = 2; all_olla_settings = all_olla_settings(1:2, :); end
    
    olla_outs = cell(1, n_olla);
    for k = 1:n_olla
        u_name = sprintf('olla_set_%d', k);
        olla_outs{k} = ctx.unit(u_name, @() eval_olla_setting(C_traces, all_olla_settings(k, :), envE, ctx));
    end
    [olla_500_setting, olla_500_score] = merge_olla_settings(olla_outs, all_olla_settings, ctx);
    ctx.hbf(sprintf('OLLA-tuned-500: target=%.2f, step=%.2f, score=%.4f', ...
        olla_500_setting(1), olla_500_setting(2), olla_500_score));
    
    % ---- 5. Unit: composite_table ----
    ctx.unit('composite_table', @() build_composite(C_traces, fixed_500_offset, fixed_500_score, ...
        fixedpu_500_tab, fixedpu_500_score, fixedpu_sep_tab, fixedpu_sep_score, ...
        ctx_500_tab, ctx_500_score, olla_500_setting, olla_500_score, envE, ctx));
    
    ctx.hbf('g6a finished successfully');
end

% =========================================================================
function out = eval_sep_chunk(traces, cands, envE, ctx)
    nT = numel(traces);
    nC = numel(cands);
    b0 = min(envE.burn_in, size(traces(1).SINR, 1) - 1);
    
    totN = zeros(1, nC);
    totD = zeros(1, nC);
    acc = zeros(2, 3, nC);
    cnt = zeros(2, 3, nC);
    
    for j = 1:nT
        Strue = traces(j).SINR; obsS = traces(j).obsS; meta = traces(j).meta; Uc = traces(j).U;
        for c = 1:nC
            e = envE; e.fixed_offset = cands(c);
            rng(61000 + 100*meta.trace_id + c);
            [tpc, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed', [], Strue, obsS, e, meta, Uc);
            [num, den] = userMetric_v17(e, tpc, inf, b0);
            totN(c) = totN(c) + sum(num);
            totD(c) = totD(c) + sum(den);
            for i = 1:envE.N
                [dc, vc] = userClass_v17(meta.delays(i), mean(meta.speeds(:, i)));
                acc(dc, vc, c) = acc(dc, vc, c) + num(i);
                cnt(dc, vc, c) = cnt(dc, vc, c) + den(i);
            end
        end
    end
    out = struct('totN', totN, 'totD', totD, 'acc', acc, 'cnt', cnt);
end

% =========================================================================
function [f_off, f_score, pu_tab, pu_score] = merge_sep_grid(chunks, cands, envE, traces, ctx)
    nC = numel(cands);
    totN = zeros(1, nC); totD = zeros(1, nC);
    acc = zeros(2, 3, nC); cnt = zeros(2, 3, nC);
    for k = 1:numel(chunks)
        totN = totN + chunks{k}.totN;
        totD = totD + chunks{k}.totD;
        acc  = acc  + chunks{k}.acc;
        cnt  = cnt  + chunks{k}.cnt;
    end
    sc = totN ./ max(totD, 1);
    [f_score, bestIdx] = max(sc);
    f_off = cands(bestIdx);
    
    % FixedPU separable: per-class argmax
    pu_tab = zeros(2, 3);
    for d = 1:2
        for v = 1:3
            class_sc = squeeze(acc(d, v, :)) ./ max(squeeze(cnt(d, v, :)), 1);
            [~, bi] = max(class_sc);
            pu_tab(d, v) = cands(bi);
        end
    end
    
    % Evaluate separable table jointly to get joint score
    e = envE; e.fixed_class_tab = pu_tab; e.class_tab = pu_tab;
    pu_score = score_table(traces, e, 'fixed_class');
end

% =========================================================================
function out = eval_fixedpu_joint_sweep(traces, cur_tab, cur_score, cands, envE, sweep_num, ctx)
    ctx.hbf(sprintf('FixedPU joint refinement sweep %d (current score %.4f)', sweep_num, cur_score));
    best_tab = cur_tab;
    best_score = cur_score;
    improved = false;
    
    % Lexicographic order: (1,1), (1,2), (1,3), (2,1), (2,2), (2,3)
    for d = 1:2
        for v = 1:3
            cur_off = best_tab(d, v);
            for c = 1:numel(cands)
                cand_off = cands(c);
                if cand_off == cur_off, continue; end
                t2 = best_tab; t2(d, v) = cand_off;
                e = envE; e.fixed_class_tab = t2; e.class_tab = t2;
                sc = score_table(traces, e, 'fixed_class');
                if sc > best_score + 1e-6
                    best_score = sc;
                    best_tab = t2;
                    improved = true;
                    ctx.hb(sprintf('FixedPU sweep %d: class (%d,%d) moved %d -> %d (score %.4f)', ...
                        sweep_num, d, v, cur_off, cand_off, sc));
                end
            end
        end
    end
    out = struct('improved', improved, 'best_tab', best_tab, 'best_score', best_score);
end

% =========================================================================
function [tabs, n] = generate_ctx_tables(cands)
    [G1, G2, G3] = ndgrid(cands, cands, cands);
    tabs = [G1(:), G2(:), G3(:)];
    n = size(tabs, 1);
end

% =========================================================================
function out = eval_ctx_chunk(traces, tab_chunk, envE, ctx)
    nTabs = size(tab_chunk, 1);
    scores = zeros(1, nTabs);
    for k = 1:nTabs
        e = envE; e.ctx_tab = tab_chunk(k, :);
        scores(k) = score_table(traces, e, 'ctxtab');
    end
    [best_score, bi] = max(scores);
    out = struct('best_tab', tab_chunk(bi, :), 'best_score', best_score, 'all_scores', scores, 'all_tabs', tab_chunk);
end

% =========================================================================
function [best_tab, best_score] = merge_ctx_chunks(chunk_outs, ctx)
    best_score = -Inf;
    best_tab = [];
    for k = 1:numel(chunk_outs)
        if chunk_outs{k}.best_score > best_score + 1e-12
            best_score = chunk_outs{k}.best_score;
            best_tab   = chunk_outs{k}.best_tab;
        end
    end
end

% =========================================================================
function [sets, n] = generate_olla_settings(targets, steps)
    [T, S] = ndgrid(targets, steps);
    sets = [T(:), S(:)];
    n = size(sets, 1);
end

% =========================================================================
function out = eval_olla_setting(traces, setting, envE, ctx)
    e = envE;
    e.olla_target = setting(1);
    e.olla_target_tuned = setting(1);
    e.olla_step_down = setting(2);
    sc = score_table(traces, e, 'olla_tuned');
    out = struct('setting', setting, 'score', sc);
end

% =========================================================================
function [best_set, best_score] = merge_olla_settings(outs, all_sets, ctx)
    best_score = -Inf;
    best_set = [];
    for k = 1:numel(outs)
        if outs{k}.score > best_score + 1e-12
            best_score = outs{k}.score;
            best_set   = outs{k}.setting;
        end
    end
end

% =========================================================================
function out = build_composite(traces, F, sc_F, P, sc_P, P_sep, sc_P_sep, X, sc_X, O, sc_O, envE, ctx)
    % Composite table: min(2, max(-4, P(d,v) + X(b) - F))
    % Cells: b in 1..3, d in 1..2, v in 1..3, u in 1..2
    comp = zeros(3, 2, 3, 2);
    for b = 1:3
        for d = 1:2
            for v = 1:3
                for u = 1:2
                    raw = P(d, v) + X(b) - F;
                    comp(b, d, v, u) = min(2, max(-4, raw));
                end
            end
        end
    end
    
    % Evaluate composite table
    e = envE; e.ctxj_tab = comp;
    sc_comp = score_table(traces, e, 'ctxj');
    ctx.hbf(sprintf('Composite table evaluated: score = %.4f', sc_comp));
    
    % Write composite_table.csv
    csvF = fullfile(ctx.outdir, 'composite_table.csv');
    f = fopen(csvF, 'w');
    fprintf(f, 'slack_bin,delay_class,speed_class,busy_bin,offset\n');
    for b = 1:3
        for d = 1:2
            for v = 1:3
                for u = 1:2
                    fprintf(f, '%d,%d,%d,%d,%d\n', b, d, v, u - 1, comp(b, d, v, u));
                end
            end
        end
    end
    fclose(f);
    
    % Write cal500_single.txt
    txtF = fullfile(ctx.outdir, 'cal500_single.txt');
    f = fopen(txtF, 'w');
    fprintf(f, 'CALIBRATION 500 SINGLE-CUE SUMMARY (%s)\n', datestr(now, 31));
    fprintf(f, 'Fixed-500: offset = %+d | score = %.5f\n', F, sc_F);
    fprintf(f, 'FixedPU-500 (separable): score = %.5f\n', sc_P_sep);
    fprintf(f, 'FixedPU-500 (final): score = %.5f\n', sc_P);
    fprintf(f, 'Context-500: [%s] | score = %.5f\n', num2str(X), sc_X);
    fprintf(f, 'OLLA-tuned-500: target = %.2f, step = %.2f dB | score = %.5f\n', O(1), O(2), sc_O);
    fprintf(f, 'Composite table: score = %.5f\n', sc_comp);
    fclose(f);
    
    out = struct('composite_tab', comp, 'composite_score', sc_comp, ...
                 'fixed_offset', F, 'fixed_score', sc_F, ...
                 'fixedpu_tab', P, 'fixedpu_score', sc_P, ...
                 'fixedpu_sep_tab', P_sep, 'fixedpu_sep_score', sc_P_sep, ...
                 'ctx_tab', X, 'ctx_score', sc_X, ...
                 'olla_setting', O, 'olla_score', sc_O);
end

% =========================================================================
function v = score_table(traces, e, ptype)
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

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
