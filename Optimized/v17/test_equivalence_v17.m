% test_equivalence_v17  Stage B2.1 sanity: with defaults (pf_avg='acked', drain=false),
% v17 must give bit-exact identical outputs to v16 across:
%   - Calibration (fixed, ctxtab)
%   - 3 classical eval traces across all comparators (baseline, olla, fixed, multi_olla, ctxtab)
%   - 1 RTT-8 deadline trace
%   - 1 RTT-8 full-buffer trace
%   - 5 episodes of DeepA2C_Shared training
% Fails -> stop.

root   = 'D:\Adaptive AMC A2C+QL';
v16dir = fullfile(root, 'Optimized', 'v16');
v17dir = fullfile(root, 'Optimized', 'v17');
addpath(v16dir); addpath(v17dir);
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

simTime       = 200;
N             = 10;
nCalib        = 6;
nEval         = 3;
traceSeedBase = 9000;

fprintf('=== v16 vs v17 equivalence test (default settings) ===\n');

env16 = defaultEnv_v16(23, N);
env17 = defaultEnv_v17(23, N);
env16.calib_sched = 'pf'; env17.calib_sched = 'pf';

% Assert v17 defaults match requirements
assert(strcmp(env17.pf_avg, 'acked'), 'env17 default pf_avg must be acked');
assert(env17.drain == false, 'env17 default drain must be false');

fprintf('-- calibrating v16 comparators --\n');
env16 = calibrateFixedClass_v16(env16, nCalib, simTime);
env16 = calibrateCtx_v16(env16, env16.n_calib_ctx, simTime);

fprintf('-- calibrating v17 comparators --\n');
env17 = calibrateFixedClass_v17(env17, nCalib, simTime);
env17 = calibrateCtx_v17(env17, env17.n_calib_ctx, simTime);

fo = fieldnames(env16);
calibMismatch = {};
for q = 1:numel(fo)
    f = fo{q};
    if ~isfield(env17, f), continue; end
    a = env16.(f); b = env17.(f);
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

fprintf('\n-- classical evaluation (3 traces, 5 comparators) --\n');
for j = 1:nEval
    rng(traceSeedBase + j);
    [S16, ~, meta16] = generateChannel_v16(simTime, env16);
    obs16 = cqiFeedback_v16(S16, env16, meta16.delays);
    meta16.trace_id = j;

    rng(traceSeedBase + j);
    [S17, ~, meta17] = generateChannel_v17(simTime, env17);
    obs17 = cqiFeedback_v17(S17, env17, meta17.delays);
    meta17.trace_id = j;

    rng(50000 + j); U16 = rand(simTime, N);
    rng(50000 + j); U17 = rand(simTime, N);

    dSINR = max(abs(S16(:) - S17(:)));
    dObs  = max(abs(obs16(:) - obs17(:)));
    if dSINR > tol || dObs > tol
        fprintf('  [trace %d] CHANNEL MISMATCH: dSINR=%.3g dObs=%.3g\n', j, dSINR, dObs);
        allPass = false;
    end

    for k = 1:numel(ptypes)
        pt = ptypes{k};
        rng(77000 + 100*j + 10*k);
        [tp16, bl16, ce16, act16, inf16] = evalPolicy_v16(pt, [], S16, obs16, env16, meta16, U16);
        rng(77000 + 100*j + 10*k);
        [tp17, bl17, ce17, act17, inf17] = evalPolicy_v17(pt, [], S17, obs17, env17, meta17, U17);

        bl16n = bl16; bl16n(isnan(bl16n)) = 0;
        bl17n = bl17; bl17n(isnan(bl17n)) = 0;

        dTp  = max(abs(tp16(:)  - tp17(:)));
        dBl  = max(abs(bl16n(:) - bl17n(:)));
        dCe  = max(abs(ce16(:)  - ce17(:)));
        dAct = max(abs(act16(:) - act17(:)));
        dOk  = max(abs(double(inf16.okU(:))  - double(inf17.okU(:))));
        dRes = max(abs(double(inf16.resU(:)) - double(inf17.resU(:))));

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
% 1 RTT-8 deadline trace
% -------------------------------------------------------------------
fprintf('\n-- RTT-8 deadline-traffic evaluation (ptype=olla, 1 trace) --\n');
env16dl = env16; env17dl = env17;
dlFields = struct('traffic', 'deadline', 'O2I_dB', 0, 'pkt_bits', 12000, ...
    'pkt_period', 20, 'pkt_deadline', 10, 'reward_kind', 'ontime', 'primary', 'ontime', ...
    'feat_extra', {{'slack'}}, 'ctx_cue', 'slack', 'ctx_edges', [2 5], ...
    'harq_rtt', 8, 'harq_nproc', 8);
fn = fieldnames(dlFields);
for q = 1:numel(fn)
    env16dl.(fn{q}) = dlFields.(fn{q});
    env17dl.(fn{q}) = dlFields.(fn{q});
end

rng(traceSeedBase + 101);
[Sdl16, ~, metadl16] = generateChannel_v16(simTime, env16dl);
obsdl16 = cqiFeedback_v16(Sdl16, env16dl, metadl16.delays);
metadl16.trace_id = 101;
rng(traceSeedBase + 101);
[Sdl17, ~, metadl17] = generateChannel_v17(simTime, env17dl);
obsdl17 = cqiFeedback_v17(Sdl17, env17dl, metadl17.delays);
metadl17.trace_id = 101;
rng(50101); Udl16 = rand(simTime, N);
rng(50101); Udl17 = rand(simTime, N);

rng(77889);
[tpdl16, bldl16, cedl16, actdl16, infdl16] = evalPolicy_v16('olla', [], Sdl16, obsdl16, env16dl, metadl16, Udl16);
rng(77889);
[tpdl17, bldl17, cedl17, actdl17, infdl17] = evalPolicy_v17('olla', [], Sdl17, obsdl17, env17dl, metadl17, Udl17);

bldl16n = bldl16; bldl16n(isnan(bldl16n)) = 0;
bldl17n = bldl17; bldl17n(isnan(bldl17n)) = 0;
dOkDl  = max(abs(double(infdl16.okU(:))  - double(infdl17.okU(:))));
dResDl = max(abs(double(infdl16.resU(:)) - double(infdl17.resU(:))));
dDl = max([max(abs(tpdl16(:) - tpdl17(:))), max(abs(bldl16n(:) - bldl17n(:))), ...
           max(abs(cedl16(:) - cedl17(:))), max(abs(actdl16(:) - actdl17(:))), dOkDl, dResDl]);
dlOk = (dDl <= tol);
if dlOk
    fprintf('  RTT-8 deadline evaluation PASS\n');
else
    fprintf('  RTT-8 deadline evaluation FAIL  d=%.3g\n', dDl);
end
allPass = allPass && dlOk;

% -------------------------------------------------------------------
% 1 RTT-8 full-buffer trace
% -------------------------------------------------------------------
fprintf('\n-- RTT-8 full-buffer evaluation (ptype=olla, 1 trace) --\n');
env16fb = env16; env17fb = env17;
env16fb.harq_rtt = 8; env16fb.harq_nproc = 8;
env17fb.harq_rtt = 8; env17fb.harq_nproc = 8;

rng(traceSeedBase + 201);
[Sfb16, ~, metafb16] = generateChannel_v16(simTime, env16fb);
obsfb16 = cqiFeedback_v16(Sfb16, env16fb, metafb16.delays);
metafb16.trace_id = 201;
rng(traceSeedBase + 201);
[Sfb17, ~, metafb17] = generateChannel_v17(simTime, env17fb);
obsfb17 = cqiFeedback_v17(Sfb17, env17fb, metafb17.delays);
metafb17.trace_id = 201;
rng(50201); Ufb16 = rand(simTime, N);
rng(50201); Ufb17 = rand(simTime, N);

rng(77991);
[tpfb16, blfb16, cefb16, actfb16, inffb16] = evalPolicy_v16('olla', [], Sfb16, obsfb16, env16fb, metafb16, Ufb16);
rng(77991);
[tpfb17, blfb17, cefb17, actfb17, inffb17] = evalPolicy_v17('olla', [], Sfb17, obsfb17, env17fb, metafb17, Ufb17);

blfb16n = blfb16; blfb16n(isnan(blfb16n)) = 0;
blfb17n = blfb17; blfb17n(isnan(blfb17n)) = 0;
dOkFb  = max(abs(double(inffb16.okU(:))  - double(inffb17.okU(:))));
dResFb = max(abs(double(inffb16.resU(:)) - double(inffb17.resU(:))));
dFb = max([max(abs(tpfb16(:) - tpfb17(:))), max(abs(blfb16n(:) - blfb17n(:))), ...
           max(abs(cefb16(:) - cefb17(:))), max(abs(actfb16(:) - actfb17(:))), dOkFb, dResFb]);
fbOk = (dFb <= tol);
if fbOk
    fprintf('  RTT-8 full-buffer evaluation PASS\n');
else
    fprintf('  RTT-8 full-buffer evaluation FAIL  d=%.3g\n', dFb);
end
allPass = allPass && fbOk;

% -------------------------------------------------------------------
% A2C training equivalence check (5 episodes, same seed)
% -------------------------------------------------------------------
fprintf('\n-- Deep A2C training (5 episodes, same seed) --\n');
ep_eq = 5; a2cSeed = 4242;

t0 = tic;
[~, ~, lc16, ent16] = DeepA2C_Shared_v16(simTime, ep_eq, a2cSeed, env16);
t16 = toc(t0);

t0 = tic;
[~, ~, lc17, ent17] = DeepA2C_Shared_v17(simTime, ep_eq, a2cSeed, env17);
t17 = toc(t0);

dLc  = max(abs(lc16(:)  - lc17(:)));
dEnt = max(abs(ent16(:) - ent17(:)));
a2cOk = (dLc <= tol) && (dEnt <= tol);
if a2cOk
    fprintf('  DeepA2C_Shared     PASS  (v16 %.2fs, v17 %.2fs)\n', t16, t17);
else
    fprintf('  DeepA2C_Shared     FAIL  dLearningCurve=%.3g dEntropyCurve=%.3g\n', dLc, dEnt);
end
allPass = allPass && a2cOk;

if allPass
    fprintf('\n=== EQUIVALENCE TEST: ALL PASS -- v17 reproduces v16 bit-for-bit ===\n');
else
    fprintf('\n=== EQUIVALENCE TEST: FAIL -- v17 does NOT reproduce v16 ===\n');
    error('test_equivalence_v17:mismatch', 'v17 does not reproduce v16 bit-for-bit.');
end
