function pf = stage_hr1_preflight(ctx)
% stage_hr1_preflight  Preflight timing for Plan 4 headroom instrumented evaluator.
% Times 2 traces across cases and schemes using hr_instrument_v17.

    addpath(ctx.v17);
    addpath(fullfile(ctx.v17, 'headroom'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    v17_setup;

    cases = {'M1_dl_rtt8', 'M3_gp_rtt8'};
    schemes = {'Fixed', 'Context table', 'Context-joint-500', 'M1', 'NR2'};

    nT = 2;
    trace_set = struct('n_traces', nT, 'trace_seed_base', 60000, 'crn_seed_base', 62000);

    opts = struct();
    opts.smoke = true;
    opts.do_equiv = true;
    opts.save_logs = false;
    opts.hbf = @(msg) ctx.hbf(['preflight: ' msg]);

    t0 = tic;
    out = hr_instrument_v17(cases, schemes, trace_set, opts);
    total_elapsed = toc(t0);

    % Total scheme-case evaluations in preflight:
    % M1: 5 schemes, M3: 4 schemes -> 9 evaluations per trace
    n_eval_pairs = numel(out.equiv_lines);
    total_trace_evals = nT * n_eval_pairs;
    sec_per_eval = total_elapsed / total_trace_evals;
    sec_per_trace_all = total_elapsed / nT;

    % Projected units: in smoke mode, 2 traces x 9 evals = 18 units; full pass = 500 x 9 = 4500 units
    n_units_full = 500 * n_eval_pairs;
    n_units = ternary(ctx.smoke, total_trace_evals, n_units_full);

    pf = struct( ...
        'unit', 'eval', ...
        'sec_per_unit', sec_per_eval, ...
        'basis', max(sec_per_eval, 0.20), ...
        'n_units_total', n_units, ...
        'sec_per_trace_all_schemes', sec_per_trace_all, ...
        'proj_500_hours', (sec_per_trace_all * 500) / 3600, ...
        'note', sprintf('HR1 headroom preflight (%.3f s/eval, %.3f s/trace all schemes, 500 traces = %.2f h)', ...
                        sec_per_eval, sec_per_trace_all, (sec_per_trace_all * 500) / 3600) ...
    );
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
