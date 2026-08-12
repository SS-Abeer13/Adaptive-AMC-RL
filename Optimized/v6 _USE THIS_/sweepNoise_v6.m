function sweepNoise_v6(noises, opts)
% sweepNoise_v6  Evaluates noise resilience by sweeping measurement noise standard deviation.
%
%   sweepNoise_v6()
%   sweepNoise_v6([0.0, 0.5, 1.0, 2.0, 3.0], struct('n_seeds', 3, 'n_eval', 20))

    if nargin < 1 || isempty(noises), noises = [0.0, 0.5, 1.0, 2.0, 3.0]; end
    if nargin < 2, opts = struct(); end
    if ~isfield(opts, 'n_seeds'), opts.n_seeds = 3; end
    if ~isfield(opts, 'n_eval'),  opts.n_eval = 20; end
    if ~isfield(opts, 'N'),       opts.N = 10; end
    if ~isfield(opts, 'cqi_delay'), opts.cqi_delay = 4; end

    nN = numel(noises);
    schemes = {'Baseline', 'OLLA', 'QL v6', 'Tab AC v6', 'Deep A2C v6'};
    K = numel(schemes);
    
    cellTp = zeros(nN, K);
    bler = zeros(nN, K);
    p_olla = nan(nN, 1); p_base = nan(nN, 1);

    for ni = 1:nN
        noise = noises(ni);
        fprintf('\n##### sweepNoise_v6: sigma_meas = %.2f dB #####\n', noise);
        o = opts;
        o.sigma_meas = noise;
        o.tag = sprintf('noise%s', strrep(sprintf('%.1f', noise), '.', 'p'));

        res = runComparison_v6(23, o);
        M = res.metrics(1); % PF scheduler

        for k = 1:K
            cellTp(ni, k) = mean(M.cell_tp{k}(:));
            bler(ni, k) = mean(M.bler{k}(:), 'omitnan');
        end
        p_base(ni) = res.pvals_a2c_vs_baseline_olla(1);
        p_olla(ni) = res.pvals_a2c_vs_baseline_olla(2);
    end

    % Save data (collision-proof: never overwrite an existing summary)
    here = fileparts(mfilename('fullpath'));
    outdir = here;
    if exist(fullfile(here,'Dataset'), 'dir'), outdir = fullfile(here,'Dataset'); end
    sp = fullfile(outdir, 'sweepNoise_v6_results.mat');
    if exist(sp, 'file')
        sp = fullfile(outdir, sprintf('sweepNoise_v6_results_%s.mat', datestr(now,'yyyymmdd_HHMMSS')));
    end
    save(sp, 'noises', 'cellTp', 'bler', 'p_base', 'p_olla');
    fprintf('  Saved: %s\n', sp);
    
    % Plotting
    cols = {[0 0 0], [0.5 0.5 0.5], [0.85 0.15 0.15], [0.15 0.3 0.85], [0.10 0.65 0.20]};
    styles = {'--o', '-.s', '-^', '-d', '-o'};
    
    figure('Color','w','Position',[100 100 1100 450],'Name','v6 Noise Resilience Sweep');
    
    subplot(1, 2, 1); hold on; grid on;
    for k = 1:K
        plot(noises, cellTp(:, k), styles{k}, 'Color', cols{k}, 'LineWidth', 1.8, 'MarkerSize', 6);
    end
    xlabel('Measurement Noise \sigma_{meas} (dB)', 'FontSize', 10);
    ylabel('Cell Throughput (Mbps)', 'FontSize', 10);
    title('Cell Throughput vs. CQI Measurement Noise', 'FontSize', 11);
    legend(schemes, 'Location', 'southwest', 'FontSize', 9);
    
    subplot(1, 2, 2); hold on; grid on;
    for k = 1:K
        plot(noises, bler(:, k), styles{k}, 'Color', cols{k}, 'LineWidth', 1.8, 'MarkerSize', 6);
    end
    yline(0.1, 'k--', 'target', 'LineWidth', 1.1);
    xlabel('Measurement Noise \sigma_{meas} (dB)', 'FontSize', 10);
    ylabel('Realized BLER', 'FontSize', 10);
    ylim([0 1]);
    title('Realized BLER vs. CQI Measurement Noise', 'FontSize', 11);
    
    sgtitle(sprintf('v6 Noise Resilience Sweep (N=%d, delay=%d)', opts.N, opts.cqi_delay), 'FontWeight', 'bold', 'FontSize', 13);
    
    % Print summary
    fprintf('\n======================================================================\n');
    fprintf('  SUMMARY: Noise Resilience Sweep (PF, N=%d, delay=%d)\n', opts.N, opts.cqi_delay);
    fprintf('----------------------------------------------------------------------\n');
    for ni = 1:nN
        margin = cellTp(ni, 5) - cellTp(ni, 2);
        pct_margin = 100 * margin / max(cellTp(ni, 2), eps);
        fprintf('  Noise = %.1f dB | OLLA: %5.2f | A2C: %5.2f Mbps | Margin: %+5.2f Mbps (%+5.1f%%) | A2C BLER: %.3f\n', ...
                noises(ni), cellTp(ni, 2), cellTp(ni, 5), margin, pct_margin, bler(ni, 5));
    end
    fprintf('======================================================================\n\n');
end
