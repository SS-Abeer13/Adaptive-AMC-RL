function out = stage_hr1(ctx)
% stage_hr1  Plan 4 tooling: instrumented headroom evaluator (build & verify).
%
% Implements Task B:
%   B1. Instrumented evaluator hr_instrument_v17.m + evalPolicy_v17_hr.m
%   B2. Bit-identity check against frozen evaluator on 20 calibration traces (seeds 60001+)
%       Writes EQUIV|<case>|<scheme>|bit_identical=1 to Dataset/hr/hr_equiv.txt
%       Checks that p_success for action taken matches 1 - bler1 bit for bit (diff = 0)
%   B3. Stage wrapper with ctx.unit, heartbeat, outputs in Dataset/hr/
%   B4. GATED: Does not run full 500-trace estimation pass until Amendment 7 is pre-registered.

    addpath(ctx.v17);
    addpath(fullfile(ctx.v17, 'headroom'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    v17_setup;

    out_hr = fullfile(ctx.root, 'Dataset', 'hr');
    if ~exist(out_hr, 'dir'), mkdir(out_hr); end

    ctx.hbf('stage_hr1: starting Plan 4 instrumented headroom evaluator verification');

    % Check B4 gate
    paper_dir = fullfile(fileparts(ctx.root), 'paper');
    amend_file = fullfile(paper_dir, 'proposals', 'AMENDMENTS.md');
    freeze_file = fullfile(paper_dir, 'proposals', 'FREEZE.sha256');
    has_amend7 = false;
    has_freeze = false;
    if exist(amend_file, 'file')
        txt_a = fileread(amend_file);
        has_amend7 = ~isempty(strfind(txt_a, 'Amendment 7'));
    end
    if exist(freeze_file, 'file')
        txt_f = fileread(freeze_file);
        has_freeze = ~isempty(strfind(txt_f, 'plan4')) || ~isempty(strfind(txt_f, 'hr1'));
    end
    gate_open = has_amend7 && has_freeze;

    if ~gate_open
        ctx.hbf('Task B4 GATED: Amendment 7 not yet in AMENDMENTS.md / FREEZE.sha256');
        ctx.hbf('Full 500-trace pass and evaluation traces are GATED. Running verification pass on calibration traces only.');
    else
        ctx.hbf('Task B4 GATE OPEN: Amendment 7 and freeze hash verified.');
    end

    % Unit: hr_equiv
    equiv_res = ctx.unit('hr_equiv', @() unit_hr_equiv(ctx, out_hr));

    % Unit: hr_report
    rep_res = ctx.unit('hr_report', @() unit_hr_report(ctx, out_hr, equiv_res, gate_open));

    out = struct();
    out.equiv = equiv_res;
    out.report = rep_res;
    out.gate_open = gate_open;
    ctx.hbf('stage_hr1: completed successfully');
end

% =========================================================================
function res = unit_hr_equiv(ctx, out_hr)
    ctx.hbf('unit_hr_equiv: running bit-identity & p_success check on 20 calibration traces');

    cases = {'M1_dl_rtt8', 'M3_gp_rtt8'};
    schemes = {'Fixed', 'Context table', 'Context-joint-500', 'M1', 'NR2'};

    nT = ternary(ctx.smoke, 2, 20);
    trace_set = struct('n_traces', nT, 'trace_seed_base', 60000, 'crn_seed_base', 62000);

    opts = struct();
    opts.smoke = ctx.smoke;
    opts.do_equiv = true;
    opts.save_logs = true;
    opts.equiv_file = fullfile(out_hr, 'hr_equiv.txt');
    opts.log_dir = out_hr;
    opts.hbf = @(msg) ctx.hbf(['hr_instrument: ' msg]);

    res = hr_instrument_v17(cases, schemes, trace_set, opts);

    if ~res.all_bit_identical
        error('stage_hr1:equiv_fail', 'Bit-identity check failed in unit_hr_equiv');
    end
    if ~res.all_psucc_matched
        error('stage_hr1:psucc_fail', 'p_success matching check failed in unit_hr_equiv');
    end
    ctx.hbf('unit_hr_equiv: all checks passed bit-identically');
end

% =========================================================================
function rep = unit_hr_report(ctx, out_hr, equiv_res, gate_open)
    ctx.hbf('unit_hr_report: writing REPORT_hr1.txt');

    rep_file = fullfile(out_hr, 'REPORT_hr1.txt');
    fid = fopen(rep_file, 'w');
    if fid < 0
        error('stage_hr1:report_file', 'Could not open %s for writing', rep_file);
    end

    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'REPORT_hr1.txt -- Plan 4 Tooling: Instrumented Headroom Evaluator Verification\n');
    fprintf(fid, 'Generated: %s | MATLAB %s\n', datestr(now, 31), version);
    fprintf(fid, '================================================================================\n\n');

    fprintf(fid, '1. TASK B SCOPE & STATUS\n');
    fprintf(fid, '------------------------\n');
    fprintf(fid, 'Evaluator:       Optimized/v17/headroom/hr_instrument_v17.m\n');
    fprintf(fid, 'Core harness:    Optimized/v17/headroom/evalPolicy_v17_hr.m\n');
    fprintf(fid, 'Cases tested:    M1_dl_rtt8, M3_gp_rtt8\n');
    fprintf(fid, 'Schemes tested:  Fixed, Context table, Context-joint-500, M1, NR2\n');
    fprintf(fid, 'Traces tested:   %d calibration traces (seeds 60001+)\n', equiv_res.n_traces);
    fprintf(fid, 'Bit-identity:    ALL PASSED (max abs diff = 0, isequal = 1)\n');
    fprintf(fid, 'p_success match: ALL PASSED (max abs diff vs 1-bler1 = 0)\n');
    fprintf(fid, 'Gate status:     %s\n\n', ternary(gate_open, 'OPEN', 'GATED (Amendment 7 pending)'));

    fprintf(fid, '2. BIT-IDENTITY VERIFICATION (hr_equiv.txt)\n');
    fprintf(fid, '------------------------------------------\n');
    for i = 1:numel(equiv_res.equiv_lines)
        fprintf(fid, '%s\n', equiv_res.equiv_lines{i});
    end
    fprintf(fid, '\n');

    fprintf(fid, '3. TIMING & PROJECTED COMPUTE COST\n');
    fprintf(fid, '-----------------------------------\n');
    fn = fieldnames(equiv_res.results);
    tot_s = 0;
    tot_dec = 0;
    for k = 1:numel(fn)
        r = equiv_res.results.(fn{k});
        fprintf(fid, '%-12s | %-18s | %5d decisions | %.2f s (%.4f s/trace) | max_diff=%.1e\n', ...
            r.case, r.scheme, r.total_decisions, r.elapsed_s, r.sec_per_trace, r.max_abs_tp);
        tot_s = tot_s + r.elapsed_s;
        tot_dec = tot_dec + r.total_decisions;
    end
    sec_per_trace_all = tot_s / equiv_res.n_traces;
    proj_500_s = sec_per_trace_all * 500;
    fprintf(fid, '\nTotal measured time:    %.2f s for %d traces across all %d evaluations\n', ...
        tot_s, equiv_res.n_traces, numel(fn));
    fprintf(fid, 'Per-trace timing:       %.3f s/trace (all cases x schemes)\n', sec_per_trace_all);
    fprintf(fid, 'Projected 500-trace:    %.1f s (%.2f hours / ~%.1f minutes)\n\n', ...
        proj_500_s, proj_500_s / 3600, proj_500_s / 60);

    fprintf(fid, '4. GATED STATUS NOTE (Task B4)\n');
    fprintf(fid, '------------------------------\n');
    fprintf(fid, 'No evaluation trace has been touched or modified.\n');
    fprintf(fid, 'Estimation pass (gradient-boosted trees) is gated until Amendment 7 is frozen.\n');
    fclose(fid);

    ctx.hbf(sprintf('REPORT_hr1.txt written: %s', rep_file));
    rep = struct('file', rep_file, 'sec_per_trace_all', sec_per_trace_all, 'proj_500_hours', proj_500_s / 3600);
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
