% test_timing_v16.m  Stage B test B2: Feedback Timing Verification.
% Verifies:
% 1. Transmission at t modifies OLLA and processes at exactly t + rtt.
% 2. Retransmissions occur no earlier than t + rtt.

root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v16'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_timing_v16: HARQ Feedback Timing Test ===\n');

N = 2;
env = defaultEnv_v16(23, N);
env.harq_rtt = 8;
env.harq_nproc = 8;
env.harq_on = 1;
env.olla_target = 0.10;
env.olla_step_down = 0.50;
du = env.olla_step_down * env.olla_target / (1 - env.olla_target);
dd = env.olla_step_down;

% Initialize
H = harqInit_v16(N, env);
Q = trafficInit_v16(env, N, 0);
off = zeros(1, N);

% User 1 has an active packet
Q.has(1) = true; Q.rem(1) = 12000; Q.tx_rem(1) = 12000; Q.dl(1) = 25; Q.arr(1) = 1;

% Force NACK on first transmission by setting u = 0 (channel draw <= bler)
u_nack = zeros(1, N);
sent = 8 * ones(1, N);
rb = [env.total_RB, 0];
Strue_row = [5.0, 5.0];

% Transmit at t = 1
t = 1;
% At t=1, no feedback yet
[H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v16(H, Q, off, env, t, du, dd);
assert(off(1) == 0, 'OLLA offset modified prematurely at t=1');
assert(~any(H.proc_busy(1, :)), 'Processes should not be busy before transmission');

% Transmission step
dec_ids = [101, 0];
[H, Q, bler1, isRetxTx] = harqTransmit_v16(sent, Strue_row, rb, H, Q, env, t, u_nack, dec_ids);
assert(H.proc_busy(1, 1), 'Process 1 should be busy after tx at t=1');
assert(H.proc_ready_t(1, 1) == 9, 'Process ready_t should be 1 + 8 = 9');
assert(~H.proc_isRetx(1, 1), 'Process should not be marked retx before feedback arrives');
assert(off(1) == 0, 'OLLA offset should still be 0 right after tx');

% Test TTIs 2 through 8: feedback must NOT mature, offset must NOT change
for tt = 2:8
    [H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v16(H, Q, off, env, tt, du, dd);
    assert(off(1) == 0, sprintf('OLLA offset prematurely modified at t=%d', tt));
    assert(~H.proc_isRetx(1, 1), sprintf('Retx prematurely flagged at t=%d', tt));
    assert(isempty(fbList), sprintf('Feedback prematurely delivered at t=%d', tt));
end
fprintf('  TTIs 1..8: No premature feedback or OLLA updates (PASS)\n');

% At t = 9 (1 + rtt): feedback MUST arrive
tt = 9;
[H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v16(H, Q, off, env, tt, du, dd);
assert(nackEv(1), 'NACK event expected at t=9');
assert(abs(off(1) - (-dd)) < 1e-9, sprintf('OLLA offset at t=9 should be -%.2f, got %.2f', dd, off(1)));
assert(H.proc_isRetx(1, 1), 'Process 1 should be marked retx-ready at t=9');
assert(numel(fbList) == 1 && fbList(1).dec_id == 101 && ~fbList(1).is_ack, 'fbList mismatch at t=9');
fprintf('  TTI 9: Feedback matured exactly at t = 1 + rtt (PASS)\n');

% At t = 9, retransmission is transmitted
[H, Q, bler1, isRetxTx] = harqTransmit_v16(sent, Strue_row, rb, H, Q, env, tt, u_nack);
assert(isRetxTx(1), 'Retransmission should be executed at t=9');
assert(~H.proc_isRetx(1, 1), 'Process 1 should no longer be marked retx-ready after retransmission');
assert(H.proc_ready_t(1, 1) == 17, 'Next feedback ready_t should be 9 + 8 = 17');
fprintf('  TTI 9: Retransmission scheduled no earlier than t + rtt (PASS)\n');

fprintf('=== test_timing_v16: ALL CHECKS PASSED ===\n');
