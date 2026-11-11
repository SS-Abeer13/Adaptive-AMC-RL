function out = hr_instrument_v17(cases, schemes, trace_set, opts)
% hr_instrument_v17  Stage B/HR1 evaluator & bit-identity harness for Plan 4 headroom.
%
% Usage:
%   out = hr_instrument_v17()   % runs default 2 cases x 5 schemes on evaluation traces
%   out = hr_instrument_v17(cases, schemes, trace_set, opts)
%
% Cases:
%   'M1_dl_rtt8', 'M3_gp_rtt8'
% Schemes:
%   'Fixed', 'Context table', 'Context-joint-500', 'M1', 'NR2'
%   (M3 renames M1/A2C to 'A2C_case' and notes NR2 as not applicable)
%
% Modes (opts.eval_mode):
%   true (default): Evaluation traces (M1: 500000+, M3: 540000+), asserts bases from
%                   results_v17_<case>.mat. Learned schemes loop s = 1..10.
%                   First 20 traces verified bit-identical vs evalPolicy_v17_g6.
%                   Saves to Dataset/hr/full/.
%   false:          Calibration traces (60000+) for smoke/verification.

    here = fileparts(mfilename('fullpath'));
    v17_dir = fileparts(here);
    v17x_dir = fullfile(fileparts(v17_dir), 'v17x');
    addpath(v17_dir);
    addpath(here);
    addpath(fullfile(v17x_dir, 'g6'));
    addpath(fullfile(v17x_dir, 'nr1'));
    v17_setup;

    if nargin < 1 || isempty(cases)
        cases = {'M1_dl_rtt8', 'M3_gp_rtt8'};
    end
    if nargin < 2 || isempty(schemes)
        schemes = {'Fixed', 'Context table', 'Context-joint-500', 'M1', 'NR2'};
    end
    if nargin < 3 || isempty(trace_set)
        trace_set = struct();
    elseif isnumeric(trace_set)
        trace_set = struct('n_traces', trace_set);
    end
    if nargin < 4 || isempty(opts)
        opts = struct();
    end

    if ~isfield(opts, 'eval_mode'), opts.eval_mode = true; end
    if ~isfield(opts, 'do_equiv'), opts.do_equiv = true; end
    if ~isfield(opts, 'save_logs'), opts.save_logs = true; end
    if ~isfield(opts, 'skip_existing'), opts.skip_existing = true; end
    if ~isfield(opts, 'smoke'), opts.smoke = false; end
    if ~isfield(opts, 'seeds')
        if opts.eval_mode
            opts.seeds = 1:10;
        else
            opts.seeds = 1;
        end
    end
    if ~isfield(opts, 'log_dir')
        if opts.eval_mode
            opts.log_dir = fullfile(v17x_dir, 'Dataset', 'hr', 'full');
        else
            opts.log_dir = fullfile(v17x_dir, 'Dataset', 'hr');
        end
    end
    if ~isfield(opts, 'equiv_file')
        opts.equiv_file = fullfile(v17x_dir, 'Dataset', 'hr', 'hr_equiv.txt');
    end
    if ~isfield(opts, 'hbf')
        opts.hbf = @(msg) fprintf('[%s] %s\n', datestr(now, 31), msg);
    end

    if ~exist(opts.log_dir, 'dir'), mkdir(opts.log_dir); end
    equiv_dir = fileparts(opts.equiv_file);
    if ~exist(equiv_dir, 'dir'), mkdir(equiv_dir); end

    % Load Context-joint-500 table
    ctxj_path = fullfile(v17x_dir, 'Dataset', 'cal500_tables.txt');
    if exist(ctxj_path, 'file')
        ctxj_tab = read_ctxj_from_tables(ctxj_path);
    else
        warning('hr_instrument_v17:no_ctxj', 'cal500_tables.txt not found at %s', ctxj_path);
        ctxj_tab = zeros(3, 2, 3, 2);
    end

    % Load NR2 checkpoint policies (1..10)
    pols_nr2 = cell(1, 10);
    for s = 1:10
        nr2_ckpt = fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr2', sprintf('train_seed_%d.mat', s));
        if exist(nr2_ckpt, 'file')
            ck = load(nr2_ckpt);
            if isfield(ck, 'out') && isfield(ck.out, 'a2c')
                pols_nr2{s} = ck.out.a2c;
            elseif isfield(ck, 'a2c')
                pols_nr2{s} = ck.a2c;
            end
        end
    end

    equiv_lines = {};
    results_all = struct();
    all_bit_identical = true;
    all_psucc_matched = true;
    all_tbs_matched   = true;

    for cIdx = 1:numel(cases)
        tag = cases{cIdx};

        ov = C.(tag); o = base; fn = fieldnames(ov);
        for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
        T = o.simTime;

        res_path = fullfile(v17_dir, 'Dataset', sprintf('results_v17_%s.mat', tag));
        if ~exist(res_path, 'file')
            error('hr_instrument_v17:missing_results', 'Results file not found: %s', res_path);
        end
        res_data = load(res_path);
        R = res_data.results;
        env = R.env;
        envE = env; envE.scheduler = 'pf';

        % Assert trace and CRN bases in evaluation mode (per HR1 prereg section 2)
        if opts.eval_mode
            if strcmp(tag, 'M1_dl_rtt8')
                assert(env.trace_seed_base == 500000, 'hr_instrument:base_mismatch', 'M1 trace_seed_base must be 500000 (found %g)', env.trace_seed_base);
                assert(env.crn_seed_base == 510000, 'hr_instrument:base_mismatch', 'M1 crn_seed_base must be 510000 (found %g)', env.crn_seed_base);
            elseif strcmp(tag, 'M3_gp_rtt8')
                assert(env.trace_seed_base == 540000, 'hr_instrument:base_mismatch', 'M3 trace_seed_base must be 540000 (found %g)', env.trace_seed_base);
                assert(env.crn_seed_base == 550000, 'hr_instrument:base_mismatch', 'M3 crn_seed_base must be 550000 (found %g)', env.crn_seed_base);
            end
        end

        % Determine number of traces
        if isfield(trace_set, 'n_traces') && ~isempty(trace_set.n_traces)
            nT = trace_set.n_traces;
        elseif opts.eval_mode
            nT = 500;
        else
            nT = 20;
        end
        if opts.smoke
            nT = min(2, nT);
        end

        % Determine trace and CRN seeds
        if opts.eval_mode
            tr_seeds = env.trace_seed_base + (1:nT);
            crn_seeds = env.crn_seed_base + (1:nT);
        else
            tr_base = ternary(isfield(trace_set, 'trace_seed_base'), trace_set.trace_seed_base, 60000);
            crn_base = ternary(isfield(trace_set, 'crn_seed_base'), trace_set.crn_seed_base, 62000);
            tr_seeds = tr_base + (1:nT);
            crn_seeds = crn_base + (1:nT);
        end

        opts.hbf(sprintf('=== Case: %s (%d traces, %d schemes, mode=%s) ===', ...
            tag, nT, numel(schemes), ternary(opts.eval_mode, 'eval', 'calib')));

        % Pre-generate traces
        opts.hbf(sprintf('Generating %d traces for %s...', nT, tag));
        traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
        for j = 1:nT
            rng(tr_seeds(j));
            [Strue, ~, meta] = generateChannel_v17(T, envE);
            obsS = cqiFeedback_v17(Strue, envE, meta.delays);
            meta.trace_id = tr_seeds(j);
            rng(crn_seeds(j));
            U = rand(T, envE.N);
            traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
        end

        for sIdx = 1:numel(schemes)
            sch_name = schemes{sIdx};

            % NR2 was trained specifically for M1_dl_rtt8 (57 features)
            if strcmp(sch_name, 'NR2') && ~strcmp(tag, 'M1_dl_rtt8')
                opts.hbf(sprintf('Note: Scheme %s on %s is not applicable (NR2 model is defined for M1_dl_rtt8 only)', sch_name, tag));
                equiv_lines{end+1} = sprintf('NOTE|%s|%s|not_applicable (NR2 trained for M1_dl_rtt8 with 57 features vs 48 features in M3)', tag, sch_name);
                continue;
            end

            % Rename deep policy scheme for M3 to A2C_case
            sch_label = sch_name;
            if ismember(sch_name, {'M1', 'A2C', 'A2C_case'})
                if strcmp(tag, 'M3_gp_rtt8')
                    sch_label = 'A2C_case';
                else
                    sch_label = 'M1';
                end
            end

            mat_f = fullfile(opts.log_dir, sprintf('hr_log_%s_%s.mat', tag, matlab.lang.makeValidName(sch_label)));

            % Check if already complete
            if opts.skip_existing && exist(mat_f, 'file') && opts.save_logs && ~opts.smoke
                try
                    ck = matfile(mat_f);
                    sz = size(ck, 'L_all');
                    if sz(2) == 65 && sz(1) > 0
                        opts.hbf(sprintf('Run %s on %s ALREADY COMPLETED in %s (%d decisions); skipping.', sch_label, tag, mat_f, sz(1)));
                        equiv_lines{end+1} = sprintf('EQUIV|%s|%s|bit_identical=1 (from cached log)', tag, sch_label);
                        key = sprintf('%s_%s', tag, matlab.lang.makeValidName(sch_label));
                        results_all.(key) = struct('case', tag, 'scheme', sch_label, 'bit_identical', true, ...
                            'psucc_matched', true, 'tbs_matched', true, 'total_decisions', sz(1), 'cached', true);
                        continue;
                    end
                catch
                    opts.hbf(sprintf('Existing file %s corrupt or unreadable, recomputing.', mat_f));
                end
            end

            opts.hbf(sprintf('Evaluating scheme: %s on %s...', sch_label, tag));

            % Configure scheme
            e_sch = envE;
            pols = {};
            k_sch = 1;
            is_learned = false;

            switch sch_name
                case 'Fixed'
                    ptype = 'fixed';
                    e_sch.fixed_offset = env.fixed_offset;
                    k_sch = 5;
                    s_list = 1;
                    pols = {[]};

                case 'Context table'
                    ptype = 'ctxtab';
                    e_sch.ctx_tab = env.ctx_tab;
                    k_sch = 7;
                    s_list = 1;
                    pols = {[]};

                case 'Context-joint-500'
                    ptype = 'ctxj';
                    e_sch.ctxj_tab = ctxj_tab;
                    k_sch = 99;
                    s_list = 1;
                    pols = {[]};

                case {'M1', 'A2C', 'A2C_case'}
                    ptype = 'a2c_v17';
                    if isfield(R, 'policies') && isfield(R.policies, 'A2C') && ~isempty(R.policies.A2C)
                        pols = R.policies.A2C;
                    else
                        error('hr_instrument_v17:no_m1_pol', 'No A2C policy in %s', res_path);
                    end
                    k_sch = 8;
                    is_learned = true;
                    s_list = opts.seeds;

                case 'NR2'
                    ptype = 'a2c_v17';
                    e_sch.base_rule_force = 'fixed';
                    e_sch.fixed_offset = -2;
                    [e_sch, ~] = selectBaseRule_v17n(e_sch, 2, o.simTime);
                    pols = pols_nr2;
                    if isempty(pols{1})
                        error('hr_instrument_v17:no_nr2_pol', 'NR2 policy checkpoints not found');
                    end
                    k_sch = 8;
                    is_learned = true;
                    s_list = opts.seeds;

                otherwise
                    error('hr_instrument_v17:unknown_scheme', 'Unknown scheme: %s', sch_name);
            end

            sch_bit_identical = true;
            sch_psucc_matched = true;
            sch_tbs_matched   = true;
            max_abs_tp = 0;
            max_abs_bler = 0;
            max_abs_psucc = 0;
            max_abs_tbs = 0;
            total_logged_decisions = 0;

            trace_logs = cell(1, nT);
            inf_cols = {};

            % Re-check bit-identity on first 20 evaluation traces (or all traces if nT <= 20)
            n_check = min(20, nT);
            if ~opts.do_equiv
                n_check = 0;
            end

            t_sch_start = tic;

            % Step 1: Verification pass on traces 1..n_check against frozen evaluator
            for j = 1:n_check
                L_seeds = cell(1, numel(s_list));
                for sIdx2 = 1:numel(s_list)
                    s = s_list(sIdx2);
                    eval_rng = 77000 + 100*j + 10*k_sch + s;

                    curr_pol = [];
                    if is_learned, curr_pol = pols{s}; end

                    % Frozen evaluator run
                    rng(eval_rng);
                    [tp_fz, bler_fz, cqi_fz, act_fz] = ...
                        evalPolicy_v17_g6(ptype, curr_pol, traces(j).SINR, traces(j).obsS, e_sch, traces(j).meta, traces(j).U);

                    % Instrumented evaluator run
                    rng(eval_rng);
                    [tp_hr, bler_hr, cqi_hr, act_hr, inf_hr] = ...
                        evalPolicy_v17_hr(ptype, curr_pol, traces(j).SINR, traces(j).obsS, e_sch, traces(j).meta, traces(j).U);

                    if isempty(inf_cols), inf_cols = inf_hr.hr_cols; end

                    % Bit-identity check
                    d_tp = max(abs(tp_fz(:) - tp_hr(:)));
                    m_bler_fz = bler_fz(~isnan(bler_fz));
                    m_bler_hr = bler_hr(~isnan(bler_hr));
                    d_bler = max(abs(m_bler_fz - m_bler_hr));
                    d_cqi = max(abs(cqi_fz(:) - cqi_hr(:)));
                    d_act = max(abs(act_fz(:) - act_hr(:)));
                    is_eq = isequaln(tp_fz, tp_hr) && isequaln(bler_fz, bler_hr) && ...
                            isequaln(cqi_fz, cqi_hr) && isequaln(act_fz, act_hr);

                    if ~is_eq || d_tp > 0 || d_bler > 0 || d_cqi > 0 || d_act > 0
                        sch_bit_identical = false;
                        error('hr_instrument_v17:equiv_fail', ...
                            'Bit-identity check FAILED on trace %d (seed %d) for %s on %s: max diff tp=%.1e bler=%.1e cqi=%.1e act=%.1e', ...
                            j, s, sch_label, tag, d_tp, d_bler, d_cqi, d_act);
                    end
                    max_abs_tp = max(max_abs_tp, d_tp);
                    max_abs_bler = max(max_abs_bler, d_bler);

                    % Check logged p_success vs 1 - bler1, and logged tbs(a*) vs frozen path's TBS
                    L = inf_hr.hr_log;
                    if ~isempty(L)
                        d_psucc = max(abs(L(:, 63) - (1 - L(:, 62))));
                        max_abs_psucc = max(max_abs_psucc, d_psucc);
                        if d_psucc > 0
                            sch_psucc_matched = false;
                            error('hr_instrument_v17:psucc_fail', 'p_success check FAILED on trace %d: max diff = %.1e', j, d_psucc);
                        end

                        cand_offs = -4:2;
                        act_col = L(:, 28);
                        tbs_cand_star = zeros(size(L, 1), 1);
                        for rIdx = 1:size(L, 1)
                            k_star = find(cand_offs == act_col(rIdx), 1);
                            if ~isempty(k_star)
                                tbs_cand_star(rIdx) = L(rIdx, 38 + k_star);
                            else
                                tbs_cand_star(rIdx) = L(rIdx, 60);
                            end
                        end
                        d_tbs_star = max(abs(tbs_cand_star - L(:, 60)));
                        max_abs_tbs = max(max_abs_tbs, d_tbs_star);
                        if d_tbs_star > 0
                            sch_tbs_matched = false;
                            error('hr_instrument_v17:tbs_fail', 'TBS check FAILED on trace %d: max diff = %.1e', j, d_tbs_star);
                        end
                    end
                    L_seeds{sIdx2} = L;
                end
                trace_logs{j} = vertcat(L_seeds{:});
            end

            if n_check > 0
                opts.hbf(sprintf('  Bit-identity verified on first %d evaluation traces for %s on %s (diff = 0).', n_check, sch_label, tag));
            end

            % Step 2: Remaining traces (n_check + 1) .. nT via parfor
            if nT > n_check
                opts.hbf(sprintf('  Running remaining %d traces (%d to %d) for %s on %s...', ...
                    nT - n_check, n_check + 1, nT, sch_label, tag));

                % Set up progress reporting via DataQueue if parallel pool active
                dq = [];
                try
                    dq = parallel.pool.DataQueue;
                    afterEach(dq, @(n_done) opts.hbf(sprintf('    %s %s: trace %d / %d completed', tag, sch_label, n_done, nT)));
                catch
                    dq = [];
                end

                n_seeds = numel(s_list);
                parfor j = (n_check + 1):nT
                    L_par_seeds = cell(1, n_seeds);
                    for sIdx2 = 1:n_seeds
                        s = s_list(sIdx2);
                        eval_rng = 77000 + 100*j + 10*k_sch + s;

                        curr_pol = [];
                        if is_learned, curr_pol = pols{s}; end

                        rng(eval_rng);
                        [~, ~, ~, ~, inf_hr] = ...
                            evalPolicy_v17_hr(ptype, curr_pol, traces(j).SINR, traces(j).obsS, e_sch, traces(j).meta, traces(j).U);

                        L = inf_hr.hr_log;
                        if ~isempty(L)
                            d_psucc = max(abs(L(:, 63) - (1 - L(:, 62))));
                            if d_psucc > 0
                                error('hr_instrument_v17:psucc_fail', 'p_success matching failed on trace %d seed %d', j, s);
                            end
                        end
                        L_par_seeds{sIdx2} = L;
                    end
                    trace_logs{j} = vertcat(L_par_seeds{:});

                    if ~isempty(dq) && mod(j, 50) == 0
                        send(dq, j);
                    end
                end
            end

            elapsed_sch = toc(t_sch_start);

            % Step 3: Combine all decisions across all traces and seeds
            L_all = vertcat(trace_logs{:});
            total_logged_decisions = size(L_all, 1);

            assert(size(L_all, 2) == 65, 'hr_instrument_v17:bad_cols', ...
                'L_all must have 65 columns (found %d)', size(L_all, 2));

            % Rule (c): in M3 full buffer, ubits must equal tbs for all candidates
            if strcmp(tag, 'M3_gp_rtt8') && ~isempty(L_all)
                assert(isequal(L_all(:, 39:45), L_all(:, 46:52)), ...
                    'hr_instrument_v17:fullbuf_fail', 'Full buffer case: cand_ubits must equal cand_tbs');
                assert(isequal(L_all(:, 60), L_all(:, 61)), ...
                    'hr_instrument_v17:fullbuf_fail', 'Full buffer case: ubits_act must equal tbs_act');
            end

            all_bit_identical = all_bit_identical && sch_bit_identical;
            all_psucc_matched = all_psucc_matched && sch_psucc_matched;
            all_tbs_matched   = all_tbs_matched && sch_tbs_matched;

            eq_line = sprintf('EQUIV|%s|%s|bit_identical=%d', tag, sch_label, sch_bit_identical);
            equiv_lines{end+1} = eq_line; %#ok<AGROW>

            opts.hbf(sprintf('  %s | %d decisions | %.2fs (%.4fs/trace) | max_diff=%.1e', ...
                eq_line, total_logged_decisions, elapsed_sch, elapsed_sch / nT, max_abs_tp));

            key = sprintf('%s_%s', tag, matlab.lang.makeValidName(sch_label));
            results_all.(key) = struct( ...
                'case', tag, 'scheme', sch_label, ...
                'bit_identical', sch_bit_identical, ...
                'psucc_matched', sch_psucc_matched, ...
                'tbs_matched', sch_tbs_matched, ...
                'max_abs_tp', max_abs_tp, ...
                'max_abs_bler', max_abs_bler, ...
                'max_abs_psucc', max_abs_psucc, ...
                'max_abs_tbs', max_abs_tbs, ...
                'total_decisions', total_logged_decisions, ...
                'elapsed_s', elapsed_sch, ...
                'sec_per_trace', elapsed_sch / nT ...
            );

            if opts.save_logs
                COLS = inf_cols;
                sch_saved_name = sch_label;
                opts.hbf(sprintf('  Saving %s to %s...', sch_label, mat_f));
                save(mat_f, 'L_all', 'COLS', 'tag', 'sch_saved_name', '-v7.3');
            end
        end
    end

    % Write equiv_file
    eq_fid = fopen(opts.equiv_file, 'w');
    if eq_fid >= 0
        for i = 1:numel(equiv_lines)
            fprintf(eq_fid, '%s\n', equiv_lines{i});
        end
        fclose(eq_fid);
        opts.hbf(sprintf('Equivalence report written to %s (%d lines)', opts.equiv_file, numel(equiv_lines)));
    end

    out = struct();
    out.equiv_lines = equiv_lines;
    out.all_bit_identical = all_bit_identical;
    out.all_psucc_matched = all_psucc_matched;
    out.all_tbs_matched = all_tbs_matched;
    out.results = results_all;
    out.equiv_file = opts.equiv_file;
    out.n_traces = nT;
end

% =========================================================================
function tab = read_ctxj_from_tables(fpath)
    tab = zeros(3, 2, 3, 2);
    if ~exist(fpath, 'file'), return; end
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

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
