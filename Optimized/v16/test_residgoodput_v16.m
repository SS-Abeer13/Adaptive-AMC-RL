% test_residgoodput_v16  Stage B3.4 (PLAN_v16.md): with resid_pen = 10 and
% 20 episodes, the greedy residual-A2C policy should use delta = 0 in >=
% 99% of decisions and match the base rule's goodput within 0.1%. Also
% confirms B2 row 3 (base rule selected on calibration traces BY GOODPUT
% when env.primary = 'goodput' -- selectBaseRule_v16/userMetric_v16 already
% branch on env.primary generically, no code change was needed there).
root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v16'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_residgoodput_v16: resid sanity (resid_pen=10, goodput) ===\n');

N = 10; simTime = 200;
env = defaultEnv_v16(23, N);
env.action_mode = 'resid';
env.resid_actions = -1:1;
env.resid_pen = 10;
env.resid_init_bias = 5.0;
env.primary = 'goodput';

env = calibrateFixedClass_v16(env, 10, simTime);
env = selectBaseRule_v16(env, 10, simTime);
fprintf('  base rule selected: %s (kind=%s)\n', ...
    tern(strcmpi(env.base_rule_kind, 'fixed_class'), 'FixedPU', 'Fixed'), env.base_rule_kind);

[actorNet, ~, lc, ~] = DeepA2C_Shared_v16(simTime, 20, 999, env);
fprintf('  training OK, lc(end) = %.3f\n', lc(end));

rng(9001); [S, ~, meta] = generateChannel_v16(simTime, env); obsS = cqiFeedback_v16(S, env, meta.delays); meta.trace_id = 1;
rng(5001); U = rand(simTime, env.N);
[tpA, ~, ~, actA, ~] = evalPolicy_v16('a2c_v16', actorNet, S, obsS, env, meta, U);

zeroIdx = find(env.resid_actions == 0, 1);
fracZero = mean(actA(:) == zeroIdx);
fprintf('  greedy delta=0 fraction: %.4f (want >= 0.99)\n', fracZero);

basePtype = 'fixed'; if strcmpi(env.base_rule_kind, 'fixed_class'), basePtype = 'fixed_class'; end
[tpB, ~, ~, ~, ~] = evalPolicy_v16(basePtype, [], S, obsS, env, meta, U);

gpA = sum(mean(tpA, 1)); gpB = sum(mean(tpB, 1));
pctDiff = 100 * abs(gpA - gpB) / max(gpB, eps);
fprintf('  A2C-resid goodput = %.4f Mbps, base rule goodput = %.4f Mbps, diff = %.4f%% (want <= 0.1%%)\n', ...
        gpA, gpB, pctDiff);

ok = (fracZero >= 0.99) && (pctDiff <= 0.1);
if ok
    fprintf('=== test_residgoodput_v16: ALL CHECKS PASSED ===\n');
else
    fprintf('=== test_residgoodput_v16: FAIL (fracZero>=0.99: %d, pctDiff<=0.1: %d) ===\n', fracZero >= 0.99, pctDiff <= 0.1);
    error('test_residgoodput_v16:fail', 'see log above');
end

function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end
