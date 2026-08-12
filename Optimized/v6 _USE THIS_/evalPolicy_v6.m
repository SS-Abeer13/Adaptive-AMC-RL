function [tp, bler, cqi_err, act] = evalPolicy_v6(ptype, policy, SINR_true, obs_SINR, env)
% evalPolicy_v6  Frozen-policy evaluation, OLLA-relative (v6).
%   Every scheme except 'baseline' carries the per-user OLLA loop (offset
%   updated on realized ACK/NACK of the SENT CQI, only when scheduled).
%   Reference CQI = baseCQI(obs + olla_off); RL action = offset from that.
%   'olla' is literally the RL scheme with action forced to 0, so the
%   comparison is exact: any RL gain = learned state-conditional deviation.
%
%   ptype  : 'baseline' | 'olla' | 'ql' | 'ac' | 'a2c'
%   policy : []         | []     | Q     | theta | actorNet (shared)
%
%   Optional 4th output ACT (T x N) is the selected ACTION INDEX at every TTI
%   (into env.actions); act == find(env.actions==0) means the learner chose
%   the no-op, i.e. exactly the OLLA decision. Used to measure how often the
%   policy deviates from OLLA (action-0 usage).

    [T, N] = size(SINR_true);
    tp = zeros(T,N); bler = zeros(T,N); cqi_err = zeros(T,N);
    A = env.actions; no_op = find(A == 0);
    act = no_op * ones(T, N);       % default no-op (== OLLA); baseline/olla stay here
    SB = env.SINR_bins; te = env.trend_edges;
    maxC = env.max_CQI; minC = env.min_CQI; maxD = env.max_delta; minD = env.min_delta;
    OE = env.off_edges;

    [sc, sOneHot] = schedContext_v5(env.scheduler, env);
    ctx = single(repmat(sOneHot, 1, N));
    du = env.olla_step_down * env.olla_target/(1 - env.olla_target);
    dd = env.olla_step_down;
    useOLLA = ~strcmpi(ptype, 'baseline');

    % ---- Leakage-free warm-up (audit fix) ----
    % env.olla_warm_ttis > 0 prepends an INDEPENDENT channel segment (own,
    % deterministic rng substream shared by all schemes) so every
    % loop-carrying scheme's OLLA offsets converge BEFORE the scored trace,
    % without ever seeing the scored data. The warm segment is trimmed from
    % all outputs at the end.
    W = 0;
    if useOLLA && isfield(env,'olla_warm_ttis') && ~isempty(env.olla_warm_ttis) && env.olla_warm_ttis > 0
        W = round(env.olla_warm_ttis);
        rs = rng;                                          % preserve caller stream
        rng(100000 + 7*W + 13*N + 101*env.cqi_delay);      % same warm channel for every scheme
        Sw = []; Ow = [];
        while size(Sw,1) < W
            [Sb, ~, ~] = generateChannel_v5(T, env);
            [Ob, ~] = cqiFeedback_v5(Sb, env);
            Sw = [Sw; Sb]; Ow = [Ow; Ob]; %#ok<AGROW>
        end
        rng(rs);                                           % restore caller stream
        SINR_true = [Sw(1:W,:); SINR_true];
        obs_SINR  = [Ow(1:W,:); obs_SINR];
        T = T + W;
        tp = zeros(T,N); bler = zeros(T,N); cqi_err = zeros(T,N);
        act = no_op * ones(T, N);
    end

    % DEPRECATED: olla_warm_passes REPLAYS the scored trace, fitting the
    % per-user offsets on the evaluation data itself (test leakage; this is
    % what produced the impossible +164%/+220% warmed-OLLA rows). Kept only
    % to reproduce those diagnostics - do NOT use for reported results; use
    % olla_warm_ttis instead.
    nPass = 1;
    if useOLLA && isfield(env,'olla_warm_passes') && ~isempty(env.olla_warm_passes) && env.olla_warm_passes > 0
        nPass = 1 + env.olla_warm_passes;
        warning('evalPolicy_v6:warmReplayLeakage', ...
                'olla_warm_passes replays the scored trace (test leakage); use olla_warm_ttis.');
    end

    onGPU = strcmpi(ptype,'a2c') && isa(extractdata(policy.Learnables.Value{1}), 'gpuArray');
    ema = 0.05;

    off = zeros(1, N);                      % per-user OLLA offset (persists across passes)
    for pass = 1:nPass
    R_emas = zeros(1,N);
    prevRef = baseCQI_v5(obs_SINR(1,:) + off, env);
    for t = 1:T
        ref  = baseCQI_v5(obs_SINR(t,:) + off, env);   % OLLA-corrected reference
        dRef = max(minD, min(maxD, ref - prevRef));
        dS   = obs_SINR(t,:) - obs_SINR(max(t-1,1),:);

        if strcmpi(ptype,'a2c')
            S = single([ref/15; dRef/5; obs_SINR(t,:)/30; dS/5; off/5; ctx]);
            if onGPU, S = gpuArray(S); end
            logits = gather(extractdata(predict(policy, dlarray(S, 'CB'))));
        end

        sent = zeros(1,N); bl = zeros(1,N); pot = zeros(1,N);
        for i = 1:N
            switch lower(ptype)
                case 'baseline'
                    cqi = ref(i);                       % off == 0 always
                case 'olla'
                    cqi = ref(i);                       % action 0 by definition
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
                otherwise
                    error('evalPolicy_v6: unknown ptype "%s"', ptype);
            end
            sent(i) = cqi;
            bl(i)   = estimateBLER_v5(SINR_true(t,i), cqi-1);
            pot(i)  = pfPotential_v5(cqi, bl(i), env);
            genie = max(1, min(15, find(SINR_true(t,i) >= env.CQI_thresholds, 1, 'last')));
            cqi_err(t,i) = abs(cqi - genie);
        end

        rb = schedule_users_v5(env.scheduler, t, N, R_emas, pot, env.total_RB);
        for i = 1:N
            bler(t,i) = bl(i);
            if rb(i) > 0
                tp(t,i) = (1-bl(i))*tbsFromMCSandRB(sent(i)-1, rb(i))*1e-3;
                if useOLLA                              % realized ACK/NACK feedback
                    if rand > bl(i), off(i) = off(i) + du;
                    else,            off(i) = off(i) - dd; end
                end
            end
        end
        R_emas = (1-ema)*R_emas + ema*tp(t,:);
        prevRef = ref;
    end
    end   % pass loop (metrics from the final pass are returned)

    if W > 0   % trim the (never-scored) warm segment from all outputs
        tp = tp(W+1:end,:); bler = bler(W+1:end,:);
        cqi_err = cqi_err(W+1:end,:); act = act(W+1:end,:);
    end
end
