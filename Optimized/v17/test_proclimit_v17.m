% test_proclimit_v17.m  Stage B test B3: Process Limit Verification.
% Verifies:
% With nproc = 2, rtt = 8, user never exceeds 2 blocks in flight,
% and is ineligible when both are busy and neither is retx-ready.

root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v17'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_proclimit_v17: HARQ Process Limit Test ===\n');

N = 2;
env = defaultEnv_v17(23, N);
env.harq_rtt = 8;
env.harq_nproc = 2;
env.harq_on = 1;
env.total_RB = 25;
env.pkt_bits = 12000;
env.pkt_deadline = 25;

H = harqInit_v17(N, env);
Q = trafficInit_v17(env, N, 0);
Q.has(1) = true; Q.rem(1) = 12000; Q.tx_rem(1) = 12000; Q.dl(1) = 30; Q.arr(1) = 1;

sent = 8 * ones(1, N);
Strue_row = [10.0, 10.0];
rb = [env.total_RB, 0];
du = 0.05; dd = 0.5;

% Transmission 1 at t = 1
t = 1;
[H, Q, ~, ~, ~, ~, ~, ~] = harqFeedback_v17(H, Q, zeros(1, N), env, t, du, dd);
[H, Q, ~, ~] = harqTransmit_v17(sent, Strue_row, rb, H, Q, env, t, [1.0, 1.0], [1, 0]);
nBusy1 = sum(H.proc_busy(1, :));
assert(nBusy1 == 1, 'Expected exactly 1 process busy after tx 1');

% Transmission 2 at t = 2
t = 2;
[H, Q, ~, ~, ~, ~, ~, ~] = harqFeedback_v17(H, Q, zeros(1, N), env, t, du, dd);
[H, Q, ~, ~] = harqTransmit_v17(sent, Strue_row, rb, H, Q, env, t, [1.0, 1.0], [2, 0]);
nBusy2 = sum(H.proc_busy(1, :));
assert(nBusy2 == 2, 'Expected exactly 2 processes busy after tx 2');
fprintf('  t=1, 2: Two blocks placed in flight (nproc=2 limit reached) (PASS)\n');

% At t = 3: Both processes busy in-flight, neither retx-ready
t = 3;
[H, Q, ~, ~, ~, ~, ~, ~] = harqFeedback_v17(H, Q, zeros(1, N), env, t, du, dd);
retxReady = any(H.proc_isRetx, 2)';
hasFree = any(~H.proc_busy, 2)' & (Q.tx_rem > 0);
elig = Q.has & (retxReady | hasFree);
assert(~elig(1), 'User 1 must be ineligible when both processes are busy in flight');

% Even if scheduler attempted to allocate, eligibility mask blocks it:
rb_trial = [env.total_RB, 0];
rb_trial(~elig) = 0;
assert(rb_trial(1) == 0, 'Ineligible user must receive 0 RBs');

% If harqTransmit is called with rb=0, no new process is consumed
[H, Q, ~, ~] = harqTransmit_v17(sent, Strue_row, rb_trial, H, Q, env, t, [1.0, 1.0]);
assert(sum(H.proc_busy(1, :)) == 2, 'Process count must never exceed nproc=2');
fprintf('  t=3: Ineligibility enforced, 0 RBs allocated, process limit strictly held (PASS)\n');

% At t = 9: feedback for block 1 arrives, freeing process 1
t = 9;
[H, Q, ~, ackEv, ~, ~, ~, fbList] = harqFeedback_v17(H, Q, zeros(1, N), env, t, du, dd);
assert(ackEv(1), 'ACK expected at t=9');
assert(sum(H.proc_busy(1, :)) == 1, 'One process freed upon ACK arrival');
hasFree = any(~H.proc_busy, 2)' & (Q.tx_rem > 0);
elig = Q.has & (any(H.proc_isRetx, 2)' | hasFree);
assert(elig(1), 'User 1 must be eligible again after process freed');
fprintf('  t=9: Process freed upon feedback, user becomes eligible again (PASS)\n');

fprintf('=== test_proclimit_v17: ALL CHECKS PASSED ===\n');
