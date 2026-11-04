% generate_v17_figures  Stage E (PLAN_v17.md): publication figures from the
% v17 campaign results, in the v8-style palette/layout (generate_figures_v8.m).
% PNG + PDF into Optimized/v17/paper/figures/.
v17_setup;
figdir = fullfile(v17, 'paper', 'figures');
if ~exist(figdir, 'dir'), mkdir(figdir); end

c_blue   = [0.12, 0.47, 0.71];
c_orange = [1.00, 0.50, 0.05];
c_green  = [0.17, 0.63, 0.17];
c_red    = [0.84, 0.15, 0.16];
c_purple = [0.58, 0.40, 0.74];
c_gray   = [0.50, 0.50, 0.50];

names = {'M1_dl_rtt8', 'M2_dl_rtt0', 'M3_gp_rtt8', 'M4_gp_rtt0'};
R = struct();
for i = 1:numel(names)
    f = fullfile(ds, ['results_v17_' names{i} '.mat']);
    L = load(f, 'results'); R.(names{i}) = L.results;
end

% -------------------------------------------------------------
% Fig set 1: on-time/goodput bars per scheme, one figure per case
% -------------------------------------------------------------
for i = 1:numel(names)
    tag = names{i}; res = R.(tag); M = res.metrics(1); schemes = res.schemes; K = numel(schemes);
    isPrimary = contains(schemes, 'ontime') | true; %#ok<NASGU> % metric picked below
    primaryName = res.env.primary; % 'ontime' or 'goodput'
    vals = zeros(1, K); errs = zeros(1, K);
    detK = 7;
    for k = 1:K
        if strcmpi(primaryName, 'ontime')
            v = M.ontime{k}; ylab = 'On-time fraction';
        else
            v = M.cell_tp{k}; ylab = 'Cell throughput (Mbps)';
        end
        if k <= detK || contains(schemes{k}, 'ensemble')
            row = v(1, :);
        else
            row = mean(v, 1, 'omitnan');
        end
        row = row(~isnan(row));
        vals(k) = mean(row); errs(k) = 1.96 * std(row) / sqrt(numel(row));
    end
    f1 = figure('Position', [100, 100, 1000, 480], 'Visible', 'off');
    b = bar(vals, 'FaceColor', 'flat', 'EdgeColor', 'none', 'BarWidth', 0.65); hold on;
    errorbar(1:K, vals, errs, 'k.', 'LineWidth', 1, 'CapSize', 6);
    for k = 1:K
        if contains(schemes{k}, 'PPO'), b.CData(k, :) = c_purple;
        elseif contains(schemes{k}, 'offset'), b.CData(k, :) = c_green;
        elseif contains(schemes{k}, 'Deep A2C'), b.CData(k, :) = c_blue;
        else, b.CData(k, :) = c_gray;
        end
    end
    set(gca, 'XTick', 1:K, 'XTickLabel', schemes, 'XTickLabelRotation', 45, 'FontSize', 8);
    ylabel(ylab); title(sprintf('%s -- %s', tag, primaryName), 'Interpreter', 'none');
    grid on; box off;
    exportgraphics(f1, fullfile(figdir, sprintf('bars_%s.png', tag)), 'Resolution', 200);
    exportgraphics(f1, fullfile(figdir, sprintf('bars_%s.pdf', tag)));
    close(f1);
    fprintf('[fig] bars_%s\n', tag);
end

% -------------------------------------------------------------
% Fig set 2: primary residual A2C margin vs HARQ RTT (v17 only)
% -------------------------------------------------------------
% Rewritten 4 Nov 2026 (paper ledger, conflict C1): the previous version
% hard-coded superseded v15/v16 values. Every value plotted here is read
% from paper/table_core.csv (built by build_v17_tables.m from the v17
% REPLCMP lines). RTT 0 = M2/M4 (1 process), RTT 8 = M1/M3 (8 processes).
% Deadline cases use 3000 training episodes, goodput cases 800 (C2).
Tc = readtable(fullfile(v17, 'paper', 'table_core.csv'), 'TextType', 'string');
num = @(x) str2double(string(x));
pick = @(tag, cmp) Tc(Tc.case_tag == tag & Tc.scheme == "Deep A2C v17" & Tc.comparator == cmp, :);
pairs = {"M2_dl_rtt0", "M1_dl_rtt8", "deadline"; "M4_gp_rtt0", "M3_gp_rtt8", "goodput"};
cmps  = ["Context table", "Fixed"];
rtt   = [0 8];
f2 = figure('Position', [100, 100, 700, 480], 'Visible', 'off'); hold on;
cols = {c_blue, c_orange}; mk = {'-o', '-s'; '--o', '--s'};
lgd = {};
for p = 1:size(pairs, 1)
    for c = 1:numel(cmps)
        m = zeros(1, 2); lo = m; hi = m;
        for r = 1:2
            row = pick(pairs{p, r}, cmps(c));
            assert(height(row) == 1, 'table_core.csv: expected one row for %s / %s', pairs{p, r}, cmps(c));
            m(r) = num(row.pct_margin); lo(r) = num(row.ci90_lo); hi(r) = num(row.ci90_hi);
        end
        errorbar(rtt + 0.15 * (c - 1.5), m, m - lo, hi - m, mk{c, p}, 'Color', cols{p}, ...
                 'LineWidth', 1.5, 'MarkerFaceColor', cols{p}, 'MarkerSize', 7, 'CapSize', 6);
        lgd{end+1} = sprintf('%s vs %s', pairs{p, 3}, cmps(c)); %#ok<SAGROW>
    end
end
yline(0, 'k:');
xlim([-1 9]); xticks(rtt);
xlabel('HARQ RTT (TTI)'); ylabel('Residual A2C margin (%), 90% CI');
legend(lgd, 'Location', 'best');
title('v17: residual A2C margin vs calibrated rules');
grid on; box off;
exportgraphics(f2, fullfile(figdir, 'margin_vs_rtt.png'), 'Resolution', 200);
exportgraphics(f2, fullfile(figdir, 'margin_vs_rtt.pdf'));
close(f2);
fprintf('[fig] margin_vs_rtt\n');

% -------------------------------------------------------------
% Fig set 3: action histogram of A2C-resid (primary scheme), per case
% -------------------------------------------------------------
for i = 1:numel(names)
    tag = names{i}; res = R.(tag); M = res.metrics(1); schemes = res.schemes;
    aK = find(strcmp(schemes, 'Deep A2C v17'), 1);
    if isempty(aK), continue; end
    ah = sum(M.act_hist{aK}, 1); ah = ah / max(sum(ah), 1);
    actSet = res.env.resid_actions;
    ah = ah(1:numel(actSet));
    f3 = figure('Position', [100, 100, 500, 400], 'Visible', 'off');
    bar(actSet, ah, 'FaceColor', c_blue, 'EdgeColor', 'none', 'BarWidth', 0.5);
    xlabel('Residual action \delta'); ylabel('Fraction of decisions');
    title(sprintf('%s -- A2C-resid action histogram', tag), 'Interpreter', 'none');
    ylim([0, 1]); grid on; box off;
    exportgraphics(f3, fullfile(figdir, sprintf('acthist_%s.png', tag)), 'Resolution', 200);
    exportgraphics(f3, fullfile(figdir, sprintf('acthist_%s.pdf', tag)));
    close(f3);
    fprintf('[fig] acthist_%s\n', tag);
end

fprintf('All v17 figures written to %s\n', figdir);
