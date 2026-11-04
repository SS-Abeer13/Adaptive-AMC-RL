% test_headroom_preflight  Quick 2-trace test of headroom logic
clear; clc;
root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v13'));
cd(root);
v13_setup;

env = defaultEnv_v13(23, base.N);
opts = C.R1_pf;
fo = fieldnames(opts);
for q = 1:numel(fo)
    if isfield(env, fo{q}) && ~isempty(opts.(fo{q})), env.(fo{q}) = opts.(fo{q}); end
end
env.calib_sched = 'pf';

% 1. Quick calibration with 2 traces
fprintf('Testing calibrateFixedClass_v13...\n');
env = calibrateFixedClass_v13(env, 2, 50);

fprintf('Testing calibrateGenie_v13...\n');
env = calibrateGenie_v13(env, 2, 50);

% 2. Quick eval
fprintf('Testing evalPolicy_v13 with genie_cqi and fixed...\n');
[S, ~, mt] = generateChannel_v13(50, env);
obs = cqiFeedback_v13(S, env, mt.delays);
U = rand(50, env.N);

[tp1, ~, ~, ~, inf1] = evalPolicy_v13('fixed', [], S, obs, env, mt, U);
[~, ~, sc1] = userMetric_v13(env, tp1, inf1, 10);
fprintf('Fixed score: %.4f\n', sc1);

[tpg, ~, ~, ~, infg] = evalPolicy_v13('genie_cqi', [], S, obs, env, mt, U);
[~, ~, scg] = userMetric_v13(env, tpg, infg, 10);
fprintf('Genie score: %.4f\n', scg);

fprintf('Preflight passed successfully!\n');
