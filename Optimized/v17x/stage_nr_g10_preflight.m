function pf = stage_nr_g10_preflight(ctx)
% stage_nr_g10_preflight  20-trace preflight for NR-G10 evaluation.
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    envE.pkt_bits = 16000; envE.pkt_deadline = 10;
    
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
        evalPolicy_v17_g6('fixed', [], Strue, obsS, envE, meta, U);
    end
    sec = toc(t0) / nT;
    
    % Total units across 2 cells:
    %   RL training: 2 cells x 5 seeds x 3,000 ep = 30,000 ep (approx 44,211 eval equivs)
    %   Evaluation: 2 cells x 300 traces x 16 schemes = 9,600 evals
    %   Total units = 44,211 + 9,600 = 53,811 units
    n_units = ternary(ctx.smoke, 40, 53811);
    pf = struct('unit', 'eval', 'sec_per_unit', sec, ...
                'n_units_total', n_units, ...
                'note', sprintf('NR-G10 2 cells (30k ep training + 9.6k evals; %d traces benchmarked)', nT));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
