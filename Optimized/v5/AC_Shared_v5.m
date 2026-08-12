function [theta, V, learning_curve] = AC_Shared_v5(simTime, num_episodes, seed, env)
% AC_Shared_v5  Shared-parameter tabular Actor-Critic, baseline-relative.
%   ONE theta + V pooled across all N users. Actor = softmax(theta), zero
%   init (no no-op bias, audit C3). Critic = tabular V, TD(0). State/action/
%   reward identical to QL_Shared_v5 and DeepA2C_Shared_v5 (audit C4).

    if ~isempty(seed), rng(seed); end
    N = env.N; A = env.actions; nA = numel(A);
    SB = env.SINR_bins; nT = env.n_trend; te = env.trend_edges;
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;

    alpha_theta = 0.05; alpha_v = 0.10; gamma = env.gamma;
    nSched = numel(env.sched_list);

    theta = zeros(maxC, maxD-minD+1, numel(SB), nT, nSched, nA);
    V     = zeros(maxC, maxD-minD+1, numel(SB), nT, nSched);
    learning_curve = zeros(num_episodes, 1);

    for ep = 1:num_episodes
        sched = sampleSched_v5(env);
        sc = schedContext_v5(sched, env);
        [Strue, ~, ~] = generateChannel_v5(simTime, env);
        [obsS, ~] = cqiFeedback_v5(Strue, env);
        prevBase = baseCQI_v5(obsS(1, :), env);
        R_emas = zeros(1, N); ema = 0.05; ep_tp = 0;

        for t = 1:simTime
            base = baseCQI_v5(obsS(t, :), env);
            dB   = max(minD, min(maxD, base - prevBase));
            aIdx = zeros(1,N); sent = zeros(1,N); bler = zeros(1,N);
            pot = zeros(1,N); sidx = zeros(N,4); pis = cell(1,N);
            for i = 1:N
                [~, sb] = min(abs(SB - obsS(t,i)));
                tbi = trendBin_v5(obsS(t,i) - obsS(max(t-1,1),i), te);
                sd  = dB(i) + maxD + 1;
                sidx(i,:) = [base(i), sd, sb, tbi];
                prefs = squeeze(theta(base(i), sd, sb, tbi, sc, :));
                prefs = prefs - max(prefs);
                p = exp(prefs)/sum(exp(prefs)); pis{i} = p;
                a = find(rand <= cumsum(p), 1, 'first');
                if isempty(a), a = nA; end
                aIdx(i) = a;
                sent(i) = max(minC, min(maxC, base(i) + A(a)));
                bler(i) = estimateBLER_v5(Strue(t,i), sent(i)-1);
                pot(i)  = (1-bler(i))*tbsFromMCSandRB(sent(i)-1, env.total_RB)*1e-3;
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
                [~, nsb] = min(abs(SB - obsS(tn,i)));
                ntb = trendBin_v5(obsS(tn,i) - obsS(t,i), te);
                s1=sidx(i,1); s2=sidx(i,2); s3=sidx(i,3); s4=sidx(i,4);
                V_s  = V(s1,s2,s3,s4,sc);
                V_sp = V(baseN(i), dBN(i)+maxD+1, nsb, ntb, sc);
                td   = r + gamma*V_sp - V_s;
                V(s1,s2,s3,s4,sc) = V_s + alpha_v*td;
                g = -pis{i}; g(aIdx(i)) = g(aIdx(i)) + 1;
                theta(s1,s2,s3,s4,sc,:) = squeeze(theta(s1,s2,s3,s4,sc,:)) + alpha_theta*td*g;
            end
            prevBase = base;
        end
        learning_curve(ep) = ep_tp / simTime;
    end
end
