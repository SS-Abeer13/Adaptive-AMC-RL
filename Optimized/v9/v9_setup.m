% v9_setup  Paths and base options shared by the v9 scripts.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v9 = fullfile(root, 'Optimized', 'v9');
addpath(v9); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
ds = fullfile(v9, 'Dataset');
base = struct('N', 10, 'simTime', 200, 'ep_deep', 300, 'n_seeds', 10, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0, ...
              'mob_kappa', 1, 'crn', true, 'train_warm_ttis', 0, 'calib_warm', false);
pen = struct('lambda_retx', 0.05, 'lambda_drop', 0.5);
