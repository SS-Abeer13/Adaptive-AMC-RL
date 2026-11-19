function stage_eot_report(ctx)
% stage_eot_report  Report generation for stage eot.
    rep_file = fullfile(ctx.outdir, 'eot', 'eot_summary.txt');
    if exist(rep_file, 'file')
        ctx.hbf(sprintf('stage_eot_report: summary present at %s', rep_file));
    end
end
