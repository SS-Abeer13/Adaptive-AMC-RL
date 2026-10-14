% fill_step5_reward  Does the error penalty in the reward explain the agent's
% conservatism? Primary set-up (reference-rate PF, Tier-O) with a pure
% goodput reward (lambda_retx = lambda_drop = 0), from scratch and from a clone.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v8 = fullfile(root, 'Optimized', 'v8');
addpath(v8); addpath(fullfile(root, 'Optimized', 'v7'));
addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
logf = fullfile(v8, 'logs', 'fill_step5.log');
diary off; if exist(logf, 'file'), delete(logf); end
diary(logf);
ds = fullfile(v8, 'Dataset');
sumf = fullfile(ds, 'fill_summary_reward.txt');
fid = fopen(sumf, 'w');
fprintf(fid, 'STEP5 started %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
base = struct('N', 10, 'simTime', 200, 'ep_deep', 300, 'n_seeds', 10, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0);
try
    o = base; o.save_tag = 'final_headline_O_goodput';
    runComparison_v8(o);
    f = fullfile(ds, 'results_v8_final_headline_O_goodput.mat');
    fill_stats_v8(f, 'goodput_O', fid);
    fill_actions_sweep_v8(f, 'goodput_O', fid, 30, []);
    L = load(f, 'results'); lc = L.results.learning_curves;
    fprintf(fid, 'LC|goodput_O|first25=%.4f|last25=%.4f\n', mean(mean(lc(1:25, :))), mean(mean(lc(end-24:end, :))));
catch ME, fprintf(fid, 'ERROR|goodput_O|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fclose(fid); fid = fopen(sumf, 'a');
try
    fill_bc_diag_v8(base, 5, 150, 300, 100, fid);
catch ME, fprintf(fid, 'ERROR|bcdiag_goodput|%s\n', ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); end
fprintf(fid, 'STEP5 finished %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fclose(fid); diary off;
