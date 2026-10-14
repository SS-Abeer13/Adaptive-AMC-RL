% fill_step4_final  Final corrected campaign for the Author 1 drafts.
% All schemes: PF scheduler ranks users on the OLLA reference rate
% (sched_on_ref = true); primary agent = observable Tier-O state.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v8 = fullfile(root, 'Optimized', 'v8');
addpath(v8); addpath(fullfile(root, 'Optimized', 'v7'));
addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
logf = fullfile(v8, 'logs', 'fill_step4.log');
diary off; if exist(logf, 'file'), delete(logf); end
diary(logf);
ds = fullfile(v8, 'Dataset');
sumf = fullfile(ds, 'fill_summary_final.txt');
fid = fopen(sumf, 'w');
fprintf(fid, 'FINAL started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
T0 = tic;
step = @(name) fprintf('\n######## %s | %s | elapsed %.1f min ########\n', name, datestr(now, 'HH:MM:SS'), toc(T0)/60);
base = struct('N', 10, 'simTime', 200, 'ep_deep', 300, 'n_seeds', 10, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O');

step('F1 headline Tier-O');
try
    o = base; o.save_tag = 'final_headline_O';
    runComparison_v8(o);
    f = fullfile(ds, 'results_v8_final_headline_O.mat');
    fill_stats_v8(f, 'final_O', fid);
    fill_actions_sweep_v8(f, 'final_O', fid, 30, [0.1 0.2 0.3 0.4 0.5]);
    fill_sanity2_v8(f, 'final_O', fid);
catch ME, fprintf(fid, 'ERROR|final_O|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

step('F2 Tier-B (simulator-only features)');
try
    o = base; o.state_tier = 'B'; o.save_tag = 'final_headline_B';
    runComparison_v8(o);
    f = fullfile(ds, 'results_v8_final_headline_B.mat');
    fill_stats_v8(f, 'final_B', fid);
    fill_actions_sweep_v8(f, 'final_B', fid, 30, []);
catch ME, fprintf(fid, 'ERROR|final_B|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

step('F3 Tier-A');
try
    o = base; o.state_tier = 'A'; o.save_tag = 'final_headline_A';
    runComparison_v8(o);
    f = fullfile(ds, 'results_v8_final_headline_A.mat');
    fill_stats_v8(f, 'final_A', fid);
    fill_actions_sweep_v8(f, 'final_A', fid, 30, []);
catch ME, fprintf(fid, 'ERROR|final_A|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

step('F4 BC diagnostic');
try
    fill_bc_diag_v8(base, 5, 150, 300, 100, fid);
catch ME, fprintf(fid, 'ERROR|bcdiag|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

step('F5 steady1000 Tier-O');
try
    o = base; o.save_tag = 'final_steady1000_O';
    o.simTime = 1000; o.ep_deep = 150; o.n_seeds = 5; o.olla_warm_ttis = 1000;
    runComparison_v8(o);
    fill_stats_v8(fullfile(ds, 'results_v8_final_steady1000_O.mat'), 'final_steady', fid);
catch ME, fprintf(fid, 'ERROR|final_steady|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end

fprintf(fid, '\nFINAL finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
step('ALL DONE');
diary off;
