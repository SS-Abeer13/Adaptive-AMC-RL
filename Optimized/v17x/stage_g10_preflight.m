function pf = stage_g10_preflight(ctx)
% stage_g10_preflight  20-trace preflight for G10 evaluation & recalibration.
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    envE.pkt_bits = 16000; envE.pkt_deadline = 10;
    envE.ctxj_tab = zeros(3, 2, 3, 2);
    
    nT = 20;
    if (isfield(ctx, 'smoke') && ctx.smoke) || (isfield(ctx, 'cfg') && isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke)
        nT = 2;
    end
    T = o.simTime;
    t0 = tic;
    for j = 1:nT
        rng(720000 + j);
        [Strue, ~, meta] = generateChannel_v17(T, envE);
        obsS = cqiFeedback_v17(Strue, envE, meta.delays);
        meta.trace_id = j;
        rng(730000 + j); U = rand(T, envE.N);
        rng(73500 + j);
        evalPolicy_v17_g6('ctxj', [], Strue, obsS, envE, meta, U);
    end
    sec = toc(t0) / nT;
    
    % G10 true totals across 2 cells (G2_hi_d10, G3_lo_d18):
    %   Single-cue recalibration: 2 x 105,200 = 210,400 evals
    %   Combined comparator:      2 x 518,400 = 1,036,800 evals (12 sweeps expected)
    %   Final evaluation:         2 x 8,700   = 17,400 evals
    %   Feasibility / checks:     2 x 2,000   = 4,000 evals
    %   Subtotal evals: 1,268,600
    %   RL training: 2 cells x 5 seeds x 3,000 ep = 30,000 episodes
    %   Converted at basis ratio (0.140 / 0.095): 30,000 x 1.474 = 44,211 eval-equivalents
    %   Total units = 1,268,600 + 44,211 = 1,312,811 units
    n_units = ternary(ctx.smoke, 40, 1312811);
    pf = struct('unit', 'eval', 'sec_per_unit', sec, ...
                'n_units_total', n_units, ...
                'note', sprintf('G10 2 cells (recalibration 1.25M evals + 30k ep training; %d traces benchmarked)', nT));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
