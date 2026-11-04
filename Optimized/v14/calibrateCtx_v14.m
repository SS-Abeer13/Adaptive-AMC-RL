function env = calibrateCtx_v14(env, nCalib, simTime)
% calibrateCtx_v14  Offline calibration of the two v14 same-information
% comparators on calibration traces (disjoint from evaluation traces),
% objective = the primary metric, common random numbers across candidates:
%   (a) OLLA target BLER, grid env.olla_targets;
%   (b) context table: one offset per bin of env.ctx_cue, coordinate ascent
%       (2 passes) over env.ctx_offsets, starting from all-zero (= OLLA).
    if nargin < 2 || isempty(nCalib), nCalib = env.n_calib_ctx; end
    envE = env;
    if isfield(env, 'calib_sched') && ~isempty(env.calib_sched), envE.scheduler = env.calib_sched; end
    if ~(isfield(env, 'calib_warm') && env.calib_warm), envE.olla_warm_ttis = 0; end
    C = struct('S', {}, 'O', {}, 'M', {}, 'U', {});
    for j = 1:nCalib
        rng(60000 + j);
        [Strue, ~, meta] = generateChannel_v14(simTime, env);
        obsS = cqiFeedback_v14(Strue, env, meta.delays);
        meta.trace_id = 10000 + j;
        rng(62000 + j); Uc = rand(simTime, env.N);
        C(j).S = Strue; C(j).O = obsS; C(j).M = meta; C(j).U = Uc;
    end
    function v = score(e, ptype)
        n = 0; d = 0;
        for jj = 1:numel(C)
            rng(61500 + jj);
            [tpc, ~, ~, ~, inf] = evalPolicy_v14(ptype, [], C(jj).S, C(jj).O, e, C(jj).M, C(jj).U);
            b0 = min(e.burn_in, size(tpc, 1) - 1);
            [nu, de] = userMetric_v14(e, tpc, inf, b0);
            n = n + sum(nu); d = d + sum(de);
        end
        v = n / max(d, 1);
    end
    % (a) OLLA target
    best = -Inf;
    for tg = env.olla_targets
        e = envE; e.olla_target_tuned = tg;
        v = score(e, 'olla_tuned');
        fprintf('  [calib-ctx] OLLA target %.2f -> %.4f\n', tg, v);
        if v > best + 1e-12, best = v; env.olla_target_tuned = tg; end
    end
    fprintf('  [calib-ctx] tuned OLLA target = %.2f\n', env.olla_target_tuned);
    % (b) context table
    nb = nCtxBins_v14(env);
    tab = zeros(1, nb);
    e = envE; e.ctx_tab = tab; cur = score(e, 'ctxtab');
    for pass = 1:2
        changed = false;
        for bIdx = 1:nb
            for o = env.ctx_offsets
                if o == tab(bIdx), continue; end
                t2 = tab; t2(bIdx) = o; e.ctx_tab = t2;
                v = score(e, 'ctxtab');
                if v > cur + 1e-12, cur = v; tab = t2; changed = true; end
            end
        end
        if ~changed, break; end
    end
    env.ctx_tab = tab;
    fprintf('  [calib-ctx] context table (cue %s, edges %s) = %s | score %.4f\n', ...
            env.ctx_cue, mat2str(env.ctx_edges), mat2str(tab), cur);
end
