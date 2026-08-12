function [theta, V, learning_curve] = AC_Shared_v6(simTime, num_episodes, seed, env)
% AC_Shared_v6  Shared-parameter tabular Actor-Critic, OLLA-relative (v6).
%   Same MDP as QL_Shared_v6 / DeepA2C_Shared_v6: OLLA loop in every user,
%   action = offset from the OLLA-corrected reference (action 0 == OLLA),
%   OLLA-offset bin in the state, cooperative cell reward, reported-CQI PF.

    if ~isempty(seed), rng(seed); end
    N = env.N; A = env.actions; nA = numel(A);
    SB = env.SINR_bins; nT = env.n_trend; te = env.trend_edges;
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;
    OE = env.off_edges; nO = numel(OE) + 1;
    du = env.olla_step_down * env.olla_target/(1 - env.olla_target);
    dd = env.olla_step_down;

    alpha_theta = 0.05; alpha_v = 0.10; gamma = env.gamma;
    nSched = numel(env.sched_list);

    theta = zeros(maxC, maxD-minD+1, numel(SB), nT, nO, nSched, nA);
    V     = zeros(maxC, maxD-minD+1, numel(SB), nT, nO, nSched);
    learning_curve = zeros(num_episodes, 1);

    for ep = 1:num_episodes
        sched = sampleSched_v5(env);
        sc = schedContext_v5(sched, env);
        [Strue, ~, ~] = generateChannel_v5(simTime, env);
        [obsS, ~] = cqiFeedback_v5(Strue, env);
        off = zeros(1, N);
        prevRef = baseCQI_v5(obsS(1,:) + off, env);
        R_emas = zeros(1, N); ema = 0.05; ep_tp = 0;

        for t = 1:simTime
            ref  = baseCQI_v5(obsS(t,:) + off, env);
            dRef = max(minD, min(maxD, ref - prevRef));
            aIdx = zeros(1,N); sent = zeros(1,N); bler = zeros(1,N);
            pot = zeros(1,N); sidx = zeros(N,5); pis = cell(1,N);
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
