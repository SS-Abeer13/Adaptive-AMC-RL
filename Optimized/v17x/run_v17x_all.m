function run_v17x_all()
% run_v17x_all  Orchestrates the Checkpoint-5 stages in the approved order
% (G1 -> W1 -> G6a/b/c -> NR1 -> G10 -> A1/A3). Called by run_v17x_all.bat,
% which restarts MATLAB after a crash; every stage and every unit inside a stage
% is checkpointed, so a restart skips completed work.
%
% Rules implemented (paper/proposals/common_rules.md):
%   R5  20-trace preflight per stage; if the measured seconds per unit exceed
%       1.5x the basis the stage PAUSES (PAUSED_<stage>.txt, exit 3) until the
%       author creates APPROVE_<stage>.txt. A faster measured rate never pauses.
%   R6  A stage error writes ERROR_<stage>.txt and NO done marker. One retry
%       after a restart; a second failure writes HALTED.marker (exit 2). The
%       word FINISHED is written only when every requested stage is done.
%   R8  2 parfor workers.
% Exit codes: 0 finished | 1 recoverable error, restart me | 2 halted | 3 paused.
    cfg = v17x_cfg();
    addpath(cfg.root);          % v17_setup changes the working directory; keep the stage files reachable
    mk(cfg.outdir); mk(cfg.ckptdir); mk(cfg.logdir);
    hbf = @(stage, msg) v17x_hb(cfg, stage, msg, true);
    hbf('runner', sprintf('start (stages: %s; workers %d; G6B_PROFILE %s)', strjoin(cfg.stages, ','), cfg.n_workers, cfg.g6b_profile));

    if exist(fullfile(cfg.outdir, 'HALTED.marker'), 'file')
        hbf('runner', 'HALTED.marker present: fix the cause, delete HALTED.marker, ERROR_<stage>.txt and attempts_<stage>.txt, then rerun');
        v17x_status(cfg, 'HALTED');
        quit_(2);
    end
    if exist(fullfile(cfg.outdir, 'FINISHED_ALL.marker'), 'file') && all_done(cfg)
        hbf('runner', 'FINISHED_ALL.marker present and every stage done; nothing to do');
        quit_(0);
    end

    open_pool(cfg, hbf);

    for k = 1:numel(cfg.stages)
        id = cfg.stages{k};
        doneF = fullfile(cfg.outdir, ['stage_' id '.done']);
        if exist(doneF, 'file')
            hbf(id, 'already done, skipped');
            continue
        end
        ctx = make_ctx(cfg, id);
        v17x_status(cfg, ['running ' id]);

        % ---------- preflight (R5) ----------
        try
            pf = get_preflight(cfg, ctx, id, hbf);
        catch ME
            handle_error(cfg, id, ME, hbf);   % exits
            return
        end
        ratio = pf.sec_per_unit / cfg.basis.(pf.unit);
        proj_h = pf.sec_per_unit * pf.n_units_total / 3600;
        hbf(id, sprintf('preflight: %.4f s per %s (basis %.3f, ratio %.2f); projected %.1f h for %d units', ...
            pf.sec_per_unit, pf.unit, cfg.basis.(pf.unit), ratio, proj_h, pf.n_units_total));
        write_text(fullfile(cfg.outdir, ['PREFLIGHT_' id '.txt']), sprintf( ...
            '%s\nstage %s\nunit %s\nmeasured s/unit %.5f\nbasis s/unit %.5f\nratio %.3f (pause above %.2f)\nunits %d\nprojected hours %.2f\nnote: %s\n', ...
            datestr(now, 31), id, pf.unit, pf.sec_per_unit, cfg.basis.(pf.unit), ratio, cfg.pause_factor, pf.n_units_total, proj_h, pf.note));
        appr = fullfile(cfg.outdir, ['APPROVE_' id '.txt']);
        if ratio > cfg.pause_factor
            if ~exist(appr, 'file')
                write_text(fullfile(cfg.outdir, ['PAUSED_' id '.txt']), sprintf( ...
                    ['Stage %s paused by the 1.5x rule (common_rules.md R5).\nMeasured %.4f s per %s, basis %.3f s (ratio %.2f). Projected %.1f h.\n' ...
                     'To continue, create an empty file named APPROVE_%s.txt in this folder and rerun run_v17x_all.bat.\n'], ...
                    id, pf.sec_per_unit, pf.unit, cfg.basis.(pf.unit), ratio, proj_h, id));
                hbf(id, 'PAUSED by the 1.5x rule; waiting for APPROVE file');
                v17x_status(cfg, 'PAUSED');
                quit_(3);
            else
                hbf(id, 'APPROVE file found: continuing despite the 1.5x rule');
                delete_if(fullfile(cfg.outdir, ['PAUSED_' id '.txt']));
            end
        end

        % ---------- run the stage ----------
        t0 = tic;
        try
            hbf(id, 'stage start');
            feval(['stage_' id], ctx);
            write_text(doneF, sprintf('%s\nelapsed %.1f s\n', datestr(now, 31), toc(t0)));
            delete_if(fullfile(cfg.outdir, ['ERROR_' id '.txt']));
            hbf(id, sprintf('stage DONE in %.2f h', toc(t0) / 3600));
        catch ME
            handle_error(cfg, id, ME, hbf);   % exits
            return
        end
    end

    if all_done(cfg)
        write_text(fullfile(cfg.outdir, 'FINISHED_ALL.marker'), [datestr(now, 31) '\n']);
        hbf('runner', 'ALL REQUESTED STAGES FINISHED');
        v17x_status(cfg, 'FINISHED');
        close_pool(cfg);
        quit_(0);
    else
        hbf('runner', 'not every stage is done; not writing a finished marker');
        v17x_status(cfg, 'INCOMPLETE');
        quit_(1);
    end
end

% ======================================================================
function ctx = make_ctx(cfg, id)
    ctx.cfg = cfg;
    ctx.stage = id;
    ctx.root = cfg.root; ctx.v17 = cfg.v17;
    ctx.outdir = cfg.outdir; ctx.ckptdir = cfg.ckptdir; ctx.logdir = cfg.logdir;
    ctx.n_workers = cfg.n_workers;
    ctx.smoke = cfg.smoke;
    ctx.g6b_profile = cfg.g6b_profile;
    ctx.g10_cells = cfg.g10_cells;
    ctx.hb  = @(msg) v17x_hb(cfg, id, msg, false);   % throttled
    ctx.hbf = @(msg) v17x_hb(cfg, id, msg, true);    % always written
    ctx.unit = [];                                    % set below (needs ctx itself)
    ctx.unit = @(name, fcn) v17x_unit(ctx_for_unit(cfg, id), name, fcn);
end

function c = ctx_for_unit(cfg, id)
    c.stage = id; c.ckptdir = cfg.ckptdir;
    c.hbf = @(msg) v17x_hb(cfg, id, msg, true);
end

function pf = get_preflight(cfg, ctx, id, hbf)
    f = fullfile(cfg.ckptdir, ['preflight_' id '.mat']);
    if exist(f, 'file')
        S = load(f); pf = S.pf; return
    end
    hbf(id, 'preflight start (20 traces)');
    pf = feval(['stage_' id '_preflight'], ctx);
    need = {'unit', 'sec_per_unit', 'n_units_total', 'note'};
    for q = 1:numel(need)
        if ~isfield(pf, need{q}), error('v17x:preflight', 'preflight of %s lacks field %s', id, need{q}); end
    end
    if ~isfield(cfg.basis, pf.unit), error('v17x:preflight', 'unknown unit "%s"', pf.unit); end
    save(f, 'pf');
end

function handle_error(cfg, id, ME, hbf)
    msg = report_of(ME);
    notImpl = strcmp(ME.identifier, 'v17x:notImplemented');
    af = fullfile(cfg.outdir, ['attempts_' id '.txt']);
    n = 0;
    if exist(af, 'file'), n = str2double(strtrim(fileread(af))); if isnan(n), n = 0; end, end
    n = n + 1;
    write_text(af, sprintf('%d\n', n));
    write_text(fullfile(cfg.outdir, ['ERROR_' id '.txt']), sprintf('%s\nstage %s attempt %d\n%s\n', datestr(now, 31), id, n, msg));
    hbf(id, sprintf('ERROR (attempt %d): %s', n, strtok(msg, sprintf('\n'))));
    if notImpl || n >= cfg.max_attempts
        write_text(fullfile(cfg.outdir, 'HALTED.marker'), sprintf('%s\nstage %s failed (%s)\n', datestr(now, 31), id, ternary(notImpl, 'not implemented', 'second attempt')));
        hbf('runner', ['HALTED at stage ' id ' (no finished marker written)']);
        v17x_status(cfg, 'HALTED');
        quit_(2);
    else
        v17x_status(cfg, ['ERROR in ' id ', restarting']);
        quit_(1);
    end
end

function s = report_of(ME)
    try
        s = getReport(ME);
    catch
        s = ME.message;
        try
            for q = 1:min(numel(ME.stack), 10)
                s = sprintf('%s\n  at %s (line %d)', s, ME.stack(q).name, ME.stack(q).line);
            end
        catch
        end
    end
end

function tf = all_done(cfg)
    tf = numel(cfg.stages) > 0;
    for k = 1:numel(cfg.stages)
        tf = tf && exist(fullfile(cfg.outdir, ['stage_' cfg.stages{k} '.done']), 'file') == 2;
    end
    tf = tf && ~exist(fullfile(cfg.outdir, 'HALTED.marker'), 'file');
    for k = 1:numel(cfg.stages)
        tf = tf && ~exist(fullfile(cfg.outdir, ['ERROR_' cfg.stages{k} '.txt']), 'file');
    end
end

function open_pool(cfg, hbf)
    if ~cfg.use_pool, hbf('runner', 'no parpool (V17X_NO_POOL=1)'); return; end
    try
        p = gcp('nocreate');
        if ~isempty(p) && p.NumWorkers ~= cfg.n_workers, delete(p); p = []; end
        if isempty(p), parpool('local', cfg.n_workers); end
        hbf('runner', sprintf('parpool open with %d workers', cfg.n_workers));
    catch ME
        hbf('runner', ['parpool unavailable, continuing serial: ' ME.message]);
    end
end

function close_pool(cfg)
    if ~cfg.use_pool, return; end
    try, delete(gcp('nocreate')); catch, end
end

function mk(d)
    if ~exist(d, 'dir'), mkdir(d); end
end

function write_text(f, s)
    fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function delete_if(f)
    if exist(f, 'file'), delete(f); end
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end

function quit_(code)
    exit(code);
end
