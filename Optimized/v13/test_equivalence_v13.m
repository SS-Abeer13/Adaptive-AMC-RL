% test_equivalence_v13  Stage 1 sanity: with defaults, v13 must give the same
% evalPolicy output as v12 for baseline, olla, fixed, multi_olla and ctxtab
% on 3 traces, plus 5 episodes of DeepA2C_Shared. Fails -> stop.

root   = 'D:\Adaptive AMC A2C+QL';
v12dir = fullfile(root, 'Optimized', 'v12');
v13dir = fullfile(root, 'Optimized', 'v13');
addpath(v12dir); addpath(v13dir);
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

simTime       = 200;
N             = 10;
nCalib        = 6;
nEval         = 3;
traceSeedBase = 9000;

fprintf('=== v12 vs v13 equivalence test ===\n');

env12 = defaultEnv_v12(23, N);
env13 = defaultEnv_v13(23, N);
env12.calib_sched = 'pf'; env13.calib_sched = 'pf';

fprintf('-- calibrating v12 comparators --\n');
env12 = calibrateFixedClass_v12(env12, nCalib, simTime);
env12 = calibrateCtx_v12(env12, env12.n_calib_ctx, simTime);

fprintf('-- calibrating v13 comparators --\n');
env13 = calibrateFixedClass_v13(env13, nCalib, simTime);
env13 = calibrateCtx_v13(env13, env13.n_calib_ctx, simTime);

fo = fieldnames(env12);
calibMismatch = {};
for q = 1:numel(fo)
    f = fo{q};
    if ~isfield(env13, f), continue; end
    a = env12.(f); b = env13.(f);
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
    [S12, ~, meta12] = generateChannel_v12(simTime, env12);
    obs12 = cqiFeedback_v12(S12, env12, meta12.delays);
    meta12.trace_id = j;

    rng(traceSeedBase + j);
    [S13, ~, meta13] = generateChannel_v13(simTime, env13);
    obs13 = cqiFeedback_v13(S13, env13, meta13.delays);
    meta13.trace_id = j;

    rng(50000 + j); U12 = rand(simTime, N);
    rng(50000 + j); U13 = rand(simTime, N);

    dSINR = max(abs(S12(:) - S13(:)));
    dObs  = max(abs(obs12(:) - obs13(:)));
    if dSINR > tol || dObs > tol
        fprintf('  [trace %d] CHANNEL MISMATCH: dSINR=%.3g dObs=%.3g\n', j, dSINR, dObs);
        allPass = false;
    end

    for k = 1:numel(ptypes)
        pt = ptypes{k};
        rng(77000 + 100*j + 10*k);
        [tp12, bl12, ce12, act12, inf12] = evalPolicy_v12(pt, [], S12, obs12, env12, meta12, U12);
        rng(77000 + 100*j + 10*k);
        [tp13, bl13, ce13, act13, inf13] = evalPolicy_v13(pt, [], S13, obs13, env13, meta13, U13);

        bl12n = bl12; bl12n(isnan(bl12n)) = 0;
        bl13n = bl13; bl13n(isnan(bl13n)) = 0;

        dTp  = max(abs(tp12(:)  - tp13(:)));
        dBl  = max(abs(bl12n(:) - bl13n(:)));
        dCe  = max(abs(ce12(:)  - ce13(:)));
        dAct = max(abs(act12(:) - act13(:)));
        dOk  = max(abs(double(inf12.okU(:))  - double(inf13.okU(:))));
        dRes = max(abs(double(inf12.resU(:)) - double(inf13.resU(:))));

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
% A2C training equivalence check
% -------------------------------------------------------------------
fprintf('\n-- Deep A2C training (5 episodes, same seed) --\n');
ep_eq = 5; a2cSeed = 4242;

t0 = tic;
[~, ~, lc12, ent12] = DeepA2C_Shared_v12(simTime, ep_eq, a2cSeed, env12);
t12 = toc(t0);

t0 = tic;
[~, ~, lc13, ent13] = DeepA2C_Shared_v13(simTime, ep_eq, a2cSeed, env13);
t13 = toc(t0);

dLc  = max(abs(lc12(:)  - lc13(:)));
dEnt = max(abs(ent12(:) - ent13(:)));
a2cOk = (dLc <= tol) && (dEnt <= tol);
if a2cOk
    fprintf('  DeepA2C_Shared     PASS  (v12 %.2fs, v13 %.2fs)\n', t12, t13);
else
    fprintf('  DeepA2C_Shared     FAIL  dLearningCurve=%.3g dEntropyCurve=%.3g\n', dLc, dEnt);
end
allPass = allPass && a2cOk;

if allPass
    fprintf('\n=== EQUIVALENCE TEST: ALL PASS -- v13 reproduces v12 bit-for-bit ===\n');
else
    fprintf('\n=== EQUIVALENCE TEST: FAIL -- v13 does NOT reproduce v12 ===\n');
    error('test_equivalence_v13:mismatch', 'v13 does not reproduce v12 bit-for-bit.');
end
