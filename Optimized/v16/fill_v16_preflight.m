% fill_v16_preflight  Stage B3.6 (PLAN_v16.md): 2-episode, 2-seed, 6-trace
% preflight of every C2 case, timed, to extrapolate the full campaign.
v16_setup;
pf = fullfile(v16, 'logs', 'fill_v16_preflight.txt');
fid = fopen(pf, 'w'); fprintf(fid, 'V16 PREFLIGHT %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);
names = {'K1_dl_rtt8', 'K2_dl_rtt0', 'K3_gp_rtt8', 'K4_gp_rtt0', 'L1_dl_rtt8_long', 'L3_gp_rtt8_long'};
times = zeros(1, numel(names));
for q = 1:numel(names)
    tag = ['pre_' names{q}];
    try
        o = base; ov = C.(names{q}); fn = fieldnames(ov);
        for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
        o.simTime = 100; o.ep_deep = 2; o.ep_deep_ppo = 2; o.ep_deep_a2c_offset = 2; o.n_seeds = 2; o.n_eval = 6; o.n_calib = 2; o.n_calib_ctx = 2;
        % Scale PPO/A2C-offset's smaller seed count (5 in the real cases, via
        % n_seeds_ppo/n_seeds_a2c_offset) down to the same 2 used for the
        % preflight's A2C-resid, so all three schemes run an equally-sized
        % smoke test here; the real per-scheme seed counts are still used
        % below when extrapolating the full-case time.
        o.n_seeds_ppo = 2; o.n_seeds_a2c_offset = 2;
        o.save_tag = tag;
        t0 = tic;
        runComparison_v16(o);
        times(q) = toc(t0);
        f = fullfile(ds, ['results_v16_' tag '.mat']);
        fid = fopen(pf, 'a');
        fill_stats_v16(f, tag, fid, 1);
        analyze_v16_replication(f, tag, fid, 1, 'Deep A2C v16');
        fprintf(fid, 'PREFLIGHT_%s_OK|elapsed_s=%.1f\n', names{q}, times(q)); fclose(fid);
    catch ME
        fid = fopen(pf, 'a'); fprintf(fid, 'PREFLIGHT_%s_FAIL|%s\n', names{q}, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end

fid = fopen(pf, 'a');
fprintf(fid, '\n--- timing extrapolation (preflight: 2 episodes, 2 seeds [all schemes], 6 traces) ---\n');
% C2 (README_v16.md S3.3): PPO and A2C-offset are now trained at their own,
% smaller seed count (5, via n_seeds_ppo/n_seeds_a2c_offset) than the
% primary A2C-resid scheme (10). The preflight ran all three schemes at an
% equal 2 seeds (see the o.n_seeds_ppo/o.n_seeds_a2c_offset override
% above), so a single scale factor tied only to A2C-resid's seed ratio
% would not reflect PPO/A2C-offset's real seed count being HALF of
% A2C-resid's, not equal to it -- understating the time saved by the
% smaller seed counts. Scale instead by each scheme's own
% (episodes x seeds) "training units", summed over every scheme actually
% trained in that case, and similarly by each scheme's own seeds for the
% evaluation side (both ratios still taken against the preflight's
% matching per-scheme units); scale = max(trainScale, evalScale) stays a
% conservative upper bound (it ignores the per-case fixed overhead --
% calibration, trace generation -- that does not scale with episodes or
% seeds at all, and the bandits/deterministic comparators' cost).
for q = 1:numel(names)
    if times(q) <= 0, continue; end
    ov = C.(names{q});
    epDeep = base.ep_deep; if isfield(ov, 'ep_deep'), epDeep = ov.ep_deep; end
    nSeeds = base.n_seeds; if isfield(ov, 'n_seeds'), nSeeds = ov.n_seeds; end
    nEval  = base.n_eval;  if isfield(ov, 'n_eval'),  nEval  = ov.n_eval;  end
    trainPPO = base.train_ppo; if isfield(ov, 'train_ppo'), trainPPO = ov.train_ppo; end
    epDeepPPO = base.ep_deep_ppo; if isfield(ov, 'ep_deep_ppo'), epDeepPPO = ov.ep_deep_ppo; end
    nSeedsPPO = base.n_seeds_ppo; if isfield(ov, 'n_seeds_ppo'), nSeedsPPO = ov.n_seeds_ppo; end
    trainA2CO = base.train_a2c_offset; if isfield(ov, 'train_a2c_offset'), trainA2CO = ov.train_a2c_offset; end
    epDeepA2CO = base.ep_deep_a2c_offset; if isfield(ov, 'ep_deep_a2c_offset'), epDeepA2CO = ov.ep_deep_a2c_offset; end
    nSeedsA2CO = base.n_seeds_a2c_offset; if isfield(ov, 'n_seeds_a2c_offset'), nSeedsA2CO = ov.n_seeds_a2c_offset; end
    nSchemes = 1 + double(trainPPO) + double(trainA2CO);  % A2C-resid (+ PPO, + A2C-offset if trained alongside)

    unitsTrainReal = epDeep * nSeeds;
    unitsEvalReal  = nEval * nSeeds;
    if trainPPO
        unitsTrainReal = unitsTrainReal + epDeepPPO * nSeedsPPO;
        unitsEvalReal  = unitsEvalReal  + nEval * nSeedsPPO;
    end
    if trainA2CO
        unitsTrainReal = unitsTrainReal + epDeepA2CO * nSeedsA2CO;
        unitsEvalReal  = unitsEvalReal  + nEval * nSeedsA2CO;
    end
    % Preflight ran every scheme at 2 episodes, 2 seeds (o.n_seeds_ppo = 2,
    % o.n_seeds_a2c_offset = 2 above), 6 eval traces -- same nSchemes count.
    unitsTrainPre = 2 * 2 * nSchemes;
    unitsEvalPre  = 6 * 2 * nSchemes;

    trainScale = unitsTrainReal / unitsTrainPre;
    evalScale  = unitsEvalReal  / unitsEvalPre;
    scale = max(trainScale, evalScale);
    estMin = times(q) * scale / 60;
    fprintf(fid, 'EXTRAPOLATE|%s|preflight_s=%.1f|episodes=%d|n_seeds=%d|n_seeds_ppo=%d|n_seeds_a2c_offset=%d|n_eval=%d|n_schemes=%d|est_min=%.0f\n', ...
        names{q}, times(q), epDeep, nSeeds, nSeedsPPO * double(trainPPO), nSeedsA2CO * double(trainA2CO), nEval, nSchemes, estMin);
end
fclose(fid);
