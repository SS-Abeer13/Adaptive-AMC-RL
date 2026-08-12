function replotFromResults_v5(matfile)
% replotFromResults_v5  Redraw all v5 figures from a saved results_v5_*.mat
% WITHOUT retraining. Per evaluation scheduler it draws: KPI bars (Cell Tp /
% BLER / Jain), Throughput-vs-distance, and BLER-vs-distance; plus the A2C
% policy heatmap per scheduler and one scheduler-agnostic learning-curve figure.
%
%   replotFromResults_v5                              % newest results_v5_*.mat here
%   replotFromResults_v5('results_v5_case23_N50.mat') % a specific file
%
% Robustness: the per-distance curves are RECOMPUTED here by re-running the
% (cheap, no-training) evaluation of the saved policies on the deterministic
% held-out traces (rng(9000+j)). This guarantees the PF / RR / EQ curves all
% render, regardless of which fields the .mat happened to store.

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(matfile)
        d = dir(fullfile(here, 'results_v5_*.mat'));
        if isempty(d), error('replotFromResults_v5: no results_v5_*.mat in %s', here); end
        [~, ix] = max([d.datenum]); matfile = fullfile(d(ix).folder, d(ix).name);
    elseif ~isfile(matfile)
        matfile = fullfile(here, matfile);
    end
    fprintf('Replotting from %s\n', matfile);

    addpath(fullfile(here, '..', 'case2_3'));       % createTBS_Table / tbsFromMCSandRB
    S = load(matfile); R = S.results;

    env         = R.env;
    schemes     = R.schemes;
    eval_scheds = R.eval_schedulers;
    allM        = R.metrics;
    K           = numel(schemes);
    simTime     = R.opts.simTime;
    n_eval      = R.opts.n_eval;
    ptypes      = {'baseline','olla','ql','ac','a2c'};

    % Representative trained policy per scheme (mirror the harness: seed ~2)
    QL = pick(R.policies.QL); AC = pick(R.policies.AC); A2C = pick(R.policies.A2C);
    pol_of = {[], [], QL, AC, A2C};

    % Regenerate the exact held-out traces (deterministic)
    traces = struct('SINR',{},'obsS',{},'dist',{});
    for j = 1:n_eval
        rng(9000 + j);
        [Strue, dist, ~] = generateChannel_v5(simTime, env);
        [obsS, ~] = cqiFeedback_v5(Strue, env);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).dist = dist; %#ok<AGROW>
    end

    for sc = 1:numel(eval_scheds)
        lbl  = upper(eval_scheds{sc});
        envE = env; envE.scheduler = eval_scheds{sc};

        % --- recompute tp / bler fields for this scheduler (no training) ---
        tpf = cell(K, n_eval); blf = cell(K, n_eval);
        for j = 1:n_eval
            for k = 1:K
                rng(77000 + 100*j + 10*k + 2);
                [tp, bl] = evalPolicy_v5(ptypes{k}, pol_of{k}, traces(j).SINR, traces(j).obsS, envE);
                tpf{k,j} = tp; blf{k,j} = bl;
            end
        end

        kpi_bars(schemes, allM(sc), env, lbl, K);
        tp_vs_distance(schemes, tpf, traces, n_eval, lbl, K);
        bler_vs_distance(schemes, blf, traces, n_eval, lbl, K);
        try
            envH = env; envH.scheduler = eval_scheds{sc};
            plotPolicyHeatmap_v5(A2C, 'a2c', envH);
        catch ME
            warning('heatmap (%s) skipped: %s', lbl, ME.message);
        end
    end

    if isfield(R,'learning')
        learning_curves(R.learning.ql, R.learning.ac, R.learning.dac, R.entropy.dac, simTime, env);
    end
    fprintf('Replotted per-scheduler figures for {%s}.\n', strjoin(eval_scheds, '/'));
end


% ===== helpers =====

function p = pick(c)
    if isempty(c), p = []; elseif numel(c) >= 2, p = c{2}; else, p = c{1}; end
end

function [m, ci] = mci(x)
    x = x(~isnan(x)); n = numel(x); m = mean(x);
    if n > 1, ci = 1.96*std(x)/sqrt(n); else, ci = 0; end
end

function kpi_bars(schemes, M, env, lbl, K)
    mt=zeros(1,K); ct=zeros(1,K); mb=zeros(1,K); mj=zeros(1,K);
    for k = 1:K
        [mt(k),ct(k)] = mci(M.cell_tp{k}(:));
        mb(k) = mean(M.bler{k}(:),'omitnan'); mj(k) = mean(M.jain{k}(:));
    end
    sup = sprintf('v5 KPIs  |  Case %d  |  N=%d  |  scheduler=%s', env.caseId, env.N, lbl);
    figure('Position',[60 60 1200 420],'Name',sprintf('v5 KPIs (%s)', lbl),'Color','w');
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

function tp_vs_distance(schemes, tpf, traces, n_eval, lbl, K)
    [edges, ctr] = dist_bins(traces, n_eval);
    cols = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    sty  = {'--','-.','-','-','-'};
    figure('Position',[60 60 1050 460],'Name',sprintf('v5 Tp vs distance (%s)', lbl),'Color','w');
    hold on; grid on; h = gobjects(1,K);
    for k = 1:K
        dv=[]; tv=[];
        for j = 1:n_eval, dv=[dv; traces(j).dist(:)]; tv=[tv; tpf{k,j}(:)]; end %#ok<AGROW>
        sm = tv > 0; b = nan(1,numel(ctr));
        for q = 1:numel(ctr)
            in = sm & dv>=edges(q) & dv<edges(q+1);
            if any(in), b(q) = mean(tv(in)); end
        end
        h(k) = plot(ctr, b, sty{k}, 'Color', cols{k}, 'LineWidth', 1.9);
    end
    xlabel('Distance from BS (m)','FontSize',10);
    ylabel('Served throughput (Mbps)','FontSize',10);
    title(sprintf('Throughput vs distance  |  scheduler=%s  (held-out, served TTIs)', lbl), ...
          'FontWeight','bold','FontSize',11);
    legend(h, schemes, 'Location','best','FontSize',10);
end

function bler_vs_distance(schemes, blf, traces, n_eval, lbl, K)
    [edges, ctr] = dist_bins(traces, n_eval);
    cols = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    sty  = {'--','-.','-','-','-'};
    figure('Position',[60 60 1050 460],'Name',sprintf('v5 BLER vs distance (%s)', lbl),'Color','w');
    hold on; grid on; h = gobjects(1,K);
    for k = 1:K
        dv=[]; bv=[];
        for j = 1:n_eval, dv=[dv; traces(j).dist(:)]; bv=[bv; blf{k,j}(:)]; end %#ok<AGROW>
        b = nan(1,numel(ctr));               % BLER defined every TTI -> all entries
        for q = 1:numel(ctr)
            in = dv>=edges(q) & dv<edges(q+1);
            if any(in), b(q) = mean(bv(in)); end
        end
        h(k) = plot(ctr, b, sty{k}, 'Color', cols{k}, 'LineWidth', 1.9);
    end
    yline(0.1,'k--','target','LineWidth',1.1,'LabelHorizontalAlignment','left');
    xlabel('Distance from BS (m)','FontSize',10); ylabel('Mean BLER','FontSize',10); ylim([0 1]);
    title(sprintf('BLER vs distance  |  scheduler=%s  (held-out)', lbl), ...
          'FontWeight','bold','FontSize',11);
    legend(h, schemes, 'Location','best','FontSize',10);
end

function [edges, ctr] = dist_bins(traces, n_eval)
    d_all = [];
    for j = 1:n_eval, d_all = [d_all; traces(j).dist(:)]; end %#ok<AGROW>
    edges = linspace(min(d_all), max(d_all), 26);
    ctr   = (edges(1:end-1)+edges(2:end))/2;
end

function learning_curves(lc_ql, lc_ac, lc_dac, ent_dac, simTime, env)
    spe = simTime*env.N;
    figure('Position',[60 60 1050 440],'Name','v5 learning curves','Color','w');
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
    sgtitle(sprintf('v5 Learning curves  |  Case %d  |  N=%d', env.caseId, env.N),'FontWeight','bold','FontSize',12);
end

function hline = shaded(x, Y, c)
    mu = mean(Y,2).'; sd = std(Y,0,2).';
    fill([x fliplr(x)], [mu+sd fliplr(mu-sd)], c, 'FaceAlpha',0.15, 'EdgeColor','none');
    hline = plot(x, mu, 'Color', c, 'LineWidth', 1.6);
end
