function [tp, bler, cqi_err, act, info] = evalPolicy_presub(ptype, policy, SINR_true, obs_SINR, env, meta, U)
% v9: U (T x N uniforms, optional) = common random numbers for outcome draws;
%     'bandit' ptype = frozen UCB bandit offset (global or per delay class).
% evalPolicy_v17  Unified frozen-policy evaluation harness for all 7 comparators:
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
    % v17: 'olla_tuned' = OLLA with the calibrated target BLER;
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
            [Sb, ~, mb] = generateChannel_v17(T, env, meta);
            Ob = cqiFeedback_v17(Sb, env, delays);
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
    ageM = cqiAge_v17(T - W, N, Pq);
    if W > 0, ageM = [cqiAge_v17(W, N, Pq); ageM]; end
    emaO = obs_SINR(1, :);      % long-run EMA of each user's reports
    cn = 0;                     % cell-wide NACK EMA
    Q = trafficInit_v17(env, N, W + min(env.burn_in, T - W - 1));

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
            [dc, vc] = userClass_v17(delays(i), mean(speeds(:, i)));
            if isfield(env, 'class_tab') && ~isempty(env.class_tab)
                fco(i) = env.class_tab(dc, vc);
            else
                fco(i) = env.fixed_class_tab(dc, vc);
            end
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

    % P1 (README_v17.md): same-information target-mode comparators, both
    % frozen per-user for the whole trace (like fco/bo above).
    %   'olla_target_class' : per-class tuned target (same info as FixedPU)
    %   'bandit_target'     : contextual (delay-class) bandit over targets
    tgo = []; bto = [];
    if strcmpi(ptype, 'olla_target_class')
        tgo = zeros(1, N);
        for i = 1:N
            [dc, vc] = userClass_v17(delays(i), mean(speeds(:, i)));
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
    % B2 fallback fix (PLAN_v17.md): "Deep PPO v17" is dispatched through its
    % own ptype ('ppo_v17') because, even when env.action_mode = 'resid'
    % globally (A2C-resid is the primary scheme), DeepPPO_Shared_v17 was
    % ported WITHOUT resid support (offset-mode fallback -- see README_v17
    % B2) -- its logits are over numel(env.actions) offsets, not
    % numel(env.resid_actions) deltas. Decoding it through the shared
    % isResid branch below indexed resid_actions(aAll) with aAll up to
    % numel(env.actions) and crashed ("Index exceeds... must not exceed 3").
    isDeep = any(strcmpi(ptype, {'a2c', 'a2c_v17', 'ppo_v17', 'a2c_offset_v17'}));
    isEns  = strcmpi(ptype, 'a2c_ens');
    isResid = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'resid');
    isGRU = strcmpi(ptype, 'gru_v17');   % P4: recurrent policy, greedy action
    isMultiOLLA = strcmpi(ptype, 'multi_olla');

    off = zeros(1, N);
    off_fast = zeros(1, N);
    off_slow = zeros(1, N);
    H = harqInit_v17(N, env);
    useRTT = isfield(env, 'harq_rtt') && env.harq_rtt > 0;
    useDrain = isfield(env, 'drain') && env.drain && useRTT;
    useScheduledPF = isfield(env, 'pf_avg') && strcmpi(env.pf_avg, 'scheduled');
    R_emas = zeros(1, N);
    ema = 0.05;
    nk = zeros(1, N);
    prevRef = baseCQI_v17(obs_SINR(1, :) + off, env);
    % P4: trackers for the 'ack8'/'tsince'/'offtrend' feat_extra/ctx_cue
    % options (read causally -- end-of-previous-TTI values -- like nk/cn).
    ack8 = zeros(1, N); tsince = zeros(1, N); offEma = zeros(1, N);

    if upper(env.state_tier) == 'A', nBase = 5; elseif upper(env.state_tier) == 'O', nBase = 10; else, nBase = 13; end
    nSingle = nBase + numel(env.sched_list);
    nSingle = nSingle + nExtra_v17(env);
    nFeat = nSingle * L_seq;
    histS = zeros(nSingle, N, L_seq, 'single');
    sch_log = zeros(T, 5); n_sch = 0;
    b0 = min(env.burn_in, T - 1);


    b_i = zeros(1, N);
    if isResid
        base_kind = 'fixed';
        if isfield(env, 'base_rule_kind'), base_kind = lower(env.base_rule_kind); end
        if strcmpi(base_kind, 'fixed_class') || strcmpi(base_kind, 'fixedpu')
            for i = 1:N
                [dc, vc] = userClass_v17(delays(i), mean(speeds(:, i)));
                if isfield(env, 'class_tab') && ~isempty(env.class_tab)
                    b_i(i) = env.class_tab(dc, vc);
                else
                    b_i(i) = env.fixed_class_tab(dc, vc);
                end
            end
        else
            b_i(:) = env.fixed_offset;
        end
    end

    if isDeep
        if isstruct(policy)
            Wa = policy;
        else
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
        % P4: same hand-coded GRU step as DeepGRU_Shared_v17 (gate order
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
        if useRTT
            % Step 1: Feedback arrival at TTI t
            if isMultiOLLA
                dd_slow = env.multi_olla_slow;
                du_slow = dd_slow * env.olla_target / (1 - env.olla_target);
                dd_fast = env.multi_olla_fast;
                du_fast = dd_fast * env.olla_target / (1 - env.olla_target);
                [H, Q, off_fast, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v17(H, Q, off_fast, env, t, du_fast, dd_fast);
                for fbi = 1:numel(fbList)
                    ui = fbList(fbi).user;
                    if fbList(fbi).is_ack
                        if fbList(fbi).nret > 0, off_slow(ui) = off_slow(ui) + 0.5 * du_slow;
                        else, off_slow(ui) = off_slow(ui) + du_slow; end
                    else
                        if fbList(fbi).nret > env.harq_max_retx || fbList(fbi).nret == 0
                            off_slow(ui) = off_slow(ui) - dd_slow;
                        else
                            off_slow(ui) = off_slow(ui) - 0.5 * dd_slow;
                        end
                    end
                end
                if isfield(env, 'olla_off_lim') && ~isempty(env.olla_off_lim)
                    off_slow = max(-env.olla_off_lim, min(env.olla_off_lim, off_slow));
                    off_fast = max(-env.olla_off_lim, min(env.olla_off_lim, off_fast));
                end
                off = 0.5 * off_fast + 0.5 * off_slow;
            elseif useOLLA
                targ = env.olla_target;
                if targMode && any(strcmpi(ptype, {'a2c', 'a2c_v17', 'rand'})), targ = targVec;
                elseif strcmpi(ptype, 'olla_target_class'), targ = tgo;
                elseif strcmpi(ptype, 'bandit_target'), targ = bto;
                end
                if isscalar(targ), targ = targ * ones(1, N); end
                du = env.olla_step_down * targ ./ (1 - targ);
                dd = env.olla_step_down;
                [H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v17(H, Q, off, env, t, du, dd);
                if isfield(env, 'olla_off_lim') && ~isempty(env.olla_off_lim)
                    off = max(-env.olla_off_lim, min(env.olla_off_lim, off));
                end
            else
                [H, Q, ~, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v17(H, Q, off, env, t, 0, 0);
            end
        end

        [Q, H] = trafficPre_v17(Q, t, env, H);
        X = struct('age', ageM(t, :), 'dev', obs_SINR(t, :) - emaO, 'cn', cn, 'Q', Q, 't', t, ...
                    'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma, 'H', H);
        if isCtx, ctxOff = env.ctx_tab(ctxBin_v17(env, X)); end
        ref  = baseCQI_v17(obs_SINR(t, :) + off, env);
        dRef = max(minD, min(maxD, ref - prevRef));
        dS   = obs_SINR(t, :) - obs_SINR(max(t-1, 1), :);
        t0   = max(t-4, 1);
        slope4 = (obs_SINR(t, :) - obs_SINR(t0, :)) / max(t - t0, 1);

        if isDeep || isEns || any(strcmpi(ptype, {'gbt_res', 'gbt_full', 'rule', 'rule_cal'}))
            s_now = stateFeat_v17(env.state_tier, ref, dRef, obs_SINR(t, :), dS, off, ...
                                 slope4, nk, H, speeds(t, :), burstObsM(t, :), ...
                                 delays, R_emas, ctx, featExtra_v17(env, X));
            if isDeep || isEns
                histS(:, :, 2:L_seq) = histS(:, :, 1:L_seq-1);
                histS(:, :, 1) = s_now;
                S_temporal = reshape(permute(histS, [1, 3, 2]), nFeat, N);
            end
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
            % DeepGRU_Shared_v17's stateFeat_gru_v17).
            x_now = single(stateFeat_v17(env.state_tier, ref, zeros(1, N), obs_SINR(t, :), zeros(1, N), off, ...
                                 zeros(1, N), nk, H, speeds(t, :), burstObsM(t, :), ...
                                 delays, R_emas, ctx, featExtra_v17(env, X)));
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
        % userClass_v17 per user. 'rand' draws randi(numel(A), 1, N) in one
        % call, which consumes the global RNG stream in the same ascending-
        % user order as N sequential randi() calls, so CRN draws are
        % unchanged (see test_equivalence_v17.m).
        alpha_vec = 0.5 * ones(1, N);
        switch lower(ptype)
            case {'baseline', 'olla', 'warm_olla'}
                cqiAll = ref;
            case 'multi_olla'
                % Blended fast/slow multi-offset
                alpha_vec = 0.5 + 0.3 * (abs(slope4) > 1.0) + 0.2 * (nk > 0.4);
                cqi_eff_sinr = obs_SINR(t, :) + alpha_vec .* off_fast + (1 - alpha_vec) .* off_slow;
                cqiAll = baseCQI_v17(cqi_eff_sinr, env);
            case 'fixed'
                cqiAll = max(minC, min(maxC, ref + env.fixed_offset));
            case 'fixed_online'
                cqiAll = zeros(1, N);
                for i = 1:N
                    % Online estimated velocity and delay
                    est_v = mean(speeds(max(t-20,1):t, i));
                    est_d = delays(i); % Available from ACK feedback latency
                    [dc_on, vc_on] = userClass_v17(est_d, est_v);
                    if isfield(env, 'class_tab') && ~isempty(env.class_tab)
                        tab_val = env.class_tab(dc_on, vc_on);
                    else
                        tab_val = env.fixed_class_tab(dc_on, vc_on);
                    end
                    cqiAll(i) = max(minC, min(maxC, ref(i) + tab_val));
                end
            case {'fixed_class', 'fixed_oracle'}
                cqiAll = max(minC, min(maxC, ref + fco));
            case {'a2c', 'a2c_v17'}
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
            case 'ppo_v17'
                % B2 fallback: PPO always decodes in offset mode, regardless
                % of the global isResid flag (see note above isPPOoffset).
                [~, aAll] = max(logits, [], 1);
                act(t, :) = aAll;
                cqiAll = max(minC, min(maxC, ref + A(aAll)));
            case 'a2c_offset_v17'
                % C2 (README_v17.md §3.3): "Deep A2C v17 (offset)" -- the
                % legacy offset-action scheme trained alongside the primary
                % resid scheme -- always decodes in offset mode, regardless
                % of the global isResid flag (same reasoning as 'ppo_v17').
                [~, aAll] = max(logits, [], 1);
                act(t, :) = aAll;
                cqiAll = max(minC, min(maxC, ref + A(aAll)));
            case 'a2c_ens'
                [~, aAll] = max(P_ens, [], 1);
                act(t, :) = aAll;
                if isResid
                    delta = env.resid_actions(aAll);
                    cqiAll = max(minC, min(maxC, ref + b_i + delta));
                else
                    cqiAll = max(minC, min(maxC, ref + A(aAll)));
                end
            case 'gru_v17'
                % P4: greedy offset action from the recurrent policy (no
                % target-mode semi-MDP -- see README_v17.md P4 scope note).
                [~, aAll] = max(gruLogits, [], 1);
                act(t, :) = aAll;
                cqiAll = max(minC, min(maxC, ref + A(aAll)));
            case 'bandit'
                cqiAll = max(minC, min(maxC, ref + bo));
            case 'ctxtab'
                cqiAll = max(minC, min(maxC, ref + ctxOff));
            case 'ctxj'
                ctxjOff = zeros(1, N);
                for ii = 1:N
                    sl_ii = Q.dl(ii) - t + 1;
                    if sl_ii <= 2, b_ii = 1; elseif sl_ii <= 5, b_ii = 2; else, b_ii = 3; end
                    if delays(ii) <= 4, d_ii = 1; else, d_ii = 2; end
                    sp_ii = mean(speeds(:, ii));
                    if sp_ii < 10, v_ii = 1; elseif sp_ii <= 20, v_ii = 2; else, v_ii = 3; end
                    if sum(H.proc_busy(ii, :)) == 0, u_ii = 1; else, u_ii = 2; end
                    ctxjOff(ii) = env.ctxj_tab(b_ii, d_ii, v_ii, u_ii);
                end
                cqiAll = max(minC, min(maxC, ref + ctxjOff));
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
                % Stage 0 (PLAN_v17.md S0.1): Perfect-CSI bound.
                % User i gets largest CQI q in 1:15 such that estimateBLER_v17(SINR_true(t,i), q-1) <= env.genie_bler
                cqiAll = ones(1, N);
                for i = 1:N
                    gamma_i = SINR_true(t, i);
                    blers_i = estimateBLER_v17(gamma_i * ones(1, 15), 0:14);
                    valid_q = find(blers_i <= env.genie_bler);
                    if ~isempty(valid_q)
                        cqiAll(i) = max(valid_q);
                    else
                        cqiAll(i) = 1;
                    end
                end
                cqiAll = max(minC, min(maxC, cqiAll));
            case {'gbt_res', 'gbt_full'}
                for ii = 1:N
                    obs_ii = double(s_now(:, ii)');
                    obs19 = zeros(1, 19);
                    obs19(1:min(19, numel(obs_ii))) = obs_ii(1:min(19, numel(obs_ii)));
                    chosen_mcs = gbt_predict_best_mcs(policy, obs19, ref(ii), minC, maxC, lower(ptype));
                    cqiAll(ii) = chosen_mcs + 1;
                end
            case 'rule'
                for ii = 1:N
                    obs_ii = double(s_now(:, ii)');
                    c_busy = (obs_ii(14) >= (1.0/8.0 - 1e-9));
                    c_slack = (round(obs_ii(12)) == 1 && obs_ii(11) <= 0.6);
                    c_drop = (5.0 * obs_ii(6) <= -1.0);
                    delta = ternary(c_busy || c_slack || c_drop, 1, 0);
                    tot_off = max(-4, min(2, -2 + delta));
                    cqiAll(ii) = max(minC, min(maxC, ref(ii) + tot_off));
                end
            case 'rule_cal'
                th = policy;
                for ii = 1:N
                    obs_ii = double(s_now(:, ii)');
                    c_busy = false;
                    if th.B > 0, c_busy = (obs_ii(14) >= (th.B / 8.0 - 1e-9)); end
                    c_slack = false;
                    if th.S > 0, c_slack = (round(obs_ii(12)) == 1 && obs_ii(11) <= th.S); end
                    c_drop = false;
                    if th.theta > 0, c_drop = (5.0 * obs_ii(6) <= -th.theta); end
                    delta = ternary(c_busy || c_slack || c_drop, 1, 0);
                    tot_off = max(-4, min(2, -2 + delta));
                    cqiAll(ii) = max(minC, min(maxC, ref(ii) + tot_off));
                end
            otherwise
                error('evalPolicy_v17: unknown ptype "%s"', ptype);
        end
        sent = cqiAll;

        % P1: the per-user target fed into txStep_v17's OLLA step (empty =
        % env.olla_target for everyone, i.e. unchanged v10/v17-P0 physics).
        targVecForStep = [];
        if strcmpi(ptype, 'olla_target_class'), targVecForStep = tgo;
        elseif strcmpi(ptype, 'bandit_target'),  targVecForStep = bto;
        elseif targMode && any(strcmpi(ptype, {'a2c', 'a2c_v17', 'rand'})), targVecForStep = targVec;
        end

        genieAll = discretize(SINR_true(t, :), [env.CQI_thresholds(:).', Inf]);
        genieAll(isnan(genieAll)) = 1;
        genieAll = max(1, min(15, genieAll));
        cqi_err(t, :) = abs(cqiAll - genieAll);

        if useRTT
            rbFull = env.total_RB * ones(1, N);
            if isfield(env, 'sched_on_ref') && env.sched_on_ref
                potNew = tbsFromMCSandRB_v17(max(env.min_CQI, min(env.max_CQI, ref)) - 1, rbFull) * 1e-3;
            else
                potNew = tbsFromMCSandRB_v17(sent - 1, rbFull) * 1e-3;
            end
            pot = zeros(1, N);
            retxReady = any(H.proc_isRetx, 2)';
            hasFree = any(~H.proc_busy, 2)' & (Q.tx_rem > 0);
            elig = Q.has & (retxReady | hasFree);
            for i = 1:N
                if ~elig(i), continue; end
                if retxReady(i)
                    p_retx = find(H.proc_isRetx(i, :), 1);
                    pot(i) = tbsFromMCSandRB_v17(H.proc_mcs(i, p_retx), env.total_RB) * 1e-3;
                else
                    pot(i) = potNew(i);
                end
            end
            dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);
            rb = schedule_users_v17(env.scheduler, t, N, R_emas, pot, env.total_RB, dlv);
            rb(~elig) = 0;

            % Scheduled transmission rate recorded BEFORE transmission physics clear state
            sch_u = find(rb > 0);
            r_sched = zeros(1, N);
            if ~isempty(sch_u)
                if retxReady(sch_u)
                    p_retx = find(H.proc_isRetx(sch_u, :), 1);
                    r_sched(sch_u) = H.proc_tbs(sch_u, p_retx) * 1e-3;
                else
                    tx_mcs = max(0, min(14, sent(sch_u) - 1));
                    r_sched(sch_u) = tbsFromMCSandRB_v17(tx_mcs, rb(sch_u)) * 1e-3;
                end
            end
            if ~isempty(sch_u) && t > b0
                for u = sch_u(:)'
                    n_sch = n_sch + 1;
                    if n_sch > size(sch_log, 1)
                        sch_log = [sch_log; zeros(T, 5)];
                    end
                    sl_u = Q.dl(u) - t + 1;
                    is_retx_u = double(retxReady(u));
                    n_busy_u = sum(H.proc_busy(u, :));
                    act_u = act(t, u);
                    sch_log(n_sch, :) = [u, act_u, sl_u, is_retx_u, n_busy_u];
                end
            end

            if isempty(U), uRow = []; else, uRow = U(t, :); end
            [H, Q, bl1, isRetxTx] = harqTransmit_v17(sent, SINR_true(t, :), rb, H, Q, env, t, uRow);

            if useDrain
                t_tx = t - env.harq_rtt;
                if t_tx >= 1 && t_tx <= T
                    tp(t_tx, :) = tp_ack;
                end
            else
                tp(t, :) = tp_ack;
            end
            bler(t, :) = bl1;
            fbUsers = ackEv | nackEv;
            if any(fbUsers)
                cn = 0.6 * cn + 0.4 * mean(double(nackEv(fbUsers)));
            else
                cn = 0.97 * cn;
            end
            nk(fbUsers)  = 0.7 * nk(fbUsers) + 0.3 * double(nackEv(fbUsers));
            nk(~fbUsers) = 0.95 * nk(~fbUsers);
            if useScheduledPF
                R_emas = (1 - ema) * R_emas + ema * r_sched;
            else
                R_emas = (1 - ema) * R_emas + ema * tp_ack;
            end
            ack8(fbUsers) = 0.8 * ack8(fbUsers) + 0.2 * double(ackEv(fbUsers));
            tsince(rb > 0) = 0;
            tsince(rb == 0) = tsince(rb == 0) + 1;
            offEma = 0.9 * offEma + 0.1 * off;
            emaO = 0.98 * emaO + 0.02 * obs_SINR(t, :);
            prevRef = ref;
        else
            rbFull = env.total_RB * ones(1, N);
            if isfield(env, 'sched_on_ref') && env.sched_on_ref
                % FILL FIX option: scheduler ranks users by the OLLA reference rate,
                % not by the link-adaptation decision (removes scheduler gaming)
                potNew = tbsFromMCSandRB_v17(max(env.min_CQI, min(env.max_CQI, ref)) - 1, rbFull) * 1e-3;
            else
                potNew = tbsFromMCSandRB_v17(sent - 1, rbFull) * 1e-3;
            end
            pot = potNew;
            if env.harq_on && any(H.pend)
                potRetx = tbsFromMCSandRB_v17(H.mcs, rbFull) * 1e-3;
                pot(H.pend) = potRetx(H.pend);
            end

            % Multi-user scheduling
            pot(~Q.has) = 0;
            dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);  % T3 (PLAN_v17_replication.md): EDF plumbing
            rb = schedule_users_v17(env.scheduler, t, N, R_emas, pot, env.total_RB, dlv);
            rb(~Q.has) = 0;                       % v17: no data, no transmission

            % Scheduled transmission rate recorded BEFORE transmission physics clear state
            sch_u = find(rb > 0);
            r_sched = zeros(1, N);
            if ~isempty(sch_u)
                if env.harq_on && any(H.pend) && H.pend(sch_u)
                    r_sched(sch_u) = H.tbs(sch_u) * 1e-3;
                else
                    tx_mcs = max(0, min(14, sent(sch_u) - 1));
                    r_sched(sch_u) = tbsFromMCSandRB_v17(tx_mcs, rb(sch_u)) * 1e-3;
                end
            end
            if ~isempty(sch_u) && t > b0
                for u = sch_u(:)'
                    n_sch = n_sch + 1;
                    if n_sch > size(sch_log, 1)
                        sch_log = [sch_log; zeros(T, 5)];
                    end
                    sl_u = Q.dl(u) - t + 1;
                    is_retx_u = double(env.harq_on && H.pend(u));
                    n_busy_u = 0;
                    act_u = act(t, u);
                    sch_log(n_sch, :) = [u, act_u, sl_u, is_retx_u, n_busy_u];
                end
            end

            % Physics execution
            if isempty(U), uRow = []; else, uRow = U(t, :); end
            if isMultiOLLA
                [tpr, off_fast, off_slow, H, bl1, nEv] = ...
                    MultiOLLA_v17(sent, SINR_true(t, :), rb, off_fast, off_slow, H, env, alpha_vec, uRow);
                off = 0.5 * off_fast + 0.5 * off_slow;
            elseif useOLLA
                [tpr, off, H, bl1, nEv] = txStep_v17(sent, SINR_true(t, :), rb, off, H, env, uRow, targVecForStep);
            else
                [tpr, ~, H, bl1, nEv] = txStep_v17(sent, SINR_true(t, :), rb, zeros(1, N), H, env, uRow);
            end

            if isfield(env, 'useful_bits') && env.useful_bits && Q.on && isfield(Q, 'rem')
                tpr_useful = tpr;
                for ii = find(rb > 0)
                    if Q.has(ii)
                        tpr_useful(ii) = min(tpr(ii), max(0, Q.rem(ii)) * 1e-3);
                    else
                        tpr_useful(ii) = 0;
                    end
                end
                [Q, ~] = trafficPost_v17(Q, tpr_useful, t);
                tp(t, :) = tpr_useful;
            else
                [Q, ~] = trafficPost_v17(Q, tpr, t);
                tp(t, :) = tpr;
            end
            schd = rb > 0;
            if any(schd), cn = 0.6 * cn + 0.4 * mean(double(nEv(schd))); else, cn = 0.97 * cn; end
            emaO = 0.98 * emaO + 0.02 * obs_SINR(t, :);
            bler(t, :) = bl1;
            sched = rb > 0;
            nk(sched)  = 0.7 * nk(sched) + 0.3 * double(nEv(sched));
            nk(~sched) = 0.95 * nk(~sched);
            if useScheduledPF
                R_emas = (1 - ema) * R_emas + ema * r_sched;
            else
                R_emas = (1 - ema) * R_emas + ema * tpr;
            end
            % P4 trackers: ack8 (EMA ack-fraction proxy), tsince, offtrend EMA.
            ack8(sched) = 0.8 * ack8(sched) + 0.2 * double(~nEv(sched));
            tsince(sched) = 0; tsince(~sched) = tsince(~sched) + 1;
            offEma = 0.9 * offEma + 0.1 * off;
            prevRef = ref;
        end
    end

    if useDrain
        for t = T + 1 : T + env.harq_rtt
            if isMultiOLLA
                dd_slow = env.multi_olla_slow;
                du_slow = dd_slow * env.olla_target / (1 - env.olla_target);
                dd_fast = env.multi_olla_fast;
                du_fast = dd_fast * env.olla_target / (1 - env.olla_target);
                [H, Q, off_fast, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v17(H, Q, off_fast, env, t, du_fast, dd_fast);
                for fbi = 1:numel(fbList)
                    ui = fbList(fbi).user;
                    if fbList(fbi).is_ack
                        if fbList(fbi).nret > 0, off_slow(ui) = off_slow(ui) + 0.5 * du_slow;
                        else, off_slow(ui) = off_slow(ui) + du_slow; end
                    else
                        if fbList(fbi).nret > env.harq_max_retx || fbList(fbi).nret == 0
                            off_slow(ui) = off_slow(ui) - dd_slow;
                        else
                            off_slow(ui) = off_slow(ui) - 0.5 * dd_slow;
                        end
                    end
                end
                off = 0.5 * off_fast + 0.5 * off_slow;
            elseif useOLLA
                targ = env.olla_target;
                if targMode && any(strcmpi(ptype, {'a2c', 'a2c_v17', 'rand'})), targ = targVec;
                elseif strcmpi(ptype, 'olla_target_class'), targ = tgo;
                elseif strcmpi(ptype, 'bandit_target'), targ = bto;
                end
                if isscalar(targ), targ = targ * ones(1, N); end
                du = env.olla_step_down * targ ./ (1 - targ);
                dd = env.olla_step_down;
                [H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v17(H, Q, off, env, t, du, dd);
            else
                [H, Q, ~, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v17(H, Q, off, env, t, 0, 0);
            end
            t_tx = t - env.harq_rtt;
            if t_tx >= 1 && t_tx <= T
                tp(t_tx, :) = tp_ack;
            end
        end
    end

    info = struct('okU', Q.okU, 'resU', Q.resU, 'sch_log', sch_log(1:n_sch, :));
    % Strip warm-up phase if applied
    if W > 0
        tp = tp(W+1:end, :);
        bler = bler(W+1:end, :);
        cqi_err = cqi_err(W+1:end, :);
        act = act(W+1:end, :);
    end
end


% =========================================================================
function chosen_mcs = gbt_predict_best_mcs(gbt_models, obs19, ref_u, minC, maxC, mode)
    cand_offsets = -4:2;
    if strcmp(mode, 'gbt_res')
        eval_indices = [2, 3, 4]; % candidate offsets -3, -2, -1 (base -2 +/- 1)
    else
        eval_indices = 1:7;       % all candidate offsets -4..+2
    end

    unique_mcs = [];
    mcs_q_sum = [];
    mcs_count = [];

    for idx = eval_indices
        off = cand_offsets(idx);
        cq = max(minC, min(maxC, ref_u + off));
        mc = max(0, min(14, cq - 1));

        q_pred = model_predict(gbt_models{idx}, obs19);

        pos = find(unique_mcs == mc, 1);
        if isempty(pos)
            unique_mcs = [unique_mcs, mc];
            mcs_q_sum  = [mcs_q_sum, q_pred];
            mcs_count  = [mcs_count, 1];
        else
            mcs_q_sum(pos) = mcs_q_sum(pos) + q_pred;
            mcs_count(pos) = mcs_count(pos) + 1;
        end
    end

    mean_q = mcs_q_sum ./ mcs_count;

    [sorted_mcs, sort_order] = sort(unique_mcs, 'ascend');
    sorted_q = mean_q(sort_order);

    max_val = -Inf;
    chosen_mcs = sorted_mcs(1);
    for k = 1:numel(sorted_mcs)
        if sorted_q(k) > max_val + 1e-12
            max_val = sorted_q(k);
            chosen_mcs = sorted_mcs(k);
        end
    end
end

% =========================================================================
function q = model_predict(model, x)
    q = model.baseline;
    trees = model.trees;
    n_t = numel(trees);
    for k = 1:n_t
        t = trees{k};
        idx = 1;
        while ~t.is_leaf(idx)
            if x(t.feat(idx)) <= t.th(idx)
                idx = t.left(idx);
            else
                idx = t.right(idx);
            end
        end
        q = q + t.val(idx);
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
