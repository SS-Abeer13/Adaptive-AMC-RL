% test_engine_consistency_v17  Stage B2.3:
% With pf_avg = 'scheduled' and drain = true, on 20 traces in both K3 (full buffer)
% and K1 (deadline) environments (Baseline, OLLA, Fixed):
% Compare Legacy engine (rtt 0, 1 proc) vs New engine (rtt 1, 1 proc).
% Pass criteria:
%   - goodput and on-time agree within +/- 1.0%
%   - Jain fairness agrees within +/- 0.01
% If not, stop and report.

root = 'D:\Adaptive AMC A2C+QL';
addpath(fullfile(root, 'Optimized', 'v17'));
addpath(fullfile(root, 'Optimized', 'v5'));
addpath(fullfile(root, 'Optimized', 'case2_3'));

fprintf('=== test_engine_consistency_v17: Legacy RTT 0 vs New RTT 1 (20 traces) ===\n');

v17_setup;
N = 10;
simTime = 200;
nTraces = 20;
traceSeeds = 9001:9020;
comparators = {'baseline', 'olla', 'fixed'};

env_names = {'K3_goodput', 'K1_deadline'};
allPass = true;

for eIdx = 1:numel(env_names)
    envName = env_names{eIdx};
    fprintf('\n------------------------------------------------------------\n');
    fprintf('Testing environment: %s\n', envName);
    fprintf('------------------------------------------------------------\n');

    % Build base env
    envBase = defaultEnv_v17(23, N);
    fnB = fieldnames(base);
    for q = 1:numel(fnB), envBase.(fnB{q}) = base.(fnB{q}); end

    if strcmp(envName, 'K3_goodput')
        fnG = fieldnames(GP);
        for q = 1:numel(fnG), envBase.(fnG{q}) = GP.(fnG{q}); end
    else
        fnD = fieldnames(DL);
        for q = 1:numel(fnD), envBase.(fnD{q}) = DL.(fnD{q}); end
    end
    envBase.pf_avg = 'scheduled';
    envBase.drain = true;

    % Calibrate comparators
    envBase = calibrateFixedClass_v17(envBase, 6, simTime);
    envBase = calibrateCtx_v17(envBase, envBase.n_calib_ctx, simTime);

    % Config A: Legacy RTT 0 / 1 proc
    envA = envBase;
    envA.harq_rtt = 0; envA.harq_nproc = 1;

    % Config B: New RTT 1 / 1 proc
    envB = envBase;
    envB.harq_rtt = 1; envB.harq_nproc = 1;

    isDeadline = strcmp(envBase.traffic, 'deadline');

    for cIdx = 1:numel(comparators)
        cmp = comparators{cIdx};

        jainA_traces = zeros(1, nTraces);
        jainB_traces = zeros(1, nTraces);
        primA_traces = zeros(1, nTraces);
        primB_traces = zeros(1, nTraces);
        tpA_traces   = zeros(1, nTraces);
        tpB_traces   = zeros(1, nTraces);

        for j = 1:nTraces
            tSeed = traceSeeds(j);
            rng(tSeed);
            [Strue, ~, meta] = generateChannel_v17(simTime, envBase);
            obsS = cqiFeedback_v17(Strue, envBase, meta.delays);
            meta.trace_id = j;
            rng(50000 + j); U = rand(simTime, N);

            rng(70000 + 100*j + 10*cIdx);
            [tpA, ~, ~, ~, infA] = evalPolicy_v17(cmp, [], Strue, obsS, envA, meta, U);

            rng(70000 + 100*j + 10*cIdx);
            [tpB, ~, ~, ~, infB] = evalPolicy_v17(cmp, [], Strue, obsS, envB, meta, U);

            b0 = min(envBase.burn_in, size(tpA, 1) - 1);
            tpB_evalA = tpA(b0+1:end, :);
            tpB_evalB = tpB(b0+1:end, :);
            tpA_traces(j) = sum(mean(tpB_evalA, 1));
            tpB_traces(j) = sum(mean(tpB_evalB, 1));

            % Standardized definition: per-trace Jain over per-user mean primary metric in evaluation window
            [numA, denA, primA_traces(j)] = userMetric_v17(envBase, tpA, infA, b0);
            puA = numA ./ max(denA, 1);
            jainA_traces(j) = sum(puA)^2 / (N * max(sum(puA.^2), eps));

            [numB, denB, primB_traces(j)] = userMetric_v17(envBase, tpB, infB, b0);
            puB = numB ./ max(denB, 1);
            jainB_traces(j) = sum(puB)^2 / (N * max(sum(puB.^2), eps));
        end

        % Metrics: average of per-trace metrics (= M.jain and M.primary)
        meanPrimA = mean(primA_traces);
        meanPrimB = mean(primB_traces);
        gapPrimPct = (meanPrimB - meanPrimA) / meanPrimA * 100;
        passPrim = abs(gapPrimPct) <= 1.0;

        jainA = mean(jainA_traces);
        jainB = mean(jainB_traces);
        deltaJain = jainB - jainA;
        passJain = abs(deltaJain) <= 0.01;

        meanTpA = mean(tpA_traces);
        meanTpB = mean(tpB_traces);

        passCmp = passPrim && passJain;
        passStr = 'PASS'; if ~passCmp, passStr = 'FAIL'; end

        if isDeadline
            fprintf('  %-10s: OnTime: A=%.2f%% B=%.2f%% (gap %+.3f%%) | Jain: A=%.4f B=%.4f (d=%+.4f) | Useful Goodput: A=%.4f B=%.4f [%s]\n', ...
                cmp, meanPrimA*100, meanPrimB*100, gapPrimPct, jainA, jainB, deltaJain, meanTpA, meanTpB, passStr);
        else
            fprintf('  %-10s: Goodput: A=%.4f B=%.4f (gap %+.3f%%) | Jain: A=%.4f B=%.4f (d=%+.4f) [%s]\n', ...
                cmp, meanPrimA, meanPrimB, gapPrimPct, jainA, jainB, deltaJain, passStr);
        end

        if ~passCmp
            allPass = false;
        end
    end
end

if allPass
    fprintf('\n=== test_engine_consistency_v17: ALL CHECKS PASSED (within +/-1%% and +/-0.01 Jain) ===\n');
else
    fprintf('\n=== test_engine_consistency_v17: FAIL -- criteria exceeded ===\n');
    error('test_engine_consistency_v17:fail', 'Engine consistency criteria exceeded.');
end
