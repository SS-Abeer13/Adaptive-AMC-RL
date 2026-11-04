function [pol, learning_curve] = Bandit_v9(simTime, num_episodes, seed, env, ctxType)
% Bandit_v9  UCB1 bandit over the residual CQI offsets: a lightweight online
% calibrator, trained on the same episodes, scheduler and OLLA loop as Deep A2C.
%   Arms    : env.actions (offsets in CQI steps on top of the OLLA reference)
%   Context : 'global' (one arm for all users) or 'delay' (observable feedback
%             delay class, d <= 4 / d >= 5)
%   Reward  : per first-transmission decision, goodput per transmission
%             opportunity normalized by the OLLA-reference transport block,
%               r = TBS(m_tx) * 1{delivered} / (attempts * TBS(m_ref)),
%             credited when the block is delivered or dropped.
% Arm statistics are updated online during training; the returned frozen
% policy uses, per context, the arm with the highest empirical mean.
    if ~isempty(seed), rng(seed); end
    N = env.N; A = env.actions; nA = numel(A); noop = find(A == 0);
    minC = env.min_CQI; maxC = env.max_CQI;
    if strcmpi(ctxType, 'delay'), nC = 2; else, nC = 1; end
    cnt = zeros(nC, nA); sr = zeros(nC, nA);
    c_ucb = 1.0; if isfield(env, 'bandit_c'), c_ucb = env.bandit_c; end
    W = 0; if isfield(env, 'train_warm_ttis'), W = env.train_warm_ttis; end
    learning_curve = zeros(num_episodes, 1);
    for ep = 1:num_episodes
        sched = sampleSched_v5(env);
        Ttot = W + simTime;
        [Strue, ~, meta] = generateChannel_v9(Ttot, env);
        obsS = cqiFeedback_v9(Strue, env, meta.delays);
        ctx = ones(1, N);
        if nC == 2, ctx = 1 + (meta.delays >= 5); end
        off = zeros(1, N); H = harqInit_v9(N); R_emas = zeros(1, N); ema = 0.05;
        pArm = zeros(1, N); pRef = ones(1, N); pTbs = zeros(1, N); pAtt = zeros(1, N); pOn = false(1, N);
        ep_tp = 0;
        for t = 1:Ttot
            learn = t > W;
            ref = baseCQI_v5(obsS(t, :) + off, env);
            sent = ref; aIdx = noop * ones(1, N);
            if learn
                for i = 1:N
                    if ~(env.harq_on && H.pend(i))
                        c = ctx(i); n = cnt(c, :);
                        if any(n == 0)
                            cand = find(n == 0); a = cand(randi(numel(cand)));
                        else
                            mu = sr(c, :) ./ n;
                            [~, a] = max(mu + c_ucb * sqrt(2 * log(sum(n)) ./ n));
                        end
                        aIdx(i) = a;
                        sent(i) = max(minC, min(maxC, ref(i) + A(a)));
                    end
                end
            end
            pot = zeros(1, N);
            for i = 1:N
                if env.harq_on && H.pend(i)
                    pot(i) = tbsFromMCSandRB(H.mcs(i), env.total_RB) * 1e-3;
                elseif isfield(env, 'sched_on_ref') && env.sched_on_ref
                    pot(i) = tbsFromMCSandRB(max(minC, min(maxC, ref(i))) - 1, env.total_RB) * 1e-3;
                else
                    pot(i) = tbsFromMCSandRB(sent(i) - 1, env.total_RB) * 1e-3;
                end
            end
            rb = schedule_users_v5(sched, t, N, R_emas, pot, env.total_RB);
            wasRetx = env.harq_on & H.pend;
            [tp_now, off, H, ~, nEv, dropEv] = txStep_v9(sent, Strue(t, :), rb, off, H, env);
            R_emas = (1 - ema) * R_emas + ema * tp_now;
            if learn, ep_tp = ep_tp + sum(tp_now); end
            for i = 1:N
                if rb(i) <= 0, continue; end
                if ~wasRetx(i)
                    pOn(i) = learn;
                    if learn
                        pArm(i) = aIdx(i); pAtt(i) = 1;
                        pTbs(i) = tbsFromMCSandRB(sent(i) - 1, rb(i));
                        pRef(i) = max(tbsFromMCSandRB(max(minC, min(maxC, ref(i))) - 1, rb(i)), 1);
                    end
                elseif pOn(i)
                    pAtt(i) = pAtt(i) + 1;
                end
                done = (tp_now(i) > 0) || dropEv(i) || (~env.harq_on && nEv(i));
                if pOn(i) && done
                    r = double(tp_now(i) > 0) * pTbs(i) / (pAtt(i) * pRef(i));
                    c = ctx(i);
                    cnt(c, pArm(i)) = cnt(c, pArm(i)) + 1;
                    sr(c, pArm(i)) = sr(c, pArm(i)) + r;
                    pOn(i) = false;
                end
            end
        end
        learning_curve(ep) = ep_tp / simTime;
    end
    mu = sr ./ max(cnt, 1); mu(cnt == 0) = -Inf;
    arm = zeros(1, nC);
    for c = 1:nC
        if all(cnt(c, :) == 0), arm(c) = 0;
        else, [~, b] = max(mu(c, :)); arm(c) = A(b); end
    end
    pol = struct('ctxType', ctxType, 'arm', arm, 'means', mu, 'counts', cnt);
end
