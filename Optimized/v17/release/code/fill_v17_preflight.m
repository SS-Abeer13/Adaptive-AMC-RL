% fill_v17_preflight  Stage B2.6 (PLAN_v17.md): 2-episode, 2-seed, 6-trace
% preflight of every C2 case (M1-M4), timed, to extrapolate the full campaign.
v17_setup;
pf = fullfile(v17, 'logs', 'fill_v17_preflight.txt');
fid = fopen(pf, 'w'); fprintf(fid, 'V17 PREFLIGHT %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);
names = {'M1_dl_rtt8', 'M2_dl_rtt0', 'M3_gp_rtt8', 'M4_gp_rtt0'};
times = zeros(1, numel(names));
for q = 1:numel(names)
    tag = ['pre_' names{q}];
    try
        o = base; ov = C.(names{q}); fn = fieldnames(ov);
        for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
        o.simTime = 100; o.ep_deep = 2; o.ep_deep_a2c_offset = 2; o.ep_deep_a2c_resid_800 = 2;
        o.n_seeds = 2; o.n_eval = 6; o.n_calib = 2; o.n_calib_ctx = 2;
        o.n_seeds_a2c_offset = 2; o.n_seeds_a2c_resid_800 = 2;
        o.use_parfor = false; % serial during short preflight
        o.save_tag = tag;
        t0 = tic;
        runComparison_v17(o);
        times(q) = toc(t0);
        f = fullfile(ds, ['results_v17_' tag '.mat']);
        fid = fopen(pf, 'a');
        fill_stats_v17(f, tag, fid, 1);
        analyze_v17_replication(f, tag, fid, 1, 'Deep A2C v17');
        if isfield(o, 'train_a2c_offset') && o.train_a2c_offset
            analyze_v17_replication(f, tag, fid, 1, 'Deep A2C v17 (offset)');
        end
        if isfield(o, 'train_a2c_resid_800') && o.train_a2c_resid_800
            analyze_v17_replication(f, tag, fid, 1, 'Deep A2C v17 (resid-800)');
        end
        fprintf(fid, 'PREFLIGHT_%s_OK|elapsed_s=%.1f\n', names{q}, times(q)); fclose(fid);
    catch ME
        fid = fopen(pf, 'a'); fprintf(fid, 'PREFLIGHT_%s_FAIL|%s\n', names{q}, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end

fid = fopen(pf, 'a');
fprintf(fid, '\n--- timing extrapolation (per-seed rate model with parfor 4 workers) ---\n');
% Per-seed training rates from v16 empirical runs:
%   3000-ep seed at RTT 8: ~40 min
%   3000-ep seed at RTT 0: ~20 min
%   800-ep  seed at RTT 8: ~7 min (resid), ~10 min (offset)
%   800-ep  seed at RTT 0: ~3.5 min (resid)
%   Evaluation (500 traces): ~15 min
nWorkers = 4;
for q = 1:numel(names)
    ov = C.(names{q});
    rtt = ov.harq_rtt;
    isDl = strcmp(ov.traffic, 'deadline');
    
    % Primary
    nSeedsPrim = ov.n_seeds; epPrim = ov.ep_deep;
    if epPrim == 3000
        ratePrim = 20 * (1 + double(rtt > 0)); % 40 min at RTT8, 20 min at RTT0
    else
        ratePrim = 3.5 * (1 + double(rtt > 0)); % 7 min at RTT8, 3.5 min at RTT0
    end
    tTrainPrim = ceil(nSeedsPrim / nWorkers) * ratePrim;
    
    % Secondary offset
    tTrainOff = 0;
    if isfield(ov, 'train_a2c_offset') && ov.train_a2c_offset
        rateOff = 5.0 * (1 + double(rtt > 0)); % 10 min at RTT8
        tTrainOff = ceil(ov.n_seeds_a2c_offset / nWorkers) * rateOff;
    end
    
    % Secondary resid 800
    tTrainR800 = 0;
    if isfield(ov, 'train_a2c_resid_800') && ov.train_a2c_resid_800
        rateR800 = 3.5 * (1 + double(rtt > 0)); % 7 min at RTT8, 3.5 min at RTT0
        tTrainR800 = ceil(ov.n_seeds_a2c_resid_800 / nWorkers) * rateR800;
    end
    
    tEval = 15; % 500 traces
    tTotalCase = tTrainPrim + tTrainOff + tTrainR800 + tEval;
    
    fprintf(fid, 'EXTRAPOLATE|%s|preflight_s=%.1f|train_prim_min=%.0f|train_offset_min=%.0f|train_resid800_min=%.0f|eval_min=%.0f|est_min_parfor4=%.0f (%.1f h)\n', ...
        names{q}, times(q), tTrainPrim, tTrainOff, tTrainR800, tEval, tTotalCase, tTotalCase/60);
end
fclose(fid);
