function cfg = v17x_cfg()
% v17x_cfg  Runner configuration for the Checkpoint-5 stages. Environment
% variables override the defaults (set in run_v17x_all.bat):
%   STAGES        comma list, default all in the approved order
%   N_WORKERS     parfor workers (default 2: 4 ran out of memory in v17 M1)
%   G6B_PROFILE   full (default) | lite   (frozen G6 pre-registration, section 2.4)
%   G10_CELLS     comma list, default G1_lo_d10,G2_hi_d10,G3_lo_d18,G4_hi_d18
%   V17X_SELFTEST 1 | 2 | 3   dummy stages: 1 restart+checkpoints, 2 halt on repeated failure, 3 the 1.5x pause rule
%   V17X_NO_POOL  1 = do not open a parpool (self-test, Octave)
%   V17X_SMOKE    1 = tiny sizes, separate folders Dataset_smoke / logs_smoke; stages read ctx.smoke
    here = fileparts(mfilename('fullpath'));
    cfg.root    = here;
    cfg.v17     = fullfile(fileparts(here), 'v17');
    cfg.outdir  = fullfile(here, 'Dataset');
    cfg.ckptdir = fullfile(here, 'Dataset', 'ckpt');
    cfg.logdir  = fullfile(here, 'logs');
    cfg.n_workers     = envnum('N_WORKERS', 2);
    cfg.pause_factor  = 1.5;              % common_rules.md R5
    cfg.max_attempts  = 2;                % common_rules.md R6
    cfg.hb_period_s   = 30;
    cfg.basis = struct('eval', 0.095, 'episode', 0.14);   % s per unit, compute_basis.md
    cfg.g6b_profile = lower(envstr('G6B_PROFILE', 'full'));
    cfg.g10_cells   = strsplit(envstr('G10_CELLS', 'G1_lo_d10,G2_hi_d10,G3_lo_d18,G4_hi_d18'), ',');
    cfg.use_pool    = ~strcmp(envstr('V17X_NO_POOL', '0'), '1');
    st = envstr('V17X_SELFTEST', '0');
    cfg.selftest = st;
    cfg.smoke = strcmp(envstr('V17X_SMOKE', '0'), '1');
    if strcmp(st, '1')
        cfg.stages = {'st_ok', 'st_crash_once', 'st_ok2'};
    elseif strcmp(st, '2')
        cfg.stages = {'st_ok', 'st_fail_always'};
    elseif strcmp(st, '3')
        cfg.stages = {'st_slow'};
    else
        allst = {'g1', 'w1', 'g6a', 'g6b', 'g6c', 'nr1', 'g10', 'a1', 'a3'};   % approved order
        req = strtrim(strsplit(envstr('STAGES', strjoin(allst, ',')), ','));
        cfg.stages = req(ismember(req, allst));
    end
    if cfg.smoke
        cfg.outdir  = fullfile(here, 'Dataset_smoke');
        cfg.ckptdir = fullfile(here, 'Dataset_smoke', 'ckpt');
        cfg.logdir  = fullfile(here, 'logs_smoke');
    end
    if any(strcmp(st, {'1', '2', '3'}))
        cfg.outdir  = fullfile(here, 'Dataset_selftest');
        cfg.ckptdir = fullfile(here, 'Dataset_selftest', 'ckpt');
        cfg.logdir  = fullfile(here, 'logs_selftest');
    end
end

function s = envstr(name, default)
    s = getenv(name);
    if isempty(s), s = default; end
end

function v = envnum(name, default)
    s = getenv(name);
    if isempty(s), v = default; else, v = str2double(s); end
    if isnan(v), v = default; end
end
