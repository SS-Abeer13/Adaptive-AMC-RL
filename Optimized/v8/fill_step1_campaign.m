% fill_step1_campaign  Corrected v8 re-run that fills the Author 1 draft
% placeholders (R1-R9). Each point is wrapped in try/catch so one failure
% does not stop the others. Progress: logs/fill_step1.log
% Summary of all numbers: Dataset/fill_summary.txt
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v8 = fullfile(root, 'Optimized', 'v8');
addpath(v8); addpath(fullfile(root, 'Optimized', 'v7'));
addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
logf = fullfile(v8, 'logs', 'fill_step1.log');
diary off; if exist(logf, 'file'), delete(logf); end
diary(logf);
sumf = fullfile(v8, 'Dataset', 'fill_summary.txt');
fid = fopen(sumf, 'w');
fprintf(fid, 'FILL RUN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
T0 = tic;

base = struct();
base.N = 10; base.simTime = 200; base.ep_deep = 300;
base.n_seeds = 10; base.n_eval = 100; base.n_calib = 20;
base.eval_schedulers = {'pf'};
base.train_sched_weights = [1 0 0];   % train on the evaluated (PF) scheduler
base.olla_off_lim = 10;

ds = fullfile(v8, 'Dataset');
step = @(name) fprintf('\n######## %s | %s | elapsed %.1f min ########\n', name, datestr(now, 'HH:MM:SS'), toc(T0)/60);


% ---- P0 preflight of the new code paths (tiny sizes; results discarded) ----
step('P0 preflight');
pf = fopen(fullfile(v8, 'logs', 'fill_preflight.txt'), 'w');
try
    o = base; o.simTime = 60; o.ep_deep = 2; o.n_seeds = 1; o.n_eval = 3; o.n_calib = 1;
    o.state_tier = 'O'; o.save_tag = 'preflight_tierO';
    runComparison_v8(o);
    fill_stats_v8(fullfile(ds, 'results_v8_preflight_tierO.mat'), 'pre_tierO', pf);
    fill_actions_sweep_v8(fullfile(ds, 'results_v8_preflight_tierO.mat'), 'pre_tierO', pf, 1, [0.1]);
    fprintf(pf, 'PREFLIGHT_TIERO_OK\n');
catch ME, fprintf(pf, 'PREFLIGHT_TIERO_FAIL|%s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); end
try
    o = base; o.simTime = 60; o.n_calib = 1;
    fill_bc_diag_v8(o, 1, 2, 2, 3, pf);
    fprintf(pf, 'PREFLIGHT_BC_OK\n');
catch ME, fprintf(pf, 'PREFLIGHT_BC_FAIL|%s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(pf);

% ---- P1 headline (Tier-B) ----
step('P1 headline');
try
    o = base; o.save_tag = 'fill_headline';
    runComparison_v8(o);
    fill_stats_v8(fullfile(ds, 'results_v8_fill_headline.mat'), 'headline', fid);
catch ME, fprintf(fid, 'ERROR|headline|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

% ---- P1b actions + OLLA target sweep on headline ----
step('P1b actions + sweep');
try
    fill_actions_sweep_v8(fullfile(ds, 'results_v8_fill_headline.mat'), 'headline', fid, 30, [0.1 0.2 0.3 0.4 0.5]);
catch ME, fprintf(fid, 'ERROR|sweep|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

% ---- P2 Tier-A ----
step('P2 tierA');
try
    o = base; o.save_tag = 'fill_tierA'; o.state_tier = 'A';
    runComparison_v8(o);
    fill_stats_v8(fullfile(ds, 'results_v8_fill_tierA.mat'), 'tierA', fid);
catch ME, fprintf(fid, 'ERROR|tierA|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

% ---- P3 Tier-O (Tier-B without simulator-only features) ----
step('P3 tierO');
try
    o = base; o.save_tag = 'fill_tierO'; o.state_tier = 'O';
    runComparison_v8(o);
    fill_stats_v8(fullfile(ds, 'results_v8_fill_tierO.mat'), 'tierO', fid);
    fill_actions_sweep_v8(fullfile(ds, 'results_v8_fill_tierO.mat'), 'tierO', fid, 30, []);
catch ME, fprintf(fid, 'ERROR|tierO|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

% ---- P4 BC diagnostic ----
step('P4 BC diagnostic');
try
    fill_bc_diag_v8(base, 5, 150, 300, 100, fid);
catch ME, fprintf(fid, 'ERROR|bcdiag|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

% ---- P5 steady state (all schemes warmed 1000 TTIs, scored on 1000 TTIs) ----
step('P5 steady1000');
try
    o = base; o.save_tag = 'fill_steady1000';
    o.simTime = 1000; o.ep_deep = 150; o.n_seeds = 5; o.olla_warm_ttis = 1000;
    runComparison_v8(o);
    fill_stats_v8(fullfile(ds, 'results_v8_fill_steady1000.mat'), 'steady1000', fid);
catch ME, fprintf(fid, 'ERROR|steady|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

fprintf(fid, '\nFILL RUN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
step('ALL DONE');
diary off;
