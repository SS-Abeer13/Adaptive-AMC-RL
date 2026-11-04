% fill_v12_campaign  v12 replication campaign: R1_pf (primary), R2_edf (secondary).
% Progress: logs/fill_v12.log ; numbers: Dataset/fill_summary_v12.txt
% Resumable: a point whose STEP|tag|done line exists is skipped; trained seeds in Dataset/ckpt.
v12_setup;
logf = fullfile(v12, 'logs', 'fill_v12.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v12.txt');
fid = fopen(sumf, 'a');
fprintf(fid, '\nV12 CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;
P = {'R1_pf', C.R1_pf; 'R2_edf', C.R2_edf};
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
        runComparison_v12(o);
        f = fullfile(ds, ['results_v12_' tag '.mat']);
        fid = fopen(sumf, 'a');
        fill_stats_v12(f, tag, fid, 1);
        analyze_v12_replication(f, tag, fid, 1);
        fprintf(fid, 'STEP|%s|done|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
        fclose(fid);
    catch ME
        fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end
fid = fopen(sumf, 'a');
fprintf(fid, '\nV12 CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
diary off;
