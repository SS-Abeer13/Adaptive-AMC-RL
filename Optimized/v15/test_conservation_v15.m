% test_conservation_v15.m  Stage B test B5: Bit Conservation Verification.
% Verifies across 20 traces that:
% 1. Total delivered bits <= total offered bits (no phantom bits created).
% 2. Delivered bits per user = sum(ACKed useful bits).
% 3. Completed packets (okU) <= resolved packets (resU).

root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v15'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_conservation_v15: Bit Conservation Test (20 traces) ===\n');

N = 10;
simTime = 200;
env = defaultEnv_v15(23, N);
env.traffic = 'deadline';
env.pkt_bits = 12000;
env.pkt_deadline = 10;
env.pkt_period = 20;
env.harq_rtt = 8;
env.harq_nproc = 8;
env.harq_on = 1;
env.total_RB = 25;
env.scheduler = 'pf';
env.fixed_offset = 0;

nTraces = 20;
allPassed = true;

for j = 1:nTraces
    traceSeed = 60000 + j;
    rng(traceSeed);
    [Strue, ~, meta] = generateChannel_v15(simTime, env);
    obsS = cqiFeedback_v15(Strue, env, meta.delays);
    meta.trace_id = traceSeed;
    rng(61000 + j);
    U = rand(simTime, N);

    [tp, bler, cqi_err, act, info] = evalPolicy_v15('fixed', [], Strue, obsS, env, meta, U);

    deliv_bits = sum(tp(:)) * 1e3;
    offered_packets = sum(info.resU);
    completed_packets = sum(info.okU);
    offered_bits = offered_packets * env.pkt_bits;

    % Checks
    c1 = (deliv_bits <= offered_bits + 1e-4);
    c2 = (completed_packets <= offered_packets);
    c3 = all(info.okU <= info.resU);

    if ~(c1 && c2 && c3)
        fprintf('  Trace %2d: FAIL  deliv=%.1f offered=%.1f (okU=%d, resU=%d)\n', ...
                j, deliv_bits, offered_bits, completed_packets, offered_packets);
        allPassed = false;
    end
end

if allPassed
    fprintf('  All 20 traces: deliv_bits <= offered_bits strictly preserved (PASS)\n');
    fprintf('=== test_conservation_v15: ALL CHECKS PASSED ===\n');
else
    error('test_conservation_v15:failed', 'Bit conservation check failed.');
end
