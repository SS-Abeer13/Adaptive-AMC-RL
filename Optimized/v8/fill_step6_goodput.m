% fill_step6_goodput  Completes the primary set-up with a pure goodput reward
% (lambda_retx = lambda_drop = 0): analysis of the goodput headline, state
% ablation (Tier-B, Tier-A) and the steady-state point.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v8 = fullfile(root, 'Optimized', 'v8');
addpath(v8); addpath(fullfile(root, 'Optimized', 'v7'));
addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
logf = fullfile(v8, 'logs', 'fill_step6.log');
diary off; if exist(logf, 'file'), delete(logf); end
diary(logf);
ds = fullfile(v8, 'Dataset');
sumf = fullfile(ds, 'fill_summary_goodput.txt');
fid = fopen(sumf, 'w');
fprintf(fid, 'STEP6 started %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
T0 = tic;
step = @(name) fprintf('\n######## %s | %s | elapsed %.1f min ########\n', name, datestr(now, 'HH:MM:SS'), toc(T0)/60);
base = struct('N', 10, 'simTime', 200, 'ep_deep', 300, 'n_seeds', 10, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0);

step('G1 goodput headline analysis');
try
    f = fullfile(ds, 'results_v8_final_headline_O_goodput.mat');
    fill_stats_v8(f, 'gp_O', fid);
    fill_actions_sweep_v8(f, 'gp_O', fid, 30, [0.1 0.2 0.3 0.4 0.5]);
    fill_sanity2_v8(f, 'gp_O', fid);
catch ME, fprintf(fid, 'ERROR|gp_O|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');

for tier = {'B', 'A'}
    tg = ['gp_' tier{1}];
    step(['G2 ' tg]);
    try
        o = base; o.state_tier = tier{1}; o.save_tag = ['final_headline_' tier{1} '_goodput'];
        runComparison_v8(o);
        f = fullfile(ds, ['results_v8_final_headline_' tier{1} '_goodput.mat']);
        fill_stats_v8(f, tg, fid);
        fill_actions_sweep_v8(f, tg, fid, 30, []);
    catch ME, fprintf(fid, 'ERROR|%s|%s\n', tg, ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
    fclose(fid); fid = fopen(sumf, 'a');
end

step('G3 steady1000 goodput');
try
    o = base; o.save_tag = 'final_steady1000_O_goodput';
    o.simTime = 1000; o.ep_deep = 150; o.n_seeds = 5; o.olla_warm_ttis = 1000;
    runComparison_v8(o);
    fill_stats_v8(fullfile(ds, 'results_v8_final_steady1000_O_goodput.mat'), 'gp_steady', fid);
catch ME, fprintf(fid, 'ERROR|gp_steady|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fprintf(fid, '\nSTEP6 finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
step('ALL DONE');
diary off;
