function [actorNet, criticNet, learning_curve, entropy_curve, bestActorNet, bestCriticNet, bestEp, valCurve, trainInfo] = ...
            DeepA2C_Shared_v15(simTime, num_episodes, seed, env)
% DeepA2C_Shared_v15  Shared-network n-step A2C with scheduled credit assignment
% and temporal sequence memory (v8 autonomous link adaptation).
%
% Key architectural upgrades over v7:
%   1. STRICTLY AUTONOMOUS: Zero Behavior Cloning (bc_warm_eps = 0).
%   2. PER-USER SCHEDULED CREDIT ASSIGNMENT: Unscheduled users do not pollute
%      the gradient buffer with noise; only scheduled transmissions train the policy.
%   3. TEMPORAL MEMORY: Autoregressive state stacking (depth L=3) to resolve
%      delayed POMDP partial observability and track Markov interference bursts.
%   4. EXPANDED ACTION SPACE: -6 to +4 (11 actions) for rapid burst adaptation.
%   5. MATHEMATICALLY SPECIFIED REWARD: Throughput reward with packet drop penalties.
    if ~isempty(seed), rng(seed); end
    N = env.N;
    % P1 (README_v15.md): action_mode = 'target' repurposes the action set
    % as OLLA target-BLER arms (env.target_set) instead of CQI offsets
    % (env.actions); the network's output width (nA) follows automatically.
    % action_mode = 'offset' (default) is exactly the v9/v10/v15-P0 path.
    targMode = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'target');
    isResid  = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'resid');
    if targMode
        A = env.target_set;
    elseif isResid
        A = env.resid_actions;
    else
        A = env.actions;
    end
    nA = numel(A);
    targEpoch = 10; if isfield(env, 'target_epoch'), targEpoch = max(1, round(env.target_epoch)); end
    maxC = env.max_CQI; minC = env.min_CQI;
    maxD = env.max_delta; minD = env.min_delta;

    gamma = env.gamma;
    % v15: hyper-parameters overridable through env.a2c (defaults = v9)
    hp = struct(); if isfield(env, 'a2c') && isstruct(env.a2c), hp = env.a2c; end
    n_step    = hpget(hp, 'n_step', 10);
    lr_actor  = hpget(hp, 'lr_actor', 5e-4);
    lr_critic = hpget(hp, 'lr_critic', 1e-3);
    ent_start = hpget(hp, 'ent_start', 0.08);   % Exploratory start for autonomous learning
    ent_end   = hpget(hp, 'ent_end', 0.005);    % Annealed floor
    rk = 'goodput'; if isfield(env, 'reward_kind'), rk = lower(env.reward_kind); end
    Pq = 1; if isfield(env, 'cqi_period'), Pq = max(1, round(env.cqi_period)); end
    clip_norm = 5.0;
    L_seq = 3;          % Temporal sequence stacking depth

    % P0.4: validation-based model selection. env.a2c.val_every (default 0
    % = disabled, current behaviour) evaluates the greedy policy every M
    % episodes on n_val validation traces (seeds 80000+, disjoint from
    % calibration 60000+ and evaluation 9000+) and keeps the checkpoint
    % with the best validation score. bestActorNet/bestCriticNet/bestEp
    % fall back to the final ("last") network when disabled.
    val_every = hpget(hp, 'val_every', 0);
    n_val     = hpget(hp, 'n_val', 10);
    doVal = val_every > 0;
    if doVal
        rngSave0 = rng;
        valTraces = buildValTraces_v15(env, simTime, n_val);
        rng(rngSave0);
    end

    nSched = numel(env.sched_list);
    if upper(env.state_tier) == 'A'
        nBase = 5;
    elseif upper(env.state_tier) == 'O'
        nBase = 10;   % observable Tier-B (no true speed / burst / delay)
    else
        nBase = 13;
    end
    nSingle = nBase + nSched + nExtra_v15(env);
    nFeat = nSingle * L_seq; % Multi-frame temporal state dimension

    % Deep Actor and Critic Networks (DLNetwork with ReLU activations)
    actorLayers = [
        featureInputLayer(nFeat, 'Name', 'in')
        fullyConnectedLayer(128, 'Name', 'fc1'); reluLayer('Name', 'r1')
        fullyConnectedLayer(96,  'Name', 'fc2'); reluLayer('Name', 'r2')
        fullyConnectedLayer(nA,  'Name', 'logits')];

    criticLayers = [
        featureInputLayer(nFeat, 'Name', 'in')
        fullyConnectedLayer(128, 'Name', 'fc1'); reluLayer('Name', 'r1')
        fullyConnectedLayer(96,  'Name', 'fc2'); reluLayer('Name', 'r2')
        fullyConnectedLayer(1,   'Name', 'value')];

    actorNet  = dlnetwork(actorLayers);
    criticNet = dlnetwork(criticLayers);
    if isResid
        zeroIdx = find(A == 0, 1);
        if ~isempty(zeroIdx)
            idxB = find(actorNet.Learnables.Layer == "logits" & actorNet.Learnables.Parameter == "Bias");
            initB = zeros(nA, 1, 'single');
            initB(zeroIdx) = single(hpget(env, 'resid_init_bias', 3.0));
            actorNet.Learnables.Value{idxB} = dlarray(initB);
        end
    end
    toDl = @(x) dlarray(single(x), 'CB');

    Wa = extract_weights(actorNet);
    Wc = extract_weights(criticNet);

    aAvg = []; aAvgSq = []; aIt = 0;
    cAvg = []; cAvgSq = []; cIt = 0;
    learning_curve = zeros(num_episodes, 1);
    entropy_curve  = zeros(num_episodes, 1);

    % Experience buffer for scheduled transitions.
    % AUDIT FIX (2026-09-29) -- returns / bootstrapping:
    %   The previous update used rets = r + gamma * V(S_t(:, user)) for EVERY
    %   buffered transition, where S_t was the state of the *current* TTI at
    %   flush time. So (i) a transition from TTI 1 was bootstrapped from the
    %   user's state ~200 TTIs later, (ii) the newest transition was
    %   bootstrapped from its own pre-action state, and (iii) no n-step return
    %   was ever formed (n_step only sized the buffer). Under PF/RR the buffer
    %   filled once per 200-TTI episode, so almost every target was wrong.
    % Now: each user's scheduled transitions form that user's decision
    % sequence (semi-MDP over scheduled TTIs, gamma applied per scheduled
    % decision). Returns are computed backwards per user,
    %   G_j = r_j + gamma * G_{next scheduled j of same user},
    % and the last one bootstraps from V(s_i) of the state observed AFTER
    % that transition (the next TTI's state, or a post-episode state).
    %
    % AUDIT FIX -- HARQ retransmission credit: on a retransmission TTI the
    % sampled action is ignored (the retx reuses the stored MCS), so those
    % transitions are kept in the return chain / critic target but masked
    % out of the policy-gradient term (bufP = 0).
    flushAt = n_step * N * 2;
    cap = flushAt + N;
    bufS = zeros(nFeat, cap, 'single');
    bufA = zeros(1, cap);
    bufR = zeros(1, cap, 'single');
    bufU = zeros(1, cap); % User ID tracking for individual returns
    bufP = zeros(1, cap, 'single'); % 1 = action affected the transmission
    nb = 0;

    bestActorNet = actorNet; bestCriticNet = criticNet; bestScore = -Inf; bestEp = 0;
    valCurve = [];  % P0.5: one entry per validation checkpoint (score on valTraces)

    % P0.3: parallel rollouts. env.a2c.n_envs (default 1) = current,
    % unchanged behaviour below. n_envs > 1 collects that many episodes in
    % parfor using the current (frozen) weights, then performs ONE update
    % over the merged buffer; this also isolates a worker crash from the
    % main process. Not required to reproduce v10 bit-for-bit (v10 has no
    % such option); n_envs = 1 is the path covered by test_equivalence_v15.
    n_envs = max(1, round(hpget(hp, 'n_envs', 1)));

    late_credits_total = 0;
    total_credits_total = 0;

    if n_envs <= 1
    for ep = 1:num_episodes
        % Linear entropy decay across autonomous training episodes
        entW = ent_start + (ent_end - ent_start) * (ep - 1) / max(num_episodes - 1, 1);

        sched = sampleSched_v5(env);
        [~, sOneHot] = schedContext_v5(sched, env);
        ctx = single(repmat(sOneHot, 1, N));

        % v9: optional pure-OLLA warm-up before the learning part of the episode
        W = 0; if isfield(env, 'train_warm_ttis'), W = env.train_warm_ttis; end
        Ttot = W + simTime;
        [Strue, ~, meta] = generateChannel_v15(Ttot, env);
        obsS = cqiFeedback_v15(Strue, env, meta.delays);
        b_i = zeros(1, N);
        if isResid
            base_kind = 'fixed';
            if isfield(env, 'base_rule_kind'), base_kind = lower(env.base_rule_kind); end
            if strcmpi(base_kind, 'fixed_class') || strcmpi(base_kind, 'fixedpu')
                for i = 1:N
                    [dc, vc] = userClass_v15(meta.delays(i), mean(meta.speeds(:, i)));
                    b_i(i) = env.fixed_class_tab(dc, vc);
                end
            else
                b_i(:) = env.fixed_offset;
            end
        end

        burstObsM = zeros(Ttot, N);
        for i = 1:N
            idx = max((1:Ttot).' - meta.delays(i), 1);
            burstObsM(:, i) = double(meta.burst(idx));
        end

        ageM = cqiAge_v15(Ttot, N, Pq);
        emaO = obsS(1, :); cn = 0;
        Q = trafficInit_v15(env, N, 0);
        lastIdx = zeros(1, N); pendR = zeros(1, N);
        off = zeros(1, N);
        H = harqInit_v15(N, env);
        useRTT = isfield(env, 'harq_rtt') && env.harq_rtt > 0;
        if useRTT
            dec_counter = 0;
            dec_buf_idx = zeros(1, 50000);
            dec_flushed = false(1, 50000);
            bufDecId = zeros(1, 2000);
            late_credits = 0;
            total_credits = 0;
        end
        nk = zeros(1, N);
        prevRef = baseCQI_v15(obsS(1,:) + off, env);
        R_emas = zeros(1, N);
        ema = 0.05;
        ep_tp = 0;
        ep_ent = 0;
        % P4: trackers for the 'ack8'/'tsince'/'offtrend' feat_extra options.
        ack8 = zeros(1, N); tsince = zeros(1, N); offEma = zeros(1, N);

        % Initialize temporal state history buffer [nSingle x N x L_seq]
        histS = zeros(nSingle, N, L_seq, 'single');

        if targMode
            % P1 semi-MDP: one experience per user per target_epoch TTIs,
            % not per TTI. epochA/epochS0 are set at each decision boundary
            % and held; epochR/epochSched accumulate over the epoch and are
            % flushed into the buffer at the next boundary (or episode end).
            defA = find(abs(A - env.olla_target_tuned) < 1e-9, 1);
            if isempty(defA), defA = 1; end
            epochA = defA * ones(1, N);
            epochR = zeros(1, N);
            epochSched = false(1, N);
            epochS0 = zeros(nFeat, N, 'single');
        else
            noop = find(A == 0);
        end
        for t = 1:Ttot
            learn = t > W;
            if useRTT
                du = env.olla_step_down * env.olla_target / (1 - env.olla_target);
                dd = env.olla_step_down;
                [H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v15(H, Q, off, env, t, du, dd);
                if isfield(env, 'olla_off_lim') && ~isempty(env.olla_off_lim)
                    off = max(-env.olla_off_lim, min(env.olla_off_lim, off));
                end
                if learn && ~isempty(fbList)
                    for fbi = 1:numel(fbList)
                        ui = fbList(fbi).user;
                        d_id = fbList(fbi).dec_id;
                        if d_id > 0
                            total_credits = total_credits + 1;
                            r_del = 0;
                            if strcmpi(rk, 'ontime') || strcmpi(rk, 'ontime_shaped')
                                if fbList(fbi).completed
                                    r_del = env.ontime_bonus;
                                end
                                if strcmpi(rk, 'ontime_shaped')
                                    shape_c = hpget(env, 'shape_c', 0.5);
                                    tb_bits = fbList(fbi).bits;
                                    if fbList(fbi).is_ack
                                        rf_pre = max(0, Q.rem(ui) + tb_bits) / env.pkt_bits;
                                        rf_post = max(0, Q.rem(ui)) / env.pkt_bits;
                                        r_del = r_del + shape_c * (rf_pre - gamma * rf_post);
                                    end
                                end
                            else
                                if fbList(fbi).is_ack
                                    r_del = (fbList(fbi).bits * 1e-3) / env.reward_scale;
                                elseif dropEv(ui)
                                    r_del = -env.lambda_drop;
                                end
                            end

                            if d_id <= numel(dec_flushed) && ~dec_flushed(d_id) && dec_buf_idx(d_id) > 0
                                b_idx = dec_buf_idx(d_id);
                                bufR(b_idx) = bufR(b_idx) + single(r_del);
                            else
                                pendR(ui) = pendR(ui) + r_del;
                                late_credits = late_credits + 1;
                            end
                        end
                    end
                end
            end
            [Q, H, missEv] = trafficPre_v15(Q, t, env, H);
            X = struct('age', ageM(t, :), 'dev', obsS(t, :) - emaO, 'cn', cn, 'Q', Q, 't', t, ...
                        'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma, 'H', H);
            xtra = featExtra_v15(env, X);
            [S_temporal, histS, ref] = build_state_v15(t, obsS, off, prevRef, nk, H, ...
                meta.speeds(t,:), burstObsM(t,:), meta.delays, R_emas, ctx, histS, env, nFeat, xtra);
            % v15 deadline misses: credit the user's most recent buffered
            % decision. P1 target mode has no per-TTI buffer entry to find
            % (semi-MDP: one entry per epoch) -- charge the miss straight to
            % the currently-accumulating epoch reward instead.
            if learn && (strcmpi(rk, 'ontime') || strcmpi(rk, 'ontime_shaped')) && any(missEv)
                if targMode
                    epochR(missEv) = epochR(missEv) - env.miss_pen;
                else
                    for i = find(missEv)
                        if lastIdx(i) > 0, bufR(lastIdx(i)) = bufR(lastIdx(i)) - single(env.miss_pen);
                        else, pendR(i) = pendR(i) - env.miss_pen; end
                    end
                end
            end

            % Flush the buffer now that S_temporal is the successor state of
            % every buffered transition.
            if learn && nb >= flushAt
                if useRTT
                    for k = 1:nb
                        d_id = bufDecId(k);
                        if d_id > 0 && d_id <= numel(dec_flushed)
                            dec_flushed(d_id) = true;
                            dec_buf_idx(d_id) = 0;
                        end
                    end
                end
                [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = a2c_update_v15( ...
                    actorNet, criticNet, Wc, S_temporal, bufS, bufA, bufR, bufU, bufP, nb, ...
                    gamma, entW, clip_norm, lr_actor, lr_critic, toDl, ...
                    aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt);
                Wa = extract_weights(actorNet);
                Wc = extract_weights(criticNet);
                nb = 0; lastIdx(:) = 0;
            end

            % Forward actor pass
            [~, P] = forward_actor(Wa, S_temporal);
            if learn, ep_ent = ep_ent + mean(-sum(P .* log(P + 1e-12), 1)); end

            isRetx = env.harq_on & H.pend;

            if targMode
                % P1 semi-MDP (README_v15.md): a decision (held targEpoch
                % TTIs) picks a target BLER, not a CQI offset -- the action
                % affects every scheduled transmission (first-tx or retx)
                % during the epoch equally, via txStep_v15's du(targ).
                atDecision = mod(t - 1, targEpoch) == 0;
                if atDecision
                    if t > 1
                        pushIdx = find(epochSched | (epochR ~= 0));
                        if learn && ~isempty(pushIdx)
                            nSel = numel(pushIdx);
                            newNb = nb + (1:nSel);
                            bufS(:, newNb) = epochS0(:, pushIdx);
                            bufA(newNb)    = epochA(pushIdx);
                            bufR(newNb)    = single(epochR(pushIdx));
                            bufU(newNb)    = pushIdx;
                            bufP(newNb)    = single(1);  % the target affects every tx in the epoch
                            nb = nb + nSel;
                        end
                    end
                    epochR(:) = 0; epochSched(:) = false;
                    epochS0 = S_temporal;
                    if learn
                        U_act = rand(1, N);
                        Pcum = cumsum(P, 1);
                        cmp = U_act <= Pcum;
                        [tfHit, newA] = max(cmp, [], 1);
                        newA(~tfHit) = nA;
                        epochA = newA;
                    end
                end
                aIdx = epochA;
                targVec = A(epochA);
                sent = ref;   % no CQI offset -- off(i) tracks via txStep_v15's per-user target
            elseif isResid
                if learn
                    U_act = rand(1, N);
                    Pcum = cumsum(P, 1);
                    cmp = U_act <= Pcum;
                    [tfHit, aIdx] = max(cmp, [], 1);
                    aIdx(~tfHit) = nA;
                else
                    aIdx = noop * ones(1, N);
                end
                targVec = [];
                delta = A(aIdx);
                sent = max(minC, min(maxC, ref + b_i + delta));
            else
                if learn
                    U_act = rand(1, N);
                    Pcum = cumsum(P, 1);
                    cmp = U_act <= Pcum;
                    [tfHit, aIdx] = max(cmp, [], 1);
                    aIdx(~tfHit) = nA;
                else
                    aIdx = noop * ones(1, N);   % warm-up: pure OLLA
                end
                targVec = [];
                sent = max(minC, min(maxC, ref + A(aIdx)));
            end

            if useRTT
                pot = zeros(1, N);
                retxReady = any(H.proc_isRetx, 2)';
                hasFree = any(~H.proc_busy, 2)' & (Q.tx_rem > 0);
                elig = Q.has & (retxReady | hasFree);
                for i = 1:N
                    if ~elig(i), continue; end
                    if retxReady(i)
                        p_retx = find(H.proc_isRetx(i, :), 1);
                        pot(i) = tbsFromMCSandRB_v15(H.proc_mcs(i, p_retx), env.total_RB) * 1e-3;
                    else
                        pot(i) = tbsFromMCSandRB_v15(sent(i) - 1, env.total_RB) * 1e-3;
                    end
                end
                dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);
                rb = schedule_users_v15(sched, t, N, R_emas, pot, env.total_RB, dlv);
                rb(~elig) = 0;
                schedM = rb > 0;

                cur_dec_ids = zeros(1, N);
                for i = find(schedM)
                    if ~retxReady(i)
                        dec_counter = dec_counter + 1;
                        cur_dec_ids(i) = dec_counter;
                    end
                end

                [H, Q, bl1, isRetxTx] = harqTransmit_v15(sent, Strue(t,:), rb, H, Q, env, t, [], cur_dec_ids);

                tp_now = tp_ack;
                fbUsers = ackEv | nackEv;
                if any(fbUsers), cn = 0.6 * cn + 0.4 * mean(double(nackEv(fbUsers))); else, cn = 0.97 * cn; end
                emaO = 0.98 * emaO + 0.02 * obsS(t, :);

                nk(fbUsers)  = 0.7 * nk(fbUsers) + 0.3 * double(nackEv(fbUsers));
                nk(~fbUsers) = 0.95 * nk(~fbUsers);
                R_emas = (1 - ema) * R_emas + ema * tp_now;
                ack8(fbUsers) = 0.8 * ack8(fbUsers) + 0.2 * double(ackEv(fbUsers));
                tsince(schedM) = 0; tsince(~schedM) = tsince(~schedM) + 1;
                offEma = 0.9 * offEma + 0.1 * off;
                if learn, ep_tp = ep_tp + sum(tp_now); end

                if learn
                    selIdx = find(schedM);
                    nSel = numel(selIdx);
                    if nSel > 0
                        rI = zeros(1, nSel);
                        if isResid
                            rI = rI - env.resid_pen * abs(delta(selIdx));
                        end
                        rI = rI + pendR(selIdx);
                        pendR(selIdx) = 0;

                        newNb = nb + (1:nSel);
                        bufS(:, newNb)   = S_temporal(:, selIdx);
                        bufA(newNb)      = aIdx(selIdx);
                        bufR(newNb)      = single(rI);
                        bufU(newNb)      = selIdx;
                        bufP(newNb)      = single(~retxReady(selIdx));
                        bufDecId(newNb)  = cur_dec_ids(selIdx);
                        for kk = 1:nSel
                            did = cur_dec_ids(selIdx(kk));
                            if did > 0 && did <= numel(dec_buf_idx)
                                dec_buf_idx(did) = newNb(kk);
                            end
                        end
                        lastIdx(selIdx)  = newNb;
                        nb = nb + nSel;
                    end
                end
            else
                rbFull = env.total_RB * ones(1, N);
                if isfield(env, 'sched_on_ref') && env.sched_on_ref
                    potNew = tbsFromMCSandRB_v15(max(env.min_CQI, min(env.max_CQI, ref)) - 1, rbFull) * 1e-3;
                else
                    potNew = tbsFromMCSandRB_v15(sent - 1, rbFull) * 1e-3;
                end
                pot = potNew;
                if any(isRetx)
                    potRetx = tbsFromMCSandRB_v15(H.mcs, rbFull) * 1e-3;
                    pot(isRetx) = potRetx(isRetx);
                end

                % Physical transmission step
                pot(~Q.has) = 0;
                dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);  % T3: EDF plumbing
                rb = schedule_users_v15(sched, t, N, R_emas, pot, env.total_RB, dlv);
                rb(~Q.has) = 0;
                Q_prev = Q;
                [tp_now, off, H, ~, nEv, dropEv] = txStep_v15(sent, Strue(t,:), rb, off, H, env, [], targVec);
                [Q, okEv] = trafficPost_v15(Q, tp_now, t);
                if any(schedNow(rb)), cn = 0.6 * cn + 0.4 * mean(double(nEv(rb > 0))); else, cn = 0.97 * cn; end
                emaO = 0.98 * emaO + 0.02 * obsS(t, :);

                schedM = rb > 0;
                nk(schedM)  = 0.7 * nk(schedM) + 0.3 * double(nEv(schedM));
                nk(~schedM) = 0.95 * nk(~schedM);
                R_emas = (1 - ema) * R_emas + ema * tp_now;
                ack8(schedM) = 0.8 * ack8(schedM) + 0.2 * double(~nEv(schedM));
                tsince(schedM) = 0; tsince(~schedM) = tsince(~schedM) + 1;
                offEma = 0.9 * offEma + 0.1 * off;
                if learn, ep_tp = ep_tp + sum(tp_now); end

                % -------------------------------------------------------------
                % Scheduled Credit Assignment: store ONLY scheduled users.
                % -------------------------------------------------------------
                if learn
                    selIdx = find(schedM);
                    nSel = numel(selIdx);
                    if nSel > 0
                        if strcmpi(rk, 'ontime') || strcmpi(rk, 'ontime_shaped')
                            rI = env.ontime_bonus * double(okEv(selIdx));
                            if ~targMode, rI = rI + pendR(selIdx); pendR(selIdx) = 0; end
                            if strcmpi(rk, 'ontime_shaped')
                                shape_c = hpget(env, 'shape_c', 0.5);
                                rf_pre = max(0, Q_prev.rem(selIdx)) / env.pkt_bits;
                                rf_post = zeros(1, nSel);
                                has_post = Q.has(selIdx);
                                rf_post(has_post) = max(0, Q.rem(selIdx(has_post))) / env.pkt_bits;
                                F_shaping = shape_c * (rf_pre - gamma * rf_post);
                                rI = rI + F_shaping;
                            end
                            if isResid
                                rI = rI - env.resid_pen * abs(delta(selIdx));
                            end
                        elseif strcmpi(rk, 'oppcost')
                            tref = tbsFromMCSandRB_v15(max(minC, min(maxC, ref(selIdx))) - 1, rb(selIdx)) * 1e-3 * (1 - env.olla_target);
                            rI = (tp_now(selIdx) - tref) / env.reward_scale;
                        else
                            rI = (tp_now(selIdx) / env.reward_scale) ...
                                  - env.lambda_drop * double(dropEv(selIdx)) ...
                                  - env.lambda_retx * double(nEv(selIdx));
                        end
                        if targMode
                            epochR(selIdx) = epochR(selIdx) + rI;
                            epochSched(selIdx) = true;
                        else
                            newNb = nb + (1:nSel);
                            bufS(:, newNb)   = S_temporal(:, selIdx);
                            bufA(newNb)      = aIdx(selIdx);
                            bufR(newNb)      = single(rI);
                            bufU(newNb)      = selIdx;
                            bufP(newNb)      = single(~isRetx(selIdx));
                            lastIdx(selIdx)  = newNb;
                            nb = nb + nSel;
                        end
                    end
                end
            end
            prevRef = ref;
        end

        % End of episode (time-limit truncation): bootstrap from the
        % post-episode state (no new CQI report, but OLLA/HARQ/EMA updated).
        % P1 target mode: flush the still-active (partial) epoch first.
        if targMode
            pushIdx = find(epochSched | (epochR ~= 0));
            if ~isempty(pushIdx)
                nSel = numel(pushIdx);
                newNb = nb + (1:nSel);
                bufS(:, newNb) = epochS0(:, pushIdx);
                bufA(newNb)    = epochA(pushIdx);
                bufR(newNb)    = single(epochR(pushIdx));
                bufU(newNb)    = pushIdx;
                bufP(newNb)    = single(1);
                nb = nb + nSel;
            end
        end
        if nb > 0
            if useRTT
                for k = 1:nb
                    d_id = bufDecId(k);
                    if d_id > 0 && d_id <= numel(dec_flushed)
                        dec_flushed(d_id) = true;
                        dec_buf_idx(d_id) = 0;
                    end
                end
            end
            Xp = struct('age', ageM(Ttot, :), 'dev', obsS(Ttot, :) - emaO, 'cn', cn, 'Q', Q, 't', Ttot, ...
                        'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma, 'H', H);
            S_post = build_state_v15(Ttot, obsS, off, prevRef, nk, H, ...
                meta.speeds(Ttot,:), burstObsM(Ttot,:), meta.delays, R_emas, ctx, histS, env, nFeat, featExtra_v15(env, Xp));
            [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = a2c_update_v15( ...
                actorNet, criticNet, Wc, S_post, bufS, bufA, bufR, bufU, bufP, nb, ...
                gamma, entW, clip_norm, lr_actor, lr_critic, toDl, ...
                aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt);
            Wa = extract_weights(actorNet);
            Wc = extract_weights(criticNet);
            nb = 0; lastIdx(:) = 0;
        end

        learning_curve(ep) = ep_tp / simTime;
        entropy_curve(ep)  = ep_ent / simTime;

        if doVal && (mod(ep, val_every) == 0 || ep == num_episodes)
            rngSave = rng;
            sc = score_a2c_on_traces_v15(actorNet, env, valTraces);
            rng(rngSave);
            valCurve(end+1) = sc; %#ok<AGROW>
            if sc > bestScore
                bestScore = sc; bestActorNet = actorNet; bestCriticNet = criticNet; bestEp = ep;
            end
        end

        if mod(ep, 25) == 0 || ep == num_episodes
            fprintf('  Deep A2C v15 ep %3d/%d | CellTp = %5.2f Mbps | Policy Entropy = %5.3f | entW = %.3f\n', ...
                    ep, num_episodes, learning_curve(ep), entropy_curve(ep), entW);
        end
    end

    else
        % ---- parallel rollout batches (n_envs > 1) ----
        if targMode
            error('DeepA2C_Shared_v15:unsupported', ...
                ['env.a2c.n_envs > 1 is not yet implemented for action_mode = ''target'' ' ...
                 '(rollout_episode_v15 only has the offset-mode semi-MDP logic). ' ...
                 'Use n_envs = 1 for P1 target-mode runs.']);
        end
        epCount = 0;
        while epCount < num_episodes
            thisN = min(n_envs, num_episodes - epCount);
            entWs = zeros(1, thisN);
            seeds = zeros(1, thisN);
            for e = 1:thisN
                epG = epCount + e;
                entWs(e) = ent_start + (ent_end - ent_start) * (epG - 1) / max(num_episodes - 1, 1);
                seeds(e) = randi(2^31 - 1);
            end
            WaFrozen = Wa; %#ok<NASGU>
            results = cell(1, thisN);
            parfor e = 1:thisN
                results{e} = rollout_episode_v15(WaFrozen, env, simTime, seeds(e), N, A, nA, ...
                    minC, maxC, Pq, rk, nSingle, nFeat, L_seq); %#ok<PFBNS>
            end

            totalNb = 0;
            for e = 1:thisN, totalNb = totalNb + results{e}.nb; end
            bufSm = zeros(nFeat, totalNb, 'single');
            bufAm = zeros(1, totalNb);
            bufRm = zeros(1, totalNb, 'single');
            bufUm = zeros(1, totalNb);
            bufPm = zeros(1, totalNb, 'single');
            Spostm = zeros(nFeat, thisN * N, 'single');
            pos = 0;
            for e = 1:thisN
                r = results{e};
                ne = r.nb;
                bufSm(:, pos+1:pos+ne) = r.bufS;
                bufAm(pos+1:pos+ne)    = r.bufA;
                bufRm(pos+1:pos+ne)    = r.bufR;
                bufUm(pos+1:pos+ne)    = r.bufU + (e - 1) * N;
                bufPm(pos+1:pos+ne)    = r.bufP;
                Spostm(:, (e-1)*N+1 : e*N) = r.S_post;
                epG = epCount + e;
                learning_curve(epG) = r.ep_tp / simTime;
                entropy_curve(epG)  = r.ep_ent / simTime;
                pos = pos + ne;
            end

            [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = a2c_update_v15( ...
                actorNet, criticNet, Wc, Spostm, bufSm, bufAm, bufRm, bufUm, bufPm, totalNb, ...
                gamma, mean(entWs), clip_norm, lr_actor, lr_critic, toDl, ...
                aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt);
            Wa = extract_weights(actorNet);
            Wc = extract_weights(criticNet);

            epCount = epCount + thisN;

            if doVal && (mod(epCount, val_every) == 0 || epCount == num_episodes)
                rngSave = rng;
                sc = score_a2c_on_traces_v15(actorNet, env, valTraces);
                rng(rngSave);
                valCurve(end+1) = sc; %#ok<AGROW>
                if sc > bestScore
                    bestScore = sc; bestActorNet = actorNet; bestCriticNet = criticNet; bestEp = epCount;
                end
            end

            for e = 1:thisN
                epG = epCount - thisN + e;
                if mod(epG, 25) == 0 || epG == num_episodes
                    fprintf(['  Deep A2C v15 ep %3d/%d | CellTp = %5.2f Mbps | Policy Entropy = %5.3f | ' ...
                             'entW = %.3f (parallel batch, n_envs=%d)\n'], ...
                            epG, num_episodes, learning_curve(epG), entropy_curve(epG), entWs(e), thisN);
                end
            end
        end
    end

    if ~doVal
        bestActorNet = actorNet; bestCriticNet = criticNet; bestEp = num_episodes;
    end

    late_frac = 0;
    if total_credits_total > 0
        late_frac = late_credits_total / total_credits_total;
    end
    trainInfo = struct('late_credit_frac', late_frac, ...
                       'late_credits', late_credits_total, ...
                       'total_credits', total_credits_total);
end

function out = rollout_episode_v15(Wa, env, simTime, seedEp, N, A, nA, minC, maxC, Pq, rk, nSingle, nFeat, L_seq)
% rollout_episode_v15  One full episode of experience collection with FIXED
% (frozen) actor weights Wa -- no network update happens here. Used by the
% n_envs > 1 parallel-rollout path (P0.3); each worker calls this once per
% episode in the batch, and the caller merges the returned buffers and
% performs a single update. Mirrors the n_envs == 1 per-TTI logic above
% exactly, but accumulates the whole episode's scheduled transitions (no
% mid-episode flush, since the weights are frozen for the batch).
    if ~isempty(seedEp), rng(seedEp); end
    noop = find(A == 0);
    sched = sampleSched_v5(env);
    [~, sOneHot] = schedContext_v5(sched, env);
    ctx = single(repmat(sOneHot, 1, N));

    W = 0; if isfield(env, 'train_warm_ttis'), W = env.train_warm_ttis; end
    Ttot = W + simTime;
    [Strue, ~, meta] = generateChannel_v15(Ttot, env);
    obsS = cqiFeedback_v15(Strue, env, meta.delays);

    burstObsM = zeros(Ttot, N);
    for i = 1:N
        idx = max((1:Ttot).' - meta.delays(i), 1);
        burstObsM(:, i) = double(meta.burst(idx));
    end

    ageM = cqiAge_v15(Ttot, N, Pq);
    emaO = obsS(1, :); cn = 0;
    Q = trafficInit_v15(env, N, 0);
    lastIdx = zeros(1, N); pendR = zeros(1, N);
    off = zeros(1, N);
    H = harqInit_v15(N, env);
    nk = zeros(1, N);
    prevRef = baseCQI_v15(obsS(1,:) + off, env);
    R_emas = zeros(1, N);
    ema = 0.05;
    ep_tp = 0; ep_ent = 0;
    ack8 = zeros(1, N); tsince = zeros(1, N); offEma = zeros(1, N);

    histS = zeros(nSingle, N, L_seq, 'single');

    cap = Ttot * N + N;
    bufS = zeros(nFeat, cap, 'single');
    bufA = zeros(1, cap);
    bufR = zeros(1, cap, 'single');
    bufU = zeros(1, cap);
    bufP = zeros(1, cap, 'single');
    nb = 0;

    for t = 1:Ttot
        learn = t > W;
        [Q, H, missEv] = trafficPre_v15(Q, t, env, H);
        X = struct('age', ageM(t, :), 'dev', obsS(t, :) - emaO, 'cn', cn, 'Q', Q, 't', t, ...
                    'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma, 'H', H);
        xtra = featExtra_v15(env, X);
        [S_temporal, histS, ref] = build_state_v15(t, obsS, off, prevRef, nk, H, ...
            meta.speeds(t,:), burstObsM(t,:), meta.delays, R_emas, ctx, histS, env, nFeat, xtra);
        if learn && (strcmpi(rk, 'ontime') || strcmpi(rk, 'ontime_shaped')) && any(missEv)
            for i = find(missEv)
                if lastIdx(i) > 0, bufR(lastIdx(i)) = bufR(lastIdx(i)) - single(env.miss_pen);
                else, pendR(i) = pendR(i) - env.miss_pen; end
            end
        end

        [~, P] = forward_actor(Wa, S_temporal);
        if learn, ep_ent = ep_ent + mean(-sum(P .* log(P + 1e-12), 1)); end

        isRetx = env.harq_on & H.pend;
        if learn
            U_act = rand(1, N);
            Pcum = cumsum(P, 1);
            cmp = U_act <= Pcum;
            [tfHit, aIdx] = max(cmp, [], 1);
            aIdx(~tfHit) = nA;
        else
            aIdx = noop * ones(1, N);
        end
        sent = max(minC, min(maxC, ref + A(aIdx)));

        rbFull = env.total_RB * ones(1, N);
        if isfield(env, 'sched_on_ref') && env.sched_on_ref
            potNew = tbsFromMCSandRB_v15(max(env.min_CQI, min(env.max_CQI, ref)) - 1, rbFull) * 1e-3;
        else
            potNew = tbsFromMCSandRB_v15(sent - 1, rbFull) * 1e-3;
        end
        pot = potNew;
        if any(isRetx)
            potRetx = tbsFromMCSandRB_v15(H.mcs, rbFull) * 1e-3;
            pot(isRetx) = potRetx(isRetx);
        end

        pot(~Q.has) = 0;
        dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);  % T3: EDF plumbing
        rb = schedule_users_v15(sched, t, N, R_emas, pot, env.total_RB, dlv);
        rb(~Q.has) = 0;
        [tp_now, off, H, ~, nEv, dropEv] = txStep_v15(sent, Strue(t,:), rb, off, H, env);
        [Q, okEv] = trafficPost_v15(Q, tp_now, t);
        if any(rb > 0), cn = 0.6 * cn + 0.4 * mean(double(nEv(rb > 0))); else, cn = 0.97 * cn; end
        emaO = 0.98 * emaO + 0.02 * obsS(t, :);

        schedM = rb > 0;
        nk(schedM)  = 0.7 * nk(schedM) + 0.3 * double(nEv(schedM));
        nk(~schedM) = 0.95 * nk(~schedM);
        R_emas = (1 - ema) * R_emas + ema * tp_now;
        ack8(schedM) = 0.8 * ack8(schedM) + 0.2 * double(~nEv(schedM));
        tsince(schedM) = 0; tsince(~schedM) = tsince(~schedM) + 1;
        offEma = 0.9 * offEma + 0.1 * off;
        if learn, ep_tp = ep_tp + sum(tp_now); end

        if learn
            selIdx = find(schedM);
            nSel = numel(selIdx);
            if nSel > 0
                if strcmpi(rk, 'ontime')
                    rI = env.ontime_bonus * double(okEv(selIdx)) + pendR(selIdx);
                    pendR(selIdx) = 0;
                elseif strcmpi(rk, 'oppcost')
                    tref = tbsFromMCSandRB_v15(max(minC, min(maxC, ref(selIdx))) - 1, rb(selIdx)) * 1e-3 * (1 - env.olla_target);
                    rI = (tp_now(selIdx) - tref) / env.reward_scale;
                else
                    rI = (tp_now(selIdx) / env.reward_scale) ...
                          - env.lambda_drop * double(dropEv(selIdx)) ...
                          - env.lambda_retx * double(nEv(selIdx));
                end
                newNb = nb + (1:nSel);
                bufS(:, newNb)  = S_temporal(:, selIdx);
                bufA(newNb)     = aIdx(selIdx);
                bufR(newNb)     = single(rI);
                bufU(newNb)     = selIdx;
                bufP(newNb)     = single(~isRetx(selIdx));
                lastIdx(selIdx) = newNb;
                nb = nb + nSel;
            end
        end
        prevRef = ref;
    end

    Xp = struct('age', ageM(Ttot, :), 'dev', obsS(Ttot, :) - emaO, 'cn', cn, 'Q', Q, 't', Ttot, ...
                'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma, 'H', H);
    S_post = build_state_v15(Ttot, obsS, off, prevRef, nk, H, ...
        meta.speeds(Ttot,:), burstObsM(Ttot,:), meta.delays, R_emas, ctx, histS, env, nFeat, featExtra_v15(env, Xp));

    out = struct('bufS', bufS(:, 1:nb), 'bufA', bufA(1:nb), 'bufR', bufR(1:nb), ...
                 'bufU', bufU(1:nb), 'bufP', bufP(1:nb), 'nb', nb, ...
                 'S_post', S_post, 'ep_tp', ep_tp, 'ep_ent', ep_ent);
end

function [S_temporal, histS, ref] = build_state_v15(t, obsS, off, prevRef, nk, H, spd, burstObs, delays, R_emas, ctx, histS, env, nFeat, xtra)
% Build the stacked (L_seq-frame) state for all users at TTI t.
    ref  = baseCQI_v15(obsS(t,:) + off, env);
    dRef = max(env.min_delta, min(env.max_delta, ref - prevRef));
    dS   = obsS(t,:) - obsS(max(t-1,1),:);
    t0   = max(t-4, 1);
    slope4 = (obsS(t,:) - obsS(t0,:)) / max(t - t0, 1);
    s_now = stateFeat_v15(env.state_tier, ref, dRef, obsS(t,:), dS, off, ...
                         slope4, nk, H, spd, burstObs, delays, R_emas, ctx, xtra);
    L_seq = size(histS, 3);
    histS(:,:,2:L_seq) = histS(:,:,1:L_seq-1);
    histS(:,:,1) = s_now;
    S_temporal = reshape(permute(histS, [1, 3, 2]), nFeat, size(histS, 2));
end

function [actorNet, criticNet, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt] = a2c_update_v15( ...
        actorNet, criticNet, Wc, S_next, bufS, bufA, bufR, bufU, bufP, nb, ...
        gamma, entW, clip_norm, lr_actor, lr_critic, toDl, aAvg, aAvgSq, aIt, cAvg, cAvgSq, cIt)
% Per-user n-step returns over each user's scheduled transitions, with the
% final transition of each user bootstrapped from that user's successor state.
    Vnext = forward_critic(Wc, S_next);          % 1 x N
    rets = zeros(1, nb, 'single');
    R = bufR(1:nb);
    U = bufU(1:nb);
    for u = unique(U)
        idx = find(U == u);
        G = single(Vnext(u));
        for j = numel(idx):-1:1
            G = R(idx(j)) + single(gamma) * G;
            rets(idx(j)) = G;
        end
    end

    [aG, cG] = dlfeval(@a2c_grads_v15, actorNet, criticNet, ...
                       toDl(bufS(:, 1:nb)), bufA(1:nb), toDl(rets), entW, bufP(1:nb));
    aG = clipGlobal(aG, clip_norm);
    cG = clipGlobal(cG, clip_norm);
    aIt = aIt + 1;
    [actorNet, aAvg, aAvgSq] = adamupdate(actorNet, aG, aAvg, aAvgSq, aIt, lr_actor);
    cIt = cIt + 1;
    [criticNet, cAvg, cAvgSq] = adamupdate(criticNet, cG, cAvg, cAvgSq, cIt, lr_critic);
end

function [aGrad, cGrad] = a2c_grads_v15(actorNet, criticNet, S, Aacts, R, entW, pMask)
    V = forward(criticNet, S);
    adv = R - V;
    cLoss = mean(adv.^2);

    logits = forward(actorNet, S);
    m = max(logits, [], 1);
    logZ = m + log(sum(exp(logits - m), 1));
    logp_all = logits - logZ;
    B = size(S, 2);
    An = size(logits, 1);
    mask = zeros(An, B, 'single');
    mask(sub2ind([An, B], Aacts(1:B), 1:B)) = 1;
    mask = dlarray(mask);
    logp = sum(logp_all .* mask, 1);

    % Advantage normalisation over the policy-relevant (first-transmission)
    % samples only; retransmission samples get zero policy weight.
    advD = double(gather(extractdata(adv)));
    pm = double(pMask(:)') > 0;
    advN = zeros(size(advD));
    if any(pm)
        a = advD(pm);
        sd = std(a);
        if sd > 1e-6, advN(pm) = (a - mean(a)) / sd; else, advN(pm) = a - mean(a); end
    end
    advD = dlarray(cast(advN, 'like', extractdata(logits)));
    nP = max(sum(pm), 1);

    p = exp(logp_all);
    entropy = -sum(p .* logp_all, 1);
    aLoss = -sum(logp .* advD) / nP - entW * mean(entropy);

    cGrad = dlgradient(cLoss, criticNet.Learnables, 'RetainData', true);
    aGrad = dlgradient(aLoss, actorNet.Learnables);
end

function grads = clipGlobal(grads, clipNorm)
    totalSq = 0;
    for k = 1:height(grads)
        v = grads.Value{k};
        if ~isempty(v), totalSq = totalSq + sum(extractdata(v(:)).^2); end
    end
    normG = sqrt(totalSq);
    if normG > clipNorm
        scale = clipNorm / (normG + 1e-12);
        for k = 1:height(grads)
            if ~isempty(grads.Value{k})
                grads.Value{k} = grads.Value{k} * scale;
            end
        end
    end
end

function W = extract_weights(net)
    L = net.Learnables;
    W.w1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Weights"});
    W.b1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Bias"});
    W.w2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Weights"});
    W.b2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Bias"});
    isL3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Weights";
    W.w3 = extractdata(L.Value{isL3});
    isB3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Bias";
    W.b3 = extractdata(L.Value{isB3});
end

function [logits, P] = forward_actor(W, S)
    x1 = max(0, W.w1 * S + W.b1);
    x2 = max(0, W.w2 * x1 + W.b2);
    logits = double(W.w3 * x2 + W.b3);
    logits = logits - max(logits, [], 1);
    P = exp(logits) ./ sum(exp(logits), 1);
end

function V = forward_critic(W, S)
    x1 = max(0, W.w1 * S + W.b1);
    x2 = max(0, W.w2 * x1 + W.b2);
    V = double(W.w3 * x2 + W.b3);
end

function v = hpget(hp, f, d)
    if isfield(hp, f) && ~isempty(hp.(f)), v = hp.(f); else, v = d; end
end

function tf = schedNow(rb)
    tf = rb > 0;
end

function valTraces = buildValTraces_v15(env, simTime, n_val)
% buildValTraces_v15  P0.4: n_val held-out validation traces, seeds 80000+
% (disjoint from calibration 60000+ and evaluation 9000+), common random
% numbers per trace so repeated scoring across checkpoints is comparable.
    valTraces = struct('S', {}, 'O', {}, 'M', {}, 'U', {});
    for j = 1:n_val
        rng(80000 + j);
        [Strue, ~, meta] = generateChannel_v15(simTime, env);
        obsS = cqiFeedback_v15(Strue, env, meta.delays);
        meta.trace_id = 70000 + j;
        rng(81000 + j); U = rand(simTime, env.N);
        valTraces(j).S = Strue; valTraces(j).O = obsS; valTraces(j).M = meta; valTraces(j).U = U;
    end
end

function v = score_a2c_on_traces_v15(actorNet, env, valTraces)
% score_a2c_on_traces_v15  Greedy-policy primary-metric score of actorNet
% on the validation traces (same pattern as calibrateCtx_v15's score()).
    n = 0; d = 0;
    for jj = 1:numel(valTraces)
        [tpc, ~, ~, ~, inf] = evalPolicy_v15('a2c_v15', actorNet, ...
            valTraces(jj).S, valTraces(jj).O, env, valTraces(jj).M, valTraces(jj).U);
        b0 = min(env.burn_in, size(tpc, 1) - 1);
        [nu, de] = userMetric_v15(env, tpc, inf, b0);
        n = n + sum(nu); d = d + sum(de);
    end
    v = n / max(d, 1);
end
