function stage_g6a_report(ctx)
% stage_g6a_report  Descriptive report for G6a (calibration-set information only).
% Spec: paper/proposals/G6_calibration_budget_prereg.md §2.5
    f_single = fullfile(ctx.outdir, 'cal500_single.txt');
    f_comp   = fullfile(ctx.outdir, 'composite_table.csv');
    f_rep    = fullfile(ctx.outdir, 'REPORT_g6a.txt');
    
    repF = fopen(f_rep, 'w');
    fprintf(repF, 'REPORT G6a: Calibration Budget Re-calibration (%s)\n', datestr(now, 31));
    fprintf(repF, 'Scope: Calibration-set information only (500 traces 600001-600500, CRN 610001+).\n\n');
    
    if exist(f_single, 'file')
        txt = fileread(f_single);
        fprintf(repF, '--- Single-cue rules summary ---\n%s\n', txt);
    end
    
    if exist(f_comp, 'file')
        fprintf(repF, '--- Composite table ---\nWritten to: %s\n\n', f_comp);
    end
    
    fprintf(repF, '--- Projected g6b time ---\n');
    fprintf(repF, 'Profile: full (4 starts x sweeps to convergence, cap 6 sweeps per start).\n');
    fprintf(repF, 'Expected evaluations: ~1.3M evaluations (approx 34 h on 2 workers).\n');
    fclose(repF);
end
