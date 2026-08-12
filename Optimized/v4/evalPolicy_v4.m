function [tp, bler, cqi_err] = evalPolicy_v4(ptype, policy, SINR_true, obs_SINR, obs_CQI, env)
% evalPolicy_v4  Frozen-policy evaluation on a held-out trace (audit section 4).
%   All schemes see the SAME imperfect observations (obs_SINR/obs_CQI) and the
%   SAME true channel (SINR_true); the comparison harness pre-generates these
%   traces once so every scheme is evaluated on identical realizations.
%
%   ptype  : 'baseline' | 'olla' | 'ql' | 'ac' | 'a2c'
%   policy : []          | []     | Q-table | theta | actorNet
%
%   tp      : T x N achieved throughput (Mbps), 0 when unscheduled
%   bler    : T x N true BLER of the transmitted MCS
%   cqi_err : T x N |chosen CQI - genie CQI(true SINR)| tracking error

    [T, N] = size(SINR_true);
    tp = zeros(T, N); bler = zeros(T, N); cqi_err = zeros(T, N);

    actions = env.actions;
    no_op = find(actions == 0);
    SINR_bins = env.SINR_bins;
    maxC = env.max_CQI; minC = env.min_CQI;
    maxD = env.max_delta; minD = env.min_delta;
    te = env.trend_edges;

    % differential-policy state
    cur = obs_CQI(1, :); prev = cur; d = zeros(1, N);
    % OLLA state
    olla_off = zeros(1, N);
    du = env.olla_step_down * env.olla_target / (1 - env.olla_target);
    dd = env.olla_step_down;

    onGPU = false;
    if strcmpi(ptype, 'a2c')
        onGPU = isa(extractdata(policy.Learnables.Value{1}), 'gpuArray');
    end

    R_emas = zeros(1, N); ema_a = 0.05;

    for t = 1:T
        mcs = zeros(1, N); bl = zeros(1, N); pot = zeros(1, N);

        dS_row = obs_SINR(t, :) - obs_SINR(max(t-1, 1), :);
        if strcmpi(ptype, 'a2c')
            S = single([cur/15; d/5; obs_SINR(t, :)/30; dS_row/5]);
            if onGPU, S = gpuArray(S); end
            logits = gather(extractdata(predict(policy, dlarray(S, 'CB'))));
        end

        for i = 1:N
            switch lower(ptype)
                case 'baseline'             % outdated-CQI fixed mapping
                    cqi = obs_CQI(t, i);
                case 'olla'                 % outer-loop link adaptation
                    se = obs_SINR(t, i) + olla_off(i);
                    cqi = find(se >= env.CQI_thresholds, 1, 'last');
                    cqi = max(1, min(15, cqi));
                case 'ql'
                    [~, sb] = min(abs(SINR_bins - obs_SINR(t, i)));
                    tbi = trendBin_v4(dS_row(i), te);
                    a = argmaxNoOp_v4( ...
                        squeeze(policy(cur(i), d(i)+maxD+1, sb, tbi, :, i)), no_op);
                    cqi = max(minC, min(maxC, cur(i) + actions(a)));
                case 'ac'
                    [~, sb] = min(abs(SINR_bins - obs_SINR(t, i)));
                    tbi = trendBin_v4(dS_row(i), te);
                    a = argmaxNoOp_v4( ...
                        squeeze(policy(cur(i), d(i)+maxD+1, sb, tbi, :, i)), no_op);
                    cqi = max(minC, min(maxC, cur(i) + actions(a)));
                case 'a2c'
                    [~, a] = max(logits(:, i));
                    cqi = max(minC, min(maxC, cur(i) + actions(a)));
                otherwise
                    error('evalPolicy_v4: unknown ptype "%s"', ptype);
            end
            mcs(i) = cqi - 1;
            bl(i)  = estimateBLER_v4(SINR_true(t, i), mcs(i));
            pot(i) = (1 - bl(i)) * tbsFromMCSandRB(mcs(i), env.total_RB) * 1e-3;

            genie = find(SINR_true(t, i) >= env.CQI_thresholds, 1, 'last');
            genie = max(1, min(15, genie));
            cqi_err(t, i) = abs(cqi - genie);
        end

        rb = schedule_users_v4(env.scheduler, t, N, R_emas, pot, env.total_RB);

        for i = 1:N
            bler(t, i) = bl(i);
            if rb(i) > 0
                tp(t, i) = (1 - bl(i)) * tbsFromMCSandRB(mcs(i), rb(i)) * 1e-3;
                if strcmpi(ptype, 'olla')   % ACK/NACK update on served TTIs
                    if rand > bl(i), olla_off(i) = olla_off(i) + du;
                    else,            olla_off(i) = olla_off(i) - dd;
                    end
                end
            end
            % differential state update (used by ql/ac/a2c; harmless otherwise)
            cqi_i = mcs(i) + 1;
            nd = max(minD, min(maxD, cqi_i - prev(i)));
            prev(i) = cur(i); cur(i) = cqi_i; d(i) = nd;
        end
        R_emas = (1 - ema_a) * R_emas + ema_a * tp(t, :);
    end
end
