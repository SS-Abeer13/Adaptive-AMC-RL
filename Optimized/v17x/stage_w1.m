function stage_w1(ctx)
% stage_w1  Warm-up robustness of the M1 comparison (v17w).
% Units:
%   repro20
%   comparators_det
%   bandit_seed_K (K = 1..n_seeds)
%   a2c_seed_K (K = 1..n_seeds)
%   ens
%   secondary_recal
% Outputs:
%   Dataset/fill_summary_v17w.txt
%   paper/table_warmup.csv
    addpath(ctx.v17);
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env;
    envE = env; envE.scheduler = 'pf';
    
    n_eval = ternary(ctx.smoke, 2, o.n_eval);
    n_seeds = ternary(ctx.smoke, 2, o.n_seeds);
    n_repro = ternary(ctx.smoke, 2, 20);
    T = o.simTime;
    
    ctx.hbf(sprintf('W1 start: n_eval=%d, n_seeds=%d', n_eval, n_seeds));
    
    % ---- 1. Pre-generate evaluation traces exactly as M1 ----
    ctx.hb('generating evaluation traces');
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        rng(o.trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(o.crn_seed_base + j); U = rand(T, env.N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end
    
    % Scheme map matching M1 results
    % 1: Baseline, 2: OLLA, 3: OLLA (tuned target), 4: Multi-OLLA, 5: Fixed,
    % 6: FixedPU (Oracle), 7: Context table, 8: Deep A2C v17, 10: Deep A2C v17 (ensemble),
    % 13: Bandit (global), 14: Bandit (delay class)
    
    % ---- 2. Unit: repro20 (Sanity check: cold start matches stored M1 on first 20 traces) ----
    ctx.unit('repro20', @() unit_repro20(R, traces, envE, n_repro, ctx));
    
    % ---- 3. Warm-up environment ----
    envWarm = envE;
    envWarm.olla_warm_ttis = 200;
    
    % ---- 4. Unit: comparators_det ----
    det_out = ctx.unit('comparators_det', @() unit_det(traces, envWarm, R, ctx));
    
    % ---- 5. Units: bandit_seed_K ----
    bandit_outs = cell(1, n_seeds);
    for s = 1:n_seeds
        u_name = sprintf('bandit_seed_%d', s);
        bandit_outs{s} = ctx.unit(u_name, @() unit_bandit(traces, envWarm, R, s, ctx));
    end
    
    % ---- 6. Units: a2c_seed_K ----
    a2c_outs = cell(1, n_seeds);
    for s = 1:n_seeds
        u_name = sprintf('a2c_seed_%d', s);
        a2c_outs{s} = ctx.unit(u_name, @() unit_a2c(traces, envWarm, R, s, ctx));
    end
    
    % ---- 7. Unit: ens ----
    ens_out = ctx.unit('ens', @() unit_ens(traces, envWarm, R, ctx));
    
    % ---- 8. Unit: secondary_recal ----
    sec_out = ctx.unit('secondary_recal', @() unit_secondary_recal(traces, envE, o, ctx));
    
    % ---- 9. Assemble results, statistical testing, write outputs ----
    ctx.hbf('Assembling results and running statistical tests');
    assemble_and_report(ctx, R, det_out, bandit_outs, a2c_outs, ens_out, sec_out, n_eval, n_seeds);
    ctx.hbf('W1 done successfully');
end

% =========================================================================
function out = unit_repro20(R, traces, envE, n_repro, ctx)
    ctx.hbf(sprintf('repro20: checking bit-exact reproduction on %d traces with warm-up OFF', n_repro));
    envCold = envE; envCold.olla_warm_ttis = 0;
    b0 = min(envCold.burn_in, size(traces(1).SINR, 1) - 1);
    
    % Check A2C seed 1
    pol = R.policies.A2C{1};
    for j = 1:n_repro
        rng(77000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('a2c_v17', pol, traces(j).SINR, traces(j).obsS, envCold, traces(j).meta, traces(j).U);
        [~, ~, p] = userMetric_v17(envCold, tp, inf, b0);
        stored_p = R.metrics(1).primary{8}(1, j);
        diff = abs(p - stored_p);
        if diff ~= 0
            error('v17x:w1:repro', 'repro20 failed for A2C seed 1 trace %d: diff = %e', j, diff);
        end
    end
    
    % Check Context table
    for j = 1:n_repro
        rng(77000 + 100*j + 10*7 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('ctxtab', [], traces(j).SINR, traces(j).obsS, envCold, traces(j).meta, traces(j).U);
        [~, ~, p] = userMetric_v17(envCold, tp, inf, b0);
        stored_p = R.metrics(1).primary{7}(1, j);
        diff = abs(p - stored_p);
        if diff ~= 0
            error('v17x:w1:repro', 'repro20 failed for Context table trace %d: diff = %e', j, diff);
        end
    end
    out = struct('repro_ok', true, 'n_checked', n_repro);
end

% =========================================================================
function out = unit_det(traces, envWarm, R, ctx)
    ctx.hbf('Evaluating deterministic comparators under 200 TTI warm-up');
    nT = numel(traces);
    b0 = min(envWarm.burn_in, size(traces(1).SINR, 1) - 1);
    ptypes = {'baseline', 'olla', 'olla_tuned', 'multi_olla', 'fixed', 'fixed_class', 'ctxtab'};
    kIndices = [1, 2, 3, 4, 5, 6, 7];
    
    primary = zeros(7, nT);
    cell_tp = zeros(7, nT);
    jain    = zeros(7, nT);
    edge_tp = zeros(7, nT);
    
    for idx = 1:7
        k = kIndices(idx);
        ptype = ptypes{idx};
        ctx.hb(sprintf('evaluating comparator %s', ptype));
        for j = 1:nT
            rng(77000 + 100*j + 10*k + 1);
            [tp, ~, ~, ~, inf] = evalPolicy_v17(ptype, [], traces(j).SINR, traces(j).obsS, envWarm, traces(j).meta, traces(j).U);
            [~, ~, primary(idx, j)] = userMetric_v17(envWarm, tp, inf, b0);
            pu = mean(tp(b0+1:end, :), 1);
            cell_tp(idx, j) = sum(pu);
            edge_tp(idx, j) = prctile(pu, 5);
            if all(pu == 0), jain(idx, j) = 0; else, jain(idx, j) = (sum(pu))^2 / (envWarm.N * sum(pu.^2)); end
        end
    end
    out = struct('primary', primary, 'cell_tp', cell_tp, 'jain', jain, 'edge_tp', edge_tp);
end

% =========================================================================
function out = unit_bandit(traces, envWarm, R, s, ctx)
    nT = numel(traces);
    b0 = min(envWarm.burn_in, size(traces(1).SINR, 1) - 1);
    
    prim_g = zeros(1, nT); tp_g = zeros(1, nT); jain_g = zeros(1, nT); edge_g = zeros(1, nT);
    prim_d = zeros(1, nT); tp_d = zeros(1, nT); jain_d = zeros(1, nT); edge_d = zeros(1, nT);
    
    pol_g = R.policies.Bandit{s};
    pol_d = R.policies.BanditD{s};
    
    for j = 1:nT
        % Bandit global (scheme 13)
        rng(77000 + 100*j + 10*13 + s);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('bandit', pol_g, traces(j).SINR, traces(j).obsS, envWarm, traces(j).meta, traces(j).U);
        [~, ~, prim_g(j)] = userMetric_v17(envWarm, tp, inf, b0);
        pu = mean(tp(b0+1:end, :), 1);
        tp_g(j) = sum(pu); edge_g(j) = prctile(pu, 5);
        if all(pu == 0), jain_g(j) = 0; else, jain_g(j) = (sum(pu))^2 / (envWarm.N * sum(pu.^2)); end
        
        % Bandit delay (scheme 14)
        rng(77000 + 100*j + 10*14 + s);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('bandit', pol_d, traces(j).SINR, traces(j).obsS, envWarm, traces(j).meta, traces(j).U);
        [~, ~, prim_d(j)] = userMetric_v17(envWarm, tp, inf, b0);
        pu = mean(tp(b0+1:end, :), 1);
        tp_d(j) = sum(pu); edge_d(j) = prctile(pu, 5);
        if all(pu == 0), jain_d(j) = 0; else, jain_d(j) = (sum(pu))^2 / (envWarm.N * sum(pu.^2)); end
    end
    out = struct('prim_g', prim_g, 'tp_g', tp_g, 'jain_g', jain_g, 'edge_g', edge_g, ...
                 'prim_d', prim_d, 'tp_d', tp_d, 'jain_d', jain_d, 'edge_d', edge_d);
end

% =========================================================================
function out = unit_a2c(traces, envWarm, R, s, ctx)
    nT = numel(traces);
    b0 = min(envWarm.burn_in, size(traces(1).SINR, 1) - 1);
    prim = zeros(1, nT); cell_tp = zeros(1, nT); jain = zeros(1, nT); edge_tp = zeros(1, nT);
    pol = R.policies.A2C{s};
    
    for j = 1:nT
        rng(77000 + 100*j + 10*8 + s);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('a2c_v17', pol, traces(j).SINR, traces(j).obsS, envWarm, traces(j).meta, traces(j).U);
        [~, ~, prim(j)] = userMetric_v17(envWarm, tp, inf, b0);
        pu = mean(tp(b0+1:end, :), 1);
        cell_tp(j) = sum(pu); edge_tp(j) = prctile(pu, 5);
        if all(pu == 0), jain(j) = 0; else, jain(j) = (sum(pu))^2 / (envWarm.N * sum(pu.^2)); end
    end
    out = struct('primary', prim, 'cell_tp', cell_tp, 'jain', jain, 'edge_tp', edge_tp);
end

% =========================================================================
function out = unit_ens(traces, envWarm, R, ctx)
    nT = numel(traces);
    b0 = min(envWarm.burn_in, size(traces(1).SINR, 1) - 1);
    prim = zeros(1, nT); cell_tp = zeros(1, nT); jain = zeros(1, nT); edge_tp = zeros(1, nT);
    pol = R.policies.A2C;
    
    for j = 1:nT
        rng(77000 + 100*j + 10*10 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('a2c_ens', pol, traces(j).SINR, traces(j).obsS, envWarm, traces(j).meta, traces(j).U);
        [~, ~, prim(j)] = userMetric_v17(envWarm, tp, inf, b0);
        pu = mean(tp(b0+1:end, :), 1);
        cell_tp(j) = sum(pu); edge_tp(j) = prctile(pu, 5);
        if all(pu == 0), jain(j) = 0; else, jain(j) = (sum(pu))^2 / (envWarm.N * sum(pu.^2)); end
    end
    out = struct('primary', prim, 'cell_tp', cell_tp, 'jain', jain, 'edge_tp', edge_tp);
end

% =========================================================================
function out = unit_secondary_recal(traces, envE, o, ctx)
    ctx.hbf('Secondary analysis: recalibrating Fixed/FixedPU/Context with calib_warm=true');
    nT = numel(traces);
    b0 = min(envE.burn_in, size(traces(1).SINR, 1) - 1);
    
    env_w = envE;
    env_w.calib_warm = true;
    env_w.olla_warm_ttis = 200;
    nCalib = ternary(ctx.smoke, 2, 20);
    
    env_w = calibrateFixedClass_v17(env_w, nCalib, o.simTime);
    env_w = calibrateCtx_v17(env_w, ternary(ctx.smoke, 2, env_w.n_calib_ctx), o.simTime);
    
    prim_f = zeros(1, nT); prim_pu = zeros(1, nT); prim_ctx = zeros(1, nT);
    
    for j = 1:nT
        % Fixed
        rng(77000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('fixed', [], traces(j).SINR, traces(j).obsS, env_w, traces(j).meta, traces(j).U);
        [~, ~, prim_f(j)] = userMetric_v17(env_w, tp, inf, b0);
        
        % FixedPU
        rng(77000 + 100*j + 10*6 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('fixed_class', [], traces(j).SINR, traces(j).obsS, env_w, traces(j).meta, traces(j).U);
        [~, ~, prim_pu(j)] = userMetric_v17(env_w, tp, inf, b0);
        
        % Context
        rng(77000 + 100*j + 10*7 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17('ctxtab', [], traces(j).SINR, traces(j).obsS, env_w, traces(j).meta, traces(j).U);
        [~, ~, prim_ctx(j)] = userMetric_v17(env_w, tp, inf, b0);
    end
    out = struct('env_recal', env_w, 'prim_fixed', prim_f, 'prim_fixedpu', prim_pu, 'prim_ctx', prim_ctx);
end

% =========================================================================
function assemble_and_report(ctx, R_cold, det_out, bandit_outs, a2c_outs, ens_out, sec_out, n_eval, n_seeds)
    % Comparators:
    % 1: Baseline
    % 2: OLLA
    % 3: OLLA (tuned target)
    % 4: Multi-OLLA
    % 5: Fixed
    % 6: FixedPU (Oracle)
    % 7: Context table
    % 8: Bandit (global)
    % 9: Bandit (delay class)
    cmpNames = {'Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', ...
                'Fixed', 'FixedPU (Oracle)', 'Context table', ...
                'Bandit (global)', 'Bandit (delay class)'};
    
    warm_prim = cell(1, 9);
    for k = 1:7
        warm_prim{k} = det_out.primary(k, :);
    end
    
    % Bandits
    bg = zeros(n_seeds, n_eval);
    bd = zeros(n_seeds, n_eval);
    for s = 1:n_seeds
        bg(s, :) = bandit_outs{s}.prim_g;
        bd(s, :) = bandit_outs{s}.prim_d;
    end
    warm_prim{8} = mean(bg, 1);
    warm_prim{9} = mean(bd, 1);
    
    % A2C primary policy (mean over seeds)
    a2c_mat = zeros(n_seeds, n_eval);
    for s = 1:n_seeds
        a2c_mat(s, :) = a2c_outs{s}.primary;
    end
    warm_a2c = mean(a2c_mat, 1);
    warm_ens = ens_out.primary;
    
    % Stored cold metrics
    % Map comparators to cold scheme indices
    cold_indices = [1, 2, 3, 4, 5, 6, 7, 13, 14];
    cold_prim = cell(1, 9);
    for idx = 1:9
        k = cold_indices(idx);
        cold_prim{idx} = mean(R_cold.metrics(1).primary{k}(:, 1:n_eval), 1, 'omitnan');
    end
    cold_a2c = mean(R_cold.metrics(1).primary{8}(:, 1:n_eval), 1, 'omitnan');
    cold_ens = R_cold.metrics(1).primary{10}(1, 1:n_eval);
    
    % Statistical tests: Holm over 9 comparators
    % For Cold and Warm
    stats_cold = run_cmp_stats(cold_a2c, cold_prim, cmpNames);
    stats_warm = run_cmp_stats(warm_a2c, warm_prim, cmpNames);
    
    % Gain over OLLA family {OLLA, OLLA tuned, Multi-OLLA} (indices 2, 3, 4)
    [cold_best_olla_name, cold_best_olla_gain] = get_olla_gain(stats_cold);
    [warm_best_olla_name, warm_best_olla_gain] = get_olla_gain(stats_warm);
    
    % Claim B check (vs Fixed, FixedPU, Context table -> indices 5, 6, 7)
    cold_claimB = stats_cold.beats(5) && stats_cold.beats(6) && stats_cold.beats(7);
    warm_claimB = stats_warm.beats(5) && stats_warm.beats(6) && stats_warm.beats(7);
    
    % Write table_warmup.csv
    outDir = ctx.outdir;
    csvF = fullfile(outDir, 'table_warmup.csv');
    f = fopen(csvF, 'w');
    fprintf(f, 'comparator,cold_margin_pct,cold_ci90_lo,cold_ci90_hi,cold_holm_p,cold_beats,warm_margin_pct,warm_ci90_lo,warm_ci90_hi,warm_holm_p,warm_beats\n');
    for idx = 1:9
        fprintf(f, '%s,%+.2f,%.2f,%.2f,%.2e,%d,%+.2f,%.2f,%.2f,%.2e,%d\n', ...
            cmpNames{idx}, ...
            stats_cold.pct(idx), stats_cold.ci_lo(idx), stats_cold.ci_hi(idx), stats_cold.holm_p(idx), stats_cold.beats(idx), ...
            stats_warm.pct(idx), stats_warm.ci_lo(idx), stats_warm.ci_hi(idx), stats_warm.holm_p(idx), stats_warm.beats(idx));
    end
    fclose(f);
    
    % Also copy to paper/table_warmup.csv
    paperCsv = fullfile(fileparts(ctx.root), 'paper', 'table_warmup.csv');
    try
        copyfile(csvF, paperCsv);
    catch
    end
    
    % Write fill_summary_v17w.txt
    txtF = fullfile(outDir, 'fill_summary_v17w.txt');
    f = fopen(txtF, 'w');
    fprintf(f, 'W1 WARM-UP SUMMARY (%s, MATLAB %s)\n\n', datestr(now, 31), version);
    fprintf(f, 'CONFIG|W1|olla_warm_ttis=200|n_eval=%d|n_seeds=%d\n', n_eval, n_seeds);
    fprintf(f, 'PRIMARY_COLD|ontime=%.4f\n', mean(cold_a2c));
    fprintf(f, 'PRIMARY_WARM|ontime=%.4f\n', mean(warm_a2c));
    fprintf(f, 'ENS_WARM|ontime=%.4f\n', mean(warm_ens));
    fprintf(f, 'OLLA_GAIN_COLD|vs=%s|gain=+%.2f%%\n', cold_best_olla_name, cold_best_olla_gain);
    fprintf(f, 'OLLA_GAIN_WARM|vs=%s|gain=+%.2f%%\n', warm_best_olla_name, warm_best_olla_gain);
    fprintf(f, 'CLAIM_B_COLD|passes=%d\n', cold_claimB);
    fprintf(f, 'CLAIM_B_WARM|passes=%d\n\n', warm_claimB);
    
    for idx = 1:9
        fprintf(f, 'REPLCMP_WARM|pf|A2C vs %s|pct=%+.2f|ci90pct=[%.2f %.2f]|p=%.2e|holm=%.2e|beats=%d\n', ...
            cmpNames{idx}, stats_warm.pct(idx), stats_warm.ci_lo(idx), stats_warm.ci_hi(idx), ...
            stats_warm.p(idx), stats_warm.holm_p(idx), stats_warm.beats(idx));
    end
    
    % Secondary recalibrated rules
    sec_fixed = mean(sec_out.prim_fixed);
    sec_pu = mean(sec_out.prim_fixedpu);
    sec_ctx = mean(sec_out.prim_ctx);
    fprintf(f, '\nSECONDARY_RECAL|warm_fixed=%.4f|warm_fixedpu=%.4f|warm_ctx=%.4f\n', ...
        sec_fixed, sec_pu, sec_ctx);
    fclose(f);
    
    ctx.hbf(sprintf('W1 results: Cold Claim B = %d, Warm Claim B = %d, Warm gain over OLLA = +%.2f%%', ...
        cold_claimB, warm_claimB, warm_best_olla_gain));
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

% =========================================================================
function [best_name, min_gain] = get_olla_gain(st)
    % Indices 2: OLLA, 3: OLLA tuned, 4: Multi-OLLA
    names = {'OLLA', 'OLLA (tuned target)', 'Multi-OLLA'};
    olla_gains = [st.pct(2), st.pct(3), st.pct(4)];
    % "best-performing member of the OLLA family" -> smallest margin over it
    [min_gain, min_idx] = min(olla_gains);
    best_name = names{min_idx};
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
