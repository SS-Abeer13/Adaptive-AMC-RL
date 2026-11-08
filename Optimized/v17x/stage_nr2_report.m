function stage_nr2_report(ctx)
% stage_nr2_report  Descriptive report for NR2 (calibration & REPRO info).
    f_rep = fullfile(ctx.outdir, 'REPORT_nr2.txt');
    f_sum = fullfile(ctx.outdir, 'fill_summary_v17nr2.txt');
    f_tab = fullfile(ctx.outdir, 'table_nr2.csv');
    
    fid = fopen(f_rep, 'w');
    if fid == -1, return; end
    fprintf(fid, 'REPORT NR2: Confirmatory Replication (%s)\n', datestr(now, 31));
    if exist(f_sum, 'file')
        fprintf(fid, '\n--- Summary ---\n%s\n', fileread(f_sum));
    end
    if exist(f_tab, 'file')
        fprintf(fid, '\n--- Trace-Level Results ---\n%s\n', fileread(f_tab));
    end
    fclose(fid);
end
