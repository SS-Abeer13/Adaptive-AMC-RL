function v17x_status(cfg, headline)
% v17x_status  Rewrite Dataset/STATUS.txt from the marker files. A stage is
% done / paused / error / pending. FINISHED appears only when every requested
% stage has a done marker and no error marker exists.
    if ~exist(cfg.outdir, 'dir'), mkdir(cfg.outdir); end
    L = {};
    nDone = 0;
    for k = 1:numel(cfg.stages)
        id = cfg.stages{k};
        if exist(fullfile(cfg.outdir, ['stage_' id '.done']), 'file'), s = 'done'; nDone = nDone + 1;
        elseif exist(fullfile(cfg.outdir, ['ERROR_' id '.txt']), 'file'), s = 'ERROR (see ERROR file)';
        elseif exist(fullfile(cfg.outdir, ['PAUSED_' id '.txt']), 'file'), s = 'PAUSED (create APPROVE file to continue)';
        else, s = 'pending';
        end
        L{end+1} = sprintf('%-10s %s', id, s); %#ok<AGROW>
    end
    if nargin < 2, headline = 'running'; end
    if nDone == numel(cfg.stages) && ~exist(fullfile(cfg.outdir, 'HALTED.marker'), 'file') && numel(cfg.stages) > 0
        headline = 'FINISHED';
    end
    fid = fopen(fullfile(cfg.outdir, 'STATUS.txt'), 'w');
    fprintf(fid, '%s | %s\n', datestr(now, 31), headline);
    fprintf(fid, '%s\n', L{:});
    fclose(fid);
end
