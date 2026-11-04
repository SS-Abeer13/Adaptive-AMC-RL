% fill_v11_preflight  Tiny end-to-end run of every pre-registered v11-P1
% case (code paths only; README_v11.md, target-BLER action space).
v11_setup;
pf = fullfile(v11, 'logs', 'fill_v11_preflight.txt');
fid = fopen(pf, 'w'); fprintf(fid, 'V11 PREFLIGHT %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);
names = {'T1_gp', 'T2_stale', 'T4_deadline'};
for q = 1:numel(names)
    tag = ['pre_' names{q}];
    try
        o = base; ov = C.(names{q}); fn = fieldnames(ov);
        for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
        o.simTime = 100; o.ep_deep = 2; o.n_seeds = 1; o.n_eval = 4; o.n_calib = 2; o.n_calib_ctx = 2;
        o.save_tag = tag;
        runComparison_v11(o);
        fid = fopen(pf, 'a');
        fill_stats_v11(fullfile(ds, ['results_v11_' tag '.mat']), tag, fid);
        fprintf(fid, 'PREFLIGHT_%s_OK\n', names{q}); fclose(fid);
    catch ME
        fid = fopen(pf, 'a'); fprintf(fid, 'PREFLIGHT_%s_FAIL|%s\n', names{q}, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end
