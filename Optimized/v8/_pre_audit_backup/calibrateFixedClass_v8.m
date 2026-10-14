function env = calibrateFixedClass_v8(env, nCalib, simTime)
% calibrateFixedClass_v8  Grid-search calibration of Fixed and FixedPU
% comparators on held-out calibration traces (disjoint from evaluation traces).
    if nargin < 2 || isempty(nCalib),  nCalib = 6;    end
    if nargin < 3 || isempty(simTime), simTime = 200; end

    cands = env.fixed_cands;
    nC = numel(cands);
    acc = zeros(2, 3, nC);
    cnt = zeros(2, 3, nC);
    tot = zeros(1, nC);
    envE = env;
    envE.scheduler = 'pf';
    envE.olla_warm_ttis = 0;

    fprintf('  [calib] fixed-offset candidate grid: %s across %d calibration traces...\n', ...
            mat2str(cands), nCalib);
    for j = 1:nCalib
        rng(60000 + j);
        [Strue, ~, meta] = generateChannel_v7(simTime, env);
        obsS = cqiFeedback_v8(Strue, env, meta.delays);
        for c = 1:nC
            envE.fixed_offset = cands(c);
            rng(61000 + 100*j + c);
            tpc = evalPolicy_v8('fixed', [], Strue, obsS, envE, meta);
            b0 = min(env.burn_in, size(tpc,1)-1);
            pu = mean(tpc(b0+1:end,:), 1);
            tot(c) = tot(c) + sum(pu);
            for i = 1:env.N
                [dc, vc] = userClass_v8(meta.delays(i), mean(meta.speeds(:,i)));
                acc(dc, vc, c) = acc(dc, vc, c) + pu(i);
                cnt(dc, vc, c) = cnt(dc, vc, c) + 1;
            end
        end
    end

    [~, bestG] = max(tot);
    env.fixed_offset = cands(bestG);

    env.fixed_class_tab = zeros(2, 3);
    for dc = 1:2
        for vc = 1:3
            m = squeeze(acc(dc, vc, :) ./ max(cnt(dc, vc, :), 1));
            if all(cnt(dc, vc, :) == 0)
                env.fixed_class_tab(dc, vc) = env.fixed_offset;
            else
                [~, b] = max(m);
                env.fixed_class_tab(dc, vc) = cands(b);
            end
        end
    end

    fprintf('  [calib] Best global fixed offset: %+d\n', env.fixed_offset);
    fprintf('  [calib] FixedPU 2x3 class table (rows: delay<=4, >=5 | cols: <10, 10-20, >20 m/s):\n');
    disp(env.fixed_class_tab);
end
