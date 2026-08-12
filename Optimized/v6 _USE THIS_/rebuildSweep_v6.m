function S = rebuildSweep_v6()
% rebuildSweep_v6  Reconstruct the powered delay-sweep summary + figure.
%
% Why this exists: the 5-seed x 30-trace sweep of 2026-07-11 completed
% delays {0,2,4,6} in one MATLAB session (whose sweepDelay_v6 would only
% save its summary at the very end). The delay-8 point was finished
% separately. This script hard-codes the four completed points (verbatim
% from the per-point PF tables / robustness rows) and fills delay 8
% automatically from results_v6_case23_N10.mat if that file holds a
% cqi_delay=8 run - otherwise it leaves NaNs and tells you.
%
% Output identical in format to sweepDelay_v6: saves
% sweepDelay_v6_case23.mat and draws the two-panel headline figure.
%
% Provenance of hard-coded rows (5 seeds x 30 traces, N=10, primary=PF):
%   d0: run started 2026-07-11 13:45, runtime  54.5 min
%   d2: run started 2026-07-11 14:40, runtime  67.0 min
%   d4: run started 2026-07-11 15:47, runtime  84.4 min  (== FINAL_..._d4_cameraready)
%   d6: run started 2026-07-11 17:12, runtime 313.2 min  (== FINAL_..._d6_cameraready; wall time inflated by PC sleep)

    schemes = {'Baseline','OLLA','QL v6','Tab AC v6','Deep A2C v6'};
    delays  = [0 2 4 6 8];

    %          Baseline   OLLA     QL v6   TabAC v6  A2C v6
    cellTp = [  7.169    11.057    9.535   10.540    11.221 ;   % d0
                5.904     7.447    6.970    7.124     7.708 ;   % d2
                4.764     6.162    5.851    5.973     6.274 ;   % d4
                4.191     5.374    5.312    5.320     5.729 ;   % d6
                NaN       NaN      NaN      NaN       NaN   ];  % d8 (auto-filled)

    p_base = [1.734e-06; 1.734e-06; 1.734e-06; 1.734e-06; NaN];
    p_olla = [0.03872;   0.01044;   0.06871;   4.072e-05; NaN];

    % ---- auto-fill delay 8 from the standalone run, if present ----
    here = fileparts(mfilename('fullpath'));
    cand = {'FINAL_results_v6_N10_d8_sweeppoint.mat', 'results_v6_case23_N10.mat'};
    f8 = '';
    for c = 1:numel(cand)
        if exist(fullfile(here, cand{c}), 'file'), f8 = fullfile(here, cand{c}); break; end
    end
    if ~isempty(f8)
        R = load(f8, 'results'); R = R.results;
        if R.env.cqi_delay == 8
            M = R.metrics(1);                       % primary scheduler (PF)
            for k = 1:numel(schemes)
                cellTp(5,k) = mean(M.cell_tp{k}(:));
            end
            p_base(5) = R.pvals_a2c_vs_baseline_olla(1);
            p_olla(5) = R.pvals_a2c_vs_baseline_olla(2);
            fprintf('delay-8 row filled from %s (seeds=%d, traces=%d)\n', ...
                    f8, R.opts.n_seeds, R.opts.n_eval);
        else
            warning(['%s holds cqi_delay=%d, not 8. Run\n' ...
                     '  runCase23_v6(''N'',10,''n_seeds'',5,''n_eval'',30,''cqi_delay'',8);\n' ...
                     'then re-run rebuildSweep_v6.'], f8, R.env.cqi_delay);
        end
    else
        warning('No results_v6_case23_N10.mat found - delay-8 row left as NaN.');
    end

    S.delays = delays; S.schemes = schemes; S.cellTp = cellTp;
    S.margin_vs_baseline = cellTp(:,5) - cellTp(:,1);
    S.margin_vs_olla     = cellTp(:,5) - cellTp(:,2);
    S.rel_margin_vs_olla = 100*(cellTp(:,5)./cellTp(:,2) - 1);
    S.p_vs_baseline = p_base; S.p_vs_olla = p_olla;
    S.protocol = '5 seeds x 30 held-out traces, N=10, primary=PF, v6 OLLA-relative';
    save(fullfile(here, 'sweepDelay_v6_case23.mat'), 'S');

    % ---- headline figure (same layout as sweepDelay_v6) ----
    ok = ~isnan(cellTp(:,1));
    d  = delays(ok);
    figure('Color','w','Position',[80 80 1050 430],'Name','v6 delay sweep (rebuilt)');
    subplot(1,2,1); hold on; grid on;
    cols = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    mk = {'--o','-.s','-^','-d','-o'};
    for k = 1:numel(schemes)
        plot(d, cellTp(ok,k), mk{k}, 'Color', cols{k}, 'LineWidth', 1.8);
    end
    xlabel('CQI feedback delay (TTIs)'); ylabel('Cell Tp (Mbps)');
    title('Cell throughput vs CQI delay'); legend(schemes, 'Location','best');

    subplot(1,2,2); hold on; grid on;
    plot(d, S.margin_vs_baseline(ok), '-o', 'LineWidth',1.8, 'Color',[0.1 0.65 0.2]);
    plot(d, S.margin_vs_olla(ok),     '-s', 'LineWidth',1.8, 'Color',[0.15 0.3 0.85]);
    yline(0,'k--');
    for di = find(ok(:)')
        if ~isnan(p_olla(di)) && p_olla(di) < 0.05
            text(delays(di), S.margin_vs_olla(di), '  *', 'FontSize', 15, 'Color', [0.15 0.3 0.85]);
        end
    end
    xlabel('CQI feedback delay (TTIs)'); ylabel('Deep A2C margin (Mbps)');
    title('A2C advantage vs delay (* = p<0.05 over OLLA)');
    legend({'over Baseline','over OLLA'}, 'Location','best');
    sgtitle('v6 (OLLA-relative)  |  N=10, 5 seeds x 30 traces', 'FontWeight','bold');

    fprintf('\nrel. A2C-over-OLLA margin (%%): '); fprintf('%+.1f  ', S.rel_margin_vs_olla);
    fprintf('\nsaved sweepDelay_v6_case23.mat\n');
end
