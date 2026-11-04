% build_v16_tables  Stage E (PLAN_v16.md): table_core.csv, table_harq_ablation.csv
% and table_training_length.csv, parsed from the already-validated
% REPLCMP/REPL/WIN lines in Dataset/fill_summary_v16.txt (same numbers
% reported in README_v16.md and to the user; no re-computation).
v16_setup;
outDir = fullfile(v16, 'paper');
if ~exist(outDir, 'dir'), mkdir(outDir); end
sumf = fullfile(ds, 'fill_summary_v16.txt');
lines = strsplit(fileread(sumf), '\n');

% ---- table_core.csv: every REPLCMP line (case, scheme, comparator, margin, CI, p, holm, beats) ----
% REPLCMP|<tag>|<sched>|<schemeShort> vs <comparator>|pct=<..>|ci90pct=[<lo> <hi>]|p=<..>|holm=<..>|beats=<..>
% Each REPLCMP block is preceded by the matching REPL block's "scheme=" line
% a few lines later -- but REPLCMP itself only names the comparator, not
% which RL scheme it is testing. We track the active scheme by remembering
% the most recent CONFIG/analyze_v16_replication call boundary: each
% analyze_v16_replication(...) call emits its REPLCMP block, then its
% REPLSEED line, then its REPL line(s) -- so the REPL line(s) immediately
% following a REPLCMP block state which scheme that block was for.
core = fopen(fullfile(outDir, 'table_core.csv'), 'w');
fprintf(core, 'case_tag,scheme,comparator,pct_margin,ci90_lo,ci90_hi,wilcoxon_p,holm_p,beats\n');

pendingCMP = {};  % buffer of REPLCMP rows waiting for their scheme label
for i = 1:numel(lines)
    ln = strtrim(lines{i});
    if startsWith(ln, 'REPLCMP|')
        parts = strsplit(ln, '|');
        tag = parts{2};
        schemeVsComp = parts{4};  % "A2C vs <comparator>"
        comp = strtrim(regexprep(schemeVsComp, '^.*? vs ', ''));
        pct = regexprep(parts{5}, 'pct=', '');
        ci = regexprep(parts{6}, 'ci90pct=\[|\]', '');
        ciParts = strsplit(strtrim(ci), ' ');
        p = regexprep(parts{7}, 'p=', '');
        holm = regexprep(parts{8}, 'holm=', '');
        beats = regexprep(parts{9}, 'beats=', '');
        pendingCMP(end+1) = {struct('tag', tag, 'comp', comp, 'pct', pct, ...
            'lo', ciParts{1}, 'hi', ciParts{2}, 'p', p, 'holm', holm, 'beats', beats)}; %#ok<AGROW>
    elseif startsWith(ln, 'REPL|') && ~isempty(pendingCMP)
        parts = strsplit(ln, '|');
        tag = parts{2};
        schemeTok = parts{4};  % "scheme=<name>"
        scheme = regexprep(schemeTok, '^scheme=', '');
        % Flush every buffered REPLCMP row for this tag (the block that
        % belongs to the scheme named by this REPL line -- buffered rows
        % are consumed exactly once, in the same case-by-case,
        % scheme-by-scheme order they were written).
        keep = true(1, numel(pendingCMP));
        for r = 1:numel(pendingCMP)
            row = pendingCMP{r};
            if strcmp(row.tag, tag)
                fprintf(core, '%s,%s,%s,%s,%s,%s,%s,%s,%s\n', ...
                    tag, scheme, row.comp, row.pct, row.lo, row.hi, row.p, row.holm, row.beats);
                keep(r) = false;
            end
        end
        pendingCMP = pendingCMP(keep);
    end
end
fclose(core);
fprintf('table_core.csv written (%s)\n', fullfile(outDir, 'table_core.csv'));

% ---- table_harq_ablation.csv: K1 vs K2 (deadline) and K3 vs K4 (goodput), A2C-resid primary scheme ----
% Pull each case's primary-scheme (A2C-resid, scheme == 'Deep A2C v16')
% margin vs Fixed from table_core.csv (already written), then compute the
% RTT8-minus-RTT0 swing.
T = readtable(fullfile(outDir, 'table_core.csv'));
abl = fopen(fullfile(outDir, 'table_harq_ablation.csv'), 'w');
fprintf(abl, 'traffic,case_rtt8,case_rtt0,comparator,pct_rtt8,pct_rtt0,swing_pp\n');
pairs = {'deadline', 'K1_dl_rtt8', 'K2_dl_rtt0'; 'goodput', 'K3_gp_rtt8', 'K4_gp_rtt0'};
comparators = {'Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', 'Fixed', ...
               'FixedPU (Oracle)', 'Context table', 'Bandit (global)', 'Bandit (delay class)'};
for r = 1:size(pairs, 1)
    traffic = pairs{r, 1}; c8 = pairs{r, 2}; c0 = pairs{r, 3};
    for ci = 1:numel(comparators)
        row8 = T(strcmp(T.case_tag, c8) & strcmp(T.scheme, 'Deep A2C v16') & strcmp(T.comparator, comparators{ci}), :);
        row0 = T(strcmp(T.case_tag, c0) & strcmp(T.scheme, 'Deep A2C v16') & strcmp(T.comparator, comparators{ci}), :);
        if isempty(row8) || isempty(row0), continue; end
        p8 = row8.pct_margin(1); p0 = row0.pct_margin(1);
        fprintf(abl, '%s,%s,%s,%s,%.2f,%.2f,%.2f\n', traffic, c8, c0, comparators{ci}, p8, p0, p8 - p0);
    end
end
fclose(abl);
fprintf('table_harq_ablation.csv written (%s)\n', fullfile(outDir, 'table_harq_ablation.csv'));

% ---- table_training_length.csv: K1 vs L1, K3 vs L3, A2C-resid vs Fixed, with C5's CI-based verdict ----
tl = fopen(fullfile(outDir, 'table_training_length.csv'), 'w');
fprintf(tl, 'traffic,case_800ep,case_3000ep,comparator,pct_800ep,ci90_800ep_lo,ci90_800ep_hi,pct_3000ep,ci90_3000ep_lo,ci90_3000ep_hi,verdict\n');
tlPairs = {'deadline', 'K1_dl_rtt8', 'L1_dl_rtt8_long'; 'goodput', 'K3_gp_rtt8', 'L3_gp_rtt8_long'};
for r = 1:size(tlPairs, 1)
    traffic = tlPairs{r, 1}; c800 = tlPairs{r, 2}; c3000 = tlPairs{r, 3};
    row800 = T(strcmp(T.case_tag, c800) & strcmp(T.scheme, 'Deep A2C v16') & strcmp(T.comparator, 'Fixed'), :);
    row3000 = T(strcmp(T.case_tag, c3000) & strcmp(T.scheme, 'Deep A2C v16') & strcmp(T.comparator, 'Fixed'), :);
    if isempty(row800) || isempty(row3000), continue; end
    lo800 = row800.ci90_lo(1); hi800 = row800.ci90_hi(1);
    lo3000 = row3000.ci90_lo(1); hi3000 = row3000.ci90_hi(1);
    % C5: "training-limited" if the 3000-episode margin's CI lies entirely
    % above the 800-episode margin's CI.
    if lo3000 > hi800
        verdict = 'training-limited';
    else
        verdict = 'not training-limited';
    end
    fprintf(tl, '%s,%s,%s,Fixed,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%s\n', ...
        traffic, c800, c3000, row800.pct_margin(1), lo800, hi800, row3000.pct_margin(1), lo3000, hi3000, verdict);
end
fclose(tl);
fprintf('table_training_length.csv written (%s)\n', fullfile(outDir, 'table_training_length.csv'));
