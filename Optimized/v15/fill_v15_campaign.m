% fill_v15_campaign  v15 campaign execution
% Sequence: Z1_rtt8 -> Z2_rtt4 -> Z3_rtt8_loose
% Progress: logs/fill_v15.log ; numbers: Dataset/fill_summary_v15.txt
% Resumable: a point whose STEP|tag|done line exists is skipped; trained seeds in Dataset/ckpt.

v15_setup;
logf = fullfile(v15, 'logs', 'fill_v15.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v15.txt');
if ~exist(sumf, 'file')
    fid = fopen(sumf, 'w'); fclose(fid);
end
fid = fopen(sumf, 'a');
fprintf(fid, '\nV15 CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;

P = {
    'Z1_rtt8',       C.Z1_rtt8;
    'Z2_rtt4',       C.Z2_rtt4;
    'Z3_rtt8_loose', C.Z3_rtt8_loose
};

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
        runComparison_v15(o);
        f = fullfile(ds, ['results_v15_' tag '.mat']);
        fid = fopen(sumf, 'a');
        fill_stats_v15(f, tag, fid, 1);
        analyze_v15_replication(f, tag, fid, 1);
        fprintf(fid, 'STEP|%s|done|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
        fclose(fid);
    catch ME
        fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end

fid = fopen(sumf, 'a');
analyze_v15_rtteff(fid);
fprintf(fid, '\nV15 CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
diary off;
