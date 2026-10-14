% fill_step3_schedfix  Diagnostic: does the A2C deficit come from scheduler
% gaming? Same headline set-up, but the PF scheduler ranks users by the OLLA
% reference rate (env.sched_on_ref = true) for ALL schemes, so the agent's
% MCS choice no longer decides who gets scheduled.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v8 = fullfile(root, 'Optimized', 'v8');
addpath(v8); addpath(fullfile(root, 'Optimized', 'v7'));
addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
logf = fullfile(v8, 'logs', 'fill_step3.log');
diary off; if exist(logf, 'file'), delete(logf); end
diary(logf);
ds = fullfile(v8, 'Dataset');
sumf = fullfile(ds, 'fill_summary_step3.txt');
fid = fopen(sumf, 'w');
fprintf(fid, 'STEP3 started %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
base = struct('N', 10, 'simTime', 200, 'ep_deep', 300, 'n_seeds', 5, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true);
for tier = {'O', 'B'}
    tg = ['schedfix_tier' tier{1}];
    try
        o = base; o.state_tier = tier{1}; o.save_tag = ['fill_' tg];
        runComparison_v8(o);
        f = fullfile(ds, ['results_v8_fill_' tg '.mat']);
        fill_stats_v8(f, tg, fid);
        fill_actions_sweep_v8(f, tg, fid, 30, []);
        L = load(f, 'results'); lc = L.results.learning_curves;
        fprintf(fid, 'LC|%s|first25=%.4f|last25=%.4f\n', tg, mean(mean(lc(1:25, :))), mean(mean(lc(end-24:end, :))));
    catch ME, fprintf(fid, 'ERROR|%s|%s\n', tg, ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
    fclose(fid); fid = fopen(sumf, 'a');
end
fprintf(fid, 'STEP3 finished %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fclose(fid); diary off;
