function S = sweepDelay_v6(delays, caseId, opts)
% sweepDelay_v6  Headline figure: A2C margin over Baseline / OLLA vs CQI delay.
%   S = sweepDelay_v6();                          % delays [0 2 4 6 8], case 23
%   S = sweepDelay_v6([0 2 4 6 8], 23, struct('N',10,'n_seeds',3));
%
% Mechanism hypothesis: OLLA is reactive (a scalar per user, corrects the
% AVERAGE bias) so its performance should be ~flat in delay; the RL agents
% see the SINR trend and the OLLA-offset state, so their margin over OLLA
% should widen as the CQI ages. Each point re-runs the full multi-seed
% train + held-out eval (slow; reduce n_seeds/ep_* via opts to scan).

    if nargin < 1 || isempty(delays), delays = [0 2 4 6 8]; end
    if nargin < 2 || isempty(caseId), caseId = 23; end
    if nargin < 3, opts = struct(); end
    nD = numel(delays);
    schemes = {'Baseline','OLLA','QL v6','Tab AC v6','Deep A2C v6'};
    cellTp = zeros(nD, numel(schemes));
    p_base = zeros(nD,1); p_olla = zeros(nD,1);

    for di = 1:nD
        fprintf('\n##### sweepDelay_v6: cqi_delay = %d (%d/%d) #####\n', delays(di), di, nD);
        o = opts; o.cqi_delay = delays(di);
        res = runComparison_v6(caseId, o);
        M = res.metrics(1);                       % primary scheduler
        for k = 1:numel(schemes), cellTp(di,k) = mean(M.cell_tp{k}(:)); end
        p_base(di) = res.pvals_a2c_vs_baseline_olla(1);
        p_olla(di) = res.pvals_a2c_vs_baseline_olla(2);
    end

    S.delays = delays; S.schemes = schemes; S.cellTp = cellTp;
    S.margin_vs_baseline = cellTp(:,5) - cellTp(:,1);
    S.margin_vs_olla     = cellTp(:,5) - cellTp(:,2);
    S.p_vs_baseline = p_base; S.p_vs_olla = p_olla;

    here = fileparts(mfilename('fullpath'));
    save(fullfile(here, sprintf('sweepDelay_v6_case%d.mat', caseId)), 'S');

    figure('Color','w','Position',[80 80 1050 430],'Name','v6 delay sweep');
    subplot(1,2,1); hold on; grid on;
    cols = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    mk = {'--o','-.s','-^','-d','-o'};
    for k = 1:numel(schemes)
        plot(delays, cellTp(:,k), mk{k}, 'Color', cols{k}, 'LineWidth', 1.8);
    end
    xlabel('CQI feedback delay (TTIs)'); ylabel('Cell Tp (Mbps)');
    title('Cell throughput vs CQI delay'); legend(schemes, 'Location','best');

    subplot(1,2,2); hold on; grid on;
    plot(delays, S.margin_vs_baseline, '-o', 'LineWidth',1.8, 'Color',[0.1 0.65 0.2]);
    plot(delays, S.margin_vs_olla,     '-s', 'LineWidth',1.8, 'Color',[0.15 0.3 0.85]);
    yline(0,'k--');
    for di = 1:nD
        if p_olla(di) < 0.05
            text(delays(di), S.margin_vs_olla(di), '  *', 'FontSize', 14, 'Color', [0.15 0.3 0.85]);
        end
    end
    xlabel('CQI feedback delay (TTIs)'); ylabel('Deep A2C margin (Mbps)');
    title('A2C advantage vs delay (* = p<0.05 over OLLA)');
    legend({'over Baseline','over OLLA'}, 'Location','best');
    sgtitle(sprintf('v6 (OLLA-relative)  |  case %d', caseId), 'FontWeight','bold');
end
