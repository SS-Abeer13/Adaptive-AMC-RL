function out = v17x_unit(ctx, name, fcn)
% v17x_unit  Run fcn() once and checkpoint its result. If the checkpoint
% exists (from an earlier run or before a restart) it is loaded and fcn is NOT
% called. The checkpoint is written atomically (temp file, then move), so a
% crash during the save never leaves a half-written file that counts as done.
%   out = v17x_unit(ctx, 'seed3', @() train_one_seed(3));
% name: letters, digits, underscore, minus. fcn: no inputs, one output.
    d = fullfile(ctx.ckptdir, ctx.stage);
    if ~exist(d, 'dir'), mkdir(d); end
    f = fullfile(d, [name '.mat']);
    if exist(f, 'file')
        try
            S = load(f, 'out');
            out = S.out;
            ctx.hbf(['unit ' name ': loaded checkpoint, skipped']);
            return
        catch
            ctx.hbf(['unit ' name ': checkpoint unreadable, recomputing']);
            delete(f);
        end
    end
    t0 = tic;
    ctx.hbf(['unit ' name ': start']);
    out = fcn();
    tmp = [f '.part'];
    if exist('OCTAVE_VERSION', 'builtin'), save('-v7', tmp, 'out'); else, save(tmp, 'out', '-v7.3'); end
    movefile(tmp, f, 'f');
    ctx.hbf(sprintf('unit %s: done in %.1f s', name, toc(t0)));
end
