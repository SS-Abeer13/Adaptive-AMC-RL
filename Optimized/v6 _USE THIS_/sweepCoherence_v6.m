function sweepCoherence_v6(rhos, delays, opts)
% sweepCoherence_v6  Sweeps channel coherence time (fading correlation rho) vs. CQI delay.
%
%   sweepCoherence_v6()
%   sweepCoherence_v6([0.80, 0.90, 0.95, 0.98], [4, 6], struct('n_seeds', 3, 'n_eval', 20))

    if nargin < 1 || isempty(rhos),   rhos = [0.80, 0.90, 0.95, 0.98]; end
    if nargin < 2 || isempty(delays), delays = [4, 6]; end
    if nargin < 3, opts = struct(); end
    if ~isfield(opts, 'n_seeds'), opts.n_seeds = 3; end
    if ~isfield(opts, 'n_eval'),  opts.n_eval = 20; end
    if ~isfield(opts, 'N'),       opts.N = 10; end

    nR = numel(rhos);
    nD = numel(delays);
    
    % Store cell throughputs for Baseline (1), OLLA (2), and Deep A2C (5)
    cellTp = zeros(nR, nD, 3); 
    
    for di = 1:nD
        d = delays(di);
        for ri = 1:nR
            r = rhos(ri);
            fprintf('\n##### sweepCoherence_v6: delay=%d, rho=%.2f #####\n', d, r);
            o = opts;
            o.cqi_delay = d;
            o.rho_fading = r;
            o.tag = sprintf('rho%s_d%d', strrep(sprintf('%.2f', r), '.', 'p'), d);

            res = runComparison_v6(23, o);
            M = res.metrics(1); % PF scheduler
            
            cellTp(ri, di, 1) = mean(M.cell_tp{1}(:)); % Baseline
            cellTp(ri, di, 2) = mean(M.cell_tp{2}(:)); % OLLA
            cellTp(ri, di, 3) = mean(M.cell_tp{5}(:)); % Deep A2C
        end
    end
    
    % Save data (collision-proof: never overwrite an existing summary)
    here = fileparts(mfilename('fullpath'));
    outdir = here;
    if exist(fullfile(here,'Dataset'), 'dir'), outdir = fullfile(here,'Dataset'); end
    sp = fullfile(outdir, 'sweepCoherence_v6_results.mat');
    if exist(sp, 'file')
        sp = fullfile(outdir, sprintf('sweepCoherence_v6_results_%s.mat', datestr(now,'yyyymmdd_HHMMSS')));
    end
    save(sp, 'rhos', 'delays', 'cellTp');
    fprintf('  Saved: %s\n', sp);
    
    % Plotting
    cols = {[0 0 0], [0.5 0.5 0.5], [0.10 0.65 0.20]}; % Baseline (black), OLLA (grey), A2C (green)
    styles = {'--d', '-.s', '-o'};
    
    figure('Color','w','Position',[100 100 1100 500],'Name','v6 Coherence vs. Delay Sweep');
    for di = 1:nD
        subplot(1, nD, di); hold on; grid on;
        for k = 1:3
            plot(rhos, cellTp(:, di, k), styles{k}, 'Color', cols{k}, 'LineWidth', 1.8, 'MarkerSize', 6);
        end
        xlabel('Fading Correlation (\rho)', 'FontSize', 10);
        ylabel('Cell Throughput (Mbps)', 'FontSize', 10);
        title(sprintf('CQI Delay = %d TTIs', delays(di)), 'FontSize', 11);
        if di == 1
            legend({'Baseline', 'OLLA', 'Deep A2C v6'}, 'Location', 'northwest', 'FontSize', 9);
        end
    end
    sgtitle(sprintf('v6 Coherence Sweep: Throughput vs. Fading Correlation (N=%d)', opts.N), 'FontWeight', 'bold', 'FontSize', 13);
    
    % Print table
    fprintf('\n======================================================================\n');
    fprintf('  SUMMARY: Coherence vs. Delay Sweep (PF, N=%d)\n', opts.N);
    fprintf('----------------------------------------------------------------------\n');
    for di = 1:nD
        fprintf('  Delay = %d TTIs:\n', delays(di));
        for ri = 1:nR
            margin = cellTp(ri, di, 3) - cellTp(ri, di, 2);
            pct_margin = 100 * margin / max(cellTp(ri, di, 2), eps);
            fprintf('    rho = %.2f | BL: %5.2f | OLLA: %5.2f | A2C: %5.2f Mbps | Margin: %+5.2f Mbps (%+5.1f%%)\n', ...
                    rhos(ri), cellTp(ri, di, 1), cellTp(ri, di, 2), cellTp(ri, di, 3), margin, pct_margin);
        end
    end
    fprintf('======================================================================\n\n');
end
