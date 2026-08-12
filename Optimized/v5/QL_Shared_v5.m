function [Q, learning_curve] = QL_Shared_v5(simTime, num_episodes, seed, env)
% QL_Shared_v5  Shared-parameter tabular Q-Learning, baseline-relative.
%   ONE Q-table pooled across all N users (case2_3 v4 idea: N x more samples
%   per state-action cell). State = (base_CQI, d_base, obs_SINR bin, trend);
%   action = offset from baseline CQI (offset 0 == baseline). Reward from the
%   true channel. No bias init, no imitation bonus (audit C3/C4); greedy ties
%   broken toward no-op (audit fix for the v4 QL collapse).

    if ~isempty(seed), rng(seed); end
    N = env.N; A = env.actions; nA = numel(A); no_op = find(A == 0);
    SB = env.SINR_bins; nT = env.n_trend; te = env.trend_edges;
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;

    alpha = 0.1; gamma = env.gamma;
    epsilon = 0.30; eps_decay = (0.05/0.30)^(1/max(num_episodes,1));
    nSched = numel(env.sched_list);

    % shared table; extra dimension = observable scheduler regime
    Q = zeros(maxC, maxD-minD+1, numel(SB), nT, nSched, nA);
    learning_curve = zeros(num_episodes, 1);

    for ep = 1:num_episodes
        sched = sampleSched_v5(env);
        sc = schedContext_v5(sched, env);   % regime index (observable)
        [Strue, ~, ~] = generateChannel_v5(simTime, env);
        [obsS, ~] = cqiFeedback_v5(Strue, env);
        prevBase = baseCQI_v5(obsS(1, :), env);
        R_emas = zeros(1, N); ema = 0.05; ep_tp = 0;

        for t = 1:simTime
            base = baseCQI_v5(obsS(t, :), env);
            dB   = max(minD, min(maxD, base - prevBase));
            aIdx = zeros(1,N); sent = zeros(1,N); bler = zeros(1,N);
            pot = zeros(1,N); si = zeros(1,N); tb = zeros(1,N);
            for i = 1:N
                [~, si(i)] = min(abs(SB - obsS(t,i)));
                tb(i) = trendBin_v5(obsS(t,i) - obsS(max(t-1,1),i), te);
                sd = dB(i) + maxD + 1;
                if rand < epsilon, aIdx(i) = randi(nA);
                else, aIdx(i) = argmaxNoOp_v5(squeeze(Q(base(i),sd,si(i),tb(i),sc,:)), no_op); end
                sent(i) = max(minC, min(maxC, base(i) + A(aIdx(i))));
                bler(i) = estimateBLER_v5(Strue(t,i), sent(i)-1);
                pot(i)  = (1-bler(i)) * tbsFromMCSandRB(sent(i)-1, env.total_RB) * 1e-3;
            end

            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            tp_now = zeros(1,N);
            for i = 1:N
                if rb(i) > 0, tp_now(i) = (1-bler(i))*tbsFromMCSandRB(sent(i)-1, rb(i))*1e-3; end
            end
            R_emas = (1-ema)*R_emas + ema*tp_now; ep_tp = ep_tp + sum(tp_now);

            tn = min(t+1, simTime);
            baseN = baseCQI_v5(obsS(tn, :), env);
            dBN = max(minD, min(maxD, baseN - base));
            for i = 1:N
                if rb(i) > 0, r = computeReward_v5(bler(i), tbsFromMCSandRB(sent(i)-1, rb(i)), env);
                else, r = 0; end
                [~, nsi] = min(abs(SB - obsS(tn,i)));
                ntb = trendBin_v5(obsS(tn,i) - obsS(t,i), te);
                sd = dB(i) + maxD + 1;
                maxQ = max(Q(baseN(i), dBN(i)+maxD+1, nsi, ntb, sc, :));
                Q(base(i),sd,si(i),tb(i),sc,aIdx(i)) = Q(base(i),sd,si(i),tb(i),sc,aIdx(i)) + ...
                    alpha*(r + gamma*maxQ - Q(base(i),sd,si(i),tb(i),sc,aIdx(i)));
            end
            prevBase = base;
        end
        learning_curve(ep) = ep_tp / simTime;
        epsilon = epsilon * eps_decay;
    end
end
