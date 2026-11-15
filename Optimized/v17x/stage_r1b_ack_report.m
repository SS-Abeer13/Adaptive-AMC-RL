function stage_r1b_ack_report(ctx)
% stage_r1b_ack_report  R9 descriptive report for stage r1b_ack.
    rep_file = fullfile(ctx.outdir, 'REPORT_r1b_ack.txt');
    if exist(rep_file, 'file')
        ctx.hbf(sprintf('stage_r1b_ack_report: report present at %s', rep_file));
    end
end
