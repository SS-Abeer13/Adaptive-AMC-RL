function S = sweepN_v5(Ns, opts)
% sweepN_v5  Sweep the number of users N and record each scheme's cell Tp and
% the A2C margins. Hypothesis: AMC correction matters most at small N (less
% multiuser diversity), so the A2C-over-baseline margin should shrink as N
% grows. Use this to pick the N that best showcases the policy advantage.
%
%   S = sweepN_v5([5 10 20 50]);
%   S = sweepN_v5([5 10 20 50], struct('n_seeds',3,'n_eval',20,'ep_deep',200));
%
% Always case 23. Slow (full comparison per N); reduce n_seeds/ep_deep to scan.

    if nargin < 1 || isempty(Ns), Ns = [5 10 20 50]; end
    if nargin < 2, opts = struct(); end

    here = fileparts(mfilename('fullpath'));
    nN = numel(Ns);
    schemes = {'Baseline','OLLA','QL v5','Tab AC v5','Deep A2C v5'};
    cellTp = zeros(nN, 5); cellCI = zeros(nN, 5);
    p_base = zeros(nN,1); p_olla = zeros(nN,1);

    for ni = 1:nN
        o = opts; o.N = Ns(ni);
        fprintf('\n##### sweepN: N = %d #####\n', Ns(ni));
        res = runComparison_v5(23, o);
        M = res.metrics(1);
        for k = 1:5

            
            x = M.cell_tp{k}(:);
            cellTp(ni,k) = mean(x);
            if numel(x) > 1, cellCI(ni,k) = 1.96*std(x)/sqrt(numel(x)); end
        end
        p_base(ni) = res.pvals_a2c_vs_baseline_olla(1);
        p_olla(ni) = res.pvals_a2c_vs_baseline_olla(2);
    end

    S.Ns = Ns; S.schemes = schemes; S.cellTp = cellTp; S.cellCI = cellCI;
    S.margin_vs_baseline = cellTp(:,5) - cellTp(:,1);
    S.margin_pct_vs_baseline = 100*(cellTp(:,5) - cellTp(:,1)) ./ max(cellTp(:,1), eps);
    S.p_vs_baseline = p_base; S.p_vs_olla = p_olla;

    figure('Position',[60 60 1000 420],'Name','v5 N sweep');
    subplot(1,2,1); hold on; grid on;
    cols = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    for k = 1:5
        errorbar(Ns, cellTp(:,k), cellCI(:,k), '-o', 'Color', cols{k}, 'LineWidth',1.5);
    end
    xlabel('Number of users N'); ylabel('Cell Tp (Mbps)');
    title('Throughput vs N'); legend(schemes,'Location','best');
    subplot(1,2,2); yyaxis left;
    plot(Ns, S.margin_vs_baseline, '-o', 'LineWidth',1.7); ylabel('A2C margin (Mbps)');
    yyaxis right;
    plot(Ns, S.margin_pct_vs_baseline, '-s', 'LineWidth',1.7); ylabel('A2C margin (%)');
    grid on; xlabel('Number of users N'); title('A2C advantage vs N');

    save(fullfile(here, 'sweepN_v5_case23.mat'), 'S');
    fprintf('\nSaved sweepN_v5_case23.mat\n');
end
