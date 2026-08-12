function results = runComparison_v4(caseId, opts)
% runComparison_v4  Statistically rigorous comparison harness (audit section 4).
%
%   results = runComparison_v4(1)    -> Case 1  (single user, radial)
%   results = runComparison_v4(23)   -> Case 2/3 (5 users, PF scheduler)
%
%   opts (all optional): simTime, ep_tab, ep_deep, n_seeds, n_eval, base_seed,
%                        eval_schedulers (cellstr, robustness sweep)
%
% Protocol:
%   - n_seeds independent trainings of QL / Tab-AC / Deep A2C on the SAME
%     unified MDP (defaultEnv_v4).
%   - n_eval held-out channel+feedback traces, pre-generated once, identical
%     for every scheme; policies frozen, greedy.
%   - Baselines: outdated-CQI fixed mapping and OLLA (industry standard).
%   - Reported: mean +/- 95% CI over seeds x traces, Wilcoxon signed-rank
%     (A2C vs each baseline, paired over traces), Jain index, edge-user
%     throughput, CQI tracking error.
%   - Robustness: each policy (trained on env.scheduler) is re-evaluated
%     under every scheduler in eval_schedulers without retraining.

    if nargin < 2, opts = struct(); end
    g = @(f, d) getfield_default(opts, f, d);
    simTime  = g('simTime', 200);
    ep_tab   = g('ep_tab', 400);
    ep_deep  = g('ep_deep', 200);
    n_seeds  = g('n_seeds', 3);
    n_eval   = g('n_eval', 20);
    baseSeed = g('base_seed', 42);

    env = defaultEnv_v4(caseId);
    if caseId == 1
        eval_scheds = g('eval_schedulers', {'all'});
    else
        eval_scheds = g('eval_schedulers', {'pf', 'rr', 'eq'});
    end

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, '..', 'case2_3'));   % createTBS_Table, tbsFromMCSandRB

    fprintf('=== v4 comparison: case %d | N=%d sched=%s | T=%d, seeds=%d, eval traces=%d ===\n', ...
            caseId, env.N, env.scheduler, simTime, n_seeds, n_eval);

    % ---------------- training (multi-seed) ----------------
    QLs = cell(1, n_seeds); ACs = cell(1, n_seeds); A2Cs = cell(1, n_seeds);
    lc_ql = zeros(ep_tab, n_seeds); lc_ac = zeros(ep_tab, n_seeds);
    lc_dac = zeros(ep_deep, n_seeds); ent_dac = zeros(ep_deep, n_seeds);

    for s = 1:n_seeds
        sd = baseSeed + 1000 * s;
        fprintf('[seed %d/%d] Q-Learning ...\n', s, n_seeds); tic;
        [QLs{s}, lc_ql(:, s)] = QL_AMC_Multi_v4(simTime, ep_tab, sd, env);
        fprintf('   %.1f s\n', toc);
        fprintf('[seed %d/%d] Tabular AC ...\n', s, n_seeds); tic;
        [ACs{s}, ~, lc_ac(:, s)] = AC_AMC_Multi_v4(simTime, ep_tab, sd, env);
        fprintf('   %.1f s\n', toc);
        fprintf('[seed %d/%d] Deep A2C ...\n', s, n_seeds); tic;
        [A2Cs{s}, ~, lc_dac(:, s), ent_dac(:, s)] = ...
            DeepA2C_AMC_Multi_v4(simTime, ep_deep, sd, env);
        fprintf('   %.1f s\n', toc);
    end

    % ---------------- held-out evaluation traces ----------------
    traces = struct('SINR', [], 'obsS', [], 'obsC', [], 'dist', []);
    traces(n_eval).SINR = [];
    for j = 1:n_eval
        rng(9000 + j);
        [Strue, dist, ~] = generateChannel_v4(simTime, env);
        [obsS, obsC] = cqiFeedback_v4(Strue, env);
        traces(j).SINR = Strue; traces(j).obsS = obsS;
        traces(j).obsC = obsC;  traces(j).dist = dist;
    end

    schemes = {'Baseline', 'OLLA', 'QL v4', 'Tab AC v4', 'Deep A2C v4'};
    ptypes  = {'baseline', 'olla', 'ql', 'ac', 'a2c'};
    K = numel(schemes);

    % metric(k).x : rows = seeds (1 for baselines), cols = traces
    for sc = 1:numel(eval_scheds)
        envE = env; envE.scheduler = eval_scheds{sc};
        M = init_metrics(K, n_seeds, n_eval);

        for j = 1:n_eval
            for k = 1:K
                if k <= 2, ns = 1; else, ns = n_seeds; end
                for s = 1:ns
                    pol = [];
                    if k == 3, pol = QLs{s};  end
                    if k == 4, pol = ACs{s};  end
                    if k == 5, pol = A2Cs{s}; end
                    rng(77000 + 100*j + 10*k + s);   % reproducible OLLA ACKs
                    [tp, bl, ce] = evalPolicy_v4(ptypes{k}, pol, ...
                        traces(j).SINR, traces(j).obsS, traces(j).obsC, envE);
                    % v4.1: steady-state scoring -- drop the burn-in so OLLA
                    % convergence and PF/EMA transients bias no scheme
                    b0 = min(env.burn_in, size(tp, 1) - 1);
                    tpB = tp(b0+1:end, :); blB = bl(b0+1:end, :);
                    ceB = ce(b0+1:end, :);
                    pu = mean(tpB, 1);                         % per-user mean
                    M.cell_tp{k}(s, j) = sum(pu);
                    M.edge_tp{k}(s, j) = min(pu);
                    served = tpB > 0;
                    if any(served(:)), M.bler{k}(s, j) = mean(blB(served));
                    else,              M.bler{k}(s, j) = NaN; end
                    M.jain{k}(s, j) = sum(pu)^2 / (env.N * max(sum(pu.^2), eps));
                    M.cqie{k}(s, j) = mean(ceB(:));
                    if sc == 1 && s == min(ns, 2)   % keep one tp field for plots
                        M.tp_field{k, j} = tp;
                    end
                end
            end
        end
        allM(sc) = M; %#ok<AGROW>
    end
    M = allM(1);   % primary scheduler

    % ---------------- statistics ----------------
    fprintf('\n--- Case %d, scheduler "%s", mean over %d seeds x %d traces (95%% CI) ---\n', ...
            caseId, eval_scheds{1}, n_seeds, n_eval);
    fprintf('%-13s | %16s | %16s | %9s | %7s | %8s\n', ...
            'Scheme', 'CellTp (Mbps)', 'EdgeTp (Mbps)', 'BLER', 'Jain', 'CQIerr');
    txt = sprintf('v4 results, case %d, scheduler %s, %s\n', caseId, eval_scheds{1}, datestr(now));
    for k = 1:K
        [m1, c1] = mci(M.cell_tp{k}(:)); [m2, c2] = mci(M.edge_tp{k}(:));
        line = sprintf('%-13s | %7.3f +/- %5.3f | %7.3f +/- %5.3f | %9.4f | %7.3f | %8.3f', ...
            schemes{k}, m1, c1, m2, c2, mean(M.bler{k}(:), 'omitnan'), ...
            mean(M.jain{k}(:)), mean(M.cqie{k}(:)));
        fprintf('%s\n', line); txt = [txt line newline]; %#ok<AGROW>
    end

    % Paired Wilcoxon signed-rank: A2C vs baselines, over traces (seed-mean)
    a2c_tr = mean(M.cell_tp{5}, 1);
    pvals = nan(1, 2);
    if exist('signrank', 'file') == 2
        pvals(1) = signrank(a2c_tr, M.cell_tp{1}(1, :));
        pvals(2) = signrank(a2c_tr, M.cell_tp{2}(1, :));
        line = sprintf('Wilcoxon (cell Tp, paired over traces): A2C vs Baseline p=%.4g, A2C vs OLLA p=%.4g', ...
                       pvals(1), pvals(2));
    else
        line = 'signrank unavailable (Statistics Toolbox): report CIs only';
    end
    fprintf('%s\n', line); txt = [txt line newline];

    % Robustness summary across schedulers
    if numel(eval_scheds) > 1
        txt = [txt newline 'Robustness (cell Tp mean by eval scheduler):' newline];
        fprintf('\nRobustness (trained on %s):\n%-13s', env.scheduler, 'Scheme');
        fprintf(' | %8s', eval_scheds{:}); fprintf('\n');
        for k = 1:K
            fprintf('%-13s', schemes{k}); ln = sprintf('%-13s', schemes{k});
            for sc = 1:numel(eval_scheds)
                v = mean(allM(sc).cell_tp{k}(:));
                fprintf(' | %8.3f', v); ln = [ln sprintf(' | %8.3f', v)]; %#ok<AGROW>
            end
            fprintf('\n'); txt = [txt ln newline]; %#ok<AGROW>
        end
    end

    % ---------------- figures ----------------
    plot_kpi_bars(schemes, M, env);
    plot_learning(lc_ql, lc_ac, lc_dac, ent_dac, simTime, env);
    plot_vs_distance(schemes, M, traces, n_eval);
    try
        plotPolicyHeatmap_v4(A2Cs{1}, 'a2c', env);
    catch ME
        warning('heatmap skipped: %s', ME.message);
    end

    % ---------------- save ----------------
    results.caseId = caseId; results.env = env; results.schemes = schemes;
    results.metrics = allM; results.eval_schedulers = eval_scheds;
    results.pvals_a2c_vs_baseline_olla = pvals;
    results.learning.ql = lc_ql; results.learning.ac = lc_ac;
    results.learning.dac = lc_dac; results.entropy.dac = ent_dac;
    results.policies.QL = QLs; results.policies.AC = ACs; results.policies.A2C = A2Cs;
    results.opts = struct('simTime', simTime, 'ep_tab', ep_tab, 'ep_deep', ep_deep, ...
                          'n_seeds', n_seeds, 'n_eval', n_eval, 'base_seed', baseSeed);
    save(fullfile(here, sprintf('results_v4_case%d.mat', caseId)), 'results', '-v7.3');
    fid = fopen(fullfile(here, sprintf('results_v4_case%d.txt', caseId)), 'w');
    fprintf(fid, '%s', txt); fclose(fid);
    fprintf('\nSaved results_v4_case%d.mat / .txt in %s\n', caseId, here);
end


% ======================= helpers =======================

function v = getfield_default(s, f, d)
    if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function M = init_metrics(K, n_seeds, n_eval)
    for k = 1:K
        if k <= 2, ns = 1; else, ns = n_seeds; end
        M.cell_tp{k} = zeros(ns, n_eval); M.edge_tp{k} = zeros(ns, n_eval);
        M.bler{k}    = zeros(ns, n_eval); M.jain{k}    = zeros(ns, n_eval);
        M.cqie{k}    = zeros(ns, n_eval);
    end
    M.tp_field = cell(K, n_eval);
end

function [m, ci] = mci(x)
    x = x(~isnan(x)); n = numel(x);
    m = mean(x);
    if n > 1, ci = 1.96 * std(x) / sqrt(n); else, ci = 0; end
end

function plot_kpi_bars(schemes, M, env)
    K = numel(schemes);
    mt = zeros(1, K); ct = zeros(1, K); mb = zeros(1, K); mj = zeros(1, K);
    for k = 1:K
        [mt(k), ct(k)] = local_mci(M.cell_tp{k}(:));
        mb(k) = mean(M.bler{k}(:), 'omitnan'); mj(k) = mean(M.jain{k}(:));
    end
    figure('Position', [60 60 1150 380], 'Name', 'v4 KPIs');
    subplot(1,3,1); bar(mt); hold on;
    errorbar(1:K, mt, ct, 'k.', 'LineWidth', 1.2);
    set(gca, 'XTickLabel', schemes, 'XTickLabelRotation', 30);
    ylabel('Cell throughput (Mbps)'); title('Throughput (95% CI)'); grid on;
    subplot(1,3,2); bar(mb); hold on; yline(0.1, 'r--', 'target');
    set(gca, 'XTickLabel', schemes, 'XTickLabelRotation', 30);
    ylabel('Mean BLER (served)'); title('BLER'); grid on;
    subplot(1,3,3); bar(mj); ylim([0 1.05]);
    set(gca, 'XTickLabel', schemes, 'XTickLabelRotation', 30);
    ylabel('Jain index'); title(sprintf('Fairness (N=%d)', env.N)); grid on;
end

function [m, ci] = local_mci(x)
    x = x(~isnan(x)); n = numel(x); m = mean(x);
    if n > 1, ci = 1.96 * std(x) / sqrt(n); else, ci = 0; end
end

function plot_learning(lc_ql, lc_ac, lc_dac, ent_dac, simTime, env)
    spe = simTime * env.N;   % env steps per episode
    figure('Position', [60 60 1000 420], 'Name', 'v4 learning curves');
    subplot(1,2,1); hold on; grid on;
    h1 = shaded(spe * (1:size(lc_ql,1)),  lc_ql,  [0.85 0.15 0.15]);
    h2 = shaded(spe * (1:size(lc_ac,1)),  lc_ac,  [0.15 0.30 0.85]);
    h3 = shaded(spe * (1:size(lc_dac,1)), lc_dac, [0.10 0.65 0.20]);
    xlabel('Environment steps'); ylabel('Cell Tp per interval (Mbps)');
    title('Learning curves (mean \pm 1 std over seeds)');
    legend([h1 h2 h3], {'QL', 'Tab AC', 'Deep A2C'}, 'Location', 'best');
    subplot(1,2,2); plot(mean(ent_dac, 2), 'LineWidth', 1.5); grid on;
    xlabel('Episode'); ylabel('Policy entropy (nats)');
    title('A2C policy entropy (convergence diagnostic)');
end

function hline = shaded(x, Y, c)
    mu = mean(Y, 2).'; sd = std(Y, 0, 2).';
    fill([x fliplr(x)], [mu+sd fliplr(mu-sd)], c, 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    hline = plot(x, mu, 'Color', c, 'LineWidth', 1.6);
end

function plot_vs_distance(schemes, M, traces, n_eval)
    K = numel(schemes);
    d_all = [];
    for j = 1:n_eval, d_all = [d_all; traces(j).dist(:)]; end %#ok<AGROW>
    edges = linspace(min(d_all), max(d_all), 26);
    ctr = (edges(1:end-1) + edges(2:end)) / 2;
    cols = {[0 0 0], [0.5 0.5 0.5], [0.85 0.15 0.15], [0.15 0.3 0.85], [0.1 0.65 0.2]};
    figure('Position', [60 60 1000 440], 'Name', 'v4 Tp vs distance');
    hold on; grid on;
    for k = 1:K
        dv = []; tv = [];
        for j = 1:n_eval
            tp = M.tp_field{k, j};
            if isempty(tp), continue; end
            dv = [dv; traces(j).dist(:)]; tv = [tv; tp(:)]; %#ok<AGROW>
        end
        served = tv > 0;
        b = nan(1, numel(ctr));
        for q = 1:numel(ctr)
            in = served & dv >= edges(q) & dv < edges(q+1);
            if any(in), b(q) = mean(tv(in)); end
        end
        plot(ctr, b, '-', 'Color', cols{k}, 'LineWidth', 1.7);
    end
    xlabel('Distance from BS (m)'); ylabel('Served throughput (Mbps)');
    title('Throughput vs distance (held-out traces)');
    legend(schemes, 'Location', 'best');
end
