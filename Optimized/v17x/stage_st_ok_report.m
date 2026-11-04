function stage_st_ok_report(ctx)
% Self-test: a report that works.
    fid = fopen(fullfile(ctx.outdir, 'REPORT_st_ok.txt'), 'w'); fprintf(fid, 'descriptive report for st_ok\n'); fclose(fid);
end
