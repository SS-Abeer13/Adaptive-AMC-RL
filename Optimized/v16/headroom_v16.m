% headroom_v16  Stage E (PLAN_v16.md): genie and per-trace hindsight offset
% reference bounds (C1's "reported reference bounds"), computed on the
% EVALUATION traces (not calibration traces -- unlike feasibility_v15.m's
% calibration-trace check) for every C2 case, after the campaign.
v16_setup;
outDir = fullfile(v16, 'paper');
if ~exist(outDir, 'dir'), mkdir(outDir); end
hfile = fullfile(outDir, 'headroom.csv');
fid = fopen(hfile, 'w');
fprintf(fid, 'case,primary_metric,n_traces,fixed,genie,hindsight\n');

names = {'K1_dl_rtt8', 'K2_dl_rtt0', 'K3_gp_rtt8', 'K4_gp_rtt0', 'L1_dl_rtt8_long', 'L3_gp_rtt8_long'};
cand_offsets = -4:2;

for q = 1:numel(names)
    tag = names{q};
    ov = C.(tag);
    o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end

    env = defaultEnv_v16(23, o.N);
    fo = fieldnames(o);
    for k = 1:numel(fo)
        if isfield(env, fo{k}) && ~isempty(o.(fo{k})), env.(fo{k}) = o.(fo{k}); end
    end
    env.max_delta = max(abs(env.actions)); env.min_delta = -env.max_delta;
    env.calib_sched = o.eval_schedulers{1};
    if isfield(env, 'action_mode') && strcmpi(env.action_mode, 'resid')
        env = selectBaseRule_v16(env, o.n_calib, o.simTime);
    end
    env = calibrateFixedClass_v16(env, o.n_calib, o.simTime);
    env = calibrateGenie_v16(env, o.n_calib, o.simTime);
    envE = env; envE.scheduler = o.eval_schedulers{1};
    b0 = min(env.burn_in, o.simTime - 1);

    nEval = o.n_eval;
    traceSeedBase = o.trace_seed_base; crnSeedBase = o.crn_seed_base;
    sc_fixed = zeros(1, nEval); sc_genie = zeros(1, nEval); sc_hind = zeros(1, nEval);

    t0 = tic;
    for j = 1:nEval
        rng(traceSeedBase + j);
        [Strue, ~, meta] = generateChannel_v16(o.simTime, env);
        obsS = cqiFeedback_v16(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(crnSeedBase + j); U = rand(o.simTime, env.N);

        rng(90000 + 100*j + 1);
        [tp_f, ~, ~, ~, inf_f] = evalPolicy_v16('fixed', [], Strue, obsS, envE, meta, U);
        [~, ~, sc_fixed(j)] = userMetric_v16(env, tp_f, inf_f, b0);

        cand_sc = zeros(1, numel(cand_offsets));
        for oIdx = 1:numel(cand_offsets)
            envO = envE; envO.fixed_offset = cand_offsets(oIdx);
            rng(90000 + 100*j + 1);
            [tp_c, ~, ~, ~, inf_c] = evalPolicy_v16('fixed', [], Strue, obsS, envO, meta, U);
            [~, ~, cand_sc(oIdx)] = userMetric_v16(env, tp_c, inf_c, b0);
        end
        sc_hind(j) = max(cand_sc);

        rng(90000 + 100*j + 3);
        [tp_g, ~, ~, ~, inf_g] = evalPolicy_v16('genie_cqi', [], Strue, obsS, envE, meta, U);
        [~, ~, sc_genie(j)] = userMetric_v16(env, tp_g, inf_g, b0);
    end
    fprintf('HEADROOM|%s|fixed=%.4f|genie=%.4f|hindsight=%.4f|elapsed_s=%.1f\n', ...
        tag, mean(sc_fixed), mean(sc_genie), mean(sc_hind), toc(t0));
    fprintf(fid, '%s,%s,%d,%.4f,%.4f,%.4f\n', tag, env.primary, nEval, mean(sc_fixed), mean(sc_genie), mean(sc_hind));
end
fclose(fid);
fprintf('Headroom reference bounds saved to %s\n', hfile);
