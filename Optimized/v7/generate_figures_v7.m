function generate_figures_v7()
% generate_figures_v7  Build the v7 paper figure set from saved results.
%
%   matlab -batch "generate_figures_v7"
%
% Reads Dataset\results_v7_*.mat (produced by runComparison_v7 /
% sweep_olla_target_v7) and writes PNG + FIG files to v7\figures\.
% No training, no dlnetwork objects touched - safe to run anytime after
% the campaign, in any MATLAB session. Each figure is wrapped in its own
% try/catch so one missing .mat does not abort the rest.

    here = fileparts(mfilename('fullpath'));
    cd(here);
    figdir = fullfile(here, 'figures');
    if ~exist(figdir, 'dir'), mkdir(figdir); end
    datadir = fullfile(here, 'Dataset');

    fprintf('===== v7 figure generation =====\n');

    % ---- point registry: tag -> display label ----
    points = {
        'phase0_calm',        'Calm (hetero=0)'
        'hetero050',          'Hetero 0.5'
        'hetero100',          'Hetero 1.0'
        'burst06dB',          'Burst +6dB'
        'burst09dB',          'Burst +9dB (Headline)'
        'burst12dB',          'Burst +12dB'
        'headline_tierA',     'Tier-A ablation'
        'headline_warm1000',  'Warm OLLA (1000 TTI)'
        'headline_fresh',     'Fresh-seed replicate'
        'headline_tier1',     'Tier1 (BC, entropy bug)'
        'headline_tier1b',    'Tier1b (BC, fixed)'
        'headline_tier1_nobc','Tier1 no-BC'
    };

    % ---- load whatever exists ----
    R = struct(); ok = false(size(points,1),1);
    for i = 1:size(points,1)
        f = fullfile(datadir, sprintf('results_v7_%s.mat', points{i,1}));
        if exist(f, 'file')
            L = load(f, 'results');
            R.(points{i,1}) = L.results;
            ok(i) = true;
        else
            fprintf('  [skip] %s not found\n', f);
        end
    end

    % =====================================================================
    fprintf('-- fig1: campaign forest plot (A2C vs FixedPU / vs OLLA) --\n');
    try
        idx = find(ok);
        n = numel(idx);
        mFPU = nan(n,1); pFPU = nan(n,1); mOLLA = nan(n,1); pOLLA = nan(n,1);
        lbl = cell(n,1);
        for j = 1:n
            i = idx(j);
            res = R.(points{i,1});
            sc = find(strcmpi(res.eval_schedulers, 'pf'), 1);
            M = res.metrics(sc);
            tr7 = mean(M.cell_tp{7}, 1);   % A2C
            tr4 = mean(M.cell_tp{4}, 1);   % FixedPU
            tr2 = mean(M.cell_tp{2}, 1);   % OLLA
            mFPU(j)  = 100*(mean(tr7)-mean(tr4))/mean(tr4);
            mOLLA(j) = 100*(mean(tr7)-mean(tr2))/mean(tr2);
            if isfield(res,'pvals') && isfield(res.pvals,'a2c_vs_fixedPU')
                pFPU(j) = res.pvals.a2c_vs_fixedPU;
            elseif exist('signrank','file')==2
                pFPU(j) = signrank(tr7, tr4);
            end
            if isfield(res,'pvals') && isfield(res.pvals,'a2c_vs_olla')
                pOLLA(j) = res.pvals.a2c_vs_olla;
            elseif exist('signrank','file')==2
                pOLLA(j) = signrank(tr7, tr2);
            end
            lbl{j} = points{i,2};
        end

        fig = figure('Visible','off','Position',[100 100 900 500]);
        barh(1:n, mFPU, 0.6, 'FaceColor',[0.6 0.6 0.6]); hold on;
        for j = 1:n
            c = [0.6 0.6 0.6];
            if pFPU(j) < 0.05, c = [0.85 0.2 0.2]; if mFPU(j) > 0, c = [0.2 0.55 0.2]; end, end
            barh(j, mFPU(j), 0.6, 'FaceColor', c);
            txt = sprintf('%+.1f%% (p=%.3g)', mFPU(j), pFPU(j));
            xoff = 0.3 * sign(mFPU(j)+eps);
            ha = 'left'; if mFPU(j) < 0, ha = 'right'; end
            text(mFPU(j)+xoff, j, txt, 'FontSize', 8, 'HorizontalAlignment', ha);
        end
        xline(0, 'k-', 'LineWidth', 1);
        set(gca, 'YTick', 1:n, 'YTickLabel', lbl, 'YDir','reverse');
        xlabel('A2C vs FixedPU margin (%)  [PF scheduler]');
        title('v7 Campaign: Pre-Registered Win Condition Across All Points');
        grid on; box on;
        exportgraphics(fig, fullfile(figdir,'fig1_campaign_forest_vs_fixedpu.png'), 'Resolution',300);
        savefig(fig, fullfile(figdir,'fig1_campaign_forest_vs_fixedpu.fig'));
        close(fig);

        fig = figure('Visible','off','Position',[100 100 900 500]);
        for j = 1:n
            c = [0.6 0.6 0.6];
            if pOLLA(j) < 0.05, c = [0.85 0.2 0.2]; if mOLLA(j) > 0, c = [0.2 0.55 0.2]; end, end
            barh(j, mOLLA(j), 0.6, 'FaceColor', c); hold on;
            txt = sprintf('%+.1f%% (p=%.3g)', mOLLA(j), pOLLA(j));
            xoff = 0.3 * sign(mOLLA(j)+eps);
            ha = 'left'; if mOLLA(j) < 0, ha = 'right'; end
            text(mOLLA(j)+xoff, j, txt, 'FontSize', 8, 'HorizontalAlignment', ha);
        end
        xline(0, 'k-', 'LineWidth', 1);
        set(gca, 'YTick', 1:n, 'YTickLabel', lbl, 'YDir','reverse');
        xlabel('A2C vs OLLA margin (%)  [PF scheduler]');
        title('v7 Campaign: A2C vs OLLA (Setpoint-Control Gain) Across All Points');
        grid on; box on;
        exportgraphics(fig, fullfile(figdir,'fig1b_campaign_forest_vs_olla.png'), 'Resolution',300);
        savefig(fig, fullfile(figdir,'fig1b_campaign_forest_vs_olla.fig'));
        close(fig);
        fprintf('   saved fig1, fig1b\n');
    catch ME
        fprintf(2, '   [fig1 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig2: learner comparison bar chart (headline vs tier1b) --\n');
    try
        tagsF2 = {'burst09dB','headline_tier1_nobc','headline_tier1b'};
        lblF2  = {'burst09dB (vanilla)','tier1-nobc (fixes, no clone)','tier1b (fixes + BC clone)'};
        schemes = {'Baseline','OLLA','Fixed','FixedPU','QL','TabAC','Deep A2C'};
        present = tagsF2(isfield(R, tagsF2));
        if numel(present) >= 1
            K = numel(schemes);
            mm = nan(K, numel(tagsF2)); ci = nan(K, numel(tagsF2));
            for c = 1:numel(tagsF2)
                if ~isfield(R, tagsF2{c}), continue; end
                res = R.(tagsF2{c});
                sc = find(strcmpi(res.eval_schedulers,'pf'),1);
                M = res.metrics(sc);
                for k = 1:K
                    tr = mean(M.cell_tp{k}, 1);
                    mm(k,c) = mean(tr);
                    ci(k,c) = 1.96*std(tr)/sqrt(numel(tr));
                end
            end
            fig = figure('Visible','off','Position',[100 100 950 500]);
            bh = bar(mm, 'grouped'); hold on;
            ngrp = numel(tagsF2);
            for c = 1:ngrp
                xpos = bh(c).XEndPoints;
                errorbar(xpos, mm(:,c), ci(:,c), 'k.', 'LineWidth', 1);
            end
            set(gca, 'XTick', 1:K, 'XTickLabel', schemes);
            ylabel('Cell throughput (Mbps)');
            legend(lblF2, 'Location','northoutside','Orientation','horizontal');
            title('Learner Comparison: Tabular vs Deep, Vanilla vs Fixed (PF scheduler)');
            grid on; box on;
            exportgraphics(fig, fullfile(figdir,'fig2_learner_comparison.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig2_learner_comparison.fig'));
            close(fig);
            fprintf('   saved fig2\n');
        else
            fprintf('   [skip] neither burst09dB nor headline_tier1b available\n');
        end
    catch ME
        fprintf(2, '   [fig2 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig3/4: entropy + cellTp RL fine-tune learning curves (tier1 vs tier1b) --\n');
    try
        haveT1  = isfield(R, 'headline_tier1');
        haveT1b = isfield(R, 'headline_tier1b');
        if haveT1 || haveT1b
            fig = figure('Visible','off','Position',[100 100 900 450]);
            hold on; leg = {};
            if haveT1
                ent = R.headline_tier1.learning.ent;   % ep x seeds
                plot(1:size(ent,1), mean(ent,2), 'r-', 'LineWidth', 1.5);
                leg{end+1} = 'tier1 (entropy bug)';
            end
            if haveT1b
                ent = R.headline_tier1b.learning.ent;
                plot(1:size(ent,1), mean(ent,2), 'b-', 'LineWidth', 1.5);
                leg{end+1} = 'tier1b (fixed)';
            end
            yline(1.95, 'k--', 'max entropy (7 actions)');
            xlabel('RL fine-tune episode'); ylabel('Policy entropy (nats, seed-avg)');
            title('Entropy Trajectory After Behavior-Cloning Warm Start');
            legend(leg, 'Location','southeast'); grid on; box on;
            exportgraphics(fig, fullfile(figdir,'fig3_entropy_learning_curves.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig3_entropy_learning_curves.fig'));
            close(fig);

            fig = figure('Visible','off','Position',[100 100 900 450]);
            hold on; leg = {};
            if haveT1
                dac = R.headline_tier1.learning.dac;
                plot(1:size(dac,1), mean(dac,2), 'r-', 'LineWidth', 1.5);
                leg{end+1} = 'tier1 (entropy bug)';
            end
            if haveT1b
                dac = R.headline_tier1b.learning.dac;
                plot(1:size(dac,1), mean(dac,2), 'b-', 'LineWidth', 1.5);
                leg{end+1} = 'tier1b (fixed)';
            end
            xlabel('RL fine-tune episode'); ylabel('Cell throughput (Mbps, seed-avg)');
            title('Cell Throughput During RL Fine-Tuning (Post Behavior-Cloning)');
            legend(leg, 'Location','southeast'); grid on; box on;
            exportgraphics(fig, fullfile(figdir,'fig4_cellTp_learning_curves.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig4_cellTp_learning_curves.fig'));
            close(fig);
            fprintf('   saved fig3, fig4\n');
        else
            fprintf('   [skip] tier1/tier1b learning curves not available\n');
        end
    catch ME
        fprintf(2, '   [fig3/4 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig5: Tier-A vs Tier-B state ablation --\n');
    try
        if isfield(R,'headline_tierA') && isfield(R,'burst09dB')
            tags5 = {'headline_tierA','burst09dB'};
            lbl5  = {'Tier-A (info-equal)','Tier-B (headline)'};
            mFPU5 = nan(1,2); pFPU5 = nan(1,2);
            for c = 1:2
                res = R.(tags5{c});
                sc = find(strcmpi(res.eval_schedulers,'pf'),1);
                M = res.metrics(sc);
                tr7 = mean(M.cell_tp{7},1); tr4 = mean(M.cell_tp{4},1);
                mFPU5(c) = 100*(mean(tr7)-mean(tr4))/mean(tr4);
                if isfield(res,'pvals') && isfield(res.pvals,'a2c_vs_fixedPU')
                    pFPU5(c) = res.pvals.a2c_vs_fixedPU;
                elseif exist('signrank','file')==2
                    pFPU5(c) = signrank(tr7, tr4);
                end
            end
            fig = figure('Visible','off','Position',[700 100 500 450]);
            b = bar(mFPU5, 0.5); hold on;
            b.FaceColor = 'flat';
            for c=1:2, b.CData(c,:) = [0.3 0.4 0.7]; end
            for c = 1:2
                text(c, mFPU5(c) + 0.3*sign(mFPU5(c)+eps), ...
                    sprintf('%+.1f%%\np=%.3g', mFPU5(c), pFPU5(c)), ...
                    'HorizontalAlignment','center', 'FontSize', 9);
            end
            set(gca, 'XTick', 1:2, 'XTickLabel', lbl5);
            ylabel('A2C vs FixedPU margin (%)');
            title('State Information Ablation: Richer State Buys Nothing');
            yline(0,'k-'); grid on; box on;
            exportgraphics(fig, fullfile(figdir,'fig5_tierA_vs_tierB_ablation.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig5_tierA_vs_tierB_ablation.fig'));
            close(fig);
            fprintf('   saved fig5\n');
        else
            fprintf('   [skip] headline_tierA or burst09dB missing\n');
        end
    catch ME
        fprintf(2, '   [fig5 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig6: OLLA target-BLER sweep frontier --\n');
    try
        sf = fullfile(datadir, 'results_v7_olla_sweep.mat');
        if exist(sf, 'file')
            L = load(sf, 'out'); out = L.out;
            mO = mean(out.tpO, 2); ciO = 1.96*std(out.tpO,0,2)/sqrt(out.n_eval);
            mA = mean(out.tpA); ciA = 1.96*std(out.tpA)/sqrt(out.n_eval);
            mC = mean(out.tpC); ciC = 1.96*std(out.tpC)/sqrt(out.n_eval);
            mR = mean(out.tpR); ciR = 1.96*std(out.tpR)/sqrt(out.n_eval);

            fig = figure('Visible','off','Position',[100 100 800 500]);
            errorbar(out.targets, mO, ciO, '-o', 'LineWidth',1.5, 'Color',[0.2 0.4 0.8]); hold on;
            yline(mA, 'r-', 'LineWidth',1.5);
            yline(mA+ciA, 'r:'); yline(mA-ciA, 'r:');
            yline(mC, 'g--', 'LineWidth',1.2);
            yline(mR, 'k:', 'LineWidth',1.2);
            legend({'OLLA (target sweep)','Deep A2C (tier1b)','A2C 95% CI','', ...
                    'Constant -1','Random action'}, 'Location','southoutside', ...
                    'Orientation','horizontal', 'NumColumns', 3);
            xlabel('OLLA target BLER'); ylabel('Cell throughput (Mbps)');
            title('OLLA Re-Tuned Across Target BLER vs A2C Operating Point');
            grid on; box on;
            exportgraphics(fig, fullfile(figdir,'fig6_olla_target_sweep.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig6_olla_target_sweep.fig'));
            close(fig);
            fprintf('   saved fig6\n');
        else
            fprintf('   [skip] results_v7_olla_sweep.mat not found\n');
        end
    catch ME
        fprintf(2, '   [fig6 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig7: burst vs calm throughput (headline_tier1b) --\n');
    try
        tag7 = 'headline_tier1b'; if ~isfield(R, tag7), tag7 = 'burst09dB'; end
        if isfield(R, tag7)
            res = R.(tag7);
            sc = find(strcmpi(res.eval_schedulers,'pf'),1);
            M = res.metrics(sc);
            schemes = {'Baseline','OLLA','Fixed','FixedPU','QL','TabAC','Deep A2C'};
            K = numel(schemes);
            tb = zeros(K,1); tc = zeros(K,1);
            for k = 1:K
                tb(k) = mean(M.tp_burst{k}(:), 'omitnan');
                tc(k) = mean(M.tp_calm{k}(:), 'omitnan');
            end
            fig = figure('Visible','off','Position',[100 100 950 500]);
            bar([tb tc], 'grouped');
            set(gca, 'XTick', 1:K, 'XTickLabel', schemes);
            ylabel('Cell throughput (Mbps)');
            legend({'During burst','Calm'}, 'Location','northoutside','Orientation','horizontal');
            title(sprintf('Burst vs Calm Throughput by Scheme (%s, PF)', strrep(tag7,'_','\_')));
            grid on; box on;
            exportgraphics(fig, fullfile(figdir,'fig7_burst_vs_calm_throughput.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig7_burst_vs_calm_throughput.fig'));
            close(fig);
            fprintf('   saved fig7\n');
        else
            fprintf('   [skip] no headline data for burst/calm figure\n');
        end
    catch ME
        fprintf(2, '   [fig7 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig8: first-Tx BLER comparison (headline points) --\n');
    try
        tags8 = {'burst09dB','headline_tier1b'};
        lbl8  = {'burst09dB (vanilla)','tier1b (BC+fixes)'};
        present = tags8(isfield(R, tags8));
        if numel(present) >= 1
            schemes = {'Baseline','OLLA','Fixed','FixedPU','QL','TabAC','Deep A2C'};
            K = numel(schemes);
            bl = nan(K, numel(tags8));
            for c = 1:numel(tags8)
                if ~isfield(R, tags8{c}), continue; end
                res = R.(tags8{c});
                sc = find(strcmpi(res.eval_schedulers,'pf'),1);
                M = res.metrics(sc);
                for k = 1:K
                    bl(k,c) = mean(M.bler{k}(:), 'omitnan');
                end
            end
            fig = figure('Visible','off','Position',[100 100 950 500]);
            bar(bl, 'grouped');
            set(gca, 'XTick', 1:K, 'XTickLabel', schemes);
            ylabel('First-transmission BLER');
            yline(0.10, 'k--', 'OLLA 10% target');
            legend(lbl8, 'Location','northoutside','Orientation','horizontal');
            title('First-Transmission BLER by Scheme: The Run-Hot Operating Point');
            grid on; box on;
            exportgraphics(fig, fullfile(figdir,'fig8_bler1_comparison.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig8_bler1_comparison.fig'));
            close(fig);
            fprintf('   saved fig8\n');
        else
            fprintf('   [skip] no headline data for BLER figure\n');
        end
    catch ME
        fprintf(2, '   [fig8 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig9: trace-by-trace win/loss scatter (A2C vs FixedPU) --\n');
    try
        tag9 = 'headline_tier1b'; if ~isfield(R, tag9), tag9 = 'burst09dB'; end
        if isfield(R, tag9)
            res = R.(tag9);
            sc = find(strcmpi(res.eval_schedulers,'pf'),1);
            M = res.metrics(sc);
            tr7 = mean(M.cell_tp{7}, 1);   % A2C, per-trace
            tr4 = mean(M.cell_tp{4}, 1);   % FixedPU, per-trace
            nWin = sum(tr7 > tr4); nLoss = sum(tr7 < tr4); nTie = sum(tr7==tr4);
            lo = min([tr7 tr4]); hi = max([tr7 tr4]);

            fig = figure('Visible','off','Position',[100 100 600 600]);
            scatter(tr4, tr7, 55, 'filled', 'MarkerFaceColor',[0.2 0.4 0.8], ...
                    'MarkerFaceAlpha',0.7); hold on;
            plot([lo hi],[lo hi],'k--','LineWidth',1.2);
            xlabel('FixedPU cell throughput (Mbps), per trace');
            ylabel('Deep A2C cell throughput (Mbps), per trace');
            title(sprintf('Trace-Level Win Rate: A2C wins %d / loses %d / ties %d (n=%d)', ...
                  nWin, nLoss, nTie, numel(tr7)));
            axis equal; grid on; box on;
            text(hi, lo, 'A2C loses  ', 'HorizontalAlignment','right', ...
                 'VerticalAlignment','bottom', 'FontSize',9, 'Color',[0.6 0.6 0.6]);
            text(lo, hi, '  A2C wins', 'HorizontalAlignment','left', ...
                 'VerticalAlignment','top', 'FontSize',9, 'Color',[0.6 0.6 0.6]);
            exportgraphics(fig, fullfile(figdir,'fig9_trace_winrate_scatter.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig9_trace_winrate_scatter.fig'));
            close(fig);
            fprintf('   saved fig9 (win=%d loss=%d tie=%d)\n', nWin, nLoss, nTie);
        else
            fprintf('   [skip] no headline data\n');
        end
    catch ME
        fprintf(2, '   [fig9 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig10: three-scheduler grouped comparison (PF/RR/EQ) --\n');
    try
        tag10 = 'headline_tier1b'; if ~isfield(R, tag10), tag10 = 'burst09dB'; end
        if isfield(R, tag10)
            res = R.(tag10);
            schemes = {'Baseline','OLLA','Fixed','FixedPU','QL','TabAC','Deep A2C'};
            K = numel(schemes);
            scheds = res.eval_schedulers;
            nS = numel(scheds);
            mm = nan(K, nS); ci = nan(K, nS);
            for s = 1:nS
                M = res.metrics(s);
                for k = 1:K
                    tr = mean(M.cell_tp{k}, 1);
                    mm(k,s) = mean(tr); ci(k,s) = 1.96*std(tr)/sqrt(numel(tr));
                end
            end
            fig = figure('Visible','off','Position',[100 100 950 500]);
            bh = bar(mm, 'grouped'); hold on;
            for s = 1:nS
                errorbar(bh(s).XEndPoints, mm(:,s), ci(:,s), 'k.', 'LineWidth',1);
            end
            set(gca, 'XTick', 1:K, 'XTickLabel', schemes);
            ylabel('Cell throughput (Mbps)');
            legend(upper(scheds), 'Location','northoutside','Orientation','horizontal');
            title(sprintf('Scheduler Sensitivity by Scheme (%s)', strrep(tag10,'_','\_')));
            grid on; box on;
            exportgraphics(fig, fullfile(figdir,'fig10_scheduler_comparison.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig10_scheduler_comparison.fig'));
            close(fig);
            fprintf('   saved fig10\n');
        else
            fprintf('   [skip] no headline data\n');
        end
    catch ME
        fprintf(2, '   [fig10 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig11: fairness (Jain) + edge throughput --\n');
    try
        tag11 = 'headline_tier1b'; if ~isfield(R, tag11), tag11 = 'burst09dB'; end
        if isfield(R, tag11)
            res = R.(tag11);
            sc = find(strcmpi(res.eval_schedulers,'pf'),1);
            M = res.metrics(sc);
            schemes = {'Baseline','OLLA','Fixed','FixedPU','QL','TabAC','Deep A2C'};
            K = numel(schemes);
            jn = zeros(K,1); edg = zeros(K,1);
            for k = 1:K
                jn(k)  = mean(M.jain{k}(:));
                edg(k) = mean(mean(M.edge_tp{k},1));
            end
            fig = figure('Visible','off','Position',[100 100 950 420]);
            subplot(1,2,1);
            bar(jn, 'FaceColor',[0.3 0.55 0.35]);
            set(gca,'XTick',1:K,'XTickLabel',schemes); xtickangle(45);
            ylabel("Jain's fairness index"); ylim([min(jn)-0.02, 1]); grid on;
            title('Fairness');
            subplot(1,2,2);
            bar(edg, 'FaceColor',[0.7 0.45 0.2]);
            set(gca,'XTick',1:K,'XTickLabel',schemes); xtickangle(45);
            ylabel('Edge (min-user) throughput, Mbps'); grid on;
            title('Edge Throughput');
            sgtitle(sprintf('Fairness and Edge Performance (%s, PF)', strrep(tag11,'_','\_')));
            exportgraphics(fig, fullfile(figdir,'fig11_fairness_edge.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig11_fairness_edge.fig'));
            close(fig);
            fprintf('   saved fig11\n');
        else
            fprintf('   [skip] no headline data\n');
        end
    catch ME
        fprintf(2, '   [fig11 FAILED] %s\n', ME.message);
    end

    % =====================================================================
    fprintf('-- fig13: tabular vs deep training curves --\n');
    try
        tag13 = 'headline_tier1b'; if ~isfield(R, tag13), tag13 = 'burst09dB'; end
        if isfield(R, tag13) && isfield(R.(tag13),'learning')
            L = R.(tag13).learning;
            fig = figure('Visible','off','Position',[100 100 900 450]);
            hold on;
            if isfield(L,'ql'),  plot(1:size(L.ql,1),  mean(L.ql,2),  'Color',[0.8 0.4 0.2], 'LineWidth',1.3); end
            if isfield(L,'ac'),  plot(1:size(L.ac,1),  mean(L.ac,2),  'Color',[0.4 0.7 0.3], 'LineWidth',1.3); end
            if isfield(L,'dac'), plot(1:size(L.dac,1), mean(L.dac,2), 'Color',[0.2 0.4 0.8], 'LineWidth',1.5); end
            xlabel('Training episode'); ylabel('Cell throughput (Mbps, seed-avg)');
            legend({'QL (tabular)','Tab AC (tabular)','Deep A2C'}, 'Location','southeast');
            title(sprintf('Training Convergence: Tabular vs Deep (%s)', strrep(tag13,'_','\_')));
            grid on; box on;
            exportgraphics(fig, fullfile(figdir,'fig13_tabular_vs_deep_curves.png'), 'Resolution',300);
            savefig(fig, fullfile(figdir,'fig13_tabular_vs_deep_curves.fig'));
            close(fig);
            fprintf('   saved fig13\n');
        else
            fprintf('   [skip] no learning curves available\n');
        end
    catch ME
        fprintf(2, '   [fig13 FAILED] %s\n', ME.message);
    end

    fprintf('===== v7 figure generation done. See %s =====\n', figdir);
end
