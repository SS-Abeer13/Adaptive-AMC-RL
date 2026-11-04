% fill_v11_P2_campaign  README_v11.md pre-registered P2 cases (PPO + GAE,
% trained alongside A2C): T1_gp_ppo, T2_stale_ppo, T4_deadline_ppo. Same
% cases/comparators/win-criterion as the P1 campaign, under new tags.
% Progress: logs/fill_v11_P2.log ; numbers: Dataset/fill_summary_v11_P2.txt
% Resumable: a point whose STEP|tag|done line exists is skipped.
v11_setup;
logf = fullfile(v11, 'logs', 'fill_v11_P2.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v11_P2.txt');
fid = fopen(sumf, 'a');
fprintf(fid, '\nV11-P2 CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;
P = cell(0, 2);
P(end+1, :) = {'T1_gp_ppo',       C.T1_gp_ppo};
P(end+1, :) = {'T2_stale_ppo',    C.T2_stale_ppo};
P(end+1, :) = {'T4_deadline_ppo', C.T4_deadline_ppo};
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
fprintf(fid, '\nV11-P2 CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
diary off;
