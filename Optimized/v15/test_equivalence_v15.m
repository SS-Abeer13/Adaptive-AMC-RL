% test_equivalence_v15  Stage B sanity: with defaults, v15 must give the same
% evalPolicy output as v14 for baseline, olla, fixed, multi_olla and ctxtab
% on 3 traces, plus 5 episodes of DeepA2C_Shared. Fails -> stop.

root   = 'D:\Adaptive AMC A2C+QL';
v14dir = fullfile(root, 'Optimized', 'v14');
v15dir = fullfile(root, 'Optimized', 'v15');
addpath(v14dir); addpath(v15dir);
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

simTime       = 200;
N             = 10;
nCalib        = 6;
nEval         = 3;
traceSeedBase = 9000;

fprintf('=== v14 vs v15 equivalence test ===\n');

env14 = defaultEnv_v14(23, N);
env15 = defaultEnv_v15(23, N);
env14.calib_sched = 'pf'; env15.calib_sched = 'pf';

fprintf('-- calibrating v14 comparators --\n');
env14 = calibrateFixedClass_v14(env14, nCalib, simTime);
env14 = calibrateCtx_v14(env14, env14.n_calib_ctx, simTime);

fprintf('-- calibrating v15 comparators --\n');
env15 = calibrateFixedClass_v15(env15, nCalib, simTime);
env15 = calibrateCtx_v15(env15, env15.n_calib_ctx, simTime);

fo = fieldnames(env14);
calibMismatch = {};
for q = 1:numel(fo)
    f = fo{q};
    if ~isfield(env15, f), continue; end
    a = env14.(f); b = env15.(f);
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
    [S13, ~, meta13] = generateChannel_v14(simTime, env14);
    obs13 = cqiFeedback_v14(S13, env14, meta13.delays);
    meta13.trace_id = j;

    rng(traceSeedBase + j);
    [S14, ~, meta14] = generateChannel_v15(simTime, env15);
    obs14 = cqiFeedback_v15(S14, env15, meta14.delays);
    meta14.trace_id = j;

    rng(50000 + j); U13 = rand(simTime, N);
    rng(50000 + j); U14 = rand(simTime, N);

    dSINR = max(abs(S13(:) - S14(:)));
    dObs  = max(abs(obs13(:) - obs14(:)));
    if dSINR > tol || dObs > tol
        fprintf('  [trace %d] CHANNEL MISMATCH: dSINR=%.3g dObs=%.3g\n', j, dSINR, dObs);
        allPass = false;
    end

    for k = 1:numel(ptypes)
        pt = ptypes{k};
        rng(77000 + 100*j + 10*k);
        [tp13, bl13, ce13, act13, inf13] = evalPolicy_v14(pt, [], S13, obs13, env14, meta13, U13);
        rng(77000 + 100*j + 10*k);
        [tp14, bl14, ce14, act14, inf14] = evalPolicy_v15(pt, [], S14, obs14, env15, meta14, U14);

        bl13n = bl13; bl13n(isnan(bl13n)) = 0;
        bl14n = bl14; bl14n(isnan(bl14n)) = 0;

        dTp  = max(abs(tp13(:)  - tp14(:)));
        dBl  = max(abs(bl13n(:) - bl14n(:)));
        dCe  = max(abs(ce13(:)  - ce14(:)));
        dAct = max(abs(act13(:) - act14(:)));
        dOk  = max(abs(double(inf13.okU(:))  - double(inf14.okU(:))));
        dRes = max(abs(double(inf13.resU(:)) - double(inf14.resU(:))));

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
[~, ~, lc13, ent13] = DeepA2C_Shared_v14(simTime, ep_eq, a2cSeed, env14);
t13 = toc(t0);

t0 = tic;
[~, ~, lc14, ent14] = DeepA2C_Shared_v15(simTime, ep_eq, a2cSeed, env15);
t14 = toc(t0);

dLc  = max(abs(lc13(:)  - lc14(:)));
dEnt = max(abs(ent13(:) - ent14(:)));
a2cOk = (dLc <= tol) && (dEnt <= tol);
if a2cOk
    fprintf('  DeepA2C_Shared     PASS  (v14 %.2fs, v15 %.2fs)\n', t13, t14);
else
    fprintf('  DeepA2C_Shared     FAIL  dLearningCurve=%.3g dEntropyCurve=%.3g\n', dLc, dEnt);
end
allPass = allPass && a2cOk;

if allPass
    fprintf('\n=== EQUIVALENCE TEST: ALL PASS -- v15 reproduces v14 bit-for-bit ===\n');
else
    fprintf('\n=== EQUIVALENCE TEST: FAIL -- v15 does NOT reproduce v14 ===\n');
    error('test_equivalence_v15:mismatch', 'v15 does not reproduce v14 bit-for-bit.');
end
