function env = calibrateGenie_v14(env, nCalib, simTime)
% calibrateGenie_v14  Offline calibration of env.genie_bler on calibration traces
% (traces 60001+, disjoint from evaluation traces), objective = primary metric,
% grid = [0.001 0.01 0.03 0.10 0.20]. See PLAN_v14.md S0.1.
    if nargin < 2 || isempty(nCalib),  nCalib = 6;    end
    if nargin < 3 || isempty(simTime), simTime = 200; end

    grid = [0.001 0.01 0.03 0.10 0.20];
    if isfield(env, 'genie_bler_grid') && ~isempty(env.genie_bler_grid)
        grid = env.genie_bler_grid;
    end

    envE = env;
    if isfield(env, 'calib_sched') && ~isempty(env.calib_sched)
        envE.scheduler = env.calib_sched;
    end
    if ~(isfield(env, 'calib_warm') && env.calib_warm)
        envE.olla_warm_ttis = 0;
    end

    C = struct('S', {}, 'O', {}, 'M', {}, 'U', {});
    for j = 1:nCalib
        rng(60000 + j);
        [Strue, ~, meta] = generateChannel_v14(simTime, env);
        obsS = cqiFeedback_v14(Strue, env, meta.delays);
        meta.trace_id = 10000 + j;
        rng(62000 + j); Uc = rand(simTime, env.N);
        C(j).S = Strue; C(j).O = obsS; C(j).M = meta; C(j).U = Uc;
    end

    bestVal = -Inf;
    bestBler = grid(1);

    fprintf('  [calib-genie] testing genie_bler grid %s across %d calibration traces...\n', ...
            mat2str(grid), nCalib);

    for gb = grid
        e = envE;
        e.genie_bler = gb;
        n = 0; d = 0;
        for jj = 1:numel(C)
            rng(61500 + jj);
            [tpc, ~, ~, ~, inf] = evalPolicy_v14('genie_cqi', [], C(jj).S, C(jj).O, e, C(jj).M, C(jj).U);
            b0 = min(e.burn_in, size(tpc, 1) - 1);
            [nu, de] = userMetric_v14(e, tpc, inf, b0);
            n = n + sum(nu); d = d + sum(de);
        end
        v = n / max(d, 1);
        fprintf('  [calib-genie] target BLER %.4f -> %.4f\n', gb, v);
        if v > bestVal + 1e-12
            bestVal = v;
            bestBler = gb;
        end
    end

    env.genie_bler = bestBler;
    fprintf('  [calib-genie] best genie_bler = %.4f (score = %.4f)\n', env.genie_bler, bestVal);
end
