function pf = stage_g10_preflight(ctx)
% stage_g10_preflight  20-episode preflight for G10 A2C training.
    addpath(ctx.v17);
    addpath(fullfile(fileparts(mfilename('fullpath')), 'g6'));
    v17_setup;
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    envE.pkt_bits = 16000; envE.pkt_deadline = 10;
    
    n_ep = 20;
    if (isfield(ctx, 'smoke') && ctx.smoke) || (isfield(ctx, 'cfg') && isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke)
        n_ep = 2;
    end
    t0 = tic;
    DeepA2C_Shared_v17(o.simTime, n_ep, 31042 + 201, envE);
    sec = toc(t0) / n_ep;
    
    n_total = ternary(ctx.smoke, 4, 2 * 5 * 3000);
    pf = struct('unit', 'episode', 'sec_per_unit', sec, ...
                'n_units_total', n_total, ...
                'note', sprintf('G10 A2C training (%d episodes)', n_ep));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
