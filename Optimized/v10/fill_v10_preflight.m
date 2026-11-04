% fill_v10_preflight  Tiny end-to-end run of every v10 case (code paths only).
v10_setup;
pf = fullfile(v10, 'logs', 'fill_v10_preflight.txt');
fid = fopen(pf, 'w'); fprintf(fid, 'V10 PREFLIGHT %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);
names = {'E1_train', 'E2_stale', 'E3_cellcue', 'E4_deadline'};
for q = 1:numel(names)
    tag = ['pre_' names{q}];
    try
        o = base; ov = C.(names{q}); fn = fieldnames(ov);
        for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
        o.simTime = 100; o.ep_deep = 3; o.n_seeds = 1; o.n_eval = 4; o.n_calib = 2; o.n_calib_ctx = 2;
        o.save_tag = tag;
        runComparison_v10(o);
        fid = fopen(pf, 'a');
        fill_stats_v10(fullfile(ds, ['results_v10_' tag '.mat']), tag, fid);
        fprintf(fid, 'PREFLIGHT_%s_OK\n', names{q}); fclose(fid);
    catch ME
        fid = fopen(pf, 'a'); fprintf(fid, 'PREFLIGHT_%s_FAIL|%s\n', names{q}, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end
