function v17x_reset(stage)
% v17x_reset  Clear the error state of one stage so the runner can retry it
% after you fixed the cause:  v17x_reset('w1')
% Removes HALTED.marker, ERROR_<stage>.txt, attempts_<stage>.txt and PAUSED_<stage>.txt.
% Does NOT touch checkpoints or done markers (completed work stays skipped).
    cfg = v17x_cfg();
    for f = {'HALTED.marker', ['ERROR_' stage '.txt'], ['attempts_' stage '.txt'], ['PAUSED_' stage '.txt'], 'ERROR_runner.txt'}
        p = fullfile(cfg.outdir, f{1});
        if exist(p, 'file'), delete(p); fprintf('removed %s\n', p); end
    end
end
