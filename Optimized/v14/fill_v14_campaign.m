% fill_v14_campaign  v14 campaign execution
% Sequence: Y0_base -> Y0_noshape -> Y1_lo_tight -> Y2_lo_loose -> Y3_hi_tight -> Y4_hi_loose
% Progress: logs/fill_v14.log ; numbers: Dataset/fill_summary_v14.txt
% Resumable: a point whose STEP|tag|done line exists is skipped; trained seeds in Dataset/ckpt.

v14_setup;
logf = fullfile(v14, 'logs', 'fill_v14.log');
diary off; diary(logf);
sumf = fullfile(ds, 'fill_summary_v14.txt');
if ~exist(sumf, 'file')
    fid = fopen(sumf, 'w'); fclose(fid);
end
fid = fopen(sumf, 'a');
fprintf(fid, '\nV14 CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;

P = {
    'Y0_base',       C.Y0_base;
    'Y0_noshape',    C.Y0_noshape;
    'Y1_lo_tight',   C.Y1_lo_tight;
    'Y2_lo_loose',   C.Y2_lo_loose;
    'Y3_hi_tight',   C.Y3_hi_tight;
    'Y4_hi_loose',   C.Y4_hi_loose
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
        runComparison_v14(o);
        f = fullfile(ds, ['results_v14_' tag '.mat']);
        fid = fopen(sumf, 'a');
        fill_stats_v14(f, tag, fid, 1);
        analyze_v14_replication(f, tag, fid, 1);
        
        % If tag is Y0_noshape, run paired shaping test vs Y0_base
        if strcmp(tag, 'Y0_noshape')
            f_base = fullfile(ds, 'results_v14_Y0_base.mat');
            if exist(f_base, 'file')
                fprintf(fid, '\n--- Paired Shaping Test: Y0_base vs Y0_noshape ---\n');
                shaping_pair_v14(f_base, f, fid);
            end
        end
        
        fprintf(fid, 'STEP|%s|done|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
        fclose(fid);
    catch ME
        fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end

fid = fopen(sumf, 'a');
fprintf(fid, '\nV14 CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
diary off;
