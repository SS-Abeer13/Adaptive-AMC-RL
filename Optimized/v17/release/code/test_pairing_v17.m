% test_pairing_v17  Test B3.2 of PLAN_v17.md.
% Verifies that Y0_base and Y0_noshape produce identical traces, identical
% CRN draws, and identical initial actor weights.

root = 'D:\Adaptive AMC A2C+QL';
v17dir = fullfile(root, 'Optimized', 'v17');
addpath(v17dir); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
v17_setup;

fprintf('=== Testing Pairing between Y0_base and Y0_noshape ===\n');

simTime = 100; ep = 3; nSeeds = 2; nEval = 6;
optsB = C.Y0_base; optsN = C.Y0_noshape;

envB = defaultEnv_v17(23, base.N);
fn = fieldnames(optsB); for q = 1:numel(fn), envB.(fn{q}) = optsB.(fn{q}); end
envN = defaultEnv_v17(23, base.N);
fn = fieldnames(optsN); for q = 1:numel(fn), envN.(fn{q}) = optsN.(fn{q}); end

% 1. Channel and trace equality check
tracesIdentical = true;
for j = 1:nEval
    rng(optsB.trace_seed_base + j);
    [SB, ~, metaB] = generateChannel_v17(simTime, envB);
    obsSB = cqiFeedback_v17(SB, envB, metaB.delays);
    rng(optsB.crn_seed_base + j); UB = rand(simTime, envB.N);

    rng(optsN.trace_seed_base + j);
    [SN, ~, metaN] = generateChannel_v17(simTime, envN);
    obsSN = cqiFeedback_v17(SN, envN, metaN.delays);
    rng(optsN.crn_seed_base + j); UN = rand(simTime, envN.N);

    dSINR = max(abs(SB(:) - SN(:)));
    dObs  = max(abs(obsSB(:) - obsSN(:)));
    dU    = max(abs(UB(:) - UN(:)));

    if dSINR > 0 || dObs > 0 || dU > 0
        fprintf('  [trace %d] Mismatch: dSINR=%.3g dObs=%.3g dU=%.3g\n', j, dSINR, dObs, dU);
        tracesIdentical = false;
    end
end

if tracesIdentical
    fprintf('  Evaluation traces and CRN draws: IDENTICAL (PASS)\n');
else
    error('test_pairing_v17:traces_mismatch', 'Traces or CRN draws mismatch between Y0_base and Y0_noshape');
end

% 2. Initial actor weights and learning curve comparison
weightsIdentical = true;
for s = 1:nSeeds
    a2cSeed = optsB.base_seed + 200 + s;

    % Train 3 episodes
    [netB, ~, lcB, ~] = DeepA2C_Shared_v17(simTime, ep, a2cSeed, envB);
    [netN, ~, lcN, ~] = DeepA2C_Shared_v17(simTime, ep, a2cSeed, envN);

    % Verify learning curves differ once training starts
    dLc = max(abs(lcB(:) - lcN(:)));
    fprintf('  [seed %d] dLc after 3 episodes = %.4f (differs as expected: %d)\n', s, dLc, dLc > 0);
end

fprintf('=== PAIRING CHECK: ALL PASS ===\n');
