function stage_g6b(ctx)
% stage_g6b  G6 Step 2: Combined comparator Context-joint-500 coordinate ascent search.
% Units:
%   start_k_sweep_s (k = 0..3, s = 1..cap)
% Outputs:
%   Dataset/ctxj_cells.csv
%   Dataset/cal500_tables.txt
%   Dataset/cal500_tables.sha256
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
    b0 = min(envE.burn_in, T - 1);
    
    calib_seed_base = 600000;
    calib_crn_base  = 610000;
    
    % Load composite table and g6a single-cue results
    f_comp = fullfile(ctx.outdir, 'composite_table.csv');
    if ~exist(f_comp, 'file')
        error('v17x:g6b', 'composite_table.csv missing from g6a');
    end
    comp_tab = read_composite_csv(f_comp);
    
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
    
    % ---- 1. Counting pass on calibration traces ----
    ctx.hbf('Counting pass with composite table on calibration traces');
    cell_counts = zeros(3, 2, 3, 2);
    for j = 1:nCalib
        e = envE; e.ctxj_tab = comp_tab;
        rng(61500 + j);
        [~, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxj', [], C_traces(j).SINR, C_traces(j).obsS, e, C_traces(j).meta, C_traces(j).U);
        log = inf.sch_log;
        meta = C_traces(j).meta;
        for row = 1:size(log, 1)
            u = log(row, 1);
            is_retx = log(row, 4);
            if is_retx == 1, continue; end % scheduled new transmissions only
            sl = log(row, 3);
            if sl <= 2, b = 1; elseif sl <= 5, b = 2; else, b = 3; end
            if meta.delays(u) <= 4, d = 1; else, d = 2; end
            sp = mean(meta.speeds(:, u));
            if sp < 10, v = 1; elseif sp <= 20, v = 2; else, v = 3; end
            busy = log(row, 5);
            if busy == 0, u_bin = 1; else, u_bin = 2; end
            cell_counts(b, d, v, u_bin) = cell_counts(b, d, v, u_bin) + 1;
        end
    end
    
    threshold_N = ternary(ctx.smoke, 0, 200);
    is_sparse = (cell_counts < threshold_N);
    n_searched = sum(~is_sparse(:));
    ctx.hbf(sprintf('Counting pass done: %d of 36 cells searched (decision threshold N=%d)', ...
        n_searched, threshold_N));
    
    % Write ctxj_cells.csv
    csv_cells = fullfile(ctx.outdir, 'ctxj_cells.csv');
    f = fopen(csv_cells, 'w');
    fprintf(f, 'slack_bin,delay_class,speed_class,busy_bin,decision_count,is_sparse,composite_offset\n');
    for b = 1:3
        for d = 1:2
            for v = 1:3
                for u = 1:2
                    fprintf(f, '%d,%d,%d,%d,%d,%d,%d\n', ...
                        b, d, v, u - 1, cell_counts(b, d, v, u), is_sparse(b, d, v, u), comp_tab(b, d, v, u));
                end
            end
        end
    end
    fclose(f);
    
    % ---- 2. Coordinate ascent (4 starts: S0 composite, R1-R3 random) ----
    offset_cands = -4:2;
    n_starts = ternary(ctx.smoke, 2, 4);
    max_sweeps = ternary(ctx.smoke, 1, 6);
    
    start_results = cell(1, n_starts);
    for k = 0:(n_starts - 1)
        % Initialize start table
        if k == 0
            init_tab = comp_tab;
        else
            rng(90017 + k, 'twister');
            init_tab = comp_tab;
            rand_offsets = offset_cands(randi(numel(offset_cands), 3, 2, 3, 2));
            init_tab(~is_sparse) = rand_offsets(~is_sparse);
        end
        
        cur_tab = init_tab;
        cur_e = envE; cur_e.ctxj_tab = cur_tab;
        cur_sc = score_table(C_traces, cur_e);
        
        ctx.hbf(sprintf('Start S%d initial score: %.4f', k, cur_sc));
        
        for s = 1:max_sweeps
            u_name = sprintf('start_%d_sweep_%d', k, s);
            sweep_res = ctx.unit(u_name, @() run_one_sweep(C_traces, cur_tab, cur_sc, is_sparse, offset_cands, envE, k, s, ctx));
            cur_tab = sweep_res.tab;
            cur_sc  = sweep_res.score;
            ctx.hbf(sprintf('Start S%d sweep %d: checking convergence (improved=%d, score=%.4f)', ...
                k, s, sweep_res.improved, cur_sc));
            if ~sweep_res.improved
                ctx.hbf(sprintf('Start S%d converged at sweep %d with score %.4f', k, s, cur_sc));
                break;
            else
                ctx.hbf(sprintf('Start S%d sweep %d complete; continuing to sweep %d (score %.4f)', ...
                    k, s, s + 1, cur_sc));
            end
        end
        start_results{k + 1} = struct('start_id', k, 'tab', cur_tab, 'score', cur_sc);
    end
    
    % Select start with highest calibration objective (ties broken by S0)
    best_start = 1;
    best_score = start_results{1}.score;
    best_tab   = start_results{1}.tab;
    for k = 2:n_starts
        if start_results{k}.score > best_score + 1e-12
            best_score = start_results{k}.score;
            best_tab   = start_results{k}.tab;
            best_start = k;
        end
    end
    ctx.hbf(sprintf('Selected start: S%d with score %.5f', best_start - 1, best_score));
    
    % ---- 3. Sanity check: objective >= each coarser table ----
    % Coarser tables: composite table, Fixed-500, FixedPU-500, Context-500
    f_single = fullfile(ctx.outdir, 'cal500_single.txt');
    txt_single = fileread(f_single);
    sc_comp = parse_score(txt_single, 'Composite table: score = ([0-9.]+)');
    sc_fixed = parse_score(txt_single, 'Fixed-500: .*?score = ([0-9.]+)');
    sc_fixedpu = parse_score(txt_single, 'FixedPU-500 \(final\): score = ([0-9.]+)');
    sc_ctx = parse_score(txt_single, 'Context-500: .*?score = ([0-9.]+)');
    
    ctx.hbf(sprintf('Sanity check: final %.5f vs coarser: comp=%.5f, fixed=%.5f, pu=%.5f, ctx=%.5f', ...
        best_score, sc_comp, sc_fixed, sc_fixedpu, sc_ctx));
    
    sanity_ok = (best_score >= sc_comp - 1e-6) && ...
                (best_score >= sc_fixed - 1e-6) && ...
                (best_score >= sc_fixedpu - 1e-6) && ...
                (best_score >= sc_ctx - 1e-6);
    
    if ~sanity_ok && ~ctx.smoke
        error('v17x:g6b:sanity', 'Sanity check failed: final table objective (%.5f) < coarser table', best_score);
    end
    
    % ---- 4. Freeze rule: write cal500_tables.txt and compute SHA-256 ----
    tab_file = fullfile(ctx.outdir, 'cal500_tables.txt');
    write_cal500_tables(tab_file, best_tab, best_score, sc_comp, sc_fixed, sc_fixedpu, sc_ctx, comp_tab, sanity_ok);
    
    % Compute SHA-256 hash
    sha256 = compute_file_sha256(tab_file);
    sha_file = fullfile(ctx.outdir, 'cal500_tables.sha256');
    fsha = fopen(sha_file, 'w');
    fprintf(fsha, '%s  cal500_tables.txt\n', sha256);
    fclose(fsha);
    
    ctx.hbf(sprintf('cal500_tables.txt written; SHA-256 = %s', sha256));
    ctx.hbf('g6b finished successfully');
end

% =========================================================================
function out = run_one_sweep(traces, cur_tab, cur_score, is_sparse, cands, envE, start_k, sweep_s, ctx)
    tab = cur_tab;
    score = cur_score;
    improved = false;
    
    % Lexicographic visit over searched cells
    for b = 1:3
        for d = 1:2
            for v = 1:3
                for u = 1:2
                    if is_sparse(b, d, v, u), continue; end
                    cur_off = tab(b, d, v, u);
                    best_cand_off = cur_off;
                    best_cand_score = score;
                    ctx.hb(sprintf('S%d sweep %d: eval cell (%d,%d,%d,%d) [cur offset %+d, score %.4f]', ...
                        start_k, sweep_s, b, d, v, u - 1, cur_off, score));
                    
                    for c = 1:numel(cands)
                        cand_off = cands(c);
                        if cand_off == cur_off, continue; end
                        t2 = tab; t2(b, d, v, u) = cand_off;
                        e = envE; e.ctxj_tab = t2;
                        sc = score_table(traces, e);
                        if sc > best_cand_score + 1e-6
                            best_cand_score = sc;
                            best_cand_off = cand_off;
                        end
                    end
                    
                    if best_cand_score > score + 1e-6
                        improved = true;
                        score = best_cand_score;
                        tab(b, d, v, u) = best_cand_off;
                        ctx.hb(sprintf('S%d sweep %d: cell (%d,%d,%d,%d) moved %+d -> %+d (score %.4f)', ...
                            start_k, sweep_s, b, d, v, u - 1, cur_off, best_cand_off, score));
                    else
                        ctx.hb(sprintf('S%d sweep %d: cell (%d,%d,%d,%d) kept offset %+d (score %.4f)', ...
                            start_k, sweep_s, b, d, v, u - 1, cur_off, score));
                    end
                end
            end
        end
    end
    out = struct('tab', tab, 'score', score, 'improved', improved);
end

% =========================================================================
function v = score_table(traces, e)
    n = 0; d = 0;
    b0 = min(e.burn_in, size(traces(1).SINR, 1) - 1);
    for jj = 1:numel(traces)
        rng(61500 + jj);
        [tpc, ~, ~, ~, inf] = evalPolicy_v17_g6('ctxj', [], traces(jj).SINR, traces(jj).obsS, e, traces(jj).meta, traces(jj).U);
        [nu, de] = userMetric_v17(e, tpc, inf, b0);
        n = n + sum(nu); d = d + sum(de);
    end
    v = n / max(d, 1);
end

% =========================================================================
function comp = read_composite_csv(fpath)
    comp = zeros(3, 2, 3, 2);
    lines = strsplit(fileread(fpath), sprintf('\n'));
    for i = 2:numel(lines)
        line = strtrim(lines{i});
        if isempty(line), continue; end
        parts = strsplit(line, ',');
        b = str2double(parts{1});
        d = str2double(parts{2});
        v = str2double(parts{3});
        u = str2double(parts{4}) + 1; % 0-based in CSV -> 1-based index
        off = str2double(parts{5});
        comp(b, d, v, u) = off;
    end
end

% =========================================================================
function sc = parse_score(txt, pattern)
    tok = regexp(txt, pattern, 'tokens', 'once');
    if isempty(tok), sc = 0; else, sc = str2double(tok{1}); end
end

% =========================================================================
function write_cal500_tables(fpath, best_tab, best_sc, sc_comp, sc_f, sc_pu, sc_x, comp_tab, sanity_ok)
    f = fopen(fpath, 'w');
    fprintf(f, '# cal500_tables.txt -- Frozen tables calibrated on 500 calibration traces\n');
    fprintf(f, 'DATE: %s\n', datestr(now, 31));
    fprintf(f, 'SANITY_CHECK_PASSED: %d\n', sanity_ok);
    fprintf(f, 'SCORES: Context_joint_500=%.5f | Composite=%.5f | Fixed_500=%.5f | FixedPU_500=%.5f | Context_500=%.5f\n\n', ...
        best_sc, sc_comp, sc_f, sc_pu, sc_x);
    fprintf(f, 'TABLE Context-joint-500 (slack_bin 1..3, delay_class 1..2, speed_class 1..3, busy_bin 0..1):\n');
    for b = 1:3
        for d = 1:2
            for v = 1:3
                for u = 1:2
                    fprintf(f, 'cell(%d,%d,%d,%d) = %+d\n', b, d, v, u - 1, best_tab(b, d, v, u));
                end
            end
        end
    end
    fclose(f);
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
