function [thetas, Vs, learning_curve] = AC_AMC_Multi_v4(simTime, num_episodes, seed, env)
% AC_AMC_Multi_v4  Tabular one-step Actor-Critic on the unified v4 MDP. (v4.1)
%   Actor = softmax over theta(s,a), zero init (no no-op bias, audit C3).
%   Critic = tabular V(s), TD(0). gamma/reward identical to QL and A2C (C4).
%   v4.1: observed-trend state dimension (same information as the deep agent).

    if ~isempty(seed), rng(seed); end
    N = env.N;
    actions = env.actions; num_actions = numel(actions);
    SINR_bins = env.SINR_bins;
    maxC = env.max_CQI; minC = env.min_CQI;
    maxD = env.max_delta; minD = env.min_delta;
    nT = env.n_trend; te = env.trend_edges;

    alpha_theta = 0.05;
    alpha_v     = 0.10;
    gamma       = env.gamma;

    thetas = zeros(maxC, maxD-minD+1, numel(SINR_bins), nT, num_actions, N);
    Vs     = zeros(maxC, maxD-minD+1, numel(SINR_bins), nT, N);
    learning_curve = zeros(num_episodes, 1);

    for ep = 1:num_episodes
        [SINR_true, ~, ~] = generateChannel_v4(simTime, env);
        [obs_SINR, obs_CQI] = cqiFeedback_v4(SINR_true, env);

        cur = obs_CQI(1, :); prev = cur; d = zeros(1, N);
        R_emas = zeros(1, N); ema_a = 0.05; ep_tp = 0;

        for t = 1:simTime
            a_idx = zeros(1,N); new_CQI = zeros(1,N);
            bler = zeros(1,N); pot = zeros(1,N);
            sidx = zeros(N, 4); pis = cell(1, N);
            for i = 1:N
                [~, sb] = min(abs(SINR_bins - obs_SINR(t, i)));
                dS = obs_SINR(t, i) - obs_SINR(max(t-1, 1), i);
                tbi = trendBin_v4(dS, te);
                sd = d(i) + maxD + 1;
                sidx(i, :) = [cur(i), sd, sb, tbi];

                prefs = squeeze(thetas(cur(i), sd, sb, tbi, :, i));
                prefs = prefs - max(prefs);
                p = exp(prefs) / sum(exp(prefs));
                pis{i} = p;

                a = find(rand <= cumsum(p), 1, 'first');
                if isempty(a), a = num_actions; end
                a_idx(i) = a;

                new_CQI(i) = max(minC, min(maxC, cur(i) + actions(a)));
                mcs = new_CQI(i) - 1;
                bler(i) = estimateBLER_v4(SINR_true(t, i), mcs);
                pot(i)  = (1 - bler(i)) * tbsFromMCSandRB(mcs, env.total_RB) * 1e-3;
            end

            rb = schedule_users_v4(env.scheduler, t, N, R_emas, pot, env.total_RB);

            tp_now = zeros(1, N);
            for i = 1:N
                if rb(i) > 0
                    tp_now(i) = (1 - bler(i)) * ...
                                tbsFromMCSandRB(new_CQI(i)-1, rb(i)) * 1e-3;
                end
            end
            R_emas = (1 - ema_a) * R_emas + ema_a * tp_now;
            ep_tp = ep_tp + sum(tp_now);

            for i = 1:N
                if rb(i) > 0
                    r = computeReward_v4(bler(i), tbsFromMCSandRB(new_CQI(i)-1, rb(i)), env);
                else
                    r = 0;
                end
                nd = max(minD, min(maxD, new_CQI(i) - prev(i)));
                tn = min(t+1, simTime);
                [~, nsb] = min(abs(SINR_bins - obs_SINR(tn, i)));
                ntb = trendBin_v4(obs_SINR(tn, i) - obs_SINR(t, i), te);

                s1 = sidx(i,1); s2 = sidx(i,2); s3 = sidx(i,3); s4 = sidx(i,4);
                V_s  = Vs(s1, s2, s3, s4, i);
                V_sp = Vs(new_CQI(i), nd+maxD+1, nsb, ntb, i);
                td   = r + gamma * V_sp - V_s;

                Vs(s1, s2, s3, s4, i) = V_s + alpha_v * td;

                g = -pis{i};
                g(a_idx(i)) = g(a_idx(i)) + 1;
                thetas(s1, s2, s3, s4, :, i) = ...
                    squeeze(thetas(s1, s2, s3, s4, :, i)) + alpha_theta * td * g;

                prev(i) = cur(i); cur(i) = new_CQI(i); d(i) = nd;
            end
        end
        learning_curve(ep) = ep_tp / simTime;
    end
end
