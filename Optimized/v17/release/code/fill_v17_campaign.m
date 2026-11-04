% fill_v17_campaign  v17 campaign execution (PLAN_v17.md Stage D).
% Sequence: M1_dl_rtt8 -> M2_dl_rtt0 -> M3_gp_rtt8 -> M4_gp_rtt0
% Progress: logs/fill_v17.log ; numbers: Dataset/fill_summary_v17.txt
% Resumable: a point whose STEP|tag|done line exists is skipped; trained seeds in Dataset/ckpt.
% Each RL scheme present in a case gets its own REPL line via analyze_v17_replication.

v17_setup;
logf = fullfile(v17, 'logs', 'fill_v17.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v17.txt');
if ~exist(sumf, 'file')
    fid = fopen(sumf, 'w'); fclose(fid);
end
fid = fopen(sumf, 'a');
fprintf(fid, '\nV17 CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;

P = {
    'M1_dl_rtt8',       C.M1_dl_rtt8;
    'M2_dl_rtt0',       C.M2_dl_rtt0;
    'M3_gp_rtt8',       C.M3_gp_rtt8;
    'M4_gp_rtt0',       C.M4_gp_rtt0
};

for p = 1:size(P, 1)
    tag = P{p, 1};
    sumtxt = fileread(sumf);
    if contains(sumtxt, ['STEP|' tag '|done']), fprintf('SKIP %s (done)\n', tag); continue; end
    fprintf('\n######## %s | %s | elapsed %.1f min ########\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
    fid = fopen(sumf, 'a'); fprintf(fid, '\nSTEP|%s|start|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60); fclose(fid);
    update_heartbeat_v17(tag, 'Starting case', 0, 0, 0);
    
    o = base; ov = P{p, 2}; fn = fieldnames(ov);
    for q = 1:numel(fn), o.(fn{q}) = ov.(fn{q}); end
    o.save_tag = tag;
    
    success = false;
    try
        runComparison_v17(o);
        record_case_results_v17(tag, o, ds, sumf, T0);
        success = true;
    catch ME
        isOOM = contains(lower(ME.message), 'out of memory') || ...
                contains(lower(ME.identifier), 'outofmemory') || ...
                contains(lower(getReport(ME)), 'out of memory');
        if isOOM
            fprintf('\n>>> WARNING: Case %s failed with Out of Memory. Retrying with 2 parfor workers...\n', tag);
            try
                o.use_parfor = true;
                o.n_workers  = 2;
                update_heartbeat_v17(tag, 'Retry OOM (2 workers)', 0, 0, 0);
                runComparison_v17(o);
                record_case_results_v17(tag, o, ds, sumf, T0);
                success = true;
            catch ME2
                fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME2.message); fclose(fid);
                disp(getReport(ME2, 'extended', 'hyperlinks', 'off'));
            end
        else
            fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); fclose(fid);
            disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
        end
    end
end

% Check that EVERY case has a STEP|tag|done line
sumtxt = fileread(sumf);
allDone = true;
for p = 1:size(P, 1)
    tag = P{p, 1};
    if ~contains(sumtxt, ['STEP|' tag '|done'])
        allDone = false;
        break;
    end
end

if allDone
    fid = fopen(sumf, 'a');
    fprintf(fid, '\nV17 CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
    fclose(fid);
    update_heartbeat_v17('ALL', 'V17 CAMPAIGN finished', 0, 0, 0);
    diary off;
    fprintf('\n=== ALL CASES FINISHED SUCCESSFULLY ===\n');
else
    diary off;
    fprintf(2, '\nERROR: Not all cases have STEP|tag|done. Exiting MATLAB with code 1 for auto-restart.\n');
    exit(1);
end

function record_case_results_v17(tag, o, ds, sumf, T0)
    f = fullfile(ds, ['results_v17_' tag '.mat']);
    fid = fopen(sumf, 'a');
    fill_stats_v17(f, tag, fid, 1);
    schemeNames = {'Deep A2C v17'};
    if isfield(o, 'train_a2c_offset') && o.train_a2c_offset, schemeNames{end+1} = 'Deep A2C v17 (offset)'; end
    if isfield(o, 'train_a2c_resid_800') && o.train_a2c_resid_800, schemeNames{end+1} = 'Deep A2C v17 (resid-800)'; end
    for sn = 1:numel(schemeNames)
        analyze_v17_replication(f, tag, fid, 1, schemeNames{sn});
    end
    fprintf(fid, 'STEP|%s|done|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
    fclose(fid);
end
