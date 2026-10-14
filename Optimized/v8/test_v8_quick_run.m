% test_v8_quick_run.m
addpath('Optimized/v8');
addpath('Optimized/v7');
addpath('Optimized/v5');
addpath('Optimized/case2_3');

opts = struct();
opts.N = 10;
opts.simTime = 200;
opts.ep_deep = 50;
opts.n_seeds = 2;
opts.n_eval = 30;
opts.n_calib = 4;
opts.eval_schedulers = {'pf'};

fprintf('Starting v8 verification comparison run...\n');
t_start = tic;
results = runComparison_v8(opts);
fprintf('\nTotal comparison run time: %.1f seconds.\n', toc(t_start));
