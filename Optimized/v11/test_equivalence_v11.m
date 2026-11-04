% test_equivalence_v11  P0.1: with the defaults, v11 must give the same
% evalPolicy output as v10 for baseline, olla, fixed, multi_olla and ctxtab
% on 3 traces. Fails -> stop (do not proceed to P0.2 or any experiment).

root   = 'D:\Adaptive AMC A2C+QL';
v10dir = fullfile(root, 'Optimized', 'v10');
v11dir = fullfile(root, 'Optimized', 'v11');
addpath(v10dir); addpath(v11dir);
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

simTime       = 200;
N             = 10;
nCalib        = 6;
nEval         = 3;
traceSeedBase = 9000;

fprintf('=== v10 vs v11 equivalence test (P0.1) ===\n');

env10 = defaultEnv_v10(23, N);
env11 = defaultEnv_v11(23, N);
env10.calib_sched = 'pf'; env11.calib_sched = 'pf';

fprintf('-- calibrating v10 comparators --\n');
env10 = calibrateFixedClass_v10(env10, nCalib, simTime);
env10 = calibrateCtx_v10(env10, env10.n_calib_ctx, simTime);

fprintf('-- calibrating v11 comparators --\n');
env11 = calibrateFixedClass_v11(env11, nCalib, simTime);
env11 = calibrateCtx_v11(env11, env11.n_calib_ctx, simTime);

fo = fieldnames(env10);
calibMismatch = {};
for q = 1:numel(fo)
    f = fo{q};
    a = env10.(f); b = env11.(f);
    if isnumeric(a) && isnumeric(b) && isequal(size(a), size(b))
        if max(abs(double(a(:)) - double(b(:))), [], 'omitnan') > 0
            calibMismatch{end+1} = f; %#ok<SAGROW>
        end
    end
end
if isempty(calibMismatch)
    fprintf('  calibrated env fields: IDENTICAL\n');
else
    fprintf('  calibrated env MISMATCH in fields: %s\n', strjoin(calibMismatch, ', '));
end

ptypes = {'baseline', 'olla', 'fixed', 'multi_olla', 'ctxtab'};
tol = 0;  % require bit-exact reproduction
allPass = isempty(calibMismatch);

for j = 1:nEval
    rng(traceSeedBase + j);
    [S10, ~, meta10] = generateChannel_v10(simTime, env10);
    obs10 = cqiFeedback_v10(S10, env10, meta10.delays);
    meta10.trace_id = j;

    rng(traceSeedBase + j);
    [S11, ~, meta11] = generateChannel_v11(simTime, env11);
    obs11 = cqiFeedback_v11(S11, env11, meta11.delays);
    meta11.trace_id = j;

    rng(50000 + j); U10 = rand(simTime, N);
    rng(50000 + j); U11 = rand(simTime, N);

    dSINR = max(abs(S10(:) - S11(:)));
    dObs  = max(abs(obs10(:) - obs11(:)));
    if dSINR > tol || dObs > tol
        fprintf('  [trace %d] CHANNEL MISMATCH: dSINR=%.3g dObs=%.3g\n', j, dSINR, dObs);
        allPass = false;
    end

    for k = 1:numel(ptypes)
        pt = ptypes{k};
        rng(77000 + 100*j + 10*k);
        [tp10, bl10, ce10, act10, inf10] = evalPolicy_v10(pt, [], S10, obs10, env10, meta10, U10);
        rng(77000 + 100*j + 10*k);
        [tp11, bl11, ce11, act11, inf11] = evalPolicy_v11(pt, [], S11, obs11, env11, meta11, U11);

        bl10n = bl10; bl10n(isnan(bl10n)) = 0;
        bl11n = bl11; bl11n(isnan(bl11n)) = 0;

        dTp  = max(abs(tp10(:)  - tp11(:)));
        dBl  = max(abs(bl10n(:) - bl11n(:)));
        dCe  = max(abs(ce10(:)  - ce11(:)));
        dAct = max(abs(act10(:) - act11(:)));
        dOk  = max(abs(double(inf10.okU(:))  - double(inf11.okU(:))));
        dRes = max(abs(double(inf10.resU(:)) - double(inf11.resU(:))));

        ok = (dTp <= tol) && (dBl <= tol) && (dCe <= tol) && (dAct <= tol) && (dOk <= tol) && (dRes <= tol);
        if ok
            fprintf('  [trace %d] %-12s PASS\n', j, pt);
        else
            fprintf(['  [trace %d] %-12s FAIL  dTp=%.3g dBler=%.3g dCqiErr=%.3g ' ...
                     'dAct=%.3g dOk=%.3g dRes=%.3g\n'], j, pt, dTp, dBl, dCe, dAct, dOk, dRes);
            allPass = false;
        end
    end
end

% -------------------------------------------------------------------
% A2C training equivalence + P0.2 speed check (not part of the 5-ptype
% comparator set above, but DeepA2C_Shared_v11 was also vectorised).
% -------------------------------------------------------------------
fprintf('\n-- Deep A2C training (5 episodes, same seed) --\n');
ep_eq = 5; a2cSeed = 4242;

t0 = tic;
[~, ~, lc10, ent10] = DeepA2C_Shared_v10(simTime, ep_eq, a2cSeed, env10);
t10 = toc(t0);

t0 = tic;
[~, ~, lc11, ent11] = DeepA2C_Shared_v11(simTime, ep_eq, a2cSeed, env11);
t11 = toc(t0);

dLc  = max(abs(lc10(:)  - lc11(:)));
dEnt = max(abs(ent10(:) - ent11(:)));
a2cOk = (dLc <= tol) && (dEnt <= tol);
if a2cOk
    fprintf('  DeepA2C_Shared     PASS  (v10 %.2fs, v11 %.2fs, speedup %.2fx)\n', t10, t11, t10/max(t11,eps));
else
    fprintf('  DeepA2C_Shared     FAIL  dLearningCurve=%.3g dEntropyCurve=%.3g\n', dLc, dEnt);
end
allPass = allPass && a2cOk;

if allPass
    fprintf('\n=== EQUIVALENCE TEST: ALL PASS -- v11 reproduces v10 bit-for-bit ===\n');
else
    fprintf('\n=== EQUIVALENCE TEST: FAIL -- v11 does NOT reproduce v10 ===\n');
    error('test_equivalence_v11:mismatch', 'v11 does not reproduce v10 bit-for-bit.');
end
