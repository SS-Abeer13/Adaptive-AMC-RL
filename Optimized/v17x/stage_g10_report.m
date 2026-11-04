function stage_g10_report(ctx)
% stage_g10_report  Descriptive report for G10 operating grid.
    f_rep = fullfile(ctx.outdir, 'REPORT_g10.txt');
    f_base = fullfile(ctx.outdir, 'base_rule_by_cell.csv');
    f_sum = fullfile(ctx.outdir, 'fill_summary_v17c.txt');
    
    repF = fopen(f_rep, 'w');
    fprintf(repF, 'REPORT G10: Operating Grid (%s)\n', datestr(now, 31));
    if exist(f_base, 'file')
        fprintf(repF, '\n--- Base Rule by Cell ---\n%s\n', fileread(f_base));
    end
    if exist(f_sum, 'file')
        fprintf(repF, '\n--- Cell Summary ---\n%s\n', fileread(f_sum));
    end
    fclose(repF);
end
