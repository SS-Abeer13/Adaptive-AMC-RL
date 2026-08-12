function run_v7_point(preset, val)
% run_v7_point  Run one v7 experiment, headless, resumable, logged.
%   matlab -batch "run_v7_point('headline')"
    if nargin < 1 || isempty(preset), preset = 'smoke'; end
    if nargin < 2, val = []; end

    here = fileparts(mfilename('fullpath'));
    cd(here);
    addpath(fullfile(here, '..', 'v5'));
    addpath(fullfile(here, '..', 'case2_3'));
    if ~exist(fullfile(here,'logs'), 'dir'), mkdir(fullfile(here,'logs')); end
    logfile = fullfile(here, 'logs', 'v7_master_log.txt');
    diary(logfile); diary on;

    o = struct('n_seeds',5, 'n_eval',30, 'ep_tab',300, 'ep_deep',500);
    switch lower(preset)
        case 'smoke'
            o.n_seeds = 1; o.n_eval = 3; o.ep_tab = 40; o.ep_deep = 40;
            o.n_calib = 2; o.tag = 'smoke';
        case 'phase0'
            o.hetero = 0; o.burst_on = 0; o.speed_switch = 0;
            o.tag = 'phase0_calm';
        case 'hetero'
            if isempty(val), val = 1; end
            o.hetero = val; o.burst_on = 0; o.speed_switch = 1;
            o.tag = sprintf('hetero%03d', round(100*val));
        case 'burst'
            if isempty(val), val = 9; end
            o.hetero = 1; o.burst_on = 1; o.burst_IM_dB = val; o.speed_switch = 1;
            o.tag = sprintf('burst%02ddB', round(val));
        case 'headline'
            o.hetero = 1; o.burst_on = 1; o.burst_IM_dB = 9; o.speed_switch = 1;
            o.tag = 'headline';
        case 'tiera'
            o.hetero = 1; o.burst_on = 1; o.burst_IM_dB = 9; o.speed_switch = 1;
            o.state_tier = 'A'; o.tag = 'headline_tierA';
        case 'warm'
            o.hetero = 1; o.burst_on = 1; o.burst_IM_dB = 9; o.speed_switch = 1;
            o.olla_warm_ttis = 1000; o.tag = 'headline_warm1000';
        case 'replicate'
            o.hetero = 1; o.burst_on = 1; o.burst_IM_dB = 9; o.speed_switch = 1;
            o.base_seed = 10042; o.trace_seed_base = 19000; o.tag = 'headline_fresh';
        case 'tier1'
            o.hetero = 1; o.burst_on = 1; o.burst_IM_dB = 9; o.speed_switch = 1;
            o.train_sched_weights = [1 0 0];
            o.bc_warm_eps = 150;
            o.tag = 'headline_tier1';
        case 'tier1nobc'
            o.hetero = 1; o.burst_on = 1; o.burst_IM_dB = 9; o.speed_switch = 1;
            o.train_sched_weights = [1 0 0];
            o.bc_warm_eps = 0;
            o.actions = -5:3;
            o.tag = 'headline_tier1_nobc';
        case 'tier1b'
            o.hetero = 1; o.burst_on = 1; o.burst_IM_dB = 9; o.speed_switch = 1;
            o.train_sched_weights = [1 0 0];
            o.bc_warm_eps = 150;
            o.actions = -5:3;
            o.tag = 'headline_tier1b';
        case 'tier1rep'
            o.hetero = 1; o.burst_on = 1; o.burst_IM_dB = 9; o.speed_switch = 1;
            o.train_sched_weights = [1 0 0];
            o.bc_warm_eps = 150;
            o.actions = -5:3;
            o.base_seed = 10042; o.trace_seed_base = 19000;
            o.tag = 'headline_tier1b_fresh';
        otherwise
            error('run_v7_point: unknown preset "%s"', preset);
    end

    fprintf('\n##### v7 POINT "%s" [pid %d] started %s #####\n', ...
            o.tag, feature('getpid'), datestr(now,'yyyy-mm-dd HH:MM:SS'));

    hit = dir(fullfile(here, 'Dataset', sprintf('results_v7_%s.mat', o.tag)));
    if ~isempty(hit)
        fprintf('##### SKIP: results_v7_%s.mat exists - point already complete #####\n', o.tag);
        diary off; return;
    end

    t0 = tic;
    try
        runComparison_v7(o);
        fprintf('##### v7 POINT "%s" COMPLETE (%.2f h) #####\n', o.tag, toc(t0)/3600);
    catch ME
        fprintf(2, '\n!!! v7 POINT "%s" FAILED after %.2f h: %s\n%s\n', ...
                o.tag, toc(t0)/3600, ME.identifier, getReport(ME, 'extended'));
    end
    diary off;
end
