function sweep_olla_target_v7(targets)
% sweep_olla_target_v7  OLLA target-BLER re-tuning sweep, plus
% random-action and constant-offset controls, on the tier1b held-out traces.
    if nargin < 1 || isempty(targets), targets = [0.10 0.20 0.30 0.40 0.50]; end

    here = fileparts(mfilename('fullpath'));
    cd(here);
    addpath(fullfile(here, '..', 'v5'));
    addpath(fullfile(here, '..', 'case2_3'));
    if ~exist(fullfile(here,'logs'), 'dir'), mkdir(fullfile(here,'logs')); end
    diary(fullfile(here, 'logs', 'v7_olla_sweep_log.txt')); diary on;

    matf = fullfile(here, 'Dataset', 'results_v7_headline_tier1b.mat');
    if ~exist(matf, 'file'), error('missing %s', matf); end
    L = load(matf, 'results');
    env = L.results.env; env.scheduler = 'pf';
    A2Cs = L.results.policies.A2C;
    n_seeds = numel(A2Cs);

    simTime = 200; n_eval = 30; traceSeedBase = 9000;
    fprintf('\n===== OLLA target-BLER sweep (PF, %d traces, eval only) =====\n', n_eval);
    fprintf('actions=%s  fixed=%+d  class_tab=%s\n\n', ...
            mat2str(env.actions), env.fixed_offset, mat2str(env.fixed_class_tab));

    traces = struct('SINR',[],'obsS',[],'meta',[]); traces(n_eval).SINR = [];
    for j = 1:n_eval
        rng(traceSeedBase + j);
        [S, ~, mt] = generateChannel_v7(simTime, env);
        traces(j).SINR = S; traces(j).obsS = cqiFeedback_v7(S, env, mt.delays);
        traces(j).meta = mt;
    end

    scoreT = @(tp) sum(mean(tp(min(env.burn_in,size(tp,1)-1)+1:end, :), 1));
    scoreB = @(bl) mean(bl(~isnan(bl)));

    % OLLA frontier
    nT = numel(targets);
    tpO = zeros(nT, n_eval); blO = zeros(nT, n_eval);
    for q = 1:nT
        e = env; e.olla_target = targets(q);
        for j = 1:n_eval
            rng(88000 + 100*j + q);
            [tp, bl] = evalPolicy_v7('olla', [], traces(j).SINR, traces(j).obsS, e, traces(j).meta);
            tpO(q,j) = scoreT(tp); blO(q,j) = scoreB(bl);
        end
        fprintf('  OLLA target=%.2f : Tp = %.2f +/- %.2f Mbps   BLER1 = %.3f\n', ...
                targets(q), mean(tpO(q,:)), 1.96*std(tpO(q,:))/sqrt(n_eval), mean(blO(q,:)));
    end

    % Controls: random action, constant -1
    tpR = zeros(1,n_eval); blR = zeros(1,n_eval);
    tpC = zeros(1,n_eval); blC = zeros(1,n_eval);
    eC = env; eC.fixed_offset = -1;
    for j = 1:n_eval
        rng(89000 + j);
        [tp, bl] = evalPolicy_v7('rand', [], traces(j).SINR, traces(j).obsS, env, traces(j).meta);
        tpR(j) = scoreT(tp); blR(j) = scoreB(bl);
        rng(90000 + j);
        [tp, bl] = evalPolicy_v7('fixed', [], traces(j).SINR, traces(j).obsS, eC, traces(j).meta);
        tpC(j) = scoreT(tp); blC(j) = scoreB(bl);
    end
    fprintf('\n  rand-action   : Tp = %.2f +/- %.2f Mbps   BLER1 = %.3f\n', ...
            mean(tpR), 1.96*std(tpR)/sqrt(n_eval), mean(blR));
    fprintf('  const  -1     : Tp = %.2f +/- %.2f Mbps   BLER1 = %.3f\n', ...
            mean(tpC), 1.96*std(tpC)/sqrt(n_eval), mean(blC));

    % A2C reference (seed-averaged, same traces)
    tpA = zeros(1, n_eval); blA = zeros(1, n_eval);
    for j = 1:n_eval
        acc = 0; accb = 0;
        for s = 1:n_seeds
            rng(91000 + 100*j + s);
            [tp, bl] = evalPolicy_v7('a2c', A2Cs{s}, traces(j).SINR, traces(j).obsS, env, traces(j).meta);
            acc = acc + scoreT(tp); accb = accb + scoreB(bl);
        end
        tpA(j) = acc/n_seeds; blA(j) = accb/n_seeds;
    end
    fprintf('  Deep A2C      : Tp = %.2f +/- %.2f Mbps   BLER1 = %.3f\n', ...
            mean(tpA), 1.96*std(tpA)/sqrt(n_eval), mean(blA));

    % Verdict: A2C vs best OLLA target (paired Wilcoxon)
    [~, qb] = max(mean(tpO, 2));
    fprintf('\n  Best OLLA target = %.2f (Tp %.2f)\n', targets(qb), mean(tpO(qb,:)));
    if exist('signrank','file') == 2
        p = signrank(tpA, tpO(qb,:));
        mrg = 100*(mean(tpA) - mean(tpO(qb,:)))/mean(tpO(qb,:));
        fprintf('  A2C vs BEST-OLLA  %+.1f%%  p=%.4g\n', mrg, p);
        p2 = signrank(tpA, tpC);
        fprintf('  A2C vs const -1   %+.1f%%  p=%.4g\n', ...
                100*(mean(tpA)-mean(tpC))/mean(tpC), p2);
        p3 = signrank(tpA, tpR);
        fprintf('  A2C vs rand       %+.1f%%  p=%.4g\n', ...
                100*(mean(tpA)-mean(tpR))/mean(tpR), p3);
    end

    out = struct('targets',targets,'tpO',tpO,'blO',blO,'tpR',tpR,'tpC',tpC, ...
                 'tpA',tpA,'blA',blA,'blR',blR,'blC',blC,'n_eval',n_eval);
    save(fullfile(here,'Dataset','results_v7_olla_sweep.mat'), 'out', '-v7.3');
    fprintf('\n  Saved: Dataset\\results_v7_olla_sweep.mat\n');
    diary off;
end
