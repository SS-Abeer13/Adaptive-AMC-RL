% fill_v11b_campaign  Declared deviation (20 Oct 2026, after the v11 run):
% the per-user goodput reward let the shared agent spend other users' slots
% on failed / retransmitted blocks (bimodal -4/+2 policy, training goodput
% falling 2.6 -> 1.6 Mbps in all seeds of E1). v11b charges every scheduled
% slot the OLLA-reference expected goodput (reward_kind = 'oppcost').
% Environments, comparators, seeds and the win criterion are unchanged;
% the original v11 goodput-reward results stay in the summary and are reported.
v11_setup;
logf = fullfile(v11, 'logs', 'fill_v11b.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v11.txt');
fid = fopen(sumf, 'a');
fprintf(fid, '\nV11B CAMPAIGN started %s | reward_kind=oppcost for E1-E3\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fclose(fid);
T0 = tic;
P = cell(0, 2);
P(end+1, :) = {'E1_train_b',   C.E1_train};
P(end+1, :) = {'E2_stale_b',   C.E2_stale};
P(end+1, :) = {'E3_cellcue_b', C.E3_cellcue};
o = C.E2_stale;   o.feat_extra = {}; P(end+1, :) = {'E2_stale_nofeat_b', o};
o = C.E3_cellcue; o.feat_extra = {}; P(end+1, :) = {'E3_cellcue_nofeat_b', o};
for p = 1:size(P, 1)
    tag = P{p, 1};
    sumtxt = fileread(sumf);
    if contains(sumtxt, ['STEP|' tag '|done']), fprintf('SKIP %s (done)\n', tag); continue; end
    fprintf('\n######## %s | %s | elapsed %.1f min ########\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
    fid = fopen(sumf, 'a'); fprintf(fid, '\nSTEP|%s|start|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60); fclose(fid);
    try
        o = base; ov = P{p, 2}; fn = fieldnames(ov);
        for q = 1:numel(fn), o.(fn{q}) = ov.(fn{q}); end
        o.reward_kind = 'oppcost';
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
fprintf(fid, '\nV11B CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
diary off;
