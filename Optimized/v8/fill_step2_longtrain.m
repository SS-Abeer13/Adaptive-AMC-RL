% fill_step2_longtrain  Is the headline A2C deficit an under-training artefact?
% Same headline configuration, 5x the training budget (1500 episodes), 3 seeds,
% for the observable Tier-O state and the full Tier-B state.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v8 = fullfile(root, 'Optimized', 'v8');
addpath(v8); addpath(fullfile(root, 'Optimized', 'v7'));
addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
logf = fullfile(v8, 'logs', 'fill_step2.log');
diary off; if exist(logf, 'file'), delete(logf); end
diary(logf);
ds = fullfile(v8, 'Dataset');
fid = fopen(fullfile(ds, 'fill_summary_step2.txt'), 'w');
fprintf(fid, 'STEP2 started %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
base = struct('N', 10, 'simTime', 200, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10);
try
    fill_sanity_v8(ds, fid);
catch ME, fprintf(fid, 'ERROR|sanity|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(fullfile(ds, 'fill_summary_step2.txt'), 'a');

for tier = {'O', 'B'}
    tg = ['long1500_tier' tier{1}];
    try
        o = base; o.ep_deep = 1500; o.n_seeds = 3; o.state_tier = tier{1}; o.save_tag = ['fill_' tg];
        runComparison_v8(o);
        fill_stats_v8(fullfile(ds, ['results_v8_fill_' tg '.mat']), tg, fid);
        fill_actions_sweep_v8(fullfile(ds, ['results_v8_fill_' tg '.mat']), tg, fid, 30, []);
    catch ME, fprintf(fid, 'ERROR|%s|%s\n', tg, ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
    fclose(fid); fid = fopen(fullfile(ds, 'fill_summary_step2.txt'), 'a');
end
fprintf(fid, 'STEP2 finished %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fclose(fid); diary off;
