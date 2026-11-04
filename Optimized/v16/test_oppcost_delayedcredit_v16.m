% test_oppcost_delayedcredit_v16  Stage B3.3 (PLAN_v16.md): on a 2-user toy
% run with reward_kind = 'oppcost' and harq_rtt > 0, each transmission must
% get exactly one opportunity-cost charge at t (the per-TTI buffer push in
% DeepA2C_Shared_v16, keyed by dec_id) and one delivered-goodput credit at
% t + RTT (harqFeedback_v16's fbList, routed to the same dec_id via
% dec_buf_idx). LATECREDIT (trainInfo.total_credits / .late_credits) must
% be logged, not hardcoded to zero (see the Stage A finding on v15).
root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v16'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_oppcost_delayedcredit_v16: oppcost under RTT, 2 users ===\n');

N = 2;
env = defaultEnv_v16(23, N);
env.harq_rtt = 8; env.harq_nproc = 8;
env.reward_kind = 'oppcost';

[~, ~, lc, ~, ~, ~, ~, ~, trainInfo] = DeepA2C_Shared_v16(200, 15, 777, env);

ok = true;
if trainInfo.total_credits <= 0
    fprintf('  FAIL: total_credits == 0 (LATECREDIT would be a silent no-op, not a real count)\n');
    ok = false;
else
    fprintf('  total_credits = %d, late_credits = %d, late_credit_frac = %.4f (LATECREDIT logged, nonzero denominator)\n', ...
            trainInfo.total_credits, trainInfo.late_credits, trainInfo.late_credit_frac);
end
if ~(trainInfo.late_credit_frac >= 0 && trainInfo.late_credit_frac <= 1)
    fprintf('  FAIL: late_credit_frac out of [0,1] range (%.4f)\n', trainInfo.late_credit_frac);
    ok = false;
end
if any(~isfinite(lc)) || mean(lc) == 0
    fprintf('  FAIL: training produced no throughput at all (lc all zero/non-finite)\n');
    ok = false;
end

% Pairing sanity (same spirit as test_pairing_v16, specific to oppcost):
% every ACK/NACK-driven feedback event in a short deterministic replay has
% exactly one matching transmission decision -- reuse the harqTransmit/
% harqFeedback contract directly (as test_timing_v16 does) to confirm no
% dec_id is ever credited twice.
H = harqInit_v16(N, env);
Q = trafficInit_v16(env, N, 0);
off = zeros(1, N);
du = env.olla_step_down * env.olla_target / (1 - env.olla_target);
dd = env.olla_step_down;
seenDecIds = [];
doubleCredit = false;
sent = [10 10]; rb = [env.total_RB env.total_RB];
Strue_row = [10 10];
for t = 1:40
    [H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v16(H, Q, off, env, t, du, dd); %#ok<ASGLU>
    for fbi = 1:numel(fbList)
        d_id = fbList(fbi).dec_id;
        if d_id > 0
            if any(seenDecIds == d_id) && fbList(fbi).is_ack
                doubleCredit = true;
            end
            if fbList(fbi).is_ack, seenDecIds(end+1) = d_id; end %#ok<AGROW>
        end
    end
    cur_dec_ids = [0 0];
    if t <= 2, cur_dec_ids = [t t]; end  % two decisions, TTIs 1 and 2
    [H, Q] = harqTransmit_v16(sent, Strue_row, (t <= 2) * rb, H, Q, env, t, [], cur_dec_ids);
end
if doubleCredit
    fprintf('  FAIL: a dec_id received more than one ACK credit\n');
    ok = false;
else
    fprintf('  pairing sanity: no dec_id double-credited over 40 TTIs (PASS)\n');
end

if ok
    fprintf('=== test_oppcost_delayedcredit_v16: ALL CHECKS PASSED ===\n');
else
    error('test_oppcost_delayedcredit_v16:fail', 'see log above');
end
