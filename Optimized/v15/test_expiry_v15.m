% test_expiry_v15.m  Stage B test B4: Deadline Expiry Verification.
% Verifies:
% In-flight blocks are discarded at packet deadline expiry;
% late ACKs arriving after deadline expiry are strictly ignored.

root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v15'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_expiry_v15: Deadline Expiry and Late ACK Test ===\n');

N = 2;
env = defaultEnv_v15(23, N);
env.traffic = 'deadline';
env.harq_rtt = 8;
env.harq_nproc = 4;
env.harq_on = 1;
env.total_RB = 25;
env.pkt_bits = 12000;
env.pkt_deadline = 10;
env.pkt_period = 50;

H = harqInit_v15(N, env);
Q = trafficInit_v15(env, N, 0);

% Packet arrival at t = 1, deadline is t + 10 - 1 = 10
Q.has(1) = true; Q.rem(1) = 12000; Q.tx_rem(1) = 12000; Q.dl(1) = 10; Q.arr(1) = 1;
sent = 8 * ones(1, N);
Strue_row = [15.0, 15.0];
rb = [env.total_RB, 0];
du = 0.05; dd = 0.5;

% Transmission occurs at t = 4 -> feedback arrives at t = 4 + 8 = 12 (after dl = 10!)
t = 4;
[H, Q, ~, ~] = harqTransmit_v15(sent, Strue_row, rb, H, Q, env, t, [1.0, 1.0], [42, 0]);
assert(H.proc_busy(1, 1), 'Process 1 should be busy');
assert(H.proc_ready_t(1, 1) == 12, 'Feedback scheduled for t=12');
fprintf('  t=4: Block transmitted with mature_t = 12 (past deadline 10) (PASS)\n');

% At t = 10: deadline is still active
t = 10;
[Q, H, missEv] = trafficPre_v15(Q, t, env, H);
assert(~missEv(1), 'Packet should not miss at t=10');
assert(Q.has(1), 'Packet should still be active at t=10');

% At t = 11: deadline expires (t > Q.dl = 10)
t = 11;
[Q, H, missEv] = trafficPre_v15(Q, t, env, H);
assert(missEv(1), 'Deadline miss event expected at t=11');
assert(~Q.has(1), 'Packet should be cleared after deadline miss');
assert(~any(H.proc_busy(1, :)), 'All in-flight processes must be flushed upon deadline miss');
assert(H.proc_ready_t(1, 1) == 0, 'Process ready_t must be reset to 0');
fprintf('  t=11: Packet expired, miss registered, in-flight process flushed (PASS)\n');

% At t = 12: late feedback would arrive if not flushed
t = 12;
[H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v15(H, Q, zeros(1, N), env, t, du, dd);
assert(~ackEv(1), 'No ACK event should occur from flushed process');
assert(tp_ack(1) == 0, 'No delivered throughput from late feedback');
assert(isempty(fbList), 'fbList must be empty for late feedback');
assert(Q.okU(1) == 0, 'No packet delivery credit given after deadline');
fprintf('  t=12: Late feedback arrival completely ignored (PASS)\n');

fprintf('=== test_expiry_v15: ALL CHECKS PASSED ===\n');
