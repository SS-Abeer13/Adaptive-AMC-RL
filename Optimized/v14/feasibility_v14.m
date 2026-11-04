% feasibility_v14  Feasibility check for the v14 grid (PLAN_v14.md B2.3 and C2).
% For each grid cell, on CALIBRATION TRACES ONLY (60000+):
%   - Calibrate and evaluate OLLA and Fixed.
%   - Compute hindsight per-trace offset bound (-4:2) and genie bound.
%   - If Fixed on-time is outside [0.50, 0.97], apply load substitution (C2):
%       8000 -> 10000, 16000 -> 14000.
%   - Never touch evaluation traces here.

root = 'D:\Adaptive AMC A2C+QL';
v14dir = fullfile(root, 'Optimized', 'v14');
addpath(v14dir); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
v14_setup;

outFile = fullfile(ds, 'feasibility_v14.txt');
fid = fopen(outFile, 'w');
fprintf(fid, '# v14 Grid Feasibility Check (Calibration Traces 60000+) - %s\n\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));

cellList = {
    'Y0_base',     C.Y0_base;
    'Y0_noshape',  C.Y0_noshape;
    'Y1_lo_tight', C.Y1_lo_tight;
    'Y2_lo_loose', C.Y2_lo_loose;
    'Y3_hi_tight', C.Y3_hi_tight;
    'Y4_hi_loose', C.Y4_hi_loose
};

nCalib = 20;
simTime = 200;
cand_offsets = -4:2;
nCands = numel(cand_offsets);

fprintf('========================================================================\n');
fprintf('  v14 GRID FEASIBILITY CHECK (Calibration Traces 60000+)\n');
fprintf('========================================================================\n\n');

for cIdx = 1:size(cellList, 1)
    cellName = cellList{cIdx, 1};
    raw_env = cellList{cIdx, 2};

    % Check initial configuration
    [res, substMade, final_env] = check_cell_feasibility(cellName, raw_env, base, nCalib, simTime, cand_offsets);

    % If outside [0.50, 0.97], attempt load substitution
    if res.fixed < 0.50 || res.fixed > 0.97
        subst_env = raw_env;
        if raw_env.pkt_bits == 8000
            subst_env.pkt_bits = 10000;
            [res_sub, ~, final_env] = check_cell_feasibility(cellName, subst_env, base, nCalib, simTime, cand_offsets);
            substMade = sprintf('8000->10000 (fixed=%.4f)', res_sub.fixed);
            res = res_sub;
        elseif raw_env.pkt_bits == 16000
            subst_env.pkt_bits = 14000;
            [res_sub, ~, final_env] = check_cell_feasibility(cellName, subst_env, base, nCalib, simTime, cand_offsets);
            substMade = sprintf('16000->14000 (fixed=%.4f)', res_sub.fixed);
            res = res_sub;
        end
    end

    if res.fixed >= 0.50 && res.fixed <= 0.97
        status = 'FEASIBLE';
    else
        status = 'INFEASIBLE';
    end

    lineStr = sprintf('FEAS|cell=%s|pkt_bits=%d|deadline=%d|olla=%.4f|fixed=%.4f|hindsight=%.4f|genie=%.4f|subst=%s|status=%s', ...
        cellName, final_env.pkt_bits, final_env.pkt_deadline, res.olla, res.fixed, res.hindsight, res.genie, substMade, status);

    fprintf('%s\n', lineStr);
    fprintf(fid, '%s\n', lineStr);
end

fclose(fid);
fprintf('\nFeasibility check complete. Saved to %s\n', outFile);

function [res, substMade, env] = check_cell_feasibility(cellName, raw_opts, base_opts, nCalib, simTime, cand_offsets)
    substMade = 'none';
    opts = base_opts;
    fn = fieldnames(raw_opts);
    for q = 1:numel(fn), opts.(fn{q}) = raw_opts.(fn{q}); end

    env = defaultEnv_v14(23, opts.N);
    fo = fieldnames(opts);
    for q = 1:numel(fo)
        if isfield(env, fo{q}) && ~isempty(opts.(fo{q})), env.(fo{q}) = opts.(fo{q}); end
    end
    env.max_delta = max(abs(env.actions));
    env.min_delta = -env.max_delta;
    eval_scheds = opts.eval_schedulers;
    env.calib_sched = eval_scheds{1};
    envE = env;
    envE.scheduler = eval_scheds{1};
    b0 = min(env.burn_in, simTime - 1);

    % Calibrate Fixed and Genie on calibration traces (60000+)
    env = calibrateFixedClass_v14(env, nCalib, simTime);
    env = calibrateGenie_v14(env, nCalib, simTime);
    envE.fixed_offset = env.fixed_offset;
    envE.genie_bler   = env.genie_bler;

    % Evaluate on calibration traces (60000+)
    sc_olla = zeros(1, nCalib);
    sc_fixed = zeros(1, nCalib);
    sc_hind = zeros(1, nCalib);
    sc_genie = zeros(1, nCalib);

    for j = 1:nCalib
        rng(60000 + j);
        [Strue, ~, meta] = generateChannel_v14(simTime, env);
        obsS = cqiFeedback_v14(Strue, env, meta.delays);
        meta.trace_id = 10000 + j;
        rng(62000 + j); U = rand(simTime, env.N);

        % OLLA
        rng(61000 + 100*j + 1);
        [tp_o, ~, ~, ~, inf_o] = evalPolicy_v14('olla', [], Strue, obsS, envE, meta, U);
        [~, ~, sc_olla(j)] = userMetric_v14(env, tp_o, inf_o, b0);

        % Fixed
        rng(61000 + 100*j + 2);
        [tp_f, ~, ~, ~, inf_f] = evalPolicy_v14('fixed', [], Strue, obsS, envE, meta, U);
        [~, ~, sc_fixed(j)] = userMetric_v14(env, tp_f, inf_f, b0);

        % Hindsight over cand_offsets
        cand_sc = zeros(1, numel(cand_offsets));
        for oIdx = 1:numel(cand_offsets)
            envO = envE;
            envO.fixed_offset = cand_offsets(oIdx);
            rng(61000 + 100*j + 2);
            [tp_cand, ~, ~, ~, inf_cand] = evalPolicy_v14('fixed', [], Strue, obsS, envO, meta, U);
            [~, ~, cand_sc(oIdx)] = userMetric_v14(env, tp_cand, inf_cand, b0);
        end
        sc_hind(j) = max(cand_sc);

        % Genie
        rng(61000 + 100*j + 3);
        [tp_g, ~, ~, ~, inf_g] = evalPolicy_v14('genie_cqi', [], Strue, obsS, envE, meta, U);
        [~, ~, sc_genie(j)] = userMetric_v14(env, tp_g, inf_g, b0);
    end

    res.olla = mean(sc_olla);
    res.fixed = mean(sc_fixed);
    res.hindsight = mean(sc_hind);
    res.genie = mean(sc_genie);
end
