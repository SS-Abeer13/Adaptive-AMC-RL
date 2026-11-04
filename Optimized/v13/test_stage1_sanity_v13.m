% test_stage1_sanity_v13.m
% Implements Stage 1 Sanity Tests 2, 3, and 4 from PLAN_v13.md S1.6:
%   Test 4: Shaping sanity check (shape_c = 0 with ontime_shaped is bit-exact with ontime)
%   Test 2: Residual sanity check (resid_pen = 10, 20 ep -> delta=0 in >= 99%, score within 0.1% of base rule)
%   Test 3: Ensemble sanity check (ensemble of K copies of same actor == single actor bit-for-bit, tested in both resid and offset modes)

root = 'D:\Adaptive AMC A2C+QL';
v13dir = fullfile(root, 'Optimized', 'v13');
addpath(v13dir);
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('====================================================\n');
fprintf('  v13 STAGE 1 SANITY CHECKS (Tests 2, 3, 4)\n');
fprintf('====================================================\n\n');

allPass = true;
simTime = 200;
N = 10;

% -------------------------------------------------------------------
% TEST 4: Shaping sanity check (shape_c = 0 reproduces ontime bit-for-bit)
% -------------------------------------------------------------------
fprintf('--- TEST 4: Shaping sanity check (shape_c = 0 vs ontime) ---\n');
envT4_a = defaultEnv_v13(23, N);
envT4_a.traffic = 'deadline'; envT4_a.reward_kind = 'ontime';
envT4_a.pkt_bits = 12000; envT4_a.pkt_period = 20; envT4_a.pkt_deadline = 10;
envT4_a.feat_extra = {'slack'};

envT4_b = envT4_a;
envT4_b.reward_kind = 'ontime_shaped';
envT4_b.shape_c = 0;

ep_t4 = 5; seed_t4 = 9921;
rng(seed_t4);
[netA, ~, lcA, entA] = DeepA2C_Shared_v13(simTime, ep_t4, seed_t4, envT4_a);

rng(seed_t4);
[netB, ~, lcB, entB] = DeepA2C_Shared_v13(simTime, ep_t4, seed_t4, envT4_b);

dLc = max(abs(lcA(:) - lcB(:)));
dEnt = max(abs(entA(:) - entB(:)));
fprintf('  dLc = %.3e, dEnt = %.3e\n', dLc, dEnt);

if dLc == 0 && dEnt == 0
    fprintf('  TEST 4 RESULT: PASS (shape_c=0 is bit-exact with ontime)\n\n');
else
    fprintf('  TEST 4 RESULT: FAIL\n\n');
    allPass = false;
end

% -------------------------------------------------------------------
% TEST 2: Residual sanity check (resid_pen = 10, 20 ep)
% -------------------------------------------------------------------
fprintf('--- TEST 2: Residual sanity check (resid_pen = 10, 20 episodes) ---\n');
envT2 = defaultEnv_v13(23, N);
envT2.traffic = 'deadline'; envT2.reward_kind = 'ontime'; envT2.primary = 'ontime';
envT2.pkt_bits = 12000; envT2.pkt_period = 20; envT2.pkt_deadline = 10;
envT2.feat_extra = {'slack'};
envT2.action_mode = 'resid';
envT2.resid_pen = 10.0;          % Large penalty on delta ~= 0
envT2.resid_init_bias = 3.0;     % Logit bias +3 on delta = 0
envT2.fixed_offset = -1;
envT2.base_rule_kind = 'fixed';

% Train for 20 episodes
ep_t2 = 20; seed_t2 = 1234;
fprintf('  Training DeepA2C for %d episodes with resid_pen=10.0...\n', ep_t2);
t0 = tic;
[netResid, ~, lcResid, entResid] = DeepA2C_Shared_v13(simTime, ep_t2, seed_t2, envT2);
fprintf('  Training complete in %.2f s.\n', toc(t0));

% Evaluate on 20 traces
nEval_t2 = 20;
nDecisions = 0;
nZeroDecisions = 0;
ontime_a2c = zeros(1, nEval_t2);
ontime_base = zeros(1, nEval_t2);
b0 = min(envT2.burn_in, simTime - 1);

fprintf('  Evaluating on %d traces...\n', nEval_t2);
for j = 1:nEval_t2
    rng(70000 + j);
    [S, ~, meta] = generateChannel_v13(simTime, envT2);
    obsS = cqiFeedback_v13(S, envT2, meta.delays);
    meta.trace_id = 70000 + j;
    rng(72000 + j); U = rand(simTime, N);

    % Greedy A2C
    rng(71000 + 100*j + 1);
    [tpA, ~, ~, actA, infA] = evalPolicy_v13('a2c_v13', netResid, S, obsS, envT2, meta, U);
    [~, ~, ontime_a2c(j)] = userMetric_v13(envT2, tpA, infA, b0);

    % Base rule (Fixed)
    rng(71000 + 100*j + 2);
    [tpB, ~, ~, ~, infB] = evalPolicy_v13('fixed', [], S, obsS, envT2, meta, U);
    [~, ~, ontime_base(j)] = userMetric_v13(envT2, tpB, infB, b0);

    % In residual mode with resid_actions = [-1 0 1], delta=0 corresponds to action index 2
    actB0 = actA(b0+1:end, :);
    nDecisions = nDecisions + numel(actB0);
    nZeroDecisions = nZeroDecisions + sum(actB0(:) == 2);
end

zeroPct = 100 * (nZeroDecisions / nDecisions);
meanA2C = mean(ontime_a2c);
meanBase = mean(ontime_base);
diffScore = abs(meanA2C - meanBase);

fprintf('  Total decisions evaluated: %d\n', nDecisions);
fprintf('  delta = 0 decisions:       %d (%.2f%%)\n', nZeroDecisions, zeroPct);
fprintf('  A2C on-time delivery:      %.4f\n', meanA2C);
fprintf('  Base rule on-time delivery:%.4f\n', meanBase);
fprintf('  Absolute difference:       %.4f (%.2f%%)\n', diffScore, 100*diffScore);

test2_zero_pass = zeroPct >= 99.0;
test2_score_pass = diffScore <= 0.001; % within 0.1%

if test2_zero_pass && test2_score_pass
    fprintf('  TEST 2 RESULT: PASS (zero_pct >= 99%% and |score_diff| <= 0.1%%)\n\n');
else
    fprintf('  TEST 2 RESULT: FAIL (zero_pass=%d, score_pass=%d)\n\n', test2_zero_pass, test2_score_pass);
    allPass = false;
end

% -------------------------------------------------------------------
% TEST 3: Ensemble sanity check (K copies vs single actor)
% -------------------------------------------------------------------
fprintf('--- TEST 3: Ensemble sanity check (K copies vs single actor) ---\n');
K_ens = 3;

% 3a: Resid mode using netResid
ensPolicyResid = repmat({netResid}, 1, K_ens);
test3Pass = true;
for tr = 1:2
    rng(88000 + tr);
    [S, ~, meta] = generateChannel_v13(simTime, envT2);
    obsS = cqiFeedback_v13(S, envT2, meta.delays);
    meta.trace_id = 88000 + tr;
    rng(89000 + tr); U = rand(simTime, N);

    rng(90000 + tr);
    [tp1, bl1, ce1, act1, inf1] = evalPolicy_v13('a2c_v13', netResid, S, obsS, envT2, meta, U);

    rng(90000 + tr);
    [tpE, blE, ceE, actE, infE] = evalPolicy_v13('a2c_ens', ensPolicyResid, S, obsS, envT2, meta, U);

    bl1n = bl1; bl1n(isnan(bl1n)) = 0;
    blEn = blE; blEn(isnan(blEn)) = 0;

    dTp  = max(abs(tp1(:)  - tpE(:)));
    dBl  = max(abs(bl1n(:) - blEn(:)));
    dCe  = max(abs(ce1(:)  - ceE(:)));
    dAct = max(abs(act1(:) - actE(:)));
    dOk  = max(abs(double(inf1.okU(:))  - double(infE.okU(:))));
    dRes = max(abs(double(inf1.resU(:)) - double(infE.resU(:))));

    if dTp == 0 && dBl == 0 && dCe == 0 && dAct == 0 && dOk == 0 && dRes == 0
        fprintf('  [resid mode trace %d] Bit-exact match (%d copies): PASS\n', tr, K_ens);
    else
        fprintf('  [resid mode trace %d] MISMATCH: dTp=%.3e dBl=%.3e dAct=%.3e dOk=%d\n', tr, dTp, dBl, dAct, dOk);
        test3Pass = false;
    end
end

% 3b: Offset mode using netA
ensPolicyOffset = repmat({netA}, 1, K_ens);
for tr = 1:2
    rng(88100 + tr);
    [S, ~, meta] = generateChannel_v13(simTime, envT4_a);
    obsS = cqiFeedback_v13(S, envT4_a, meta.delays);
    meta.trace_id = 88100 + tr;
    rng(89100 + tr); U = rand(simTime, N);

    rng(90100 + tr);
    [tp1, bl1, ce1, act1, inf1] = evalPolicy_v13('a2c_v13', netA, S, obsS, envT4_a, meta, U);

    rng(90100 + tr);
    [tpE, blE, ceE, actE, infE] = evalPolicy_v13('a2c_ens', ensPolicyOffset, S, obsS, envT4_a, meta, U);

    bl1n = bl1; bl1n(isnan(bl1n)) = 0;
    blEn = blE; blEn(isnan(blEn)) = 0;

    dTp  = max(abs(tp1(:)  - tpE(:)));
    dBl  = max(abs(bl1n(:) - blEn(:)));
    dCe  = max(abs(ce1(:)  - ceE(:)));
    dAct = max(abs(act1(:) - actE(:)));
    dOk  = max(abs(double(inf1.okU(:))  - double(infE.okU(:))));
    dRes = max(abs(double(inf1.resU(:)) - double(infE.resU(:))));

    if dTp == 0 && dBl == 0 && dCe == 0 && dAct == 0 && dOk == 0 && dRes == 0
        fprintf('  [offset mode trace %d] Bit-exact match (%d copies): PASS\n', tr, K_ens);
    else
        fprintf('  [offset mode trace %d] MISMATCH: dTp=%.3e dBl=%.3e dAct=%.3e dOk=%d\n', tr, dTp, dBl, dAct, dOk);
        test3Pass = false;
    end
end

if test3Pass
    fprintf('  TEST 3 RESULT: PASS (ensemble of identical actors reproduces single actor bit-for-bit)\n\n');
else
    fprintf('  TEST 3 RESULT: FAIL\n\n');
    allPass = false;
end

% -------------------------------------------------------------------
% OVERALL SANITY VERDICT
% -------------------------------------------------------------------
if allPass
    fprintf('====================================================\n');
    fprintf('  STAGE 1 SANITY CHECKS: ALL PASS\n');
    fprintf('====================================================\n');
else
    error('test_stage1_sanity_v13:failure', 'Stage 1 sanity checks failed.');
end
