function out = hr_instrument_v17(cases, schemes, trace_set, opts)
% hr_instrument_v17  Stage B evaluator & bit-identity harness for Plan 4 headroom.
%
% Usage:
%   out = hr_instrument_v17()   % runs default 2 cases x 5 schemes on 20 calibration traces
%   out = hr_instrument_v17(cases, schemes, trace_set, opts)
%
% Cases:
%   'M1_dl_rtt8', 'M3_gp_rtt8'
% Schemes:
%   'Fixed', 'Context table', 'Context-joint-500', 'M1', 'NR2'
%
% Bit-identity check:
%   For each case and scheme, on 20 calibration traces (seeds 60001:60020),
%   compares evalPolicy_v17_g6 vs evalPolicy_v17_hr bit-for-bit.
%   Writes EQUIV|<case>|<scheme>|bit_identical=1 to Optimized/v17x/Dataset/hr/hr_equiv.txt.

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
        trace_set = struct('n_traces', 20, 'trace_seed_base', 60000, 'crn_seed_base', 62000);
    elseif isnumeric(trace_set)
        trace_set = struct('n_traces', numel(trace_set), 'trace_seeds', trace_set, 'crn_seeds', 62000 + (1:numel(trace_set)));
    end
    if nargin < 4 || isempty(opts)
        opts = struct();
    end

    if ~isfield(opts, 'do_equiv'), opts.do_equiv = true; end
    if ~isfield(opts, 'save_logs'), opts.save_logs = false; end
    if ~isfield(opts, 'equiv_file')
        opts.equiv_file = fullfile(v17x_dir, 'Dataset', 'hr', 'hr_equiv.txt');
    end
    if ~isfield(opts, 'log_dir')
        opts.log_dir = fullfile(v17x_dir, 'Dataset', 'hr');
    end
    if ~isfield(opts, 'smoke'), opts.smoke = false; end
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

    % Load NR2 checkpoint policy
    nr2_ckpt = fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr2', 'train_seed_1.mat');
    pol_nr2 = [];
    if exist(nr2_ckpt, 'file')
        ck = load(nr2_ckpt);
        if isfield(ck, 'out') && isfield(ck.out, 'a2c')
            pol_nr2 = ck.out.a2c;
        elseif isfield(ck, 'a2c')
            pol_nr2 = ck.a2c;
        end
    end

    n_traces = trace_set.n_traces;
    if opts.smoke
        n_traces = min(2, n_traces);
    end

    if isfield(trace_set, 'trace_seeds')
        tr_seeds = trace_set.trace_seeds(1:n_traces);
    else
        tr_seeds = trace_set.trace_seed_base + (1:n_traces);
    end
    if isfield(trace_set, 'crn_seeds')
        crn_seeds = trace_set.crn_seeds(1:n_traces);
    else
        crn_seeds = trace_set.crn_seed_base + (1:n_traces);
    end

    equiv_lines = {};
    results_all = struct();
    all_bit_identical = true;
    all_psucc_matched = true;

    for cIdx = 1:numel(cases)
        tag = cases{cIdx};
        opts.hbf(sprintf('=== Case: %s (%d traces, %d schemes) ===', tag, n_traces, numel(schemes)));

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
        b0 = min(env.burn_in, T - 1);

        % Pre-generate traces
        opts.hbf(sprintf('Generating %d calibration traces for %s...', n_traces, tag));
        traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
        for j = 1:n_traces
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
                opts.hbf(sprintf('Skipping scheme %s on %s (NR2 model is defined for M1_dl_rtt8 only)', sch_name, tag));
                continue;
            end

            opts.hbf(sprintf('Evaluating scheme: %s on %s...', sch_name, tag));

            % Configure scheme
            e_sch = envE;
            pol = [];
            k_sch = 1;

            switch sch_name
                case 'Fixed'
                    ptype = 'fixed';
                    e_sch.fixed_offset = env.fixed_offset;
                    k_sch = 5;

                case 'Context table'
                    ptype = 'ctxtab';
                    e_sch.ctx_tab = env.ctx_tab;
                    k_sch = 7;

                case 'Context-joint-500'
                    ptype = 'ctxj';
                    e_sch.ctxj_tab = ctxj_tab;
                    k_sch = 99;

                case {'M1', 'A2C'}
                    ptype = 'a2c_v17';
                    if isfield(R, 'policies') && isfield(R.policies, 'A2C') && ~isempty(R.policies.A2C)
                        pol = R.policies.A2C{1};
                    else
                        error('hr_instrument_v17:no_m1_pol', 'No A2C policy in %s', res_path);
                    end
                    k_sch = 8;

                case 'NR2'
                    ptype = 'a2c_v17';
                    e_sch.base_rule_force = 'fixed';
                    e_sch.fixed_offset = -2;
                    [e_sch, ~] = selectBaseRule_v17n(e_sch, 2, o.simTime);
                    if isempty(pol_nr2)
                        error('hr_instrument_v17:no_nr2_pol', 'NR2 policy checkpoint not found at %s', nr2_ckpt);
                    end
                    pol = pol_nr2;
                    k_sch = 8;

                otherwise
                    error('hr_instrument_v17:unknown_scheme', 'Unknown scheme: %s', sch_name);
            end

            sch_bit_identical = true;
            sch_psucc_matched = true;
            max_abs_tp = 0;
            max_abs_bler = 0;
            max_abs_psucc = 0;
            total_logged_decisions = 0;
            logs_cell = cell(1, n_traces);

            t_sch_start = tic;
            for j = 1:n_traces
                eval_rng = 77000 + 100*j + 10*k_sch + 1;

                % Frozen evaluator run
                rng(eval_rng);
                [tp_fz, bler_fz, cqi_fz, act_fz] = ...
                    evalPolicy_v17_g6(ptype, pol, traces(j).SINR, traces(j).obsS, e_sch, traces(j).meta, traces(j).U);

                % Instrumented evaluator run
                rng(eval_rng);
                [tp_hr, bler_hr, cqi_hr, act_hr, inf_hr] = ...
                    evalPolicy_v17_hr(ptype, pol, traces(j).SINR, traces(j).obsS, e_sch, traces(j).meta, traces(j).U);

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
                end
                max_abs_tp = max(max_abs_tp, d_tp);
                max_abs_bler = max(max_abs_bler, d_bler);

                % Check logged p_success vs 1 - bler1
                L = inf_hr.hr_log;
                if ~isempty(L)
                    total_logged_decisions = total_logged_decisions + size(L, 1);
                    % Column 43: bler1, Column 44: p_success_actual
                    d_psucc = max(abs(L(:, 44) - (1 - L(:, 43))));
                    max_abs_psucc = max(max_abs_psucc, d_psucc);
                    if d_psucc > 0
                        sch_psucc_matched = false;
                    end
                end
                logs_cell{j} = L;
            end
            elapsed_sch = toc(t_sch_start);

            all_bit_identical = all_bit_identical && sch_bit_identical;
            all_psucc_matched = all_psucc_matched && sch_psucc_matched;

            eq_line = sprintf('EQUIV|%s|%s|bit_identical=%d', tag, sch_name, sch_bit_identical);
            equiv_lines{end+1} = eq_line; %#ok<AGROW>

            opts.hbf(sprintf('  %s | max_abs_diff(tp)=%.1e | max_abs_diff(psucc)=%.1e | decisions=%d | time=%.2fs', ...
                eq_line, max_abs_tp, max_abs_psucc, total_logged_decisions, elapsed_sch));

            key = sprintf('%s_%s', tag, matlab.lang.makeValidName(sch_name));
            results_all.(key) = struct( ...
                'case', tag, 'scheme', sch_name, ...
                'bit_identical', sch_bit_identical, ...
                'psucc_matched', sch_psucc_matched, ...
                'max_abs_tp', max_abs_tp, ...
                'max_abs_bler', max_abs_bler, ...
                'max_abs_psucc', max_abs_psucc, ...
                'total_decisions', total_logged_decisions, ...
                'elapsed_s', elapsed_sch, ...
                'sec_per_trace', elapsed_sch / n_traces ...
            );

            if opts.save_logs
                L_all = vertcat(logs_cell{:});
                COLS = inf_hr.hr_cols;
                mat_f = fullfile(opts.log_dir, sprintf('hr_log_%s_%s.mat', tag, matlab.lang.makeValidName(sch_name)));
                save(mat_f, 'L_all', 'COLS', 'tag', 'sch_name', '-v7.3');
            end
        end
    end

    % Write hr_equiv.txt
    eq_fid = fopen(opts.equiv_file, 'w');
    if eq_fid < 0
        error('hr_instrument_v17:file_err', 'Could not open equiv file for writing: %s', opts.equiv_file);
    end
    for i = 1:numel(equiv_lines)
        fprintf(eq_fid, '%s\n', equiv_lines{i});
    end
    fclose(eq_fid);
    opts.hbf(sprintf('Equivalence report written to %s (%d lines)', opts.equiv_file, numel(equiv_lines)));

    out = struct();
    out.equiv_lines = equiv_lines;
    out.all_bit_identical = all_bit_identical;
    out.all_psucc_matched = all_psucc_matched;
    out.results = results_all;
    out.equiv_file = opts.equiv_file;
    out.n_traces = n_traces;

    if ~all_bit_identical
        error('hr_instrument_v17:equiv_fail', 'Bit-identity check FAILED for one or more case x scheme pairs');
    end
    if ~all_psucc_matched
        error('hr_instrument_v17:psucc_fail', 'p_success matching check FAILED: max abs diff > 0');
    end
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
