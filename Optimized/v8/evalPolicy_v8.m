function [tp, bler, cqi_err, act] = evalPolicy_v8(ptype, policy, SINR_true, obs_SINR, env, meta)
% evalPolicy_v8  Unified frozen-policy evaluation harness for all 7 comparators:
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
    A = env.actions;
    no_op = find(A == 0);
    maxC = env.max_CQI; minC = env.min_CQI;
    maxD = env.max_delta; minD = env.min_delta;
    L_seq = 3;

    useOLLA = ~strcmpi(ptype, 'baseline');
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
        rng(100000 + 7*W + 13*N + 101*round(mean(delays)));
        Sw = []; Ow = []; Bw = []; Vw = [];
        while size(Sw, 1) < W
            [Sb, ~, mb] = generateChannel_v7(T, env, meta);
            Ob = cqiFeedback_v8(Sb, env, delays);
            Sw = [Sw; Sb]; Ow = [Ow; Ob]; %#ok<AGROW>
            Bw = [Bw; mb.burst]; Vw = [Vw; mb.speeds]; %#ok<AGROW>
        end
        rng(rs);
        SINR_true = [Sw(1:W, :); SINR_true];
        obs_SINR  = [Ow(1:W, :); obs_SINR];
        burst     = [Bw(1:W); burst];
        speeds    = [Vw(1:W, :); speeds];
        T = T + W;
    end

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
            [dc, vc] = userClass_v8(delays(i), mean(speeds(:, i)));
            fco(i) = env.fixed_class_tab(dc, vc);
        end
    end

    [~, sOneHot] = schedContext_v5(env.scheduler, env);
    ctx = single(repmat(sOneHot, 1, N));
    isDeep = any(strcmpi(ptype, {'a2c', 'a2c_v8'}));
    isMultiOLLA = strcmpi(ptype, 'multi_olla');

    off = zeros(1, N);
    off_fast = zeros(1, N);
    off_slow = zeros(1, N);
    H = harqInit_v8(N);
    R_emas = zeros(1, N);
    ema = 0.05;
    nk = zeros(1, N);
    prevRef = baseCQI_v5(obs_SINR(1, :) + off, env);

    if upper(env.state_tier) == 'A', nBase = 5; elseif upper(env.state_tier) == 'O', nBase = 10; else, nBase = 13; end
    nSingle = nBase + numel(env.sched_list);
    nFeat = nSingle * L_seq;
    histS = zeros(nSingle, N, L_seq, 'single');

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

    for t = 1:T
        ref  = baseCQI_v5(obs_SINR(t, :) + off, env);
        dRef = max(minD, min(maxD, ref - prevRef));
        dS   = obs_SINR(t, :) - obs_SINR(max(t-1, 1), :);
        t0   = max(t-4, 1);
        slope4 = (obs_SINR(t, :) - obs_SINR(t0, :)) / max(t - t0, 1);

        if isDeep
            s_now = stateFeat_v8(env.state_tier, ref, dRef, obs_SINR(t, :), dS, off, ...
                                 slope4, nk, H, speeds(t, :), burstObsM(t, :), ...
                                 delays, R_emas, ctx);
            histS(:, :, 2:L_seq) = histS(:, :, 1:L_seq-1);
            histS(:, :, 1) = s_now;
            S_temporal = reshape(permute(histS, [1, 3, 2]), nFeat, N);
            x1 = max(0, Wa.w1 * S_temporal + Wa.b1);
            x2 = max(0, Wa.w2 * x1 + Wa.b2);
            logits = Wa.w3 * x2 + Wa.b3;
        end

        sent = zeros(1, N);
        pot  = zeros(1, N);
        alpha_vec = 0.5 * ones(1, N);
        for i = 1:N
            switch lower(ptype)
                case 'baseline'
                    cqi = ref(i);
                case {'olla', 'warm_olla'}
                    cqi = ref(i);
                case 'multi_olla'
                    % Blended fast/slow multi-offset
                    alpha_i = 0.5 + 0.3 * (abs(slope4(i)) > 1.0) + 0.2 * (nk(i) > 0.4);
                    alpha_vec(i) = alpha_i;
                    cqi_eff_sinr = obs_SINR(t, i) + alpha_i * off_fast(i) + (1 - alpha_i) * off_slow(i);
                    cqi = baseCQI_v5(cqi_eff_sinr, env);
                case 'fixed'
                    cqi = max(minC, min(maxC, ref(i) + env.fixed_offset));
                case 'fixed_online'
                    % Online estimated velocity and delay
                    est_v = mean(speeds(max(t-20,1):t, i));
                    est_d = delays(i); % Available from ACK feedback latency
                    [dc_on, vc_on] = userClass_v8(est_d, est_v);
                    cqi = max(minC, min(maxC, ref(i) + env.fixed_class_tab(dc_on, vc_on)));
                case {'fixed_class', 'fixed_oracle'}
                    cqi = max(minC, min(maxC, ref(i) + fco(i)));
                case {'a2c', 'a2c_v8'}
                    [~, a] = max(logits(:, i));
                    act(t, i) = a;
                    cqi = max(minC, min(maxC, ref(i) + A(a)));
                case 'rand'
                    a = randi(numel(A));
                    act(t, i) = a;
                    cqi = max(minC, min(maxC, ref(i) + A(a)));
                otherwise
                    error('evalPolicy_v8: unknown ptype "%s"', ptype);
            end
            sent(i) = cqi;

            if env.harq_on && H.pend(i)
                pot(i) = tbsFromMCSandRB(H.mcs(i), env.total_RB) * 1e-3;
            else
                if isfield(env, 'sched_on_ref') && env.sched_on_ref
                    % FILL FIX option: scheduler ranks users by the OLLA reference rate,
                    % not by the link-adaptation decision (removes scheduler gaming)
                    pot(i) = tbsFromMCSandRB(max(env.min_CQI, min(env.max_CQI, ref(i))) - 1, env.total_RB) * 1e-3;
                else
                    pot(i) = tbsFromMCSandRB(sent(i) - 1, env.total_RB) * 1e-3;
                end
            end
            genie = max(1, min(15, find(SINR_true(t, i) >= env.CQI_thresholds, 1, 'last')));
            cqi_err(t, i) = abs(cqi - genie);
        end

        % Multi-user scheduling
        rb = schedule_users_v5(env.scheduler, t, N, R_emas, pot, env.total_RB);

        % Physics execution
        if isMultiOLLA
            [tpr, off_fast, off_slow, H, bl1, nEv] = ...
                MultiOLLA_v8(sent, SINR_true(t, :), rb, off_fast, off_slow, H, env, alpha_vec);
            off = 0.5 * off_fast + 0.5 * off_slow;
        elseif useOLLA
            [tpr, off, H, bl1, nEv] = txStep_v8(sent, SINR_true(t, :), rb, off, H, env);
        else
            [tpr, ~, H, bl1, nEv] = txStep_v8(sent, SINR_true(t, :), rb, zeros(1, N), H, env);
        end

        tp(t, :) = tpr;
        bler(t, :) = bl1;
        sched = rb > 0;
        nk(sched)  = 0.7 * nk(sched) + 0.3 * double(nEv(sched));
        nk(~sched) = 0.95 * nk(~sched);
        R_emas = (1 - ema) * R_emas + ema * tpr;
        prevRef = ref;
    end

    % Strip warm-up phase if applied
    if W > 0
        tp = tp(W+1:end, :);
        bler = bler(W+1:end, :);
        cqi_err = cqi_err(W+1:end, :);
        act = act(W+1:end, :);
    end
end
