% fill_v11_P1_campaign  README_v11.md pre-registered P1 cases (target-BLER
% action space): T1_gp, T2_stale, T4_deadline. 5 seeds, 300 evaluation
% traces each (per the case definitions in v11_setup.m).
% Progress: logs/fill_v11_P1.log ; numbers: Dataset/fill_summary_v11_P1.txt
% Resumable: a point whose STEP|tag|done line exists is skipped.
v11_setup;
logf = fullfile(v11, 'logs', 'fill_v11_P1.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v11_P1.txt');
fid = fopen(sumf, 'a');
fprintf(fid, '\nV11-P1 CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;
P = cell(0, 2);
P(end+1, :) = {'T1_gp',      C.T1_gp};
P(end+1, :) = {'T2_stale',   C.T2_stale};
P(end+1, :) = {'T4_deadline', C.T4_deadline};
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
fprintf(fid, '\nV11-P1 CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
diary off;
