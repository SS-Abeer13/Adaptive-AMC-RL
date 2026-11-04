function env = calibrateTargetClass_v15(env, nCalib, simTime)
% calibrateTargetClass_v15  P1 (README_v15.md) same-information comparator:
% per-class tuned OLLA target BLER (one target per delay-class x speed-class
% bin, env.target_set grid), the target-mode analogue of
% calibrateFixedClass_v15's FixedPU table. Calibrated on calibration traces
% (disjoint from evaluation traces), objective = the primary metric, common
% random numbers across candidates.
    if nargin < 2 || isempty(nCalib),  nCalib = 6;    end
    if nargin < 3 || isempty(simTime), simTime = 200; end

    cands = env.target_set;
    nC = numel(cands);
    acc = zeros(2, 3, nC);
    cnt = zeros(2, 3, nC);
    envE = env;
    envE.scheduler = 'pf';
    if isfield(env, 'calib_sched') && ~isempty(env.calib_sched), envE.scheduler = env.calib_sched; end
    if ~(isfield(env, 'calib_warm') && env.calib_warm), envE.olla_warm_ttis = 0; end

    fprintf('  [calib] target-BLER candidate grid: %s across %d calibration traces...\n', ...
            mat2str(cands), nCalib);
    for j = 1:nCalib
        rng(60000 + j);
        [Strue, ~, meta] = generateChannel_v15(simTime, env);
        obsS = cqiFeedback_v15(Strue, env, meta.delays);
        meta.trace_id = 10000 + j;
        rng(62000 + j); Uc = rand(simTime, env.N);   % common outcome draws across candidates
        for c = 1:nC
            envE.target_class_tab = cands(c) * ones(2, 3);  % uniform table: isolates each candidate's own score
            rng(61000 + 100*j + c);
            [tpc, ~, ~, ~, inf] = evalPolicy_v15('olla_target_class', [], Strue, obsS, envE, meta, Uc);
            b0 = min(env.burn_in, size(tpc,1)-1);
            [num, den] = userMetric_v15(env, tpc, inf, b0);
            for i = 1:env.N
                [dc, vc] = userClass_v15(meta.delays(i), mean(meta.speeds(:,i)));
                acc(dc, vc, c) = acc(dc, vc, c) + num(i);
                cnt(dc, vc, c) = cnt(dc, vc, c) + den(i);
            end
        end
    end

    env.target_class_tab = env.olla_target_tuned * ones(2, 3);
    for dc = 1:2
        for vc = 1:3
            m = squeeze(acc(dc, vc, :) ./ max(cnt(dc, vc, :), 1));
            if all(cnt(dc, vc, :) == 0)
                env.target_class_tab(dc, vc) = env.olla_target_tuned;
            else
                [~, b] = max(m);
                env.target_class_tab(dc, vc) = cands(b);
            end
        end
    end

    fprintf('  [calib] per-class tuned target 2x3 table (rows: delay<=4, >=5 | cols: <10, 10-20, >20 m/s):\n');
    disp(env.target_class_tab);
end
