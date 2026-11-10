function stage_nr_g10_report(ctx)
% stage_nr_g10_report  Descriptive report for NR-G10 operating grid.
    f_rep = fullfile(ctx.outdir, 'REPORT_nr_g10.txt');
    f_csv = fullfile(ctx.outdir, 'table_cells_nr.csv');
    f_sum = fullfile(ctx.outdir, 'fill_summary_v17nr_grid.txt');
    
    repF = fopen(f_rep, 'w');
    fprintf(repF, 'REPORT NR-G10: Non-Oracle Operating Grid (%s)\n', datestr(now, 31));
    if exist(f_csv, 'file')
        fprintf(repF, '\n--- Evaluation Results Table ---\n%s\n', fileread(f_csv));
    end
    if exist(f_sum, 'file')
        fprintf(repF, '\n--- Cell Summary ---\n%s\n', fileread(f_sum));
    end
    fclose(repF);
end
