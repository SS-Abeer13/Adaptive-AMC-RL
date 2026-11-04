function [pol, learning_curve] = Bandit_v17(simTime, num_episodes, seed, env, ctxType, armType)
% Bandit_v17  UCB1 bandit over the residual CQI offsets: a lightweight online
% calibrator, trained on the same episodes, scheduler and OLLA loop as Deep A2C.
%   Arms    : env.actions (offsets in CQI steps on top of the OLLA reference),
%             or, with armType = 'target' (P1, README_v17.md), env.target_set
%             (OLLA target BLER values -- "contextual bandit over targets").
%   Context : 'global' (one arm for all users) or 'delay' (observable feedback
%             delay class, d <= 4 / d >= 5)
%   Reward  : per first-transmission decision, goodput per transmission
%             opportunity normalized by the OLLA-reference transport block,
%               r = TBS(m_tx) * 1{delivered} / (attempts * TBS(m_ref)),
%             credited when the block is delivered or dropped.
% Arm statistics are updated online during training; the returned frozen
% policy uses, per context, the arm with the highest empirical mean (read
% back by evalPolicy_v17's 'bandit' / 'bandit_target' ptype as one fixed
% arm per context for the whole evaluation trace).
    if nargin < 6 || isempty(armType), armType = 'offset'; end
    isTarg = strcmpi(armType, 'target');
    if ~isempty(seed), rng(seed, 'twister'); end
    N = env.N;
    if isTarg, A = env.target_set; else, A = env.actions; end
    nA = numel(A);
    noop = find(A == 0); if isempty(noop), noop = 0; end  % 'noop' is meaningless for target arms
    minC = env.min_CQI; maxC = env.max_CQI;
    if strcmpi(ctxType, 'delay'), nC = 2; else, nC = 1; end
    cnt = zeros(nC, nA); sr = zeros(nC, nA);
    c_ucb = 1.0; if isfield(env, 'bandit_c'), c_ucb = env.bandit_c; end
    W = 0; if isfield(env, 'train_warm_ttis'), W = env.train_warm_ttis; end
    learning_curve = zeros(num_episodes, 1);
    for ep = 1:num_episodes
        sched = sampleSched_v5(env);
        Ttot = W + simTime;
        [Strue, ~, meta] = generateChannel_v17(Ttot, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        ctx = ones(1, N);
        if nC == 2, ctx = 1 + (meta.delays >= 5); end
        Q = trafficInit_v17(env, N, 0);
        off = zeros(1, N); H = harqInit_v17(N); R_emas = zeros(1, N); ema = 0.05;
        pArm = zeros(1, N); pRef = ones(1, N); pTbs = zeros(1, N); pAtt = zeros(1, N); pOn = false(1, N);
        ep_tp = 0;
        for t = 1:Ttot
            learn = t > W;
            [Q, H, missB] = trafficPre_v17(Q, t, env, H);
            pOn(missB) = false;     % expired packet: no outcome to credit
            ref = baseCQI_v17(obsS(t, :) + off, env);
            sent = ref; aIdx = noop * ones(1, N);
            targVec = []; % P1: per-user OLLA target for this TTI (armType = 'target')
            if isTarg, targVec = env.olla_target * ones(1, N); end
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
                        if isTarg
                            targVec(i) = A(a);   % target BLER arm; CQI unchanged (sent(i) stays ref(i))
                        else
                            sent(i) = max(minC, min(maxC, ref(i) + A(a)));
                        end
                    end
                end
            end
            pot = zeros(1, N);
            for i = 1:N
                if env.harq_on && H.pend(i)
                    pot(i) = tbsFromMCSandRB_v17(H.mcs(i), env.total_RB) * 1e-3;
                elseif isfield(env, 'sched_on_ref') && env.sched_on_ref
                    pot(i) = tbsFromMCSandRB_v17(max(minC, min(maxC, ref(i))) - 1, env.total_RB) * 1e-3;
                else
                    pot(i) = tbsFromMCSandRB_v17(sent(i) - 1, env.total_RB) * 1e-3;
                end
            end
            pot(~Q.has) = 0;
            dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);  % T3: EDF plumbing
            rb = schedule_users_v17(sched, t, N, R_emas, pot, env.total_RB, dlv);
            rb(~Q.has) = 0;
            wasRetx = env.harq_on & H.pend;
            [tp_now, off, H, ~, nEv, dropEv] = txStep_v17(sent, Strue(t, :), rb, off, H, env, [], targVec);
            if isfield(env, 'useful_bits') && env.useful_bits && Q.on && isfield(Q, 'rem')
                for ii = find(rb > 0)
                    if Q.has(ii)
                        tp_now(ii) = min(tp_now(ii), max(0, Q.rem(ii)) * 1e-3);
                    else
                        tp_now(ii) = 0;
                    end
                end
            end
            Q = trafficPost_v17(Q, tp_now, t);
            if isfield(env, 'pf_avg') && strcmpi(env.pf_avg, 'scheduled')
                sch_u = find(rb > 0);
                r_sched = zeros(1, N);
                if ~isempty(sch_u)
                    if env.harq_on && wasRetx(sch_u)
                        r_sched(sch_u) = H.tbs(sch_u) * 1e-3;
                    else
                        tx_mcs = max(0, min(14, sent(sch_u) - 1));
                        r_sched(sch_u) = tbsFromMCSandRB_v17(tx_mcs, rb(sch_u)) * 1e-3;
                    end
                end
                R_emas = (1 - ema) * R_emas + ema * r_sched;
            else
                R_emas = (1 - ema) * R_emas + ema * tp_now;
            end
            if learn, ep_tp = ep_tp + sum(tp_now); end
            for i = 1:N
                if rb(i) <= 0, continue; end
                if ~wasRetx(i)
                    pOn(i) = learn;
                    if learn
                        pArm(i) = aIdx(i); pAtt(i) = 1;
                        pTbs(i) = tbsFromMCSandRB_v17(sent(i) - 1, rb(i));
                        pRef(i) = max(tbsFromMCSandRB_v17(max(minC, min(maxC, ref(i))) - 1, rb(i)), 1);
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
    pol = struct('ctxType', ctxType, 'armType', armType, 'arm', arm, 'means', mu, 'counts', cnt);
end
