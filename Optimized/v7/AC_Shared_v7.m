function [theta, V, learning_curve] = AC_Shared_v7(simTime, num_episodes, seed, env)
% AC_Shared_v7  Shared-parameter tabular actor-critic (Tier-A state).
    if ~isempty(seed), rng(seed); end
    N = env.N; A = env.actions; nA = numel(A);
    SB = env.SINR_bins; nT = env.n_trend; te = env.trend_edges;
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;
    OE = env.off_edges; nO = numel(OE) + 1;

    alpha_theta = 0.05; alpha_v = 0.10; gamma = env.gamma;
    nSched = numel(env.sched_list);

    theta = zeros(maxC, maxD-minD+1, numel(SB), nT, nO, nSched, nA);
    V     = zeros(maxC, maxD-minD+1, numel(SB), nT, nO, nSched);
    learning_curve = zeros(num_episodes, 1);

    for ep = 1:num_episodes
        sched = sampleSched_v5(env);
        sc = schedContext_v5(sched, env);
        [Strue, ~, meta] = generateChannel_v7(simTime, env);
        obsS = cqiFeedback_v7(Strue, env, meta.delays);
        off = zeros(1, N); H = harqInit_v7(N);
        prevRef = baseCQI_v5(obsS(1,:) + off, env);
        R_emas = zeros(1, N); ema = 0.05; ep_tp = 0;

        for t = 1:simTime
            ref  = baseCQI_v5(obsS(t,:) + off, env);
            dRef = max(minD, min(maxD, ref - prevRef));
            aIdx = zeros(1,N); sent = zeros(1,N); pot = zeros(1,N);
            sidx = zeros(N,5); pis = cell(1,N);
            for i = 1:N
                [~, sb] = min(abs(SB - obsS(t,i)));
                tbi = trendBin_v5(obsS(t,i) - obsS(max(t-1,1),i), te);
                obn = 1 + sum(off(i) > OE);
                sd  = dRef(i) + maxD + 1;
                sidx(i,:) = [ref(i), sd, sb, tbi, obn];
                prefs = squeeze(theta(ref(i), sd, sb, tbi, obn, sc, :));
                prefs = prefs - max(prefs);
                p = exp(prefs)/sum(exp(prefs)); pis{i} = p;
                a = find(rand <= cumsum(p), 1, 'first');
                if isempty(a), a = nA; end
                aIdx(i) = a;
                sent(i) = max(minC, min(maxC, ref(i) + A(a)));
                if env.harq_on && H.pend(i)
                    pot(i) = tbsFromMCSandRB(H.mcs(i), env.total_RB) * 1e-3;
                else
                    pot(i) = tbsFromMCSandRB(sent(i)-1, env.total_RB) * 1e-3;
                end
            end

            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            [tp_now, off, H] = txStep_v7(sent, Strue(t,:), rb, off, H, env);
            R_emas = (1-ema)*R_emas + ema*tp_now; ep_tp = ep_tp + sum(tp_now);
            r_cell = sum(tp_now) / env.reward_scale;

            tn = min(t+1, simTime);
            refN  = baseCQI_v5(obsS(tn,:) + off, env);
            dRefN = max(minD, min(maxD, refN - ref));
            for i = 1:N
                r = r_cell;
                [~, nsb] = min(abs(SB - obsS(tn,i)));
                ntb = trendBin_v5(obsS(tn,i) - obsS(t,i), te);
                nob = 1 + sum(off(i) > OE);
                s1=sidx(i,1); s2=sidx(i,2); s3=sidx(i,3); s4=sidx(i,4); s5=sidx(i,5);
                V_s  = V(s1,s2,s3,s4,s5,sc);
                V_sp = V(refN(i), dRefN(i)+maxD+1, nsb, ntb, nob, sc);
                td   = r + gamma*V_sp - V_s;
                V(s1,s2,s3,s4,s5,sc) = V_s + alpha_v*td;
                g = -pis{i}; g(aIdx(i)) = g(aIdx(i)) + 1;
                theta(s1,s2,s3,s4,s5,sc,:) = squeeze(theta(s1,s2,s3,s4,s5,sc,:)) + alpha_theta*td*g;
            end
            prevRef = ref;
        end
        learning_curve(ep) = ep_tp / simTime;
    end
end
