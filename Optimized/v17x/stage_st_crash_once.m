function stage_st_crash_once(ctx)
% Self-test: unit A completes and is checkpointed; then the stage errors once
% (attempt 1). After the runner restarts, unit A must be skipped and the stage
% must succeed.
    ctx.unit('A', @() 1);
    flag = fullfile(ctx.outdir, 'st_crash_once.flag');
    if ~exist(flag, 'file')
        fid = fopen(flag, 'w'); fprintf(fid, 'crashed once\n'); fclose(fid);
        error('v17x:selftest', 'deliberate failure on the first attempt');
    end
    ctx.unit('B', @() 2);
end
