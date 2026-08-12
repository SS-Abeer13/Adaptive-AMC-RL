function outdir = saveFigures_v6(matfile, outdir)
% saveFigures_v6  Render and SAVE the v6 figure set to image files from a saved
% results .mat, WITHOUT retraining. Produces the same figures the v6/v5 harness
% draws on screen (per evaluation scheduler: KPI bars, Throughput-vs-distance,
% BLER-vs-distance; plus one learning-curve figure) and writes each as a PNG.
%
%   saveFigures_v6                                   % newest *results_v6*.mat here
%   saveFigures_v6('FINAL_results_v6_N10_d4_cameraready.mat')
%   saveFigures_v6('results_v6_case23_N10.mat', 'C:\figs')   % custom output dir
%
% The v6 .mat already stores per-scheme tp_field / bler_field and per-trace
% dist_field inside results.metrics, so the figures are reconstructed exactly
% from the saved data (no policy re-evaluation, no channel regeneration).
% Output PNGs (150 dpi) are written to <outdir>, default:
%   <v6 folder>/figures_<matfile-stem>/

    here = fileparts(mfilename('fullpath'));

    % ---- locate the results file ----
    if nargin < 1 || isempty(matfile)
        d = [dir(fullfile(here,'results_v6_*.mat')); dir(fullfile(here,'FINAL*results_v6*.mat'))];
        if isempty(d), error('saveFigures_v6: no *results_v6*.mat found in %s', here); end
        [~, ix] = max([d.datenum]);
        matfile = fullfile(d(ix).folder, d(ix).name);
    elseif ~isfile(matfile)
        matfile = fullfile(here, matfile);
    end
    [~, stem] = fileparts(matfile);
    fprintf('saveFigures_v6: loading %s\n', matfile);

    % ---- output directory ----
    if nargin < 2 || isempty(outdir)
        outdir = fullfile(here, sprintf('figures_%s', stem));
    end
    if ~exist(outdir, 'dir'), mkdir(outdir); end

    S = load(matfile); R = S.results;
    env         = R.env;
    schemes     = R.schemes;
    eval_scheds = R.eval_schedulers;
    allM        = R.metrics;
    K           = numel(schemes);

    saved = {};
    for sc = 1:numel(eval_scheds)
        lbl = upper(eval_scheds{sc});
        M   = allM(sc);

        f1 = kpi_bars(schemes, M, env, lbl, K);
        saved{end+1} = export_fig(f1, outdir, sprintf('KPI_%s', lbl)); %#ok<AGROW>

        f2 = tp_vs_distance(schemes, M, lbl, K);
        if ~isempty(f2), saved{end+1} = export_fig(f2, outdir, sprintf('TpVsDistance_%s', lbl)); end %#ok<AGROW>

        f3 = bler_vs_distance(schemes, M, lbl, K);
        if ~isempty(f3), saved{end+1} = export_fig(f3, outdir, sprintf('BLERVsDistance_%s', lbl)); end %#ok<AGROW>
    end

    % One scheduler-agnostic learning-curve figure
    if isfield(R,'learning')
        f4 = learning_curves(R.learning.ql, R.learning.ac, R.learning.dac, R.entropy.dac, simTime_of(R), env);
        saved{end+1} = export_fig(f4, outdir, 'LearningCurves'); %#ok<AGROW>
    end

    fprintf('\nSaved %d figure(s) to:\n  %s\n', numel(saved), outdir);
    for i = 1:numel(saved), fprintf('    %s\n', saved{i}); end
end


% ===================== save + helpers =====================

function p = export_fig(fh, outdir, name)
    p = fullfile(outdir, [name '.png']);
    try
        exportgraphics(fh, p, 'Resolution', 150);      % R2020a+
    catch
        try, print(fh, p, '-dpng', '-r150'); catch, saveas(fh, p); end
    end
    close(fh);
end

function v = simTime_of(R)
    if isfield(R,'opts') && isfield(R.opts,'simTime'), v = R.opts.simTime; else, v = 200; end
end

function [m, ci] = mci(x)
    x = x(~isnan(x)); n = numel(x); m = mean(x);
    if n > 1, ci = 1.96*std(x)/sqrt(n); else, ci = 0; end
end

function fh = kpi_bars(schemes, M, env, lbl, K)
    mt=zeros(1,K); ct=zeros(1,K); mb=zeros(1,K); mj=zeros(1,K);
    for k = 1:K
        [mt(k),ct(k)] = mci(M.cell_tp{k}(:));
        mb(k) = mean(M.bler{k}(:),'omitnan'); mj(k) = mean(M.jain{k}(:));
    end
    sup = sprintf('v6 KPIs  |  Case %d  |  N=%d  |  scheduler=%s', env.caseId, env.N, lbl);
    fh = figure('Position',[60 60 1200 420],'Name',sprintf('v6 KPIs (%s)', lbl),'Color','w','Visible','off');
    subplot(1,3,1); bar(mt,'FaceColor',[0.20 0.45 0.75]); hold on;
    errorbar(1:K,mt,ct,'k.','LineWidth',1.3);
    for k=1:K, text(k, mt(k)+ct(k)+0.02*max(mt), sprintf('%.2f',mt(k)), ...
            'HorizontalAlignment','center','FontSize',9,'FontWeight','bold'); end
    set(gca,'XTickLabel',schemes,'XTickLabelRotation',30,'FontSize',10);
    ylabel('Cell Tp (Mbps)'); title('Cell throughput (95% CI)'); grid on;
    yl=ylim; ylim([0 yl(2)*1.12]);
    subplot(1,3,2); bar(mb,'FaceColor',[0.85 0.40 0.30]); hold on;
    yline(0.1,'k--','target','LineWidth',1.2,'LabelHorizontalAlignment','left');
    for k=1:K, text(k, mb(k)+0.005, sprintf('%.3f',mb(k)), ...
            'HorizontalAlignment','center','FontSize',9,'FontWeight','bold'); end
    set(gca,'XTickLabel',schemes,'XTickLabelRotation',30,'FontSize',10);
    ylabel('Mean BLER (served TTIs)'); title('Block error rate'); grid on;
    subplot(1,3,3); bar(mj,'FaceColor',[0.30 0.65 0.30]); ylim([0 1.05]);
    for k=1:K, text(k, mj(k)+0.02, sprintf('%.3f',mj(k)), ...
            'HorizontalAlignment','center','FontSize',9,'FontWeight','bold'); end
    set(gca,'XTickLabel',schemes,'XTickLabelRotation',30,'FontSize',10);
    ylabel('Jain index'); title(sprintf('Fairness (N=%d users)', env.N)); grid on;
    sgtitle(sup,'FontWeight','bold','FontSize',12);
end

function fh = tp_vs_distance(schemes, M, lbl, K)
    fh = [];
    if ~isfield(M,'tp_field') || isempty(M.tp_field) || ~isfield(M,'dist_field'), return; end
    n_eval = size(M.tp_field, 2);
    [edges, ctr] = dist_bins(M, n_eval); if isempty(edges), return; end
    cols   = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    styles = {'--','-.','-','-','-'};
    fh = figure('Position',[60 60 1050 460],'Name',sprintf('v6 Tp vs distance (%s)', lbl),'Color','w','Visible','off');
    hold on; grid on; h = gobjects(1,K);
    for k = 1:K
        dv=[]; tv=[];
        for j = 1:n_eval
            tp = M.tp_field{k,j}; dd = M.dist_field{j};
            if isempty(tp) || isempty(dd), continue; end
            dv=[dv; dd(:)]; tv=[tv; tp(:)]; %#ok<AGROW>
        end
        sm = tv > 0; b = nan(1,numel(ctr));
        for q = 1:numel(ctr)
            in = sm & dv>=edges(q) & dv<edges(q+1);
            if any(in), b(q) = mean(tv(in)); end
        end
        h(k) = plot(ctr, b, styles{k}, 'Color', cols{k}, 'LineWidth', 1.9);
    end
    xlabel('Distance from BS (m)','FontSize',10);
    ylabel('Served throughput (Mbps)','FontSize',10);
    title(sprintf('Throughput vs distance  |  scheduler=%s  (held-out, served TTIs)', lbl), ...
          'FontWeight','bold','FontSize',11);
    legend(h, schemes, 'Location','best','FontSize',10);
end

function fh = bler_vs_distance(schemes, M, lbl, K)
    fh = [];
    if ~isfield(M,'bler_field') || isempty(M.bler_field) || ~isfield(M,'dist_field'), return; end
    n_eval = size(M.bler_field, 2);
    [edges, ctr] = dist_bins(M, n_eval); if isempty(edges), return; end
    cols   = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    styles = {'--','-.','-','-','-'};
    fh = figure('Position',[60 60 1050 460],'Name',sprintf('v6 BLER vs distance (%s)', lbl),'Color','w','Visible','off');
    hold on; grid on; h = gobjects(1,K);
    for k = 1:K
        dv=[]; bv=[];
        for j = 1:n_eval
            bl = M.bler_field{k,j}; dd = M.dist_field{j};
            if isempty(bl) || isempty(dd), continue; end
            dv=[dv; dd(:)]; bv=[bv; bl(:)]; %#ok<AGROW>
        end
        b = nan(1,numel(ctr));
        for q = 1:numel(ctr)
            in = dv>=edges(q) & dv<edges(q+1);
            if any(in), b(q) = mean(bv(in)); end
        end
        h(k) = plot(ctr, b, styles{k}, 'Color', cols{k}, 'LineWidth', 1.9);
    end
    yline(0.1,'k--','target','LineWidth',1.1,'LabelHorizontalAlignment','left');
    xlabel('Distance from BS (m)','FontSize',10); ylabel('Mean BLER','FontSize',10); ylim([0 1]);
    title(sprintf('BLER vs distance  |  scheduler=%s  (held-out)', lbl), ...
          'FontWeight','bold','FontSize',11);
    legend(h, schemes, 'Location','best','FontSize',10);
end

function [edges, ctr] = dist_bins(M, n_eval)
    d_all = [];
    for j = 1:n_eval
        if j <= numel(M.dist_field) && ~isempty(M.dist_field{j})
            d_all = [d_all; M.dist_field{j}(:)]; %#ok<AGROW>
        end
    end
    if isempty(d_all), edges = []; ctr = []; return; end
    edges = linspace(min(d_all), max(d_all), 26);
    ctr   = (edges(1:end-1)+edges(2:end))/2;
end

function fh = learning_curves(lc_ql, lc_ac, lc_dac, ent_dac, simTime, env)
    spe = simTime*env.N;
    fh = figure('Position',[60 60 1050 440],'Name','v6 learning curves','Color','w','Visible','off');
    subplot(1,2,1); hold on; grid on;
    h1 = shaded(spe*(1:size(lc_ql,1)),  lc_ql,  [0.85 0.15 0.15]);
    h2 = shaded(spe*(1:size(lc_ac,1)),  lc_ac,  [0.15 0.30 0.85]);
    h3 = shaded(spe*(1:size(lc_dac,1)), lc_dac, [0.10 0.65 0.20]);
    xlabel('Environment steps','FontSize',10); ylabel('Cell Tp per interval (Mbps)','FontSize',10);
    title('Mean +/- 1 std over seeds','FontSize',11);
    legend([h1 h2 h3], {'Q-Learning','Tabular AC','Deep A2C'}, 'Location','best');
    subplot(1,2,2); hold on; grid on;
    mu = mean(ent_dac,2); sd = std(ent_dac,0,2); x = 1:numel(mu);
    fill([x fliplr(x)], [mu'+sd' fliplr(mu'-sd')], [0.1 0.65 0.2], 'FaceAlpha',0.15,'EdgeColor','none');
    plot(x, mu, 'Color',[0.1 0.65 0.2], 'LineWidth',1.6);
    xlabel('Episode','FontSize',10); ylabel('Policy entropy (nats)','FontSize',10);
    title('Deep A2C entropy schedule','FontSize',11);
    sgtitle(sprintf('v6 Learning curves  |  Case %d  |  N=%d', env.caseId, env.N),'FontWeight','bold','FontSize',12);
end

function hline = shaded(x, Y, c)
    mu = mean(Y,2).'; sd = std(Y,0,2).';
    fill([x fliplr(x)], [mu+sd fliplr(mu-sd)], c, 'FaceAlpha',0.15, 'EdgeColor','none');
    hline = plot(x, mu, 'Color', c, 'LineWidth', 1.6);
end
