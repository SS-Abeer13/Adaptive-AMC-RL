% test_equivalence_v16  Stage B sanity: with defaults, v16 must give the same
% evalPolicy output as v15 for baseline, olla, fixed, multi_olla and ctxtab
% on 3 traces, plus 5 episodes of DeepA2C_Shared. Fails -> stop.

root   = 'D:\Adaptive AMC A2C+QL';
v15dir = fullfile(root, 'Optimized', 'v15');
v16dir = fullfile(root, 'Optimized', 'v16');
addpath(v15dir); addpath(v16dir);
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

simTime       = 200;
N             = 10;
nCalib        = 6;
nEval         = 3;
traceSeedBase = 9000;

fprintf('=== v15 vs v16 equivalence test ===\n');

env15 = defaultEnv_v15(23, N);
env16 = defaultEnv_v16(23, N);
env15.calib_sched = 'pf'; env16.calib_sched = 'pf';

fprintf('-- calibrating v15 comparators --\n');
env15 = calibrateFixedClass_v15(env15, nCalib, simTime);
env15 = calibrateCtx_v15(env15, env15.n_calib_ctx, simTime);

fprintf('-- calibrating v16 comparators --\n');
env16 = calibrateFixedClass_v16(env16, nCalib, simTime);
env16 = calibrateCtx_v16(env16, env16.n_calib_ctx, simTime);

fo = fieldnames(env15);
calibMismatch = {};
for q = 1:numel(fo)
    f = fo{q};
    if ~isfield(env16, f), continue; end
    a = env15.(f); b = env16.(f);
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
    [S13, ~, meta13] = generateChannel_v15(simTime, env15);
    obs13 = cqiFeedback_v15(S13, env15, meta13.delays);
    meta13.trace_id = j;

    rng(traceSeedBase + j);
    [S14, ~, meta14] = generateChannel_v16(simTime, env16);
    obs14 = cqiFeedback_v16(S14, env16, meta14.delays);
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
        [tp13, bl13, ce13, act13, inf13] = evalPolicy_v15(pt, [], S13, obs13, env15, meta13, U13);
        rng(77000 + 100*j + 10*k);
        [tp14, bl14, ce14, act14, inf14] = evalPolicy_v16(pt, [], S14, obs14, env16, meta14, U14);

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
[~, ~, lc13, ent13] = DeepA2C_Shared_v15(simTime, ep_eq, a2cSeed, env15);
t13 = toc(t0);

t0 = tic;
[~, ~, lc14, ent14] = DeepA2C_Shared_v16(simTime, ep_eq, a2cSeed, env16);
t14 = toc(t0);

dLc  = max(abs(lc13(:)  - lc14(:)));
dEnt = max(abs(ent13(:) - ent14(:)));
a2cOk = (dLc <= tol) && (dEnt <= tol);
if a2cOk
    fprintf('  DeepA2C_Shared     PASS  (v15 %.2fs, v16 %.2fs)\n', t13, t14);
else
    fprintf('  DeepA2C_Shared     FAIL  dLearningCurve=%.3g dEntropyCurve=%.3g\n', dLc, dEnt);
end
allPass = allPass && a2cOk;

% -------------------------------------------------------------------
% B3.1: "plus one deadline evaluation" -- same RTT-0/nproc-1 defaults,
% deadline traffic instead of full-buffer, ptype 'olla'.
% -------------------------------------------------------------------
fprintf('\n-- deadline-traffic evaluation (ptype=olla, 1 trace) --\n');
env15d = env15; env16d = env16;
dlFields = struct('traffic', 'deadline', 'O2I_dB', 0, 'pkt_bits', 12000, ...
    'pkt_period', 20, 'pkt_deadline', 10, 'reward_kind', 'ontime', 'primary', 'ontime', ...
    'feat_extra', {{'slack'}}, 'ctx_cue', 'slack', 'ctx_edges', [2 5]);
fn = fieldnames(dlFields);
for q = 1:numel(fn), env15d.(fn{q}) = dlFields.(fn{q}); env16d.(fn{q}) = dlFields.(fn{q}); end

rng(traceSeedBase + 1);
[Sd13, ~, metad13] = generateChannel_v15(simTime, env15d);
obsd13 = cqiFeedback_v15(Sd13, env15d, metad13.delays);
metad13.trace_id = 1;
rng(traceSeedBase + 1);
[Sd14, ~, metad14] = generateChannel_v16(simTime, env16d);
obsd14 = cqiFeedback_v16(Sd14, env16d, metad14.delays);
metad14.trace_id = 1;
rng(50000 + 1); Ud13 = rand(simTime, N);
rng(50000 + 1); Ud14 = rand(simTime, N);

rng(77000 + 110);
[tpd13, bld13, ced13, actd13, infd13] = evalPolicy_v15('olla', [], Sd13, obsd13, env15d, metad13, Ud13);
rng(77000 + 110);
[tpd14, bld14, ced14, actd14, infd14] = evalPolicy_v16('olla', [], Sd14, obsd14, env16d, metad14, Ud14);

bld13n = bld13; bld13n(isnan(bld13n)) = 0;
bld14n = bld14; bld14n(isnan(bld14n)) = 0;
dOkD  = max(abs(double(infd13.okU(:))  - double(infd14.okU(:))));
dResD = max(abs(double(infd13.resU(:)) - double(infd14.resU(:))));
dOkRes = max([max(abs(tpd13(:) - tpd14(:))), max(abs(bld13n(:) - bld14n(:))), ...
              max(abs(ced13(:) - ced14(:))), max(abs(actd13(:) - actd14(:))), dOkD, dResD]);
deadlineOk = dOkRes <= tol;
if deadlineOk
    fprintf('  deadline evaluation PASS\n');
else
    fprintf('  deadline evaluation FAIL  d=%.3g\n', dOkRes);
end
allPass = allPass && deadlineOk;

if allPass
    fprintf('\n=== EQUIVALENCE TEST: ALL PASS -- v16 reproduces v15 bit-for-bit ===\n');
else
    fprintf('\n=== EQUIVALENCE TEST: FAIL -- v16 does NOT reproduce v15 ===\n');
    error('test_equivalence_v16:mismatch', 'v16 does not reproduce v15 bit-for-bit.');
end
