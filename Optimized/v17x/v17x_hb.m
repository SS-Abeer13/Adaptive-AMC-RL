function v17x_hb(cfg, stage, msg, force)
% v17x_hb  Append a heartbeat line to logs/heartbeat_v17x.txt. Throttled to one
% line per cfg.hb_period_s unless force is true. Call from the client only
% (never inside parfor); long stage loops call it between chunks.
    persistent last
    if isempty(last), last = 0; end
    t = now * 86400;
    if nargin < 4, force = false; end
    if ~force && (t - last) < cfg.hb_period_s, return; end
    last = t;
    if ~exist(cfg.logdir, 'dir'), mkdir(cfg.logdir); end
    fid = fopen(fullfile(cfg.logdir, 'heartbeat_v17x.txt'), 'a');
    if fid < 0, return; end
    fprintf(fid, '%s | %-14s | %s\n', datestr(now, 31), stage, msg);
    fclose(fid);
end
