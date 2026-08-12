function [Q, learning_curve] = QL_Shared_v6(simTime, num_episodes, seed, env)
% QL_Shared_v6  Shared-parameter tabular Q-Learning, OLLA-relative (v6).
%   Each user carries the SAME OLLA outer loop as the OLLA comparator
%   (offset updated on realized ACK/NACK of the sent CQI, when scheduled).
%   Reference CQI = baseCQI(obs + olla_off); action = offset from that,
%   so action 0 == OLLA and the learner starts at OLLA performance.
%   State = (ref_CQI, d_ref, obs-SINR bin, trend, OLLA-offset bin, regime).
%   Cooperative cell reward + reported-CQI PF inherited from audited v5.

    if ~isempty(seed), rng(seed); end
    N = env.N; A = env.actions; nA = numel(A); no_op = find(A == 0);
    SB = env.SINR_bins; nT = env.n_trend; te = env.trend_edges;
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;
    OE = env.off_edges; nO = numel(OE) + 1;
    du = env.olla_step_down * env.olla_target/(1 - env.olla_target);
    dd = env.olla_step_down;

    alpha = 0.1; gamma = env.gamma;
    epsilon = 0.30; eps_decay = (0.05/0.30)^(1/max(num_episodes,1));
    nSched = numel(env.sched_list);

    Q = zeros(maxC, maxD-minD+1, numel(SB), nT, nO, nSched, nA);
    learning_curve = zeros(num_episodes, 1);

    for ep = 1:num_episodes
        sched = sampleSched_v5(env);
        sc = schedContext_v5(sched, env);
        [Strue, ~, ~] = generateChannel_v5(simTime, env);
        [obsS, ~] = cqiFeedback_v5(Strue, env);
        off = zeros(1, N);                          % per-user OLLA state
        prevRef = baseCQI_v5(obsS(1,:) + off, env);
        R_emas = zeros(1, N); ema = 0.05; ep_tp = 0;

        for t = 1:simTime
            ref  = baseCQI_v5(obsS(t,:) + off, env);
            dRef = max(minD, min(maxD, ref - prevRef));
            aIdx = zeros(1,N); sent = zeros(1,N); bler = zeros(1,N);
            pot = zeros(1,N); si = zeros(1,N); tb = zeros(1,N); ob = zeros(1,N);
            for i = 1:N
                [~, si(i)] = min(abs(SB - obsS(t,i)));
                tb(i) = trendBin_v5(obsS(t,i) - obsS(max(t-1,1),i), te);
                ob(i) = 1 + sum(off(i) > OE);
                sd = dRef(i) + maxD + 1;
                if rand < epsilon, aIdx(i) = randi(nA);
                else, aIdx(i) = argmaxNoOp_v5(squeeze(Q(ref(i),sd,si(i),tb(i),ob(i),sc,:)), no_op); end
                sent(i) = max(minC, min(maxC, ref(i) + A(aIdx(i))));
                bler(i) = estimateBLER_v5(Strue(t,i), sent(i)-1);
                pot(i)  = pfPotential_v5(sent(i), bler(i), env);
            end

            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            tp_now = zeros(1,N);
            for i = 1:N
                if rb(i) > 0
                    tp_now(i) = (1-bler(i))*tbsFromMCSandRB(sent(i)-1, rb(i))*1e-3;
                    if rand > bler(i), off(i) = off(i) + du;   % realized ACK/NACK
                    else,              off(i) = off(i) - dd; end
                end
            end
            R_emas = (1-ema)*R_emas + ema*tp_now; ep_tp = ep_tp + sum(tp_now);
            coopR  = isfield(env,'reward_agg') && strcmpi(env.reward_agg,'cell');
            r_cell = sum(tp_now) / env.reward_scale;

            tn = min(t+1, simTime);
            refN  = baseCQI_v5(obsS(tn,:) + off, env);
            dRefN = max(minD, min(maxD, refN - ref));
            for i = 1:N
                if coopR, r = r_cell;
                elseif rb(i) > 0, r = computeReward_v5(bler(i), tbsFromMCSandRB(sent(i)-1, rb(i)), env);
                else, r = 0; end
                [~, nsi] = min(abs(SB - obsS(tn,i)));
                ntb = trendBin_v5(obsS(tn,i) - obsS(t,i), te);
                nob = 1 + sum(off(i) > OE);
                sd = dRef(i) + maxD + 1;
                maxQ = max(Q(refN(i), dRefN(i)+maxD+1, nsi, ntb, nob, sc, :));
                Q(ref(i),sd,si(i),tb(i),ob(i),sc,aIdx(i)) = Q(ref(i),sd,si(i),tb(i),ob(i),sc,aIdx(i)) + ...
                    alpha*(r + gamma*maxQ - Q(ref(i),sd,si(i),tb(i),ob(i),sc,aIdx(i)));
            end
            prevRef = ref;
        end
        learning_curve(ep) = ep_tp / simTime;
        epsilon = epsilon * eps_decay;
    end
end
