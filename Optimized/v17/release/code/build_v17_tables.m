% build_v17_tables  Stage E (PLAN_v17.md): table_core.csv, table_harq_ablation.csv
% and table_training_length.csv, parsed from the already-validated
% REPLCMP/REPL/WIN lines in Dataset/fill_summary_v17.txt (same numbers
% reported in README_v17.md and to the user; no re-computation).
v17_setup;
outDir = fullfile(v17, 'paper');
if ~exist(outDir, 'dir'), mkdir(outDir); end
sumf = fullfile(ds, 'fill_summary_v17.txt');
lines = strsplit(fileread(sumf), '\n');

% ---- table_core.csv: every REPLCMP line (case, scheme, comparator, margin, CI, p, holm, beats) ----
% REPLCMP|<tag>|<sched>|<schemeShort> vs <comparator>|pct=<..>|ci90pct=[<lo> <hi>]|p=<..>|holm=<..>|beats=<..>
% Each REPLCMP block is preceded by the matching REPL block's "scheme=" line
% a few lines later -- but REPLCMP itself only names the comparator, not
% which RL scheme it is testing. We track the active scheme by remembering
% the most recent CONFIG/analyze_v17_replication call boundary: each
% analyze_v17_replication(...) call emits its REPLCMP block, then its
% REPLSEED line, then its REPL line(s) -- so the REPL line(s) immediately
% following a REPLCMP block state which scheme that block was for.
core = fopen(fullfile(outDir, 'table_core.csv'), 'w');
fprintf(core, 'case_tag,scheme,comparator,pct_margin,ci90_lo,ci90_hi,wilcoxon_p,holm_p,beats,jain_rl,jain_cmp,edge_rl,edge_cmp\n');

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
        jain_rl = ''; jain_cmp = ''; edge_rl = ''; edge_cmp = '';
        if numel(parts) >= 13
            jain_rl = regexprep(parts{10}, 'jain_rl=', '');
            jain_cmp = regexprep(parts{11}, 'jain_cmp=', '');
            edge_rl = regexprep(parts{12}, 'edge_rl=', '');
            edge_cmp = regexprep(parts{13}, 'edge_cmp=', '');
        end
        pendingCMP(end+1) = {struct('tag', tag, 'comp', comp, 'pct', pct, ...
            'lo', ciParts{1}, 'hi', ciParts{2}, 'p', p, 'holm', holm, 'beats', beats, ...
            'jain_rl', jain_rl, 'jain_cmp', jain_cmp, 'edge_rl', edge_rl, 'edge_cmp', edge_cmp)}; %#ok<AGROW>
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
                fprintf(core, '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n', ...
                    tag, scheme, row.comp, row.pct, row.lo, row.hi, row.p, row.holm, row.beats, ...
                    row.jain_rl, row.jain_cmp, row.edge_rl, row.edge_cmp);
                keep(r) = false;
            end
        end
        pendingCMP = pendingCMP(keep);
    end
end
fclose(core);
fprintf('table_core.csv written (%s)\n', fullfile(outDir, 'table_core.csv'));

% ---- table_harq_ablation.csv: K1 vs K2 (deadline) and K3 vs K4 (goodput), A2C-resid primary scheme ----
% Pull each case's primary-scheme (A2C-resid, scheme == 'Deep A2C v17')
% margin vs Fixed from table_core.csv (already written), then compute the
% RTT8-minus-RTT0 swing.
T = readtable(fullfile(outDir, 'table_core.csv'));
abl = fopen(fullfile(outDir, 'table_harq_ablation.csv'), 'w');
fprintf(abl, 'traffic,case_rtt8,case_rtt0,comparator,pct_rtt8,pct_rtt0,swing_pp\n');
pairs = {'deadline', 'M1_dl_rtt8', 'M2_dl_rtt0'; 'goodput', 'M3_gp_rtt8', 'M4_gp_rtt0'};
comparators = {'Baseline', 'OLLA', 'OLLA (tuned target)', 'Multi-OLLA', 'Fixed', ...
               'FixedPU (Oracle)', 'Context table', 'Bandit (global)', 'Bandit (delay class)'};
for r = 1:size(pairs, 1)
    traffic = pairs{r, 1}; c8 = pairs{r, 2}; c0 = pairs{r, 3};
    for ci = 1:numel(comparators)
        row8 = T(strcmp(T.case_tag, c8) & strcmp(T.scheme, 'Deep A2C v17') & strcmp(T.comparator, comparators{ci}), :);
        row0 = T(strcmp(T.case_tag, c0) & strcmp(T.scheme, 'Deep A2C v17') & strcmp(T.comparator, comparators{ci}), :);
        if isempty(row8) || isempty(row0), continue; end
        p8 = row8.pct_margin(1); p0 = row0.pct_margin(1);
        fprintf(abl, '%s,%s,%s,%s,%.2f,%.2f,%.2f\n', traffic, c8, c0, comparators{ci}, p8, p0, p8 - p0);
    end
end
fclose(abl);
fprintf('table_harq_ablation.csv written (%s)\n', fullfile(outDir, 'table_harq_ablation.csv'));

% ---- table_training_length.csv: 800ep vs 3000ep in M1 and M2, with CI-based verdict ----
tl = fopen(fullfile(outDir, 'table_training_length.csv'), 'w');
fprintf(tl, 'traffic,case_tag,comparator,pct_800ep,ci90_800ep_lo,ci90_800ep_hi,pct_3000ep,ci90_3000ep_lo,ci90_3000ep_hi,verdict\n');
cases = {'deadline_rtt8', 'M1_dl_rtt8'; 'deadline_rtt0', 'M2_dl_rtt0'};
for r = 1:size(cases, 1)
    traffic = cases{r, 1}; ctag = cases{r, 2};
    row800 = T(strcmp(T.case_tag, ctag) & strcmp(T.scheme, 'Deep A2C v17 (resid-800)') & strcmp(T.comparator, 'Fixed'), :);
    row3000 = T(strcmp(T.case_tag, ctag) & strcmp(T.scheme, 'Deep A2C v17') & strcmp(T.comparator, 'Fixed'), :);
    if isempty(row800) || isempty(row3000), continue; end
    lo800 = row800.ci90_lo(1); hi800 = row800.ci90_hi(1);
    lo3000 = row3000.ci90_lo(1); hi3000 = row3000.ci90_hi(1);
    if lo3000 > hi800
        verdict = 'training-limited';
    else
        verdict = 'not training-limited';
    end
    fprintf(tl, '%s,%s,Fixed,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%s\n', ...
        traffic, ctag, row800.pct_margin(1), lo800, hi800, row3000.pct_margin(1), lo3000, hi3000, verdict);
end
fclose(tl);
fprintf('table_training_length.csv written (%s)\n', fullfile(outDir, 'table_training_length.csv'));
