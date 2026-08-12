function [tp, bler, cqi_err] = evalPolicy_v5(ptype, policy, SINR_true, obs_SINR, env)
% evalPolicy_v5  Frozen-policy evaluation on a held-out trace, baseline-relative.
%   All schemes see the SAME true channel and the SAME observed (delayed+noisy)
%   SINR. Action = offset from baseCQI(obs_SINR); offset 0 == baseline.
%
%   ptype  : 'baseline' | 'olla' | 'ql' | 'ac' | 'a2c'
%   policy : []         | []     | Q     | theta | actorNet (shared, no user dim)
%   tp/bler: T x N ;  cqi_err: |sent CQI - genie CQI(true SINR)|

    [T, N] = size(SINR_true);
    tp = zeros(T,N); bler = zeros(T,N); cqi_err = zeros(T,N);
    A = env.actions; no_op = find(A == 0);
    SB = env.SINR_bins; te = env.trend_edges;
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;

    [sc, sOneHot] = schedContext_v5(env.scheduler, env);   % observable regime
    ctx = single(repmat(sOneHot, 1, N));
    prevBase = baseCQI_v5(obs_SINR(1, :), env);
    olla_off = zeros(1, N);
    du = env.olla_step_down * env.olla_target/(1 - env.olla_target);
    dd = env.olla_step_down;

    onGPU = strcmpi(ptype,'a2c') && isa(extractdata(policy.Learnables.Value{1}), 'gpuArray');
    R_emas = zeros(1,N); ema = 0.05;

    for t = 1:T
        base = baseCQI_v5(obs_SINR(t, :), env);
        dB   = max(minD, min(maxD, base - prevBase));
        dS   = obs_SINR(t,:) - obs_SINR(max(t-1,1),:);

        if strcmpi(ptype,'a2c')
            S = single([base/15; dB/5; obs_SINR(t,:)/30; dS/5; ctx]);
            if onGPU, S = gpuArray(S); end
            logits = gather(extractdata(predict(policy, dlarray(S, 'CB'))));
        end

        sent = zeros(1,N); bl = zeros(1,N); pot = zeros(1,N);
        for i = 1:N
            switch lower(ptype)
                case 'baseline'
                    cqi = base(i);                              % offset 0
                case 'olla'
                    q = find(obs_SINR(t,i)+olla_off(i) >= env.CQI_thresholds, 1, 'last');
                    cqi = max(1, min(15, q));
                case {'ql','ac'}
                    [~, sb] = min(abs(SB - obs_SINR(t,i)));
                    tbi = trendBin_v5(dS(i), te);
                    tab = squeeze(policy(base(i), dB(i)+maxD+1, sb, tbi, sc, :));
                    a = argmaxNoOp_v5(tab, no_op);
                    cqi = max(minC, min(maxC, base(i) + A(a)));
                case 'a2c'
                    [~, a] = max(logits(:, i));
                    cqi = max(minC, min(maxC, base(i) + A(a)));
                otherwise
                    error('evalPolicy_v5: unknown ptype "%s"', ptype);
            end
            sent(i) = cqi;
            bl(i)   = estimateBLER_v5(SINR_true(t,i), cqi-1);
            pot(i)  = (1-bl(i))*tbsFromMCSandRB(cqi-1, env.total_RB)*1e-3;
            genie = max(1, min(15, find(SINR_true(t,i) >= env.CQI_thresholds, 1, 'last')));
            cqi_err(t,i) = abs(cqi - genie);
        end

        rb = schedule_users_v5(env.scheduler, t, N, R_emas, pot, env.total_RB);
        for i = 1:N
            bler(t,i) = bl(i);
            if rb(i) > 0
                tp(t,i) = (1-bl(i))*tbsFromMCSandRB(sent(i)-1, rb(i))*1e-3;
                if strcmpi(ptype,'olla')
                    if rand > bl(i), olla_off(i) = olla_off(i) + du;
                    else,            olla_off(i) = olla_off(i) - dd; end
                end
            end
        end
        R_emas = (1-ema)*R_emas + ema*tp(t,:);
        prevBase = base;
    end
end
