function generate_figures_v8()
% generate_figures_v8  Build the v8 publication figure set from saved results.
%
% Generates PNG and FIG files into Optimized/v8/figures/ and Docs/figures/v8/
    here = fileparts(mfilename('fullpath'));
    datadir = fullfile(here, 'Dataset');
    figdir1 = fullfile(here, 'figures');
    figdir2 = fullfile(here, '..', '..', 'Docs', 'figures', 'v8');
    if ~exist(figdir1, 'dir'), mkdir(figdir1); end
    if ~exist(figdir2, 'dir'), mkdir(figdir2); end

    fprintf('===== RL-AMC v8 Publication Figure Generation =====\n');

    % Point definitions
    points = {
        'headline',    'Headline (+9dB, Het=1.0)'
        'calm',        'Calm (0dB Burst)'
        'burst12dB',   'Severe Burst (+12dB)'
        'tierA',       'Tier-A State Ablation'
        'steady1000',  'Steady-State (1000 TTI)'
    };

    R = struct();
    ok = false(size(points, 1), 1);
    for i = 1:size(points, 1)
        f = fullfile(datadir, sprintf('results_v8_%s.mat', points{i, 1}));
        if exist(f, 'file')
            L = load(f, 'results');
            R.(points{i, 1}) = L.results;
            ok(i) = true;
            fprintf('  [loaded] %s\n', f);
        else
            fprintf('  [skip] %s not found\n', f);
        end
    end

    if ~isfield(R, 'headline')
        warning('Headline results not found. Aborting figure generation.');
        return;
    end

    hl = R.headline;
    M_pf = hl.metrics(1);
    schemes = hl.schemes;
    K = numel(schemes);

    % Color palette (Publication-ready)
    c_blue   = [0.12, 0.47, 0.71];
    c_orange = [1.00, 0.50, 0.05];
    c_green  = [0.17, 0.63, 0.17];
    c_red    = [0.84, 0.15, 0.16];
    c_purple = [0.58, 0.40, 0.74];
    c_gray   = [0.50, 0.50, 0.50];

    % -------------------------------------------------------------
    % Fig 1: Cell Throughput Comparison (PF Scheduler)
    % -------------------------------------------------------------
    fprintf('-- Generating Fig 1: Cell Throughput Comparison --\n');
    f1 = figure('Position', [100, 100, 800, 480], 'Visible', 'off');
    tp_means = zeros(1, K);
    tp_errs  = zeros(1, K);
    N_eval = size(M_pf.cell_tp{1}, 2);
    for k = 1:K
        if k <= 7
            v = M_pf.cell_tp{k}(1, :);
        else
            v = mean(M_pf.cell_tp{k}, 1);
        end
        tp_means(k) = mean(v);
        tp_errs(k)  = 1.96 * std(v) / sqrt(N_eval);
    end

    b = bar(tp_means, 'FaceColor', 'flat', 'EdgeColor', 'none', 'BarWidth', 0.65);
    for k = 1:K
        if k == 8
            b.CData(k, :) = c_blue;
        elseif k == 7
            b.CData(k, :) = c_orange;
        elseif k == 4
            b.CData(k, :) = c_green;
        else
            b.CData(k, :) = c_gray;
        end
    end
    hold on;
    errorbar(1:K, tp_means, tp_errs, 'k.', 'LineWidth', 1.5, 'CapSize', 8);
    set(gca, 'XTick', 1:K, 'XTickLabel', schemes, 'XTickLabelRotation', 25, 'FontSize', 10);
    ylabel('Cell Throughput (Mbps)', 'FontSize', 12, 'FontWeight', 'bold');
    title('RL-AMC v8: Cell Throughput Comparison (PF Scheduler, 3GPP Macrocell)', 'FontSize', 12);
    grid on; box on; ylim([0, max(tp_means + tp_errs) * 1.25]);
    for k = 1:K
        text(k, tp_means(k) + tp_errs(k) + 0.1, sprintf('%.2f', tp_means(k)), ...
             'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
    end
    save_fig_dual(f1, 'fig1_v8_cell_throughput', figdir1, figdir2);
    close(f1);

    % -------------------------------------------------------------
    % Fig 2: Burst vs. Calm Adaptation Advantage
    % -------------------------------------------------------------
    fprintf('-- Generating Fig 2: Burst vs. Calm Adaptation Advantage --\n');
    f2 = figure('Position', [150, 150, 850, 480], 'Visible', 'off');
    burst_vals = zeros(1, K);
    calm_vals  = zeros(1, K);
    for k = 1:K
        burst_vals(k) = nanmean(M_pf.tp_burst{k}(:));
        calm_vals(k)  = nanmean(M_pf.tp_calm{k}(:));
    end
    bar_data = [burst_vals; calm_vals]';
    b2 = bar(bar_data, 0.75);
    b2(1).FaceColor = c_red;
    b2(2).FaceColor = c_blue;
    set(gca, 'XTick', 1:K, 'XTickLabel', schemes, 'XTickLabelRotation', 25, 'FontSize', 10);
    ylabel('Throughput (Mbps)', 'FontSize', 12, 'FontWeight', 'bold');
    title('Throughput Under Markov Non-Stationarity: Interference Burst vs. Calm', 'FontSize', 12);
    legend({'Burst (+9 dB)', 'Calm State'}, 'Location', 'northwest', 'FontSize', 11);
    grid on; box on;
    save_fig_dual(f2, 'fig2_v8_burst_adaptation', figdir1, figdir2);
    close(f2);

    % -------------------------------------------------------------
    % Fig 3: User Fairness & Cell-Edge Throughput
    % -------------------------------------------------------------
    fprintf('-- Generating Fig 3: User Fairness & Cell-Edge Throughput --\n');
    f3 = figure('Position', [200, 200, 850, 480], 'Visible', 'off');
    jains = zeros(1, K);
    edges = zeros(1, K);
    for k = 1:K
        jains(k) = nanmean(M_pf.jain{k}(:));
        edges(k) = nanmean(M_pf.edge_tp{k}(:));
    end
    yyaxis left
    b3 = bar(jains, 0.5, 'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'none');
    ylabel('Jain Fairness Index', 'FontSize', 12, 'FontWeight', 'bold');
    ylim([0, 1.05]);
    yyaxis right
    p3 = plot(1:K, edges, 'r-s', 'LineWidth', 2.2, 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    ylabel('5th-Percentile Cell-Edge Tp (Mbps)', 'FontSize', 12, 'FontWeight', 'bold');
    set(gca, 'XTick', 1:K, 'XTickLabel', schemes, 'XTickLabelRotation', 25, 'FontSize', 10);
    title('Fairness and Edge Connectivity Under Doppler & Delay Heterogeneity', 'FontSize', 12);
    legend({'Jain Index (Left)', 'Cell-Edge Tp (Right)'}, 'Location', 'northwest', 'FontSize', 11);
    grid on; box on;
    save_fig_dual(f3, 'fig3_v8_fairness_edge', figdir1, figdir2);
    close(f3);

    % -------------------------------------------------------------
    % Fig 4: TOST Equivalence & Wilcoxon Significance Plot
    % -------------------------------------------------------------
    fprintf('-- Generating Fig 4: TOST Equivalence Forest Plot --\n');
    f4 = figure('Position', [250, 250, 850, 480], 'Visible', 'off');
    tp_a2c = mean(M_pf.cell_tp{8}, 1);
    diff_means = zeros(7, 1);
    diff_cis   = zeros(7, 1);
    eq_margin  = 0.10; % +/- 0.10 Mbps
    for k = 1:7
        tp_k = M_pf.cell_tp{k}(1, :);
        d = tp_a2c - tp_k;
        diff_means(k) = mean(d);
        diff_cis(k)   = 1.96 * std(d) / sqrt(numel(d));
    end
    y_pos = 7:-1:1;
    hold on;
    fill([-eq_margin, eq_margin, eq_margin, -eq_margin], [0, 0, 8, 8], ...
         [0.9, 0.95, 0.9], 'EdgeColor', 'none', 'DisplayName', 'Equivalence Bound (\pm 0.10 Mbps)');
    plot([0, 0], [0, 8], 'k--', 'LineWidth', 1.2, 'DisplayName', 'Zero Difference');
    errorbar(diff_means, y_pos, diff_cis, 'horizontal', 'ko', 'LineWidth', 1.8, ...
             'MarkerSize', 7, 'MarkerFaceColor', c_blue, 'CapSize', 6, 'DisplayName', 'Mean Difference (95% CI)');
    set(gca, 'YTick', 1:7, 'YTickLabel', flip(schemes(1:7)), 'FontSize', 10);
    xlabel('\Delta Throughput: Deep A2C v8 - Comparator (Mbps)', 'FontSize', 12, 'FontWeight', 'bold');
    title('TOST Statistical Equivalence & Superiority Forest Plot', 'FontSize', 12);
    legend('Location', 'southeast', 'FontSize', 10);
    grid on; box on; xlim([-0.6, 0.8]); ylim([0.5, 7.5]);
    save_fig_dual(f4, 'fig4_v8_tost_forest', figdir1, figdir2);
    close(f4);

    % -------------------------------------------------------------
    % Fig 5: Autonomous Learning Curves (Zero BC)
    % -------------------------------------------------------------
    fprintf('-- Generating Fig 5: Autonomous Learning Curves --\n');
    f5 = figure('Position', [300, 300, 850, 450], 'Visible', 'off');
    lc  = hl.learning_curves;
    ent = hl.entropy_curves;
    ep  = 1:size(lc, 1);
    yyaxis left
    plot(ep, mean(lc, 2), 'b-', 'LineWidth', 2.2);
    ylabel('Cell Throughput (Mbps)', 'FontSize', 12, 'FontWeight', 'bold');
    yyaxis right
    plot(ep, mean(ent, 2), 'm--', 'LineWidth', 2.0);
    ylabel('Policy Entropy (nats)', 'FontSize', 12, 'FontWeight', 'bold');
    xlabel('Autonomous Training Episode (Zero BC)', 'FontSize', 12, 'FontWeight', 'bold');
    title('Deep A2C v8 Autonomous Training Progression from Random Weights', 'FontSize', 12);
    legend({'Reward / Throughput (Left)', 'Entropy Annealing (Right)'}, 'Location', 'east', 'FontSize', 11);
    grid on; box on;
    save_fig_dual(f5, 'fig5_v8_learning_entropy', figdir1, figdir2);
    close(f5);

    % -------------------------------------------------------------
    % Fig 6: 3GPP 15-CQI AWGN Waterfall Curves
    % -------------------------------------------------------------
    fprintf('-- Generating Fig 6: 3GPP 15-CQI Waterfall Curves --\n');
    f6 = figure('Position', [350, 350, 850, 480], 'Visible', 'off');
    sinr_axis = -10:0.2:25;
    env_mock = defaultEnv_v8(23, 10);
    hold on;
    cm = parula(15);
    for q = 1:15
        bl = arrayfun(@(s) estimateBLER_v8(s, q), sinr_axis);
        plot(sinr_axis, bl, 'LineWidth', 1.8, 'Color', cm(q, :), 'DisplayName', sprintf('CQI %d', q));
    end
    plot([-10, 25], [0.10, 0.10], 'r--', 'LineWidth', 1.5, 'DisplayName', 'Target BLER (10%)');
    ylim([0, 1.05]); xlim([-10, 25]);
    xlabel('Effective SINR \gamma_{eff} (dB)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('Block Error Rate (BLER)', 'FontSize', 12, 'FontWeight', 'bold');
    title('3GPP TS 36.213 Standard Sigmoidal BLER Waterfalls (15 CQIs, 10% Anchor)', 'FontSize', 12);
    legend('NumColumns', 4, 'Location', 'east', 'FontSize', 8);
    grid on; box on;
    save_fig_dual(f6, 'fig6_v8_bler_waterfalls', figdir1, figdir2);
    close(f6);

    fprintf('===== All v8 Figures Successfully Generated! =====\n');
end

function save_fig_dual(hFig, baseName, dir1, dir2)
    exportgraphics(hFig, fullfile(dir1, [baseName, '.png']), 'Resolution', 300);
    savefig(hFig, fullfile(dir1, [baseName, '.fig']));
    exportgraphics(hFig, fullfile(dir2, [baseName, '.png']), 'Resolution', 300);
    savefig(hFig, fullfile(dir2, [baseName, '.fig']));
end
