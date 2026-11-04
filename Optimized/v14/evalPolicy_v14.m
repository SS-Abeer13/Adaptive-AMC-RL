function [tp, bler, cqi_err, act, info] = evalPolicy_v14(ptype, policy, SINR_true, obs_SINR, env, meta, U)
% v9: U (T x N uniforms, optional) = common random numbers for outcome draws;
%     'bandit' ptype = frozen UCB bandit offset (global or per delay class).
% evalPolicy_v14  Unified frozen-policy evaluation harness for all 7 comparators:
%   1. 'baseline'     : Open-loop 3GPP CQI mapping (no outer loop)
%   2. 'olla'         : Standard 3GPP OLLA integrator
%   3. 'warm_olla'    : Converged steady-state OLLA (1000-TTI pre-convergence)
%   4. 'multi_olla'   : Multi-Offset OLLA with fast/slow tracking (arXiv:2604.20459)
%   5. 'fixed'        : Global best fixed offset
%   6. 'fixed_online' : Realistic online heuristic classifier (Doppler/delay)
%   7. 'fixed_class'  : Theoretical offline oracle ceiling (FixedPU)
%   8. 'a2c'          : Autonomous Recurrent/Temporal Deep A2C (v8)
%   9. 'rand'         : Uniform random action control
    [T, N] = size(SINR_true);
    if nargin < 7, U = []; end
    if ~(isfield(env, 'crn') && env.crn), U = []; end
    % v14: 'olla_tuned' = OLLA with the calibrated target BLER;
    %      'ctxtab'     = OLLA + calibrated per-cue-bin offset (same information as the A2C cue)
    if strcmpi(ptype, 'olla_tuned'), env.olla_target = env.olla_target_tuned; ptype = 'olla'; end
    isCtx = strcmpi(ptype, 'ctxtab');
    A = env.actions;
    no_op = find(A == 0);
    maxC = env.max_CQI; minC = env.min_CQI;
    maxD = env.max_delta; minD = env.min_delta;
    L_seq = 3;

    useOLLA = ~any(strcmpi(ptype, {'baseline', 'genie_cqi'}));
    isWarmOLLA = strcmpi(ptype, 'warm_olla');

    % Steady-state warm-up: independent channel segment with same user parameters
    W = 0;
    burst = meta.burst; speeds = meta.speeds; delays = meta.delays;
    if (useOLLA && isfield(env, 'olla_warm_ttis') && env.olla_warm_ttis > 0) || isWarmOLLA
        if isWarmOLLA
            W = 1000;
        else
            W = round(env.olla_warm_ttis);
        end
        rs = rng;
        if isfield(meta, 'trace_id')
            rng(100000 + 7*W + 1000*meta.trace_id);   % v9: unique per trace
        else
            rng(100000 + 7*W + 13*N + 101*round(mean(delays)));
        end
        Sw = []; Ow = []; Bw = []; Vw = [];
        while size(Sw, 1) < W
            [Sb, ~, mb] = generateChannel_v14(T, env, meta);
            Ob = cqiFeedback_v14(Sb, env, delays);
            Sw = [Sw; Sb]; Ow = [Ow; Ob]; %#ok<AGROW>
            Bw = [Bw; mb.burst]; Vw = [Vw; mb.speeds]; %#ok<AGROW>
        end
        Uw = rand(W, N);   % warm-up outcome draws, common to all schemes on this trace
        rng(rs);
        if ~isempty(U), U = [Uw; U]; end
        SINR_true = [Sw(1:W, :); SINR_true];
        obs_SINR  = [Ow(1:W, :); obs_SINR];
        burst     = [Bw(1:W); burst];
        speeds    = [Vw(1:W, :); speeds];
        T = T + W;
    end

    Pq = 1; if isfield(env, 'cqi_period'), Pq = max(1, round(env.cqi_period)); end
    ageM = cqiAge_v14(T - W, N, Pq);
    if W > 0, ageM = [cqiAge_v14(W, N, Pq); ageM]; end
    emaO = obs_SINR(1, :);      % long-run EMA of each user's reports
    cn = 0;                     % cell-wide NACK EMA
    Q = trafficInit_v14(env, N, W + min(env.burn_in, T - W - 1));

    tp = zeros(T, N);
    bler = nan(T, N);
    cqi_err = zeros(T, N);
    act = no_op * ones(T, N);

    burstObsM = zeros(T, N);
    for i = 1:N
        idx = max((1:T).' - delays(i), 1);
        burstObsM(:, i) = double(burst(idx));
    end

    % Oracle per-class offset table (FixedPU)
    fco = zeros(1, N);
    if any(strcmpi(ptype, {'fixed_class', 'fixed_oracle'}))
        for i = 1:N
            [dc, vc] = userClass_v14(delays(i), mean(speeds(:, i)));
            fco(i) = env.fixed_class_tab(dc, vc);
        end
    end

    % Bandit baseline: frozen per-context offset (context = observable delay class)
    bo = zeros(1, N);
    if strcmpi(ptype, 'bandit')
        for i = 1:N
            if strcmpi(policy.ctxType, 'delay'), c = 1 + (delays(i) >= 5); else, c = 1; end
            bo(i) = policy.arm(c);
        end
    end

    % P1 (README_v14.md): same-information target-mode comparators, both
    % frozen per-user for the whole trace (like fco/bo above).
    %   'olla_target_class' : per-class tuned target (same info as FixedPU)
    %   'bandit_target'     : contextual (delay-class) bandit over targets
    tgo = []; bto = [];
    if strcmpi(ptype, 'olla_target_class')
        tgo = zeros(1, N);
        for i = 1:N
            [dc, vc] = userClass_v14(delays(i), mean(speeds(:, i)));
            tgo(i) = env.target_class_tab(dc, vc);
        end
    end
    if strcmpi(ptype, 'bandit_target')
        bto = zeros(1, N);
        for i = 1:N
            if strcmpi(policy.ctxType, 'delay'), c = 1 + (delays(i) >= 5); else, c = 1; end
            bto(i) = policy.arm(c);
        end
    end

    % P1: action_mode = 'target' -- the A2C/'rand' action selects an OLLA
    % target BLER (env.target_set) held for env.target_epoch TTIs (semi-MDP),
    % instead of a CQI offset. curAIdx/targVec persist across TTIs here.
    targMode = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'target');
    Tset = env.target_set;
    curAIdx = ones(1, N);
    targVec = Tset(curAIdx);

    [~, sOneHot] = schedContext_v5(env.scheduler, env);
    ctx = single(repmat(sOneHot, 1, N));
    isDeep = any(strcmpi(ptype, {'a2c', 'a2c_v14'}));
    isEns  = strcmpi(ptype, 'a2c_ens');
    isResid = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'resid');
    isGRU = strcmpi(ptype, 'gru_v14');   % P4: recurrent policy, greedy action
    isMultiOLLA = strcmpi(ptype, 'multi_olla');

    off = zeros(1, N);
    off_fast = zeros(1, N);
    off_slow = zeros(1, N);
    H = harqInit_v14(N);
    R_emas = zeros(1, N);
    ema = 0.05;
    nk = zeros(1, N);
    prevRef = baseCQI_v14(obs_SINR(1, :) + off, env);
    % P4: trackers for the 'ack8'/'tsince'/'offtrend' feat_extra/ctx_cue
    % options (read causally -- end-of-previous-TTI values -- like nk/cn).
    ack8 = zeros(1, N); tsince = zeros(1, N); offEma = zeros(1, N);

    if upper(env.state_tier) == 'A', nBase = 5; elseif upper(env.state_tier) == 'O', nBase = 10; else, nBase = 13; end
    nSingle = nBase + numel(env.sched_list);
    nSingle = nSingle + nExtra_v14(env);
    nFeat = nSingle * L_seq;
    histS = zeros(nSingle, N, L_seq, 'single');


    b_i = zeros(1, N);
    if isResid
        base_kind = 'fixed';
        if isfield(env, 'base_rule_kind'), base_kind = lower(env.base_rule_kind); end
        if strcmpi(base_kind, 'fixed_class') || strcmpi(base_kind, 'fixedpu')
            for i = 1:N
                [dc, vc] = userClass_v14(delays(i), mean(speeds(:, i)));
                b_i(i) = env.fixed_class_tab(dc, vc);
            end
        else
            b_i(:) = env.fixed_offset;
        end
    end

    if isDeep
        L = policy.Learnables;
        Wa.w1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Weights"});
        Wa.b1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Bias"});
        Wa.w2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Weights"});
        Wa.b2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Bias"});
        isL3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Weights";
        Wa.w3 = extractdata(L.Value{isL3});
        isB3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Bias";
        Wa.b3 = extractdata(L.Value{isB3});
    end
    if isEns
        K_ens = numel(policy);
        Wa_ens = cell(1, K_ens);
        for kE = 1:K_ens
            L = policy{kE}.Learnables;
            Wak.w1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Weights"});
            Wak.b1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Bias"});
            Wak.w2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Weights"});
            Wak.b2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Bias"});
            isL3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Weights";
            Wak.w3 = extractdata(L.Value{isL3});
            isB3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Bias";
            Wak.b3 = extractdata(L.Value{isB3});
            Wa_ens{kE} = Wak;
        end
    end
    if isGRU
        % P4: same hand-coded GRU step as DeepGRU_Shared_v14 (gate order
        % reset/update/new, verified against dlnetwork's own forward()).
        Lp = policy.Learnables;
        Wg.Wi  = extractdata(Lp.Value{Lp.Layer == "gru" & Lp.Parameter == "InputWeights"});
        Wg.Wh  = extractdata(Lp.Value{Lp.Layer == "gru" & Lp.Parameter == "RecurrentWeights"});
        Wg.b   = extractdata(Lp.Value{Lp.Layer == "gru" & Lp.Parameter == "Bias"});
        Wg.Wfc = extractdata(Lp.Value{Lp.Layer == "fc" & Lp.Parameter == "Weights"});
        Wg.bfc = extractdata(Lp.Value{Lp.Layer == "fc" & Lp.Parameter == "Bias"});
        nH = size(Wg.Wh, 2);
        h_gru = zeros(nH, N);
        idxg = @(k) (k-1)*nH+1 : k*nH;
    end

    for t = 1:T
        [Q, H] = trafficPre_v14(Q, t, env, H);
        X = struct('age', ageM(t, :), 'dev', obs_SINR(t, :) - emaO, 'cn', cn, 'Q', Q, 't', t, ...
                    'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma);
        if isCtx, ctxOff = env.ctx_tab(ctxBin_v14(env, X)); end
        ref  = baseCQI_v14(obs_SINR(t, :) + off, env);
        dRef = max(minD, min(maxD, ref - prevRef));
        dS   = obs_SINR(t, :) - obs_SINR(max(t-1, 1), :);
        t0   = max(t-4, 1);
        slope4 = (obs_SINR(t, :) - obs_SINR(t0, :)) / max(t - t0, 1);

        if isDeep || isEns
            s_now = stateFeat_v14(env.state_tier, ref, dRef, obs_SINR(t, :), dS, off, ...
                                 slope4, nk, H, speeds(t, :), burstObsM(t, :), ...
                                 delays, R_emas, ctx, featExtra_v14(env, X));
            histS(:, :, 2:L_seq) = histS(:, :, 1:L_seq-1);
            histS(:, :, 1) = s_now;
            S_temporal = reshape(permute(histS, [1, 3, 2]), nFeat, N);
        end

        if isDeep
            x1 = max(0, Wa.w1 * S_temporal + Wa.b1);
            x2 = max(0, Wa.w2 * x1 + Wa.b2);
            logits = Wa.w3 * x2 + Wa.b3;
        end

        if isEns
            nA_ens = 3;
            if ~isResid, nA_ens = numel(A); end
            P_ens = zeros(nA_ens, N);
            for kE = 1:K_ens
                Wak = Wa_ens{kE};
                x1 = max(0, Wak.w1 * S_temporal + Wak.b1);
                x2 = max(0, Wak.w2 * x1 + Wak.b2);
                logk = double(Wak.w3 * x2 + Wak.b3);
                logk = logk - max(logk, [], 1);
                Pk = exp(logk) ./ sum(exp(logk), 1);
                P_ens = P_ens + Pk / K_ens;
            end
        end
        if isGRU
            % P4: single-frame state (no finite-difference history inputs
            % -- the GRU hidden state is the memory, matching
            % DeepGRU_Shared_v14's stateFeat_gru_v14).
            x_now = single(stateFeat_v14(env.state_tier, ref, zeros(1, N), obs_SINR(t, :), zeros(1, N), off, ...
                                 zeros(1, N), nk, H, speeds(t, :), burstObsM(t, :), ...
                                 delays, R_emas, ctx, featExtra_v14(env, X)));
            rg = idxg(1); zg = idxg(2); ng = idxg(3);
            rGate = 1 ./ (1 + exp(-(Wg.Wi(rg,:)*x_now + Wg.Wh(rg,:)*h_gru + Wg.b(rg))));
            zGate = 1 ./ (1 + exp(-(Wg.Wi(zg,:)*x_now + Wg.Wh(zg,:)*h_gru + Wg.b(zg))));
            nGate = tanh(Wg.Wi(ng,:)*x_now + rGate .* (Wg.Wh(ng,:)*h_gru) + Wg.b(ng));
            h_gru = (1 - zGate) .* nGate + zGate .* h_gru;
            gruLogits = Wg.Wfc * h_gru + Wg.bfc;
        end

        % P0.2: vectorised over users (was a per-user for-loop). ptype is the
        % same for every user in a call, so the switch runs once; only
        % 'fixed_online' (unused by the current comparator set) still needs
        % userClass_v14 per user. 'rand' draws randi(numel(A), 1, N) in one
        % call, which consumes the global RNG stream in the same ascending-
        % user order as N sequential randi() calls, so CRN draws are
        % unchanged (see test_equivalence_v14.m).
        alpha_vec = 0.5 * ones(1, N);
        switch lower(ptype)
            case {'baseline', 'olla', 'warm_olla'}
                cqiAll = ref;
            case 'multi_olla'
                % Blended fast/slow multi-offset
                alpha_vec = 0.5 + 0.3 * (abs(slope4) > 1.0) + 0.2 * (nk > 0.4);
                cqi_eff_sinr = obs_SINR(t, :) + alpha_vec .* off_fast + (1 - alpha_vec) .* off_slow;
                cqiAll = baseCQI_v14(cqi_eff_sinr, env);
            case 'fixed'
                cqiAll = max(minC, min(maxC, ref + env.fixed_offset));
            case 'fixed_online'
                cqiAll = zeros(1, N);
                for i = 1:N
                    % Online estimated velocity and delay
                    est_v = mean(speeds(max(t-20,1):t, i));
                    est_d = delays(i); % Available from ACK feedback latency
                    [dc_on, vc_on] = userClass_v14(est_d, est_v);
                    cqiAll(i) = max(minC, min(maxC, ref(i) + env.fixed_class_tab(dc_on, vc_on)));
                end
            case {'fixed_class', 'fixed_oracle'}
                cqiAll = max(minC, min(maxC, ref + fco));
            case {'a2c', 'a2c_v14'}
                if targMode
                    if mod(t - 1, env.target_epoch) == 0
                        [~, curAIdx] = max(logits, [], 1);
                    end
                    act(t, :) = curAIdx;
                    targVec = Tset(curAIdx);
                    cqiAll = ref;
                elseif isResid
                    [~, aAll] = max(logits, [], 1);
                    act(t, :) = aAll;
                    delta = env.resid_actions(aAll);
                    cqiAll = max(minC, min(maxC, ref + b_i + delta));
                else
                    [~, aAll] = max(logits, [], 1);
                    act(t, :) = aAll;
                    cqiAll = max(minC, min(maxC, ref + A(aAll)));
                end
            case 'a2c_ens'
                [~, aAll] = max(P_ens, [], 1);
                act(t, :) = aAll;
                if isResid
                    delta = env.resid_actions(aAll);
                    cqiAll = max(minC, min(maxC, ref + b_i + delta));
                else
                    cqiAll = max(minC, min(maxC, ref + A(aAll)));
                end
            case 'gru_v14'
                % P4: greedy offset action from the recurrent policy (no
                % target-mode semi-MDP -- see README_v14.md P4 scope note).
                [~, aAll] = max(gruLogits, [], 1);
                act(t, :) = aAll;
                cqiAll = max(minC, min(maxC, ref + A(aAll)));
            case 'bandit'
                cqiAll = max(minC, min(maxC, ref + bo));
            case 'ctxtab'
                cqiAll = max(minC, min(maxC, ref + ctxOff));
            case 'olla_target_class'
                cqiAll = ref;
            case 'bandit_target'
                cqiAll = ref;
            case 'rand'
                if targMode
                    if mod(t - 1, env.target_epoch) == 0
                        curAIdx = randi(numel(Tset), 1, N);
                    end
                    act(t, :) = curAIdx;
                    targVec = Tset(curAIdx);
                    cqiAll = ref;
                else
                    aAll = randi(numel(A), 1, N);
                    act(t, :) = aAll;
                    cqiAll = max(minC, min(maxC, ref + A(aAll)));
                end
            case 'genie_cqi'
                % Stage 0 (PLAN_v14.md S0.1): Perfect-CSI bound.
                % User i gets largest CQI q in 1:15 such that estimateBLER_v14(SINR_true(t,i), q-1) <= env.genie_bler
                cqiAll = ones(1, N);
                for i = 1:N
                    gamma_i = SINR_true(t, i);
                    blers_i = estimateBLER_v14(gamma_i * ones(1, 15), 0:14);
                    valid_q = find(blers_i <= env.genie_bler);
                    if ~isempty(valid_q)
                        cqiAll(i) = max(valid_q);
                    else
                        cqiAll(i) = 1;
                    end
                end
                cqiAll = max(minC, min(maxC, cqiAll));
            otherwise
                error('evalPolicy_v14: unknown ptype "%s"', ptype);
        end
        sent = cqiAll;

        % P1: the per-user target fed into txStep_v14's OLLA step (empty =
        % env.olla_target for everyone, i.e. unchanged v10/v14-P0 physics).
        targVecForStep = [];
        if strcmpi(ptype, 'olla_target_class'), targVecForStep = tgo;
        elseif strcmpi(ptype, 'bandit_target'),  targVecForStep = bto;
        elseif targMode && any(strcmpi(ptype, {'a2c', 'a2c_v14', 'rand'})), targVecForStep = targVec;
        end

        rbFull = env.total_RB * ones(1, N);
        if isfield(env, 'sched_on_ref') && env.sched_on_ref
            % FILL FIX option: scheduler ranks users by the OLLA reference rate,
            % not by the link-adaptation decision (removes scheduler gaming)
            potNew = tbsFromMCSandRB_v14(max(env.min_CQI, min(env.max_CQI, ref)) - 1, rbFull) * 1e-3;
        else
            potNew = tbsFromMCSandRB_v14(sent - 1, rbFull) * 1e-3;
        end
        pot = potNew;
        if env.harq_on && any(H.pend)
            potRetx = tbsFromMCSandRB_v14(H.mcs, rbFull) * 1e-3;
            pot(H.pend) = potRetx(H.pend);
        end

        genieAll = discretize(SINR_true(t, :), [env.CQI_thresholds(:).', Inf]);
        genieAll(isnan(genieAll)) = 1;
        genieAll = max(1, min(15, genieAll));
        cqi_err(t, :) = abs(cqiAll - genieAll);

        % Multi-user scheduling
        pot(~Q.has) = 0;
        dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);  % T3 (PLAN_v14_replication.md): EDF plumbing
        rb = schedule_users_v14(env.scheduler, t, N, R_emas, pot, env.total_RB, dlv);
        rb(~Q.has) = 0;                       % v14: no data, no transmission

        % Physics execution
        if isempty(U), uRow = []; else, uRow = U(t, :); end
        if isMultiOLLA
            [tpr, off_fast, off_slow, H, bl1, nEv] = ...
                MultiOLLA_v14(sent, SINR_true(t, :), rb, off_fast, off_slow, H, env, alpha_vec, uRow);
            off = 0.5 * off_fast + 0.5 * off_slow;
        elseif useOLLA
            [tpr, off, H, bl1, nEv] = txStep_v14(sent, SINR_true(t, :), rb, off, H, env, uRow, targVecForStep);
        else
            [tpr, ~, H, bl1, nEv] = txStep_v14(sent, SINR_true(t, :), rb, zeros(1, N), H, env, uRow);
        end

        [Q, ~] = trafficPost_v14(Q, tpr, t);
        schd = rb > 0;
        if any(schd), cn = 0.6 * cn + 0.4 * mean(double(nEv(schd))); else, cn = 0.97 * cn; end
        emaO = 0.98 * emaO + 0.02 * obs_SINR(t, :);
        tp(t, :) = tpr;
        bler(t, :) = bl1;
        sched = rb > 0;
        nk(sched)  = 0.7 * nk(sched) + 0.3 * double(nEv(sched));
        nk(~sched) = 0.95 * nk(~sched);
        R_emas = (1 - ema) * R_emas + ema * tpr;
        % P4 trackers: ack8 (EMA ack-fraction proxy), tsince, offtrend EMA.
        ack8(sched) = 0.8 * ack8(sched) + 0.2 * double(~nEv(sched));
        tsince(sched) = 0; tsince(~sched) = tsince(~sched) + 1;
        offEma = 0.9 * offEma + 0.1 * off;
        prevRef = ref;
    end

    info = struct('okU', Q.okU, 'resU', Q.resU);
    % Strip warm-up phase if applied
    if W > 0
        tp = tp(W+1:end, :);
        bler = bler(W+1:end, :);
        cqi_err = cqi_err(W+1:end, :);
        act = act(W+1:end, :);
    end
end
