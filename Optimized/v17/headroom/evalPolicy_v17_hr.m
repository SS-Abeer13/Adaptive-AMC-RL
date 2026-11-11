function [tp, bler, cqi_err, act, info] = evalPolicy_v17_hr(ptype, policy, SINR_true, obs_SINR, env, meta, U)
% evalPolicy_v17_hr  INSTRUMENTED COPY of evalPolicy_v17_g6.m for Plan 4 learnable headroom.
%
% Logs, for every scheduled NEW transmission:
%   trace_id, t, u,
%   policy's 19 observation inputs (s_now from stateFeat_v17),
%   table-cell indices (slack bin 1..3, delay class 1..2, speed class 1..3, busy-HARQ bin 1..2),
%   base-rule offset, action taken (sent - ref),
%   and for candidate offsets a in -4:+2:
%     candidate MCS and candidate p_success(a) = 1 - estimateBLER_v17(SINR_true(t,u), mcs(a)).
%
% Strictly identical simulation physics to evalPolicy_v17_g6 / evalPolicy_v17:
% No RNG draws, no state changes in instrumentation.
    [T, N] = size(SINR_true);
    if nargin < 7, U = []; end
    if ~(isfield(env, 'crn') && env.crn), U = []; end
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
            rng(100000 + 7*W + 1000*meta.trace_id);   % unique per trace
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
            dc = 1; if delays(i) > 4, dc = 2; end
            bo(i) = env.bandit_tab(dc);
        end
    end

    % Target-mode comparators
    targMode = isfield(env, 'action_target_mode') && env.action_target_mode;
    Tset = []; curAIdx = ones(1, N); targVec = env.olla_target * ones(1, N);
    if targMode
        Tset = env.target_grid;
        [~, defIdx] = min(abs(Tset - env.olla_target));
        curAIdx = defIdx * ones(1, N);
    end
    tgo = [];
    if strcmpi(ptype, 'olla_target_class')
        tgo = zeros(1, N);
        for i = 1:N
            [dc, vc] = userClass_v17(delays(i), mean(speeds(:, i)));
            tgo(i) = env.olla_target_class_tab(dc, vc);
        end
    end
    bto = [];
    if strcmpi(ptype, 'bandit_target')
        bto = zeros(1, N);
        for i = 1:N
            dc = 1; if delays(i) > 4, dc = 2; end
            bto(i) = env.bandit_target_tab(dc);
        end
    end

    isDeep = any(strcmpi(ptype, {'a2c', 'a2c_v17', 'ppo_v17', 'a2c_offset_v17'}));
    isEns  = strcmpi(ptype, 'a2c_ens');
    isResid = isfield(env, 'action_mode') && strcmpi(env.action_mode, 'resid');
    isGRU = strcmpi(ptype, 'gru_v17');
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
    ack8 = zeros(1, N); tsince = zeros(1, N); offEma = zeros(1, N);

    if upper(env.state_tier) == 'A', nBase = 5; elseif upper(env.state_tier) == 'O', nBase = 10; else, nBase = 13; end
    nSingle = nBase + numel(env.sched_list);
    nSingle = nSingle + nExtra_v17(env);
    nFeat = nSingle * L_seq;
    histS = zeros(nSingle, N, L_seq, 'single');
    sch_log = zeros(T, 5); n_sch = 0;
    b0 = min(env.burn_in, T - 1);

    % Base-rule offset vector b_i
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
    elseif strcmpi(ptype, 'fixed')
        b_i(:) = env.fixed_offset;
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
        gruNet = policy;
        hidden = zeros(gruNet.hiddenSize, N, 'single');
    end

    alpha_vec = [];
    if isMultiOLLA
        alpha_vec = zeros(1, N);
        for i = 1:N
            [dc, ~] = userClass_v17(delays(i), mean(speeds(:, i)));
            alpha_vec(i) = env.multi_olla_alpha(dc);
        end
    end

    % Scheduler one-hot context vector
    ctx = zeros(numel(env.sched_list), N, 'single');
    sIdx = find(strcmpi(env.sched_list, env.scheduler), 1);
    if ~isempty(sIdx), ctx(sIdx, :) = 1; end

    % Headroom logger initialization
    % Logged observation features correspondence:
    %   obs_1..obs_10:  base and temporal features (ref, dRef, obs_SINR, dS, off, slope4, nk, pend, nret, r_norm)
    %   obs_11:         normalized slack_remaining = min(slack, Dm) / Dm
    %   obs_12:         has_packet flag
    %   obs_13:         normalized bits_remaining = max(0, Q.rem) / pkt_bits
    %   obs_14..obs_16: HARQ extended cues (busy_frac, retx_ready, flight_frac)
    %   obs_17..obs_19: scheduler candidate cues
    % Columns 29..31 log raw unnormalized n_rb, bits_remaining, and slack_remaining explicitly.
    COLS = { ...
        'trace_id', 't', 'u', ...
        'obs_1', 'obs_2', 'obs_3', 'obs_4', 'obs_5', ...
        'obs_6', 'obs_7', 'obs_8', 'obs_9', 'obs_10', ...
        'obs_11', 'obs_12', 'obs_13', 'obs_14', 'obs_15', ...
        'obs_16', 'obs_17', 'obs_18', 'obs_19', ...
        'slack_bin', 'delay_class', 'speed_class', 'busy_harq_bin', ...
        'base_rule_offset', 'action_taken', ...
        'n_rb', 'bits_remaining', 'slack_remaining', ...
        'mcs_m4', 'mcs_m3', 'mcs_m2', 'mcs_m1', 'mcs_0', 'mcs_p1', 'mcs_p2', ...
        'tbs_m4', 'tbs_m3', 'tbs_m2', 'tbs_m1', 'tbs_0', 'tbs_p1', 'tbs_p2', ...
        'ubits_m4', 'ubits_m3', 'ubits_m2', 'ubits_m1', 'ubits_0', 'ubits_p1', 'ubits_p2', ...
        'psucc_m4', 'psucc_m3', 'psucc_m2', 'psucc_m1', 'psucc_0', 'psucc_p1', 'psucc_p2', ...
        'tbs_act', 'ubits_act', 'bler1', 'p_success_actual', 'sent_cqi', 'ref_cqi' ...
    };
    nCols = numel(COLS);
    hr_log = zeros(max(T * N, 100), nCols);
    n_hr = 0;
    tr_id = 0;
    if isfield(meta, 'trace_id'), tr_id = meta.trace_id; end

    for t = 1:T
        if useRTT
            du_slow = 0; dd_slow = 0; du_fast = 0; dd_fast = 0;
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

        % Observation features (19 features) computed for instrumentation
        feat_extra = featExtra_v17(env, X);
        s_step = stateFeat_v17(env.state_tier, ref, dRef, obs_SINR(t, :), dS, off, ...
                               slope4, nk, H, speeds(t, :), burstObsM(t, :), ...
                               delays, R_emas, ctx, feat_extra);

        if isDeep || isEns
            s_now = s_step;
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
            x_now = single(stateFeat_v17(env.state_tier, ref, zeros(1, N), obs_SINR(t, :), zeros(1, N), off, ...
                                        slope4, nk, H, speeds(t, :), burstObsM(t, :), ...
                                        delays, R_emas, ctx, featExtra_v17(env, X)));
            [gruLogits, hidden] = forwardGRU_v17(gruNet, x_now, hidden);
        end

        switch lower(ptype)
            case 'baseline'
                cqiAll = ref;
            case {'olla', 'warm_olla', 'multi_olla'}
                cqiAll = ref;
            case 'fixed'
                cqiAll = max(minC, min(maxC, ref + env.fixed_offset));
            case 'fixed_online'
                cqiAll = zeros(1, N);
                for i = 1:N
                    est_v = mean(speeds(max(t-20,1):t, i));
                    est_d = delays(i);
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
                if isResid
                    [~, aResid] = max(logits, [], 1);
                    act(t, :) = aResid;
                    cqiAll = max(minC, min(maxC, ref + b_i + env.resid_actions(aResid)));
                elseif targMode
                    if mod(t - 1, env.target_epoch) == 0
                        [~, curAIdx] = max(logits, [], 1);
                    end
                    act(t, :) = curAIdx;
                    targVec = Tset(curAIdx);
                    cqiAll = ref;
                else
                    [~, aAll] = max(logits, [], 1);
                    act(t, :) = aAll;
                    cqiAll = max(minC, min(maxC, ref + A(aAll)));
                end
            case 'a2c_offset_v17'
                [~, aAll] = max(logits, [], 1);
                act(t, :) = aAll;
                cqiAll = max(minC, min(maxC, ref + A(aAll)));
            case 'ppo_v17'
                [~, aAll] = max(logits, [], 1);
                act(t, :) = aAll;
                cqiAll = max(minC, min(maxC, ref + A(aAll)));
            case 'a2c_ens'
                if isResid
                    [~, aResid] = max(P_ens, [], 1);
                    act(t, :) = aResid;
                    cqiAll = max(minC, min(maxC, ref + b_i + env.resid_actions(aResid)));
                else
                    [~, aAll] = max(P_ens, [], 1);
                    act(t, :) = aAll;
                    cqiAll = max(minC, min(maxC, ref + A(aAll)));
                end
            case 'gru_v17'
                [~, aAll] = max(gruLogits, [], 1);
                act(t, :) = aAll;
                cqiAll = max(minC, min(maxC, ref + A(aAll)));
            case 'bandit'
                cqiAll = max(minC, min(maxC, ref + bo));
            case 'ctxtab'
                b_i = ctxOff;
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
                b_i = ctxjOff;
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
            otherwise
                error('evalPolicy_v17_hr: unknown ptype "%s"', ptype);
        end
        sent = cqiAll;

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

            % Record decision-time attributes for scheduled NEW transmissions
            new_tx_list = [];
            if ~isempty(sch_u) && t > b0
                for u = sch_u(:)'
                    if ~retxReady(u)
                        sl_u = Q.dl(u) - t + 1;
                        if sl_u <= 2, b_u = 1; elseif sl_u <= 5, b_u = 2; else, b_u = 3; end
                        if delays(u) <= 4, d_u = 1; else, d_u = 2; end
                        sp_u = mean(speeds(:, u));
                        if sp_u < 10, v_u = 1; elseif sp_u <= 20, v_u = 2; else, v_u = 3; end
                        if sum(H.proc_busy(u, :)) == 0, u_u = 1; else, u_u = 2; end
                        b_off = b_i(u);
                        act_taken = sent(u) - ref(u);
                        n_rb_u = rb(u);
                        if Q.on && isfield(Q, 'tx_rem')
                            bits_rem_u = max(0, Q.tx_rem(u));
                            slack_rem_u = sl_u;
                        else
                            bits_rem_u = Inf;
                            slack_rem_u = Inf;
                        end
                        new_tx_list = [new_tx_list; u, b_u, d_u, v_u, u_u, b_off, act_taken, n_rb_u, bits_rem_u, slack_rem_u]; %#ok<AGROW>
                    end
                end
            end

            if isempty(U), uRow = []; else, uRow = U(t, :); end
            [H, Q, bl1, isRetxTx] = harqTransmit_v17(sent, SINR_true(t, :), rb, H, Q, env, t, uRow);

            % Headroom instrumentation logging for scheduled NEW transmissions
            if ~isempty(new_tx_list)
                cand_offsets = -4:2;
                for idx = 1:size(new_tx_list, 1)
                    u           = new_tx_list(idx, 1);
                    b_u         = new_tx_list(idx, 2);
                    d_u         = new_tx_list(idx, 3);
                    v_u         = new_tx_list(idx, 4);
                    u_u         = new_tx_list(idx, 5);
                    b_off       = new_tx_list(idx, 6);
                    act_taken   = new_tx_list(idx, 7);
                    n_rb_u      = new_tx_list(idx, 8);
                    bits_rem_u  = new_tx_list(idx, 9);
                    slack_rem_u = new_tx_list(idx, 10);
                    obs_raw     = double(s_step(:, u)');
                    obs_u       = zeros(1, 19);
                    obs_u(1:min(19, numel(obs_raw))) = obs_raw(1:min(19, numel(obs_raw)));

                    % Effective SINR for 1st tx is SINR_true(t, u) with 0 combining
                    sinr_eff = SINR_true(t, u);
                    c_mcs   = zeros(1, 7);
                    c_tbs   = zeros(1, 7);
                    c_ubits = zeros(1, 7);
                    c_psucc = zeros(1, 7);
                    for ka = 1:7
                        cq = max(minC, min(maxC, ref(u) + cand_offsets(ka)));
                        mc = max(0, min(14, cq - 1));
                        tb = tbsFromMCSandRB_v17(mc, n_rb_u);
                        if isfinite(bits_rem_u)
                            ub = min(tb, bits_rem_u);
                        else
                            ub = tb;
                        end
                        c_mcs(ka)   = mc;
                        c_tbs(ka)   = tb;
                        c_ubits(ka) = ub;
                        c_psucc(ka) = 1 - estimateBLER_v17(sinr_eff, mc);
                    end

                    tx_mcs = max(0, min(14, sent(u) - 1));
                    tbs_act = tbsFromMCSandRB_v17(tx_mcs, n_rb_u);
                    if isfinite(bits_rem_u)
                        ubits_act = min(tbs_act, bits_rem_u);
                    else
                        ubits_act = tbs_act;
                    end

                    bl_act = bl1(u);
                    psucc_act = 1 - bl_act;

                    n_hr = n_hr + 1;
                    if n_hr > size(hr_log, 1)
                        hr_log = [hr_log; zeros(size(hr_log, 1), nCols)];
                    end
                    hr_log(n_hr, :) = [tr_id, t, u, obs_u, b_u, d_u, v_u, u_u, ...
                                       b_off, act_taken, n_rb_u, bits_rem_u, slack_rem_u, ...
                                       c_mcs, c_tbs, c_ubits, c_psucc, ...
                                       tbs_act, ubits_act, bl_act, psucc_act, sent(u), ref(u)];
                end
            end

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
            dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);
            rb = schedule_users_v17(env.scheduler, t, N, R_emas, pot, env.total_RB, dlv);
            rb(~Q.has) = 0;

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

            new_tx_list = [];
            if ~isempty(sch_u) && t > b0
                for u = sch_u(:)'
                    if ~(env.harq_on && H.pend(u))
                        sl_u = Q.dl(u) - t + 1;
                        if sl_u <= 2, b_u = 1; elseif sl_u <= 5, b_u = 2; else, b_u = 3; end
                        if delays(u) <= 4, d_u = 1; else, d_u = 2; end
                        sp_u = mean(speeds(:, u));
                        if sp_u < 10, v_u = 1; elseif sp_u <= 20, v_u = 2; else, v_u = 3; end
                        u_u = 1;
                        b_off = b_i(u);
                        act_taken = sent(u) - ref(u);
                        n_rb_u = rb(u);
                        if isfield(env, 'useful_bits') && env.useful_bits && Q.on && isfield(Q, 'rem')
                            bits_rem_u = max(0, Q.rem(u));
                            slack_rem_u = sl_u;
                        else
                            bits_rem_u = Inf;
                            slack_rem_u = Inf;
                        end
                        new_tx_list = [new_tx_list; u, b_u, d_u, v_u, u_u, b_off, act_taken, n_rb_u, bits_rem_u, slack_rem_u]; %#ok<AGROW>
                    end
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

            if ~isempty(new_tx_list)
                cand_offsets = -4:2;
                for idx = 1:size(new_tx_list, 1)
                    u           = new_tx_list(idx, 1);
                    b_u         = new_tx_list(idx, 2);
                    d_u         = new_tx_list(idx, 3);
                    v_u         = new_tx_list(idx, 4);
                    u_u         = new_tx_list(idx, 5);
                    b_off       = new_tx_list(idx, 6);
                    act_taken   = new_tx_list(idx, 7);
                    n_rb_u      = new_tx_list(idx, 8);
                    bits_rem_u  = new_tx_list(idx, 9);
                    slack_rem_u = new_tx_list(idx, 10);
                    obs_raw     = double(s_step(:, u)');
                    obs_u       = zeros(1, 19);
                    obs_u(1:min(19, numel(obs_raw))) = obs_raw(1:min(19, numel(obs_raw)));

                    sinr_eff = SINR_true(t, u);
                    c_mcs   = zeros(1, 7);
                    c_tbs   = zeros(1, 7);
                    c_ubits = zeros(1, 7);
                    c_psucc = zeros(1, 7);
                    for ka = 1:7
                        cq = max(minC, min(maxC, ref(u) + cand_offsets(ka)));
                        mc = max(0, min(14, cq - 1));
                        tb = tbsFromMCSandRB_v17(mc, n_rb_u);
                        if isfinite(bits_rem_u)
                            ub = min(tb, bits_rem_u);
                        else
                            ub = tb;
                        end
                        c_mcs(ka)   = mc;
                        c_tbs(ka)   = tb;
                        c_ubits(ka) = ub;
                        c_psucc(ka) = 1 - estimateBLER_v17(sinr_eff, mc);
                    end

                    tx_mcs = max(0, min(14, sent(u) - 1));
                    tbs_act = tbsFromMCSandRB_v17(tx_mcs, n_rb_u);
                    if isfinite(bits_rem_u)
                        ubits_act = min(tbs_act, bits_rem_u);
                    else
                        ubits_act = tbs_act;
                    end

                    bl_act = bl1(u);
                    psucc_act = 1 - bl_act;

                    n_hr = n_hr + 1;
                    if n_hr > size(hr_log, 1)
                        hr_log = [hr_log; zeros(size(hr_log, 1), nCols)];
                    end
                    hr_log(n_hr, :) = [tr_id, t, u, obs_u, b_u, d_u, v_u, u_u, ...
                                       b_off, act_taken, n_rb_u, bits_rem_u, slack_rem_u, ...
                                       c_mcs, c_tbs, c_ubits, c_psucc, ...
                                       tbs_act, ubits_act, bl_act, psucc_act, sent(u), ref(u)];
                end
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

    info = struct('okU', Q.okU, 'resU', Q.resU, 'sch_log', sch_log(1:n_sch, :), ...
                  'hr_log', hr_log(1:n_hr, :), 'hr_cols', {COLS});
    % Strip warm-up phase if applied
    if W > 0
        tp = tp(W+1:end, :);
        bler = bler(W+1:end, :);
        cqi_err = cqi_err(W+1:end, :);
        act = act(W+1:end, :);
    end
end
