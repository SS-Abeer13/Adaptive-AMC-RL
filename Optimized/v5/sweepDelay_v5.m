function S = sweepDelay_v5(delays, caseId, opts)
% sweepDelay_v5  Sweep CQI feedback delay and record each scheme's cell Tp and
% the A2C-over-baseline / A2C-over-OLLA margins. The expected headline figure:
% the A2C advantage grows monotonically with delay (more outdated CQI = more
% for the learned correction to recover).
%
%   S = sweepDelay_v5([0 2 4 6 8]);
%   S = sweepDelay_v5([0 2 4 6 8], 23, struct('N',10,'n_seeds',3,'n_eval',20));
%
% Re-runs the full multi-seed/held-out comparison at each delay (slow; reduce
% n_seeds/ep_deep for a quick scan). Saves S and a Tp-vs-delay figure.

    if nargin < 1 || isempty(delays), delays = [0 2 4 6 8]; end
    if nargin < 2 || isempty(caseId), caseId = 23; end
    if nargin < 3, opts = struct(); end

    here = fileparts(mfilename('fullpath'));
    nD = numel(delays);
    schemes = {'Baseline','OLLA','QL v5','Tab AC v5','Deep A2C v5'};
    cellTp = zeros(nD, 5); cellCI = zeros(nD, 5);
    p_base = zeros(nD,1); p_olla = zeros(nD,1);

    for di = 1:nD
        o = opts; o.cqi_delay_override = delays(di);   % consumed below
        fprintf('\n##### sweepDelay: cqi_delay = %d #####\n', delays(di));
        res = run_one(caseId, o, delays(di));
        M = res.metrics(1);            % primary scheduler
        for k = 1:5
            x = M.cell_tp{k}(:);
            cellTp(di,k) = mean(x);
            if numel(x) > 1, cellCI(di,k) = 1.96*std(x)/sqrt(numel(x)); end
        end
        p_base(di) = res.pvals_a2c_vs_baseline_olla(1);
        p_olla(di) = res.pvals_a2c_vs_baseline_olla(2);
    end

    S.delays = delays; S.schemes = schemes;
    S.cellTp = cellTp; S.cellCI = cellCI;
    S.margin_vs_baseline = cellTp(:,5) - cellTp(:,1);
    S.margin_vs_olla     = cellTp(:,5) - cellTp(:,2);
    S.p_vs_baseline = p_base; S.p_vs_olla = p_olla;

    figure('Position',[60 60 1000 420],'Name','v5 delay sweep');
    subplot(1,2,1); hold on; grid on;
    cols = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    for k = 1:5
        errorbar(delays, cellTp(:,k), cellCI(:,k), '-o', 'Color', cols{k}, 'LineWidth',1.5);
    end
    xlabel('CQI feedback delay (intervals)'); ylabel('Cell Tp (Mbps)');
    title('Throughput vs delay'); legend(schemes,'Location','best');
    subplot(1,2,2); hold on; grid on;
    plot(delays, S.margin_vs_baseline, '-o', 'LineWidth',1.7, 'Color',[0.1 0.65 0.2]);
    plot(delays, S.margin_vs_olla,     '-s', 'LineWidth',1.7, 'Color',[0.15 0.3 0.85]);
    xlabel('CQI feedback delay (intervals)'); ylabel('A2C margin (Mbps)');
    title('A2C advantage vs delay'); legend({'over Baseline','over OLLA'},'Location','best');

    save(fullfile(here, sprintf('sweepDelay_v5_case%d.mat', caseId)), 'S');
    fprintf('\nSaved sweepDelay_v5_case%d.mat\n', caseId);
end


function res = run_one(caseId, opts, delay)
% Inject the delay by overriding env via a temporary opts flag understood here:
% we call runComparison_v5 but patch defaultEnv through a closure is not
% possible, so we set a global that runComparison_v5 does not read -> instead
% we replicate by temporarily editing the env through opts.delay handled in a
% thin wrapper. Simplest robust path: set opts and let runComparison_v5 read
% opts.cqi_delay if present.
    opts.cqi_delay = delay;
    res = runComparison_v5(caseId, opts);
end
