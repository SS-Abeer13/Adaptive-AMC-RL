% fill_v16_campaign  v16 campaign execution (PLAN_v16.md Stage D).
% Sequence: K1_dl_rtt8 -> K3_gp_rtt8 -> K2_dl_rtt0 -> K4_gp_rtt0 -> L1_dl_rtt8_long -> L3_gp_rtt8_long
% (realistic-HARQ headline cells first, per the plan).
% Progress: logs/fill_v16.log ; numbers: Dataset/fill_summary_v16.txt
% Resumable: a point whose STEP|tag|done line exists is skipped; trained seeds in Dataset/ckpt.
% Each RL scheme present in a case (A2C-resid always; A2C-offset and PPO for
% the K cases, per README_v16.md S3.3) gets its own REPL line via
% analyze_v16_replication's schemeName argument.

v16_setup;
logf = fullfile(v16, 'logs', 'fill_v16.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v16.txt');
if ~exist(sumf, 'file')
    fid = fopen(sumf, 'w'); fclose(fid);
end
fid = fopen(sumf, 'a');
fprintf(fid, '\nV16 CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;

P = {
    'K1_dl_rtt8',       C.K1_dl_rtt8;
    'K3_gp_rtt8',       C.K3_gp_rtt8;
    'K2_dl_rtt0',       C.K2_dl_rtt0;
    'K4_gp_rtt0',       C.K4_gp_rtt0;
    'L1_dl_rtt8_long',  C.L1_dl_rtt8_long;
    'L3_gp_rtt8_long',  C.L3_gp_rtt8_long
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
        runComparison_v16(o);
        f = fullfile(ds, ['results_v16_' tag '.mat']);
        fid = fopen(sumf, 'a');
        fill_stats_v16(f, tag, fid, 1);
        schemeNames = {'Deep A2C v16'};
        if isfield(o, 'train_a2c_offset') && o.train_a2c_offset, schemeNames{end+1} = 'Deep A2C v16 (offset)'; end
        if isfield(o, 'train_ppo') && o.train_ppo, schemeNames{end+1} = 'Deep PPO v16'; end
        for sn = 1:numel(schemeNames)
            analyze_v16_replication(f, tag, fid, 1, schemeNames{sn});
        end
        fprintf(fid, 'STEP|%s|done|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
        fclose(fid);
    catch ME
        fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end

fid = fopen(sumf, 'a');
% Note: analyze_v16_rtteff.m is inherited from the v15 Z1/Z2/Z3 RTT-ablation
% cases and does not apply to v16's K1-K4/L1/L3 case set (Stage E will need
% its own K1-vs-K2 / K3-vs-K4 HARQ-ablation analyzer -- not needed for the
% campaign run itself, so not called here).
fprintf(fid, '\nV16 CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
diary off;
