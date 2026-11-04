% fill_v12_preflight  Tiny end-to-end run of both v12 cases (code paths only).
v12_setup;
pf = fullfile(v12, 'logs', 'fill_v12_preflight.txt');
fid = fopen(pf, 'w'); fprintf(fid, 'V12 PREFLIGHT %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);
names = {'R1_pf', 'R2_edf'};
for q = 1:numel(names)
    tag = ['pre_' names{q}];
    try
        o = base; ov = C.(names{q}); fn = fieldnames(ov);
        for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
        o.simTime = 100; o.ep_deep = 2; o.n_seeds = 2; o.n_eval = 6; o.n_calib = 2; o.n_calib_ctx = 2;
        o.save_tag = tag;
        runComparison_v12(o);
        f = fullfile(ds, ['results_v12_' tag '.mat']);
        fid = fopen(pf, 'a');
        fill_stats_v12(f, tag, fid, 1);
        analyze_v12_replication(f, tag, fid, 1);
        fprintf(fid, 'PREFLIGHT_%s_OK\n', names{q}); fclose(fid);
    catch ME
        fid = fopen(pf, 'a'); fprintf(fid, 'PREFLIGHT_%s_FAIL|%s\n', names{q}, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end
