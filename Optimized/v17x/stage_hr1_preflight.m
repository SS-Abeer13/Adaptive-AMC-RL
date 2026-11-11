function pf = stage_hr1_preflight(ctx)
% stage_hr1_preflight  Preflight timing for Plan 4 headroom instrumented evaluator.
% Times 2 evaluation traces per run across cases and schemes using hr_instrument_v17.

    addpath(ctx.v17);
    addpath(fullfile(ctx.v17, 'headroom'));
    addpath(fullfile(ctx.root, 'g6'));
    addpath(fullfile(ctx.root, 'nr1'));
    v17_setup;

    cases = {'M1_dl_rtt8', 'M3_gp_rtt8'};
    schemes = {'Fixed', 'Context table', 'Context-joint-500', 'M1', 'NR2'};

    nT = 2;
    opts = struct();
    opts.smoke = true;
    opts.eval_mode = true;
    opts.do_equiv = true;
    opts.save_logs = false;
    opts.skip_existing = false;
    opts.seeds = 1:10;
    opts.hbf = @(msg) ctx.hbf(['preflight: ' msg]);

    t0 = tic;
    out = hr_instrument_v17(cases, schemes, nT, opts);
    total_elapsed = toc(t0);

    % Total evaluation units in preflight:
    % Table runs: 6 runs x 2 traces = 12
    % Learned runs: 3 runs x 10 seeds x 2 traces = 60
    % Total = 72 trace-evals
    total_eval_units_pf = 72;
    sec_per_eval = total_elapsed / total_eval_units_pf;

    % Basis per-eval from REPORT_hr1.txt section 4:
    % (0.3835 + 0.2897 + 0.3776 + 10*0.6252 + 10*0.5196 + 0.2624 + 0.2378 + 0.3247 + 10*0.6128) / 36 = 0.5403 s
    basis_per_eval = 0.5403;

    n_units_full = 36 * 500; % 18000 units
    n_units = ternary(ctx.smoke, total_eval_units_pf, n_units_full);

    pf = struct( ...
        'unit', 'eval', ...
        'sec_per_unit', sec_per_eval, ...
        'basis', basis_per_eval, ...
        'n_units_total', n_units, ...
        'proj_500_hours', (sec_per_eval * n_units_full) / 3600, ...
        'note', sprintf('HR1 preflight: %.4f s/eval (basis %.4f s), projected %.2f h for 18000 units (500 traces)', ...
                        sec_per_eval, basis_per_eval, (sec_per_eval * n_units_full) / 3600) ...
    );
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
