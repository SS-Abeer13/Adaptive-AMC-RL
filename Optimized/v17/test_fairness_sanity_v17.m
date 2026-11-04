% test_fairness_sanity_v17  Stage B2.4:
% With pf_avg = 'scheduled' and drain = true, on 20 K3 (goodput, full buffer) traces:
% Compare Baseline at RTT 8 / 8 proc vs RTT 0 / 1 proc.
% Pass criteria:
%   - Goodput ratio (RTT 8 / RTT 0) lies in [0.85, 1.10]
%   - Jain fairness is within +/- 0.03 of RTT 0
% If not, stop and report.

root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v17'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_fairness_sanity_v17: Baseline RTT 8 vs RTT 0 (20 traces) ===\n');

v17_setup;
N = 10;
simTime = 200;
nTraces = 20;
traceSeeds = 9001:9020;

% Environment: K3 full-buffer goodput
envBase = defaultEnv_v17(23, N);
fnB = fieldnames(base);
for q = 1:numel(fnB), envBase.(fnB{q}) = base.(fnB{q}); end
fnG = fieldnames(GP);
for q = 1:numel(fnG), envBase.(fnG{q}) = GP.(fnG{q}); end
envBase.pf_avg = 'scheduled';
envBase.drain = true;

% Config 0: RTT 0 / 1 proc (legacy engine)
env0 = envBase;
env0.harq_rtt = 0; env0.harq_nproc = 1;

% Config 8: RTT 8 / 8 proc (new engine)
env8 = envBase;
env8.harq_rtt = 8; env8.harq_nproc = 8;

jain0_traces = zeros(1, nTraces);
jain8_traces = zeros(1, nTraces);
prim0_traces = zeros(1, nTraces);
prim8_traces = zeros(1, nTraces);

for j = 1:nTraces
    tSeed = traceSeeds(j);
    rng(tSeed);
    [Strue, ~, meta] = generateChannel_v17(simTime, envBase);
    obsS = cqiFeedback_v17(Strue, envBase, meta.delays);
    meta.trace_id = j;
    rng(50000 + j); U = rand(simTime, N);

    rng(80000 + 100*j);
    [tp0, ~, ~, ~, inf0] = evalPolicy_v17('baseline', [], Strue, obsS, env0, meta, U);

    rng(80000 + 100*j);
    [tp8, ~, ~, ~, inf8] = evalPolicy_v17('baseline', [], Strue, obsS, env8, meta, U);

    b0 = min(envBase.burn_in, size(tp0, 1) - 1);
    [num0, den0, prim0_traces(j)] = userMetric_v17(envBase, tp0, inf0, b0);
    pu0 = num0 ./ max(den0, 1);
    jain0_traces(j) = sum(pu0)^2 / (N * max(sum(pu0.^2), eps));

    [num8, den8, prim8_traces(j)] = userMetric_v17(envBase, tp8, inf8, b0);
    pu8 = num8 ./ max(den8, 1);
    jain8_traces(j) = sum(pu8)^2 / (N * max(sum(pu8.^2), eps));
end

meanTp0 = mean(prim0_traces);
meanTp8 = mean(prim8_traces);
ratioTp = meanTp8 / meanTp0;

jain0 = mean(jain0_traces);
jain8 = mean(jain8_traces);
deltaJain = jain8 - jain0;

passRatio = (ratioTp >= 0.85) && (ratioTp <= 1.10);
passJain  = abs(deltaJain) <= 0.03;
allPass   = passRatio && passJain;

strRatio = 'PASS'; if ~passRatio, strRatio = 'FAIL'; end
strJain  = 'PASS'; if ~passJain,  strJain  = 'FAIL'; end
fprintf('Baseline RTT 0: Goodput = %.4f Mbps, Jain = %.4f\n', meanTp0, jain0);
fprintf('Baseline RTT 8: Goodput = %.4f Mbps, Jain = %.4f\n', meanTp8, jain8);
fprintf('Ratio (RTT8 / RTT0) = %.4f (Required: [0.85, 1.10]) -> %s\n', ratioTp, strRatio);
fprintf('Delta Jain          = %+.4f (Required: +/- 0.03)    -> %s\n', deltaJain, strJain);

if allPass
    fprintf('\n=== test_fairness_sanity_v17: ALL CHECKS PASSED ===\n');
else
    fprintf('\n=== test_fairness_sanity_v17: FAIL -- criteria exceeded ===\n');
    error('test_fairness_sanity_v17:fail', 'Fairness sanity criteria exceeded.');
end
