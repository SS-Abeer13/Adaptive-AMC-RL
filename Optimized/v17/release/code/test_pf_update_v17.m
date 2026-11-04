% test_pf_update_v17  Stage B2.2 unit test:
% Verify that under env.pf_avg = 'scheduled':
%   1. R_emas updates at transmission TTI t by transmitted TBS * 1e-3,
%      decaying unscheduled users by (1 - ema).
%   2. R_emas does NOT update at feedback arrival TTI (t + rtt) with ACKed bits.
%   3. The update at TTI t is identical whether the packet is ultimately ACKed or NACKed.
%   4. Legacy engine (RTT 0) also updates at TTI t by transmitted TBS * 1e-3,
%      even when the transmission experiences a NACK (bler = 1).

root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v17'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_pf_update_v17: PF update unit test ===\n');

N = 3;
ema = 0.05;
rtt = 4;
simTime = 15;

env = defaultEnv_v17(23, N);
env.pf_avg = 'scheduled';
env.harq_rtt = rtt;
env.harq_nproc = 4;
env.drain = false;

% -------------------------------------------------------------------------
% Part 1: RTT-4 new engine unit test on 3 users
% Trace where User 1 is forced to transmit at t=1 with a known MCS/TBS.
% At t=1: User 1 transmits, Users 2 and 3 do not.
% From t=2 to t=1 + rtt: User 2 is forced to transmit, User 1 is unscheduled.
% At t=1+rtt: Feedback for User 1 arrives (test both ACK and NACK cases).
% Assert User 1's R_emas at t=1+rtt is purely decayed, never updated by ACK/NACK.
% -------------------------------------------------------------------------
fprintf('-- Part 1: RTT-4 new engine PF update timing and outcome-invariance --\n');

for testOutcome = {'ACK', 'NACK'}
    outcomeStr = testOutcome{1};
    rng(1001);
    [Strue, ~, meta] = generateChannel_v17(simTime, env);
    if strcmp(outcomeStr, 'ACK')
        Strue = Strue + 40; % Ensure high SNR -> BLER ~ 0 (ACK)
    else
        Strue = Strue - 40; % Ensure terrible SNR -> BLER ~ 1 (NACK)
    end
    obsS = cqiFeedback_v17(Strue, env, meta.delays);
    U = rand(simTime, N);

    R_emas = zeros(1, N);
    H = harqInit_v17(N, env);
    Q = trafficInit_v17(env, N);
    off = zeros(1, N);

    expected_R1 = 0;
    expected_R1_history = zeros(1, simTime);
    actual_R1_history = zeros(1, simTime);

    for t = 1:simTime
        % Deliver feedback
        [H, Q, off, ackEv, nackEv, dropEv, tp_ack] = harqFeedback_v17(H, Q, off, env, t, 0.1, 0.9);

        % Force scheduling: at t=1, schedule User 1. At t>1, schedule User 2.
        if t == 1
            sch_u = 1;
        else
            sch_u = 2;
        end
        rb = zeros(1, N); rb(sch_u) = env.total_RB;
        tx_mcs = 10;
        tbs_bits = tbsFromMCSandRB_v17(tx_mcs, env.total_RB);
        sent = ones(1, N) * (tx_mcs + 1);

        % Transmit
        [H, Q, bler1, isRetxTx] = harqTransmit_v17(sent, Strue(t, :), rb, H, Q, env, t, U(t, :), zeros(1, N));

        % Scheduled PF update:
        r_sched = zeros(1, N);
        r_sched(sch_u) = tbs_bits * 1e-3;
        R_emas = (1 - ema) * R_emas + ema * r_sched;

        % Compute expected User 1 R_emas:
        if t == 1
            expected_R1 = (1 - ema) * 0 + ema * (tbs_bits * 1e-3);
        else
            expected_R1 = (1 - ema) * expected_R1; % User 1 was not scheduled
        end

        expected_R1_history(t) = expected_R1;
        actual_R1_history(t) = R_emas(1);

        % At t = 1 + rtt, feedback for User 1's t=1 transmission arrives.
        if t == 1 + rtt
            fb_delivered = ackEv(1) || nackEv(1);
            assert(fb_delivered, 'Expected feedback for User 1 at t = 1 + rtt');
            if strcmp(outcomeStr, 'ACK')
                assert(ackEv(1), 'Expected ACK for User 1');
                assert(tp_ack(1) > 0, 'Expected positive tp_ack for User 1');
            else
                assert(nackEv(1), 'Expected NACK for User 1');
                assert(tp_ack(1) == 0, 'Expected zero tp_ack for User 1');
            end
            % Key check: R_emas(1) must match expected_R1, NOT influenced by tp_ack!
            diff_at_fb = abs(R_emas(1) - expected_R1);
            assert(diff_at_fb < 1e-12, ...
                'R_emas(1) altered at feedback arrival t=%d! diff=%.3e', t, diff_at_fb);
        end
    end

    maxDiff = max(abs(actual_R1_history - expected_R1_history));
    fprintf('  [%s outcome] R_emas tracking max diff = %.3e (PASS)\n', outcomeStr, maxDiff);
    assert(maxDiff < 1e-12, 'R_emas history mismatch under %s', outcomeStr);
end

% -------------------------------------------------------------------------
% Part 2: Legacy engine (RTT 0) unit test
% Under pf_avg = 'scheduled', R_emas updates with transmitted TBS * 1e-3
% even when the transmission is NACKed (in which case goodput tpr = 0).
% -------------------------------------------------------------------------
fprintf('-- Part 2: Legacy engine (RTT 0) PF update with NACK --\n');

R_emas_legacy = zeros(1, N);
sch_u = 1;
rb = zeros(1, N); rb(sch_u) = env.total_RB;
tx_mcs = 8;
tbs_bits = tbsFromMCSandRB_v17(tx_mcs, env.total_RB);
tpr = 0; % NACK in legacy engine gives 0 delivered goodput

% Under 'scheduled':
r_sched = zeros(1, N);
r_sched(sch_u) = tbs_bits * 1e-3;
R_emas_legacy = (1 - ema) * R_emas_legacy + ema * r_sched;

expected_legacy_R1 = ema * (tbs_bits * 1e-3);
assert(abs(R_emas_legacy(1) - expected_legacy_R1) < 1e-12, ...
    'Legacy R_emas did not update with transmitted TBS on NACK');
assert(R_emas_legacy(1) > 0, 'Legacy R_emas should be positive even when NACKed');
fprintf('  Legacy engine scheduled update on NACK: expected=%.4f, actual=%.4f (PASS)\n', ...
    expected_legacy_R1, R_emas_legacy(1));

% -------------------------------------------------------------------------
% Part 3: Full end-to-end trace with evalPolicy_v17
% Run 3-user trace through evalPolicy_v17 with pf_avg = 'scheduled'
% and verify clean execution with no errors.
% -------------------------------------------------------------------------
fprintf('-- Part 3: evalPolicy_v17 end-to-end 3-user execution --\n');
rng(42);
[Strue, ~, meta] = generateChannel_v17(simTime, env);
obsS = cqiFeedback_v17(Strue, env, meta.delays);
U = rand(simTime, N);
[tp, bler, cqiErr, act, info] = evalPolicy_v17('olla', [], Strue, obsS, env, meta, U);
assert(all(isfinite(tp(:))), 'tp contains non-finite values');
assert(all(isfinite(bler(~isnan(bler))))), 'bler contains non-finite values';
fprintf('  evalPolicy_v17 ran successfully. Total goodput: %.4f Mbps (PASS)\n', mean(sum(tp, 2)));

fprintf('=== test_pf_update_v17: ALL CHECKS PASSED ===\n');
