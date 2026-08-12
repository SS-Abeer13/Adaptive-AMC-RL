function [tp, bler, cqi_err, act] = evalPolicy_v7(ptype, policy, SINR_true, obs_SINR, env, meta)
% evalPolicy_v7  Frozen-policy evaluation, shared by every scheme.
%   ptype: 'baseline' | 'olla' | 'fixed' | 'fixed_class' | 'ql' | 'ac' | 'a2c' | 'rand'
    [T, N] = size(SINR_true);
    A = env.actions; no_op = find(A == 0);
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;
    SB = env.SINR_bins; te = env.trend_edges; OE = env.off_edges;
    useOLLA = ~strcmpi(ptype, 'baseline');

    % Leakage-free warm-up: independent channel segment, same users
    W = 0;
    burst = meta.burst; speeds = meta.speeds; delays = meta.delays;
    if useOLLA && isfield(env,'olla_warm_ttis') && env.olla_warm_ttis > 0
        W = round(env.olla_warm_ttis);
        rs = rng;
        rng(100000 + 7*W + 13*N + 101*round(mean(delays)));
        Sw = []; Ow = []; Bw = []; Vw = [];
        while size(Sw,1) < W
            [Sb, ~, mb] = generateChannel_v7(T, env, meta);
            Ob = cqiFeedback_v7(Sb, env, delays);
            Sw = [Sw; Sb]; Ow = [Ow; Ob]; %#ok<AGROW>
            Bw = [Bw; mb.burst]; Vw = [Vw; mb.speeds]; %#ok<AGROW>
        end
        rng(rs);
        SINR_true = [Sw(1:W,:); SINR_true];
        obs_SINR  = [Ow(1:W,:); obs_SINR];
        burst  = [Bw(1:W); burst];
        speeds = [Vw(1:W,:); speeds];
        T = T + W;
    end

    tp = zeros(T,N); bler = nan(T,N); cqi_err = zeros(T,N);
    act = no_op * ones(T, N);

    burstObsM = zeros(T, N);
    for i = 1:N
        idx = max((1:T).' - delays(i), 1);
        burstObsM(:, i) = double(burst(idx));
    end

    fco = zeros(1, N);
    if strcmpi(ptype, 'fixed_class')
        for i = 1:N
            [dc, vc] = userClass_v7(delays(i), mean(speeds(:,i)));
            fco(i) = env.fixed_class_tab(dc, vc);
        end
    end

    [sc, sOneHot] = schedContext_v5(env.scheduler, env);
    ctx = single(repmat(sOneHot, 1, N));
    isDeep = strcmpi(ptype, 'a2c');
    isTab  = any(strcmpi(ptype, {'ql','ac'}));

    off = zeros(1, N); H = harqInit_v7(N);
    R_emas = zeros(1, N); ema = 0.05;
    nk = zeros(1, N);
    prevRef = baseCQI_v5(obs_SINR(1,:) + off, env);

    for t = 1:T
        ref  = baseCQI_v5(obs_SINR(t,:) + off, env);
        dRef = max(minD, min(maxD, ref - prevRef));
        dS   = obs_SINR(t,:) - obs_SINR(max(t-1,1),:);
        t0 = max(t-4, 1);
        slope4 = (obs_SINR(t,:) - obs_SINR(t0,:)) / max(t - t0, 1);

        if isDeep
            S = stateFeat_v7(env.state_tier, ref, dRef, obs_SINR(t,:), dS, off, ...
                             slope4, nk, H, speeds(t,:), burstObsM(t,:), ctx);
            logits = extractdata(predict(policy, dlarray(S, 'CB')));
        end

        sent = zeros(1,N); pot = zeros(1,N);
        for i = 1:N
            switch lower(ptype)
                case 'baseline'
                    cqi = ref(i);
                case 'olla'
                    cqi = ref(i);
                case 'fixed'
                    cqi = max(minC, min(maxC, ref(i) + env.fixed_offset));
                case 'fixed_class'
                    cqi = max(minC, min(maxC, ref(i) + fco(i)));
                case {'ql','ac'}
                    [~, sb] = min(abs(SB - obs_SINR(t,i)));
                    tbi = trendBin_v5(dS(i), te);
                    obn = 1 + sum(off(i) > OE);
                    tab = squeeze(policy(ref(i), dRef(i)+maxD+1, sb, tbi, obn, sc, :));
                    a = argmaxNoOp_v5(tab, no_op);
                    act(t,i) = a;
                    cqi = max(minC, min(maxC, ref(i) + A(a)));
                case 'a2c'
                    [~, a] = max(logits(:, i));
                    act(t,i) = a;
                    cqi = max(minC, min(maxC, ref(i) + A(a)));
                case 'rand'
                    a = randi(numel(A));
                    act(t,i) = a;
                    cqi = max(minC, min(maxC, ref(i) + A(a)));
                otherwise
                    error('evalPolicy_v7: unknown ptype "%s"', ptype);
            end
            sent(i) = cqi;
            if env.harq_on && H.pend(i)
                pot(i) = tbsFromMCSandRB(H.mcs(i), env.total_RB) * 1e-3;
            else
                pot(i) = tbsFromMCSandRB(sent(i)-1, env.total_RB) * 1e-3;
            end
            genie = max(1, min(15, find(SINR_true(t,i) >= env.CQI_thresholds, 1, 'last')));
            cqi_err(t,i) = abs(cqi - genie);
        end

        rb = schedule_users_v5(env.scheduler, t, N, R_emas, pot, env.total_RB);
        if useOLLA
            [tpr, off, H, bl1, nEv] = txStep_v7(sent, SINR_true(t,:), rb, off, H, env);
        else
            [tpr, ~, H, bl1, nEv] = txStep_v7(sent, SINR_true(t,:), rb, zeros(1,N), H, env);
        end
        tp(t,:) = tpr; bler(t,:) = bl1;
        sched = rb > 0;
        nk(sched) = 0.7*nk(sched) + 0.3*double(nEv(sched));
        nk(~sched) = 0.95*nk(~sched);
        R_emas = (1-ema)*R_emas + ema*tpr;
        prevRef = ref;
    end

    if W > 0
        tp = tp(W+1:end,:); bler = bler(W+1:end,:);
        cqi_err = cqi_err(W+1:end,:); act = act(W+1:end,:);
    end
end
