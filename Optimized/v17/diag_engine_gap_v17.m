% diag_engine_gap_v17.m  Engine-gap diagnosis: legacy (rtt 0, nproc 1) vs new (rtt 1, nproc 1)
% Under K3-like environment, Baseline policy, 3 traces detailed, 20 traces measured decomposition.
% Compares legacy rtt 0 vs new rtt 1 under:
%   (1) Default acked PF averaging (no drain) -> ~10% gap
%   (2) Scheduled PF averaging + drain -> measured decomposition & gap quantification

root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v17'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('========================================================================\n');
fprintf('  Stage A1: Engine-Gap Diagnosis (v17)\n');
fprintf('  Comparing Legacy Engine (RTT 0, nproc 1) vs New Engine (RTT 1, nproc 1)\n');
fprintf('========================================================================\n\n');

% 1. K3 environment setup
N = 10;
simTime = 200;
nTraces = 3;
trace_seed_base = 440000;
crn_seed_base = 450000;

env = defaultEnv_v17(23, N);
env.traffic = 'full';
env.reward_kind = 'oppcost';
env.primary = 'goodput';
env.feat_extra = {'harqx'};
env.ctx_cue = 'none';
env.ctx_edges = [];
env.eval_schedulers = {'pf'};
env.sched_on_ref = true;

env_a = env; env_a.harq_rtt = 0; env_a.harq_nproc = 1;
env_b = env; env_b.harq_rtt = 1; env_b.harq_nproc = 1;

ema = 0.05;

for j = 1:nTraces
    trace_seed = trace_seed_base + j;
    crn_seed = crn_seed_base + j;
    
    rng(trace_seed);
    [Strue, ~, meta] = generateChannel_v17(simTime, env);
    obsS = cqiFeedback_v17(Strue, env, meta.delays);
    meta.trace_id = j;
    
    rng(crn_seed);
    U = rand(simTime, N);
    
    % --- (a) Instrumented Legacy Engine (rtt 0, nproc 1) ---
    off_a = zeros(1, N);
    H_a = harqInit_v17(N, env_a);
    R_emas_a = zeros(1, N);
    Q_a = trafficInit_v17(env_a, N);
    
    log_a = struct();
    log_a.sch_user = zeros(simTime, 1);
    log_a.mcs = zeros(simTime, 1);
    log_a.tbs = zeros(simTime, 1);
    log_a.is_retx = false(simTime, 1);
    log_a.outcome_draw = zeros(simTime, 1);
    log_a.bits_credited = zeros(simTime, 1);
    log_a.R_emas_sched = zeros(simTime, N);
    log_a.R_emas_post = zeros(simTime, N);
    log_a.pot = zeros(simTime, N);
    log_a.tp = zeros(simTime, N);
    
    for t = 1:simTime
        ref = baseCQI_v17(obsS(t, :) + off_a, env_a);
        sent = ref;
        rbFull = env_a.total_RB * ones(1, N);
        pot = tbsFromMCSandRB_v17(max(env_a.min_CQI, min(env_a.max_CQI, ref)) - 1, rbFull) * 1e-3;
        if env_a.harq_on && any(H_a.pend)
            pend_idx = find(H_a.pend);
            pot(pend_idx) = tbsFromMCSandRB_v17(H_a.mcs(pend_idx), 100*ones(size(pend_idx))) * 1e-3;
        end
        pot(~Q_a.has) = 0;
        dlv = inf(1, N); dlv(Q_a.has) = Q_a.dl(Q_a.has);
        
        log_a.R_emas_sched(t, :) = R_emas_a;
        log_a.pot(t, :) = pot;
        
        rb = schedule_users_v17(env_a.scheduler, t, N, R_emas_a, pot, env_a.total_RB, dlv);
        rb(~Q_a.has) = 0;
        sch_u = find(rb > 0);
        log_a.sch_user(t) = sch_u;
        
        uRow = U(t, :);
        isRetx = env_a.harq_on && any(H_a.pend) && H_a.pend(sch_u);
        log_a.is_retx(t) = isRetx;
        log_a.outcome_draw(t) = uRow(sch_u);
        if isRetx
            log_a.mcs(t) = H_a.mcs(sch_u);
            log_a.tbs(t) = H_a.tbs(sch_u);
        else
            log_a.mcs(t) = sent(sch_u) - 1;
            log_a.tbs(t) = tbsFromMCSandRB_v17(log_a.mcs(t), rb(sch_u));
        end
        
        [tpr, ~, H_a, bl1, ~] = txStep_v17(sent, Strue(t, :), rb, zeros(1, N), H_a, env_a, uRow);
        [Q_a, ~] = trafficPost_v17(Q_a, tpr, t);
        
        log_a.tp(t, :) = tpr;
        log_a.bits_credited(t) = tpr(sch_u) * 1e3;
        R_emas_a = (1 - ema) * R_emas_a + ema * tpr;
        log_a.R_emas_post(t, :) = R_emas_a;
    end
    
    % --- (b) Instrumented New Engine (rtt 1, nproc 1) default acked ---
    off_b = zeros(1, N);
    H_b = harqInit_v17(N, env_b);
    R_emas_b = zeros(1, N);
    Q_b = trafficInit_v17(env_b, N);
    
    log_b = struct();
    log_b.sch_user = zeros(simTime, 1);
    log_b.bits_credited = zeros(simTime, 1);
    log_b.R_emas_sched = zeros(simTime, N);
    log_b.R_emas_post = zeros(simTime, N);
    log_b.pot = zeros(simTime, N);
    log_b.tp = zeros(simTime, N);
    
    for t = 1:simTime
        [H_b, Q_b, ~, ~, ~, ~, tp_ack, ~] = harqFeedback_v17(H_b, Q_b, off_b, env_b, t, 0, 0);
        [Q_b, H_b] = trafficPre_v17(Q_b, t, env_b, H_b);
        ref = baseCQI_v17(obsS(t, :) + off_b, env_b);
        sent = ref;
        
        pot = zeros(1, N);
        retxReady = any(H_b.proc_isRetx, 2)';
        hasFree = any(~H_b.proc_busy, 2)' & (Q_new.tx_rem > 0);
        elig = Q_b.has & (retxReady | hasFree);
        for i = 1:N
            if ~elig(i), continue; end
            if retxReady(i)
                p_retx = find(H_b.proc_isRetx(i, :), 1);
                pot(i) = tbsFromMCSandRB_v17(H_b.proc_mcs(i, p_retx), env_b.total_RB) * 1e-3;
            else
                pot(i) = tbsFromMCSandRB_v17(sent(i) - 1, env_b.total_RB) * 1e-3;
            end
        end
        dlv = inf(1, N); dlv(Q_b.has) = Q_b.dl(Q_b.has);
        
        log_b.R_emas_sched(t, :) = R_emas_b;
        log_b.pot(t, :) = pot;
        
        rb = schedule_users_v17(env_b.scheduler, t, N, R_emas_b, pot, env_b.total_RB, dlv);
        rb(~elig) = 0;
        sch_u = find(rb > 0);
        if isempty(sch_u), sch_u = 0; end
        log_b.sch_user(t) = sch_u;
        
        uRow = U(t, :);
        [H_b, Q_b, ~, ~] = harqTransmit_v17(sent, Strue(t, :), rb, H_b, Q_b, env_b, t, uRow);
        
        log_b.tp(t, :) = tp_ack;
        log_b.bits_credited(t) = sum(tp_ack) * 1e3;
        R_emas_b = (1 - ema) * R_emas_b + ema * tp_ack;
        log_b.R_emas_post(t, :) = R_emas_b;
    end
    
    fprintf('--- TRACE %d (seed %d, crn %d) ---\n', j, trace_seed, crn_seed);
    user_diff_ttis = find(log_a.sch_user ~= log_b.sch_user);
    fprintf('  FIRST TTI WHERE SCHEDULED USER DIFFERS: TTI %d\n', user_diff_ttis(1));
    bits_diff_ttis = find(log_a.bits_credited ~= log_b.bits_credited);
    fprintf('  FIRST TTI WHERE CREDITED BITS DIFFER:   TTI %d (Legacy credited %d, New credited %d)\n\n', ...
            bits_diff_ttis(1), log_a.bits_credited(bits_diff_ttis(1)), log_b.bits_credited(bits_diff_ttis(1)));
end

% -------------------------------------------------------------------------
% 20-Trace Measured Decomposition (pf_avg = 'scheduled' + drain)
% -------------------------------------------------------------------------
fprintf('========================================================================\n');
fprintf('  MEASURED DECOMPOSITION OVER 20 TRACES (pf_avg = scheduled + drain)\n');
fprintf('========================================================================\n');

nTraces20 = 20;
tot_bits_leg = zeros(nTraces20, 1);
tot_bits_new = zeros(nTraces20, 1);
inelig_count = zeros(nTraces20, 1);
user_diff_count = zeros(nTraces20, 1);
bits_diff_count = zeros(nTraces20, 1);
jain_leg = zeros(nTraces20, 1);
jain_new = zeros(nTraces20, 1);

for j = 1:nTraces20
    rng(trace_seed_base + j); [Strue, ~, meta] = generateChannel_v17(simTime, env);
    obsS = cqiFeedback_v17(Strue, env, meta.delays);
    rng(crn_seed_base + j); U = rand(simTime, N);
    
    % (a) Legacy rtt 0, scheduled PF
    R_leg = zeros(1, N); H_leg = harqInit_v17(N, env_a); Q_leg = trafficInit_v17(env_a, N);
    sch_leg = zeros(simTime, 1);
    bits_leg = zeros(simTime, 1);
    u_tp_leg = zeros(1, N);
    
    for t = 1:simTime
        ref = baseCQI_v17(obsS(t, :), env_a); sent = ref;
        pot = tbsFromMCSandRB_v17(ref - 1, 100*ones(1, N)) * 1e-3;
        if env_a.harq_on && any(H_leg.pend)
            pend_idx = find(H_leg.pend);
            pot(pend_idx) = tbsFromMCSandRB_v17(H_leg.mcs(pend_idx), 100*ones(size(pend_idx))) * 1e-3;
        end
        rb = schedule_users_v17('pf', t, N, R_leg, pot, 100, inf(1, N));
        u = find(rb > 0); sch_leg(t) = u;
        [tpr, ~, H_leg, ~, ~] = txStep_v17(sent, Strue(t, :), rb, zeros(1, N), H_leg, env_a, U(t, :));
        bits_leg(t) = tpr(u) * 1e3;
        u_tp_leg = u_tp_leg + tpr;
        sch_rate = zeros(1, N);
        sch_rate(u) = tbsFromMCSandRB_v17(sent(u)-1, 100) * 1e-3;
        R_leg = (1 - ema) * R_leg + ema * sch_rate;
    end
    tot_bits_leg(j) = sum(bits_leg);
    pu_leg = u_tp_leg / simTime;
    jain_leg(j) = (sum(pu_leg)^2) / (N * sum(pu_leg.^2));
    
    % (b) New rtt 1, scheduled PF + drain
    R_new = zeros(1, N); H_new = harqInit_v17(N, env_b); Q_new = trafficInit_v17(env_b, N);
    sch_new = zeros(simTime, 1);
    bits_new = zeros(simTime, 1);
    u_tp_new = zeros(1, N);
    tx_user_at_t = zeros(simTime, 1);
    
    for t = 1:simTime
        [H_new, Q_new, ~, ~, ~, ~, tp_ack, ~] = harqFeedback_v17(H_new, Q_new, zeros(1, N), env_b, t, 0, 0);
        if t > 1
            u_prev = tx_user_at_t(t-1);
            if u_prev > 0
                bits_new(t-1) = tp_ack(u_prev) * 1e3;
                u_tp_new(u_prev) = u_tp_new(u_prev) + tp_ack(u_prev);
            end
        end
        
        ref = baseCQI_v17(obsS(t, :), env_b); sent = ref;
        pot_all = tbsFromMCSandRB_v17(sent - 1, 100*ones(1, N)) * 1e-3;
        [~, pf_pref] = max(pot_all ./ max(R_new, 0.1));
        
        retxReady = any(H_new.proc_isRetx, 2)';
        hasFree = any(~H_new.proc_busy, 2)' & (Q_new.tx_rem > 0);
        elig = Q_new.has & (retxReady | hasFree);
        
        if ~elig(pf_pref)
            inelig_count(j) = inelig_count(j) + 1;
        end
        
        pot = zeros(1, N);
        for i = 1:N
            if ~elig(i), continue; end
            if retxReady(i)
                p_retx = find(H_new.proc_isRetx(i, :), 1);
                pot(i) = tbsFromMCSandRB_v17(H_new.proc_mcs(i, p_retx), 100) * 1e-3;
            else
                pot(i) = tbsFromMCSandRB_v17(sent(i) - 1, 100) * 1e-3;
            end
        end
        rb = schedule_users_v17('pf', t, N, R_new, pot, 100, inf(1, N));
        rb(~elig) = 0;
        u = find(rb > 0);
        if isempty(u), u = 0; end
        sch_new(t) = u;
        tx_user_at_t(t) = u;
        
        sch_rate = zeros(1, N);
        if u > 0
            sch_rate(u) = tbsFromMCSandRB_v17(sent(u) - 1, 100) * 1e-3;
        end
        [H_new, Q_new, ~, ~] = harqTransmit_v17(sent, Strue(t, :), rb, H_new, Q_new, env_b, t, U(t, :));
        R_new = (1 - ema) * R_new + ema * sch_rate;
    end
    
    % Drain TTI: t = 201
    [H_new, Q_new, ~, ~, ~, ~, tp_ack, ~] = harqFeedback_v17(H_new, Q_new, zeros(1, N), env_b, simTime + 1, 0, 0);
    u_last = tx_user_at_t(simTime);
    if u_last > 0
        bits_new(simTime) = tp_ack(u_last) * 1e3;
        u_tp_new(u_last) = u_tp_new(u_last) + tp_ack(u_last);
    end
    
    tot_bits_new(j) = sum(bits_new);
    pu_new = u_tp_new / simTime;
    jain_new(j) = (sum(pu_new)^2) / (N * sum(pu_new.^2));
    
    user_diff_count(j) = sum(sch_leg ~= sch_new);
    bits_diff_count(j) = sum(bits_leg ~= bits_new);
end

fprintf('Summary over %d traces:\n', nTraces20);
fprintf('  Legacy Engine (rtt 0, scheduled PF):          Goodput = %.4f Mbps, Jain = %.4f\n', ...
        mean(tot_bits_leg)*1e-3/simTime, mean(jain_leg));
fprintf('  New Engine (rtt 1, scheduled PF + drain):     Goodput = %.4f Mbps, Jain = %.4f\n', ...
        mean(tot_bits_new)*1e-3/simTime, mean(jain_new));
gap_pct = 100 * (mean(tot_bits_new) - mean(tot_bits_leg)) / mean(tot_bits_leg);
fprintf('  Remaining Gap:                                %+.3f %%\n', gap_pct);
fprintf('  Jain Difference:                              %+.4f\n\n', mean(jain_new) - mean(jain_leg));

fprintf('Decomposition (4,000 TTIs across 20 traces):\n');
fprintf('  TTIs where preferred user was ineligible:     %d (%.2f %%)\n', sum(inelig_count), 100*sum(inelig_count)/(nTraces20*simTime));
fprintf('  TTIs where scheduled user differed:           %d (%.2f %%)\n', sum(user_diff_count), 100*sum(user_diff_count)/(nTraces20*simTime));
fprintf('  TTIs where credited bits differed:            %d (%.2f %%)\n', sum(bits_diff_count), 100*sum(bits_diff_count)/(nTraces20*simTime));
