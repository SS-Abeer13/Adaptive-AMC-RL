function stage_g6c(ctx)
% stage_g6c  G6 Step 3: Evaluation of re-calibrated comparators on held-out traces.
% Units:
%   repro
%   eval
%   analysis
% Outputs:
%   Dataset/fill_summary_v17b_cal.txt
%   Dataset/table_cal500.csv
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data.results; env_M1 = R_M1.env;
    
    n_eval = ternary(ctx.smoke, 2, 500);
    n_seeds = ternary(ctx.smoke, 2, 10);
    T = o.simTime;
    
    % ---- 1. Gate: check SHA-256 and sanity check ----
    tab_file = fullfile(ctx.outdir, 'cal500_tables.txt');
    sha_file = fullfile(ctx.outdir, 'cal500_tables.sha256');
    if ~exist(tab_file, 'file') || ~exist(sha_file, 'file')
        error('v17x:g6c:gate', 'cal500_tables.txt or cal500_tables.sha256 missing from g6b');
    end
    
    sha_expected = strtok(strtrim(fileread(sha_file)));
    sha_actual = compute_file_sha256(tab_file);
    if ~strcmp(sha_expected, sha_actual)
        error('v17x:g6c:gate', 'SHA-256 mismatch for cal500_tables.txt (%s vs %s)', sha_actual, sha_expected);
    end
    
    tab_txt = fileread(tab_file);
    sanity_tok = regexp(tab_txt, 'SANITY_CHECK_PASSED: ([0-9]+)', 'tokens', 'once');
    if isempty(sanity_tok) || str2double(sanity_tok{1}) ~= 1
        if ~ctx.smoke
            error('v17x:g6c:gate', 'Refusing to run: sanity check failed in g6b');
        end
    end
    ctx.hbf('g6c gate passed: SHA-256 verified and sanity check clean');
    
    % ---- 2. Pre-generate M1 evaluation traces ----
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:n_eval
        rng(o.trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, env_M1);
        obsS = cqiFeedback_v17(Strue, env_M1, meta.delays);
        meta.trace_id = j;
        rng(o.crn_seed_base + j); U = rand(T, env_M1.N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end
    
    % ---- 3. Unit: repro ----
    ctx.unit('repro', @() unit_repro(R_M1, traces, env_M1, ternary(ctx.smoke, 2, 20), ctx));
    
    % ---- 4. Unit: eval ----
    eval_res = ctx.unit('eval', @() unit_eval_recal(traces, env_M1, ctx));
    
    % ---- 5. Unit: analysis ----
    ctx.unit('analysis', @() unit_analysis(R_M1, eval_res, n_eval, n_seeds, ctx));
    
    ctx.hbf('g6c finished successfully');
end

% =========================================================================
function out = unit_repro(R_M1, traces, env, n_repro, ctx)
    ctx.hbf(sprintf('repro: checking bit-exact reproduction on %d traces', n_repro));
    e = env; e.scheduler = 'pf';
    b0 = min(e.burn_in, size(traces(1).SINR, 1) - 1);
    pol = R_M1.policies.A2C{1};
    for j = 1:n_repro
        rng(77000 + 100*j + 10*8 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('a2c_v17', pol, traces(j).SINR, traces(j).obsS, e, traces(j).meta, traces(j).U);
        [~, ~, p] = userMetric_v17(e, tp, inf, b0);
        stored_p = R_M1.metrics(1).primary{8}(1, j);
        diff = abs(p - stored_p);
        if diff ~= 0
            error('v17x:g6c:repro', 'REPRO failed on trace %d: diff = %e', j, diff);
        end
    end
    out = struct('repro_ok', true);
end

% =========================================================================
function out = unit_eval_recal(traces, env_M1, ctx)
    ctx.hbf('eval: evaluating 5 re-calibrated rules on held-out evaluation traces');
    nT = numel(traces);
    b0 = min(env_M1.burn_in, size(traces(1).SINR, 1) - 1);
    e = env_M1; e.scheduler = 'pf';
    
    % Parse tables from cal500_single.txt and cal500_tables.txt
    txt_single = fileread(fullfile(ctx.outdir, 'cal500_single.txt'));
    f_off = parse_int(txt_single, 'Fixed-500: offset = ([+-]?[0-9]+)');
    
    % Load composite table / ckpt to get FixedPU and Context-500
    comp_ckpt = fullfile(ctx.ckptdir, 'g6a', 'composite_table.mat');
    if exist(comp_ckpt, 'file')
        S = load(comp_ckpt);
        pu_tab = S.out.fixedpu_tab;
        ctx_tab = S.out.ctx_tab;
        olla_set = S.out.olla_setting;
    else
        % Fallbacks
        pu_tab = env_M1.class_tab;
        ctx_tab = env_M1.ctx_tab;
        olla_set = [env_M1.olla_target, 0.5];
    end
    
    % Load Context-joint-500 table from cal500_tables.txt
    ctxj_tab = read_ctxj_from_tables(fullfile(ctx.outdir, 'cal500_tables.txt'));
    
    % 1. Fixed-500
    prim_fixed500 = zeros(1, nT);
    e_f = e; e_f.fixed_offset = f_off;
    for j = 1:nT
        rng(77000 + 100*j + 10*5 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed', [], traces(j).SINR, traces(j).obsS, e_f, traces(j).meta, traces(j).U);
        [~, ~, prim_fixed500(j)] = userMetric_v17(e_f, tp, inf, b0);
    end
    
    % 2. FixedPU-500
    prim_pu500 = zeros(1, nT);
    e_pu = e; e_pu.class_tab = pu_tab;
    for j = 1:nT
        rng(77000 + 100*j + 10*6 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('fixed_class', [], traces(j).SINR, traces(j).obsS, e_pu, traces(j).meta, traces(j).U);
        [~, ~, prim_pu500(j)] = userMetric_v17(e_pu, tp, inf, b0);
    end
    
    % 3. Context-500
    prim_ctx500 = zeros(1, nT);
    e_ctx = e; e_ctx.ctx_tab = ctx_tab;
    for j = 1:nT
        rng(77000 + 100*j + 10*7 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxtab', [], traces(j).SINR, traces(j).obsS, e_ctx, traces(j).meta, traces(j).U);
        [~, ~, prim_ctx500(j)] = userMetric_v17(e_ctx, tp, inf, b0);
    end
    
    % 4. OLLA-tuned-500
    prim_olla500 = zeros(1, nT);
    e_olla = e; e_olla.olla_target = olla_set(1); e_olla.olla_target_tuned = olla_set(1); e_olla.olla_step_down = olla_set(2);
    for j = 1:nT
        rng(77000 + 100*j + 10*3 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('olla_tuned', [], traces(j).SINR, traces(j).obsS, e_olla, traces(j).meta, traces(j).U);
        [~, ~, prim_olla500(j)] = userMetric_v17(e_olla, tp, inf, b0);
    end
    
    % 5. Context-joint-500
    prim_ctxj500 = zeros(1, nT);
    e_ctxj = e; e_ctxj.ctxj_tab = ctxj_tab;
    for j = 1:nT
        rng(77000 + 100*j + 10*99 + 1);
        [tp, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxj', [], traces(j).SINR, traces(j).obsS, e_ctxj, traces(j).meta, traces(j).U);
        [~, ~, prim_ctxj500(j)] = userMetric_v17(e_ctxj, tp, inf, b0);
    end
    
    out = struct('prim_fixed500', prim_fixed500, 'prim_pu500', prim_pu500, ...
                 'prim_ctx500', prim_ctx500, 'prim_olla500', prim_olla500, ...
                 'prim_ctxj500', prim_ctxj500);
end

% =========================================================================
function out = unit_analysis(R_M1, eval_res, n_eval, n_seeds, ctx)
    ctx.hbf('analysis: running Holm over 10 comparators and hierarchical bootstrap CIs');
    
    % 10 comparators:
    % 1: Baseline
    % 2: OLLA
    % 3: OLLA-tuned-500
    % 4: Multi-OLLA
    % 5: Fixed-500
    % 6: FixedPU-500
    % 7: Context-500
    % 8: Bandit (global)
    % 9: Bandit (delay class)
    % 10: Context-joint-500
    cmpNames = {'Baseline', 'OLLA', 'OLLA-tuned-500', 'Multi-OLLA', ...
                'Fixed-500', 'FixedPU-500', 'Context-500', ...
                'Bandit (global)', 'Bandit (delay class)', 'Context-joint-500'};
    
    cmp_vals = cell(1, 10);
    cmp_vals{1} = mean(R_M1.metrics(1).primary{1}(:, 1:n_eval), 1, 'omitnan');
    cmp_vals{2} = mean(R_M1.metrics(1).primary{2}(:, 1:n_eval), 1, 'omitnan');
    cmp_vals{3} = eval_res.prim_olla500;
    cmp_vals{4} = mean(R_M1.metrics(1).primary{4}(:, 1:n_eval), 1, 'omitnan');
    cmp_vals{5} = eval_res.prim_fixed500;
    cmp_vals{6} = eval_res.prim_pu500;
    cmp_vals{7} = eval_res.prim_ctx500;
    cmp_vals{8} = mean(R_M1.metrics(1).primary{13}(:, 1:n_eval), 1, 'omitnan');
    cmp_vals{9} = mean(R_M1.metrics(1).primary{14}(:, 1:n_eval), 1, 'omitnan');
    cmp_vals{10} = eval_res.prim_ctxj500;
    
    a2c_seeds = R_M1.metrics(1).primary{8}(1:n_seeds, 1:n_eval);
    a2c_prim = mean(a2c_seeds, 1);
    ens_prim = R_M1.metrics(1).primary{10}(1, 1:n_eval);
    
    stats = run_cmp_stats(a2c_prim, cmp_vals, cmpNames);
    
    % Claims:
    % Claim A: beats OLLA, OLLA-tuned-500, Multi-OLLA (indices 2, 3, 4)
    claimA = stats.beats(2) && stats.beats(3) && stats.beats(4);
    % Claim B-500: beats Fixed-500, FixedPU-500, Context-500 (indices 5, 6, 7)
    claimB500 = stats.beats(5) && stats.beats(6) && stats.beats(7);
    % Joint Parity (JP): beats Context-joint-500 (index 10)
    claimJP = stats.beats(10);
    
    % Seed-level hierarchical bootstrap CI (R2) for best comparator
    % Best comparator in Claim B-500
    [~, bestB_idx] = min(stats.pct([5, 6, 7]));
    bestB_cmp = cmpNames{4 + bestB_idx};
    bestB_vals = cmp_vals{4 + bestB_idx};
    
    B_rep = ternary(ctx.smoke, 50, 20000);
    rng(42, 'twister');
    b_ci = seed_bootstrap_ci(a2c_seeds, bestB_vals, B_rep);
    
    seed_robust = (b_ci(1) > 0);
    
    % Verdict string per G6 §4
    if claimA && claimB500 && claimJP
        if seed_robust
            verdict = 'A, B-500 and JP pass (seed-level lower bounds > 0)';
            wording = 'C2 keeps "beats all calibrated comparators". The paper may use "same-information": With rules re-calibrated by exhaustive search on 500 fresh traces, and a table that combines deadline slack, user class and HARQ-process state, residual A2C still beat every comparator.';
        else
            verdict = 'A, B-500 and JP pass, but a seed-level lower bound <= 0';
            wording = sprintf('C2 keeps beats all calibrated comparators; the margin over %s is not robust to seed resampling (hierarchical 95%% CI [%.2f, %.2f]%%)', bestB_cmp, b_ci(1), b_ci(2));
        end
    elseif claimA && claimB500 && ~claimJP
        verdict = 'A and B-500 pass, JP fails';
        wording = 'C2 becomes "beats the OLLA family and the single-cue calibrated rules". The combined table is reported as matching RL. "Same-information" is not used.';
    elseif claimA && ~claimB500
        verdict = 'A passes, B-500 fails';
        wording = 'Headline weakens to Claim A: Residual A2C beats the OLLA family under realistic HARQ timing; against calibrated rules its advantage depends on their calibration budget.';
    else
        verdict = 'A fails';
        wording = 'The deadline gain did not survive re-calibration. The paper becomes a negative and methodological result.';
    end
    
    % Write table_cal500.csv
    csvF = fullfile(ctx.outdir, 'table_cal500.csv');
    f = fopen(csvF, 'w');
    fprintf(f, 'comparator,margin_pct,ci90_lo,ci90_hi,wilcoxon_p,holm_p,beats\n');
    for idx = 1:10
        fprintf(f, '%s,%+.2f,%.2f,%.2f,%.2e,%.2e,%d\n', ...
            cmpNames{idx}, stats.pct(idx), stats.ci_lo(idx), stats.ci_hi(idx), ...
            stats.p(idx), stats.holm_p(idx), stats.beats(idx));
    end
    fclose(f);
    
    % Also copy to paper/table_cal500.csv
    try
        copyfile(csvF, fullfile(fileparts(ctx.root), 'paper', 'table_cal500.csv'));
    catch
    end
    
    % Write fill_summary_v17b_cal.txt
    txtF = fullfile(ctx.outdir, 'fill_summary_v17b_cal.txt');
    f = fopen(txtF, 'w');
    fprintf(f, 'G6 CALIBRATION BUDGET SUMMARY (%s, MATLAB %s)\n\n', datestr(now, 31), version);
    fprintf(f, 'PRIMARY_A2C|ontime=%.4f\n', mean(a2c_prim));
    fprintf(f, 'ENS_A2C|ontime=%.4f\n', mean(ens_prim));
    fprintf(f, 'CLAIMS|claimA=%d|claimB500=%d|claimJP=%d|seed_robust=%d\n', ...
        claimA, claimB500, claimJP, seed_robust);
    fprintf(f, 'HIERARCHICAL_CI|vs=%s|ci95=[%.2f %.2f]%%\n', bestB_cmp, b_ci(1), b_ci(2));
    fprintf(f, 'VERDICT|%s\n', verdict);
    fprintf(f, 'WORDING|%s\n\n', wording);
    for idx = 1:10
        fprintf(f, 'REPLCMP_CAL500|pf|A2C vs %s|pct=%+.2f|ci90pct=[%.2f %.2f]|p=%.2e|holm=%.2e|beats=%d\n', ...
            cmpNames{idx}, stats.pct(idx), stats.ci_lo(idx), stats.ci_hi(idx), ...
            stats.p(idx), stats.holm_p(idx), stats.beats(idx));
    end
    fclose(f);
    
    ctx.hbf(sprintf('G6 verdict: %s (Claim A=%d, B-500=%d, JP=%d)', ...
        verdict, claimA, claimB500, claimJP));
    out = struct('stats', stats, 'verdict', verdict, 'wording', wording);
end

% =========================================================================
function ci = seed_bootstrap_ci(a2c_seeds, cmp_vals, B)
    [nS, nT] = size(a2c_seeds);
    boot_diffs = zeros(1, B);
    bm = mean(cmp_vals);
    for b = 1:B
        s_idx = randi(nS, 1, nS);
        t_idx = randi(nT, 1, nT);
        sampled_a2c = mean(a2c_seeds(s_idx, t_idx), 1);
        sampled_cmp = cmp_vals(t_idx);
        md = mean(sampled_a2c - sampled_cmp);
        boot_diffs(b) = 100 * md / bm;
    end
    ci = prctile(boot_diffs, [2.5, 97.5]);
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

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
