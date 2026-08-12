function action_histogram_v7()
% action_histogram_v7  fig12: A2C's action distribution vs FixedPU's
% per-class targets, on the tier1b held-out traces.
    here = fileparts(mfilename('fullpath'));
    cd(here);
    addpath(fullfile(here, '..', 'v5'));
    addpath(fullfile(here, '..', 'case2_3'));
    figdir = fullfile(here, 'figures');
    if ~exist(figdir, 'dir'), mkdir(figdir); end

    matf = fullfile(here, 'Dataset', 'results_v7_headline_tier1b.mat');
    if ~exist(matf, 'file'), error('missing %s - run tier1b first', matf); end
    L = load(matf, 'results'); res = L.results;
    env = res.env; env.scheduler = 'pf';
    A2Cs = res.policies.A2C; n_seeds = numel(A2Cs);

    simTime = 200; n_eval = 30; traceSeedBase = 9000;
    A = env.actions; nA = numel(A);

    fprintf('Re-evaluating A2C actions on %d held-out traces (%d seeds)...\n', n_eval, n_seeds);
    countsA2C = zeros(1, nA);
    countsFPU = zeros(1, nA);
    b0 = env.burn_in;

    for j = 1:n_eval
        rng(traceSeedBase + j);
        [Strue, ~, meta] = generateChannel_v7(simTime, env);
        obsS = cqiFeedback_v7(Strue, env, meta.delays);

        for i = 1:env.N
            [dc, vc] = userClass_v7(meta.delays(i), mean(meta.speeds(:,i)));
            [~, ai] = min(abs(A - env.fixed_class_tab(dc, vc)));
            countsFPU(ai) = countsFPU(ai) + 1;
        end

        for s = 1:n_seeds
            rng(92000 + 100*j + s);
            [~, ~, ~, act] = evalPolicy_v7('a2c', A2Cs{s}, Strue, obsS, env, meta);
            act = act(min(b0,size(act,1)-1)+1:end, :);
            for ai = 1:nA
                countsA2C(ai) = countsA2C(ai) + sum(act(:) == ai);
            end
        end
    end

    pA2C = 100 * countsA2C / sum(countsA2C);
    pFPU = 100 * countsFPU / sum(countsFPU);

    fig = figure('Visible','off','Position',[100 100 850 480]);
    bh = bar(A, [pA2C; pFPU]', 'grouped'); hold on;
    xline(0, 'k--', 'OLLA (action 0)');
    xlabel('Action offset relative to OLLA (CQI steps)');
    ylabel('Selection frequency (%)');
    legend({'Deep A2C (tier1b)', 'FixedPU class targets'}, 'Location','northeast');
    title('Action Distribution: Does A2C Condition on State, or Play a Constant?');
    grid on; box on;
    [~, modeA] = max(pA2C);
    txt = sprintf('Mode action = %+d  (%.0f%% of decisions)', A(modeA), pA2C(modeA));
    text(0.02, 0.95, txt, 'Units','normalized', 'FontSize',9, ...
         'BackgroundColor','w', 'EdgeColor',[0.5 0.5 0.5]);
    exportgraphics(fig, fullfile(figdir,'fig12_action_distribution.png'), 'Resolution',300);
    savefig(fig, fullfile(figdir,'fig12_action_distribution.fig'));
    close(fig);

    fprintf('A2C action distribution (%%%%): ');
    for ai = 1:nA, fprintf('%+d:%.1f  ', A(ai), pA2C(ai)); end
    fprintf('\nFixedPU class targets (%%%%): ');
    for ai = 1:nA, fprintf('%+d:%.1f  ', A(ai), pFPU(ai)); end
    fprintf('\nSaved: figures\\fig12_action_distribution.png\n');
end
