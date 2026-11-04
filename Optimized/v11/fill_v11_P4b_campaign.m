% fill_v11_P4b_campaign  README_v11.md follow-up (requested 22 Oct 2026):
% R2_stale_opp, R3_cellcue_opp -- R2_stale/R3_cellcue re-run with
% reward_kind = 'oppcost' (v10b's fix for the offset-mode goodput-reward
% defect), to isolate whether proper credit assignment + GRU recurrence
% closes the remaining gap to Baseline.
% Progress: logs/fill_v11_P4b.log ; numbers: Dataset/fill_summary_v11_P4b.txt
% Resumable: a point whose STEP|tag|done line exists is skipped.
v11_setup;
logf = fullfile(v11, 'logs', 'fill_v11_P4b.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v11_P4b.txt');
fid = fopen(sumf, 'a');
fprintf(fid, '\nV11-P4b CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;
P = cell(0, 2);
P(end+1, :) = {'R2_stale_opp',  C.R2_stale_opp};
P(end+1, :) = {'R3_cellcue_opp', C.R3_cellcue_opp};
for p = 1:size(P, 1)
    tag = P{p, 1};
    sumtxt = fileread(sumf);
    if contains(sumtxt, ['STEP|' tag '|done']), fprintf('SKIP %s (done)\n', tag); continue; end
    fprintf('\n######## %s | %s | elapsed %.1f min ########\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
    fid = fopen(sumf, 'a'); fprintf(fid, '\nSTEP|%s|start|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60); fclose(fid);
    try
        o = base; ov = P{p, 2}; fn = fieldnames(ov);
        for q = 1:numel(fn), o.(fn{q}) = ov.(fn{q}); end
        o.save_tag = tag;
        runComparison_v11(o);
        fid = fopen(sumf, 'a');
        fill_stats_v11(fullfile(ds, ['results_v11_' tag '.mat']), tag, fid);
        fprintf(fid, 'STEP|%s|done|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
        fclose(fid);
    catch ME
        fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end
fid = fopen(sumf, 'a');
fprintf(fid, '\nV11-P4b CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
diary off;
