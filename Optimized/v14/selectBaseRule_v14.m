function [env, baseName] = selectBaseRule_v14(env, nCalib, simTime)
% selectBaseRule_v14  Choose the base rule for residual A2C by score
% ON CALIBRATION TRACES (traces 60001+, disjoint from eval traces).
% S1.1: b_i is the calibrated offset of the better of {Fixed, FixedPU}.
    if nargin < 2 || isempty(nCalib),  nCalib = 20;   end
    if nargin < 3 || isempty(simTime), simTime = 200; end

    envE = env;
    if isfield(env, 'calib_sched') && ~isempty(env.calib_sched)
        envE.scheduler = env.calib_sched;
    end
    if ~(isfield(env, 'calib_warm') && env.calib_warm)
        envE.olla_warm_ttis = 0;
    end

    nF = 0; dF = 0;
    nPU = 0; dPU = 0;
    b0 = min(env.burn_in, simTime - 1);

    for j = 1:nCalib
        rng(60000 + j);
        [Strue, ~, meta] = generateChannel_v14(simTime, env);
        obsS = cqiFeedback_v14(Strue, env, meta.delays);
        meta.trace_id = 10000 + j;
        rng(62000 + j); Uc = rand(simTime, env.N);

        % Fixed
        rng(61000 + 100*j + 1);
        [tpF, ~, ~, ~, infF] = evalPolicy_v14('fixed', [], Strue, obsS, envE, meta, Uc);
        [nuF, deF] = userMetric_v14(envE, tpF, infF, b0);
        nF = nF + sum(nuF); dF = dF + sum(deF);

        % FixedPU
        rng(61000 + 100*j + 2);
        [tpPU, ~, ~, ~, infPU] = evalPolicy_v14('fixed_class', [], Strue, obsS, envE, meta, Uc);
        [nuPU, dePU] = userMetric_v14(envE, tpPU, infPU, b0);
        nPU = nPU + sum(nuPU); dPU = dPU + sum(dePU);
    end

    scF = nF / max(dF, 1);
    scPU = nPU / max(dPU, 1);

    if scPU > scF + 1e-12
        env.base_rule_kind = 'fixed_class';
        baseName = 'FixedPU (Oracle)';
    else
        env.base_rule_kind = 'fixed';
        baseName = 'Fixed';
    end

    fprintf('  [base-rule] Calib on-time score: Fixed = %.4f (offset %+d), FixedPU = %.4f -> chosen base rule: %s\n', ...
            scF, env.fixed_offset, scPU, baseName);
end
