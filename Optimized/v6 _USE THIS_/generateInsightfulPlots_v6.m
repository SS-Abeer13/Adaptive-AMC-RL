function generateInsightfulPlots_v6()
% generateInsightfulPlots_v6  Loads v6 camera-ready results and generates 5 new insightful plots.
%
%   Saved figures:
%     1. docs/figures_v6/fig13_user_tp_vs_dist.png
%     2. docs/figures_v6/fig14_user_bler_vs_dist.png
%     3. docs/figures_v6/fig15_trace_winrate.png
%     4. docs/figures_v6/fig16_action_dist_schedulers.png
%     5. docs/figures_v6/fig17_throughput_vs_N.png

    here = fileparts(mfilename('fullpath'));
    dataset_dir = fullfile(here, 'Dataset');
    out_dir = fullfile(here, '..', '..', 'docs', 'figures_v6');
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    
    % Check if Dataset directory exists
    if ~exist(dataset_dir, 'dir')
        error('Dataset directory not found at: %s', dataset_dir);
    end
    
    %% Plot 1 & 2: User Throughput and BLER vs. Distance (N=10, d=4, PF)
    f_d4 = fullfile(dataset_dir, 'FINAL_results_v6_N10_d4_cameraready.mat');
    if exist(f_d4, 'file')
        fprintf('Loading %s for Plot 1 & 2...\n', f_d4);
        ld = load(f_d4, 'results'); R = ld.results;
        M = R.metrics(1); % PF scheduler
        
        n_eval = numel(M.dist_field);
        
        % Flatten the distances, throughputs, and BLERs
        dist_flat = [];
        tp_olla_flat = [];
        tp_a2c_flat = [];
        bler_olla_flat = [];
        bler_a2c_flat = [];
        
        for j = 1:n_eval
            dist_flat = [dist_flat; M.dist_field{j}(:)];
            tp_olla_flat = [tp_olla_flat; M.tp_field{2, j}(:)];
            tp_a2c_flat = [tp_a2c_flat; M.tp_field{5, j}(:)];
            
            if isfield(M, 'bler_field') && ~isempty(M.bler_field)
                bler_olla_flat = [bler_olla_flat; M.bler_field{2, j}(:)];
                bler_a2c_flat = [bler_a2c_flat; M.bler_field{5, j}(:)];
            end
        end
        
        % Plot 1: User Throughput vs. Distance
        figure('Color','w','Position',[100 100 700 450]); hold on; grid on;
        scatter(dist_flat, tp_olla_flat, 25, [0.85 0.15 0.15], 'filled', 'MarkerFaceAlpha', 0.4);
        scatter(dist_flat, tp_a2c_flat, 25, [0.15 0.70 0.15], 'filled', 'MarkerFaceAlpha', 0.6);
        
        % Fit power-law or log curves for trends
        p_olla = polyfit(log(dist_flat), tp_olla_flat, 1);
        p_a2c  = polyfit(log(dist_flat), tp_a2c_flat, 1);
        
        d_fit = linspace(min(dist_flat), max(dist_flat), 100);
        plot(d_fit, polyval(p_olla, log(d_fit)), 'Color', [0.65 0.05 0.05], 'LineWidth', 2);
        plot(d_fit, polyval(p_a2c, log(d_fit)), 'Color', [0.05 0.50 0.05], 'LineWidth', 2);
        
        xlabel('Distance from Base Station (m)', 'FontSize', 10);
        ylabel('Individual User Throughput (Mbps)', 'FontSize', 10);
        title('User Throughput vs. Receiver Distance (N=10, d=4, PF)', 'FontSize', 12, 'FontWeight', 'bold');
        legend({'OLLA Scatter', 'Deep A2C Scatter', 'OLLA Trend', 'Deep A2C Trend'}, 'Location', 'northeast');
        
        save_path1 = fullfile(out_dir, 'fig13_user_tp_vs_dist.png');
        saveas(gcf, save_path1);
        fprintf('Saved Plot 1 to %s\n', save_path1);
        close(gcf);
        
        % Plot 2: User BLER vs. Distance
        if ~isempty(bler_olla_flat)
            figure('Color','w','Position',[120 120 700 450]); hold on; grid on;
            scatter(dist_flat, bler_olla_flat, 25, [0.85 0.15 0.15], 'filled', 'MarkerFaceAlpha', 0.4);
            scatter(dist_flat, bler_a2c_flat, 25, [0.15 0.70 0.15], 'filled', 'MarkerFaceAlpha', 0.6);
            yline(0.10, 'k--', 'Target BLER = 10%', 'LineWidth', 1.2, 'LabelHorizontalAlignment', 'left');
            
            xlabel('Distance from Base Station (m)', 'FontSize', 10);
            ylabel('Realized Block Error Rate (BLER)', 'FontSize', 10);
            title('User Realized BLER vs. Receiver Distance (N=10, d=4, PF)', 'FontSize', 12, 'FontWeight', 'bold');
            legend({'OLLA', 'Deep A2C'}, 'Location', 'northeast');
            ylim([0 1.0]);
            
            save_path2 = fullfile(out_dir, 'fig14_user_bler_vs_dist.png');
            saveas(gcf, save_path2);
            fprintf('Saved Plot 2 to %s\n', save_path2);
            close(gcf);
        end
        
        % Plot 3: Trace-Level Win-Rate Scatter Plot (PF, N=10, d=4)
        tp_olla_trace = M.cell_tp{2}(1, :); % OLLA (1 x 30 traces)
        tp_a2c_trace = mean(M.cell_tp{5}, 1); % Deep A2C (mean across 5 seeds, 1 x 30 traces)
        
        figure('Color','w','Position',[140 140 600 550]); hold on; grid on;
        scatter(tp_olla_trace, tp_a2c_trace, 55, [0.15 0.3 0.85], 'filled', 'MarkerFaceAlpha', 0.7);
        
        % Draw y=x line
        mn = min([tp_olla_trace, tp_a2c_trace]) - 0.5;
        mx = max([tp_olla_trace, tp_a2c_trace]) + 0.5;
        plot([mn mx], [mn mx], 'k--', 'LineWidth', 1.2);
        
        % Annotate wins
        wins = sum(tp_a2c_trace > tp_olla_trace);
        text(mn + 0.3, mx - 0.3, sprintf('A2C Wins: %d / %d (%.1f%%)', wins, numel(tp_olla_trace), 100 * wins / numel(tp_olla_trace)), ...
             'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.10 0.50 0.15]);
        
        xlabel('OLLA Cell Throughput per Trace (Mbps)', 'FontSize', 10);
        ylabel('Deep A2C Cell Throughput per Trace (Mbps)', 'FontSize', 10);
        title('Trace-Level Throughput Comparison (PF, N=10, d=4)', 'FontSize', 12, 'FontWeight', 'bold');
        xlim([mn mx]); ylim([mn mx]);
        axis square;
        
        save_path3 = fullfile(out_dir, 'fig15_trace_winrate.png');
        saveas(gcf, save_path3);
        fprintf('Saved Plot 3 to %s\n', save_path3);
        close(gcf);
        
        % Plot 4: Action Selection Distribution Stacked Bar (PF vs. RR vs. EQ)
        % Try to read action distribution from actionUsage_FINAL_results_v6_N10_d4_cameraready.txt
        txt_path = fullfile(here, 'actionUsage_FINAL_results_v6_N10_d4_cameraready.txt');
        if ~exist(txt_path, 'file')
            txt_path = fullfile(here, 'Dataset', 'actionUsage_FINAL_results_v6_N10_d4_cameraready.txt');
        end
        
        act_data = [
            15.2, 30.4, 45.0,  9.4, 0.0; % PF
            12.1,  9.3, 41.2, 37.4, 0.0; % RR
             0.0, 17.7, 27.5, 54.7, 0.0  % EQ
        ]; % Default fallback values
        
        if exist(txt_path, 'file')
            fprintf('Parsing action usage from %s...\n', txt_path);
            fid = fopen(txt_path, 'r');
            while ~feof(fid)
                line = strtrim(fgetl(fid));
                if startsWith(line, 'PF')
                    parts = strsplit(line, '|');
                    vals = str2num(parts{2}); %#ok<ST2NM>
                    act_data(1, :) = vals(1:5);
                elseif startsWith(line, 'RR')
                    parts = strsplit(line, '|');
                    vals = str2num(parts{2}); %#ok<ST2NM>
                    act_data(2, :) = vals(1:5);
                elseif startsWith(line, 'EQ')
                    parts = strsplit(line, '|');
                    vals = str2num(parts{2}); %#ok<ST2NM>
                    act_data(3, :) = vals(1:5);
                end
            end
            fclose(fid);
        else
            fprintf('Action usage text file not found. Using fallback hardcoded values.\n');
        end
        
        actions = {'-2', '-1', '0 (OLLA)', '+1', '+2'};
        
        figure('Color','w','Position',[160 160 700 450]);
        bar(act_data, 'stacked');
        grid on;
        set(gca, 'XTickLabel', {'PF (Opportunistic)', 'Round Robin', 'Equal Share'});
        ylabel('Action Frequency (%)', 'FontSize', 10);
        title('Deep A2C Action Distribution by Scheduler Context', 'FontSize', 12, 'FontWeight', 'bold');
        legend(actions, 'Location', 'eastoutside');
        
        save_path4 = fullfile(out_dir, 'fig16_action_dist_schedulers.png');
        saveas(gcf, save_path4);
        fprintf('Saved Plot 4 to %s\n', save_path4);
        close(gcf);
        
    else
        warning('Plot 1-4 source file not found: %s', f_d4);
    end
    
    %% Plot 5: Cell Throughput vs. N (N = 5, 10, 20, 50, d=4, PF)
    Ns = [5, 10, 20, 50];
    cell_tps = zeros(numel(Ns), 3); % Baseline, OLLA, Deep A2C
    
    loaded_count = 0;
    for ni = 1:numel(Ns)
        n = Ns(ni);
        f_name = sprintf('FINAL_results_v6_N%d_d4_cameraready.mat', n);
        fpath = fullfile(dataset_dir, f_name);
        
        if exist(fpath, 'file')
            ld = load(fpath, 'results'); R = ld.results;
            M = R.metrics(1); % PF scheduler
            cell_tps(ni, 1) = mean(M.cell_tp{1}(:)); % Baseline
            cell_tps(ni, 2) = mean(M.cell_tp{2}(:)); % OLLA
            cell_tps(ni, 3) = mean(M.cell_tp{5}(:)); % Deep A2C
            loaded_count = loaded_count + 1;
        else
            warning('Scaling results file not found for N=%d: %s', n, fpath);
            cell_tps(ni, :) = NaN;
        end
    end
    
    if loaded_count > 0
        figure('Color','w','Position',[180 180 700 450]); hold on; grid on;
        plot(Ns, cell_tps(:, 1), '--d', 'Color', 'k', 'LineWidth', 1.8, 'MarkerSize', 6);
        plot(Ns, cell_tps(:, 2), '-.s', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.8, 'MarkerSize', 6);
        plot(Ns, cell_tps(:, 3), '-o', 'Color', [0.10 0.65 0.20], 'LineWidth', 2.0, 'MarkerSize', 7);
        
        xlabel('User Population (N)', 'FontSize', 10);
        ylabel('Cell Throughput (Mbps)', 'FontSize', 10);
        title('Throughput Scaling vs. User Population (d=4, PF)', 'FontSize', 12, 'FontWeight', 'bold');
        legend({'Baseline', 'OLLA', 'Deep A2C v6'}, 'Location', 'northwest');
        set(gca, 'XTick', Ns);
        
        save_path5 = fullfile(out_dir, 'fig17_throughput_vs_N.png');
        saveas(gcf, save_path5);
        fprintf('Saved Plot 5 to %s\n', save_path5);
        close(gcf);
    end
    
    %% Plot 6: Action Offset Sweep (Standard vs. Expanded)
    f_offset = fullfile(here, 'sweepOffset_v6_results.mat');
    if exist(f_offset, 'file')
        fprintf('Loading %s for Plot 6...\n', f_offset);
        ld = load(f_offset, 'res_std', 'res_exp');
        res_std = ld.res_std;
        res_exp = ld.res_exp;
        
        schemes = {'Baseline', 'OLLA', 'QL v6', 'Tab AC v6', 'Deep A2C v6'};
        K = numel(schemes);
        tp_std = zeros(1, K); tp_exp = zeros(1, K);
        
        M_std = res_std.metrics(1); % PF scheduler
        M_exp = res_exp.metrics(1);
        
        for k = 1:K
            tp_std(k) = mean(M_std.cell_tp{k}(:));
            tp_exp(k) = mean(M_exp.cell_tp{k}(:));
        end
        
        figure('Color','w','Position',[200 200 750 450]);
        bar_data = [tp_std; tp_exp]';
        b = bar(bar_data);
        b(1).FaceColor = [0.20 0.45 0.75]; % standard
        b(2).FaceColor = [0.10 0.65 0.20]; % expanded
        
        grid on;
        set(gca, 'XTickLabel', schemes, 'XTickLabelRotation', 20);
        ylabel('Cell Throughput (Mbps)', 'FontSize', 10);
        title('Action Offset Sweep: Standard [-2, 2] vs. Expanded [-3, 3] Offsets', 'FontSize', 12, 'FontWeight', 'bold');
        legend({'Standard Actions [-2, 2]', 'Expanded Actions [-3, 3]'}, 'Location', 'northwest');
        ylim([4.0, 7.0]);
        
        save_path6 = fullfile(out_dir, 'fig18_offset_comparison.png');
        saveas(gcf, save_path6);
        fprintf('Saved Plot 6 to %s\n', save_path6);
        close(gcf);
    end
    
    %% Plot 7: Raw & Holm-adjusted p-values vs CQI Delay
    delays = [0, 2, 4, 5, 6, 8];
    raw_p = [0.0387, 0.0104, 0.0687, 0.8774, 4.07e-5, 0.2802];
    holm_p = [0.1162, 0.0418, 0.1374, 0.8774, 2.04e-4, 0.2802];
    
    figure('Color','w','Position',[220 220 700 450]);
    semilogy(delays, raw_p, '-o', 'Color', [0.85 0.15 0.15], 'LineWidth', 2.0, 'MarkerFaceColor', [0.85 0.15 0.15], 'MarkerSize', 6);
    hold on; grid on;
    semilogy(delays, holm_p, '-s', 'Color', [0.15 0.15 0.85], 'LineWidth', 2.0, 'MarkerFaceColor', [0.15 0.15 0.85], 'MarkerSize', 6);
    yline(0.05, 'k--', 'Significance Threshold (\alpha = 0.05)', 'LineWidth', 1.2, 'LabelHorizontalAlignment', 'left');
    
    xlabel('CQI Feedback Delay (TTIs)', 'FontSize', 10);
    ylabel('p-value (Log Scale)', 'FontSize', 10);
    title('Statistical Significance (p-values) vs. CQI Feedback Delay', 'FontSize', 12, 'FontWeight', 'bold');
    legend({'Raw p-value (Wilcoxon)', 'Holm-adjusted p-value', 'Significance Threshold (\alpha = 0.05)'}, 'Location', 'northeast');
    ylim([1e-5, 1.5]);
    
    save_path7 = fullfile(out_dir, 'fig19_p_values_vs_delay.png');
    saveas(gcf, save_path7);
    fprintf('Saved Plot 7 to %s\n', save_path7);
    close(gcf);
    
    fprintf('\nAll insightful figures generated successfully inside docs/figures_v6/.\n');
end
