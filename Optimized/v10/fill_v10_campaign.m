% fill_v10_campaign  Four structural-advantage cases + feature ablations.
% Progress: logs/fill_v10.log ; numbers: Dataset/fill_summary_v10.txt
% Resumable: a point whose STEP|tag|done line exists is skipped.
v10_setup;
logf = fullfile(v10, 'logs', 'fill_v10.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v10.txt');
fid = fopen(sumf, 'a');
fprintf(fid, '\nV10 CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;
P = cell(0, 2);
P(end+1, :) = {'E2_stale',     C.E2_stale};
P(end+1, :) = {'E3_cellcue',   C.E3_cellcue};
P(end+1, :) = {'E4_deadline',  C.E4_deadline};
P(end+1, :) = {'E1_train',     C.E1_train};
% ablations: same environment and comparators, A2C without the extra cue
ab = {'E2_stale', 'E3_cellcue', 'E4_deadline'};
for q = 1:numel(ab)
    o = C.(ab{q}); o.feat_extra = {}; P(end+1, :) = {[ab{q} '_nofeat'], o}; %#ok<SAGROW>
end
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
        runComparison_v10(o);
        fid = fopen(sumf, 'a');
        fill_stats_v10(fullfile(ds, ['results_v10_' tag '.mat']), tag, fid);
        fprintf(fid, 'STEP|%s|done|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
        fclose(fid);
    catch ME
        fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end
fid = fopen(sumf, 'a');
fprintf(fid, '\nV10 CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
diary off;
