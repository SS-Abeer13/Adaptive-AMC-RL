% run_all_preflights.m
% Measures 20-trace / 20-episode preflight rates across all stages
% against compute_basis.md and computes total projected campaign time.

here = fileparts(mfilename('fullpath'));
addpath(here);
v17 = fullfile(fileparts(here), 'v17');
addpath(v17);
v17_setup;

cfg = v17x_cfg();
cfg.smoke = false;

stages = {'g1', 'w1', 'nr1', 'g6a', 'g6b', 'g6c', 'g10', 'a1', 'a3', 'a6'};

basis_eval = 0.095;    % sec per 200-TTI evaluation
basis_ep   = 0.140;    % sec per training episode

fprintf('\n========================================================================================\n');
fprintf('  V17X CAMPAIGN PREFLIGHT BENCHMARK (20 traces / episodes, 2 parfor workers)\n');
fprintf('========================================================================================\n');
fprintf('%-6s | %-8s | %-12s | %-10s | %-8s | %-12s | %-10s\n', ...
    'Stage', 'Unit', 'Measured(s)', 'Basis(s)', 'Ratio', 'Total Units', 'Proj Time');
fprintf('----------------------------------------------------------------------------------------\n');

total_proj_hours = 0;
results = struct();

for i = 1:numel(stages)
    id = stages{i};
    pf_fcn = ['stage_' id '_preflight'];
    
    ctx = struct();
    ctx.cfg = cfg;
    ctx.smoke = false;
    ctx.id = id;
    ctx.root = here;
    ctx.v17 = v17;
    ctx.outdir = cfg.outdir;
    
    try
        pf = feval(pf_fcn, ctx);
        
        if strcmp(pf.unit, 'eval')
            b = basis_eval;
        else
            b = basis_ep;
        end
        ratio = pf.sec_per_unit / b;
        
        % Projected wall time (measured rate already reflects execution setup)
        proj_sec = pf.sec_per_unit * pf.n_units_total;
        proj_hr = proj_sec / 3600;
        total_proj_hours = total_proj_hours + proj_hr;
        
        fprintf('%-6s | %-8s | %10.4f s | %8.3f s | %7.2fx | %12d | %8.2f h\n', ...
            id, pf.unit, pf.sec_per_unit, b, ratio, pf.n_units_total, proj_hr);
            
        results.(id) = pf;
        results.(id).proj_hr = proj_hr;
        results.(id).ratio = ratio;
        
        % Write Dataset/PREFLIGHT_<id>.txt the way G1 does
        txtF = fullfile(cfg.outdir, ['PREFLIGHT_' id '.txt']);
        fid = fopen(txtF, 'w');
        if fid ~= -1
            fprintf(fid, '%s\nstage %s\nunit %s\nmeasured s/unit %.5f\nbasis s/unit %.5f\nratio %.3f (pause above %.2f)\nunits %d\nprojected hours %.2f\nnote: %s\n', ...
                datestr(now, 31), id, pf.unit, pf.sec_per_unit, b, ratio, cfg.pause_factor, pf.n_units_total, proj_hr, pf.note);
            fclose(fid);
        end
        if ~exist(cfg.ckptdir, 'dir'), mkdir(cfg.ckptdir); end
        save(fullfile(cfg.ckptdir, ['preflight_' id '.mat']), 'pf');
    catch ME
        fprintf('%-6s | ERROR: %s\n', id, ME.message);
    end
end

fprintf('----------------------------------------------------------------------------------------\n');
fprintf('TOTAL PROJECTED CAMPAIGN TIME: %.2f hours (%.2f days)\n', total_proj_hours, total_proj_hours/24);
fprintf('========================================================================================\n\n');

fprintf('\n========================================================================================\n');
fprintf('  G1 TRACE-GENERATION OVERHEAD BREAKDOWN (M1_dl_rtt8, 20 traces)\n');
fprintf('========================================================================================\n');
try
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    kA2C = find(strcmp(R.schemes, 'Deep A2C v17'));
    pol = R.policies.A2C{1};
    nT = 20; T = o.simTime;
    
    t0_gen = tic;
    traces_test = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:nT
        rng(o.trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(o.crn_seed_base + j); U = rand(T, env.N);
        traces_test(j).SINR = Strue; traces_test(j).obsS = obsS; traces_test(j).meta = meta; traces_test(j).U = U;
    end
    t_gen = toc(t0_gen) / nT;
    
    t0_eval = tic;
    for j = 1:nT
        rng(77000 + 100*j + 10*kA2C + 1);
        evalPolicy_v17_g1('a2c_v17', pol, traces_test(j).SINR, traces_test(j).obsS, envE, traces_test(j).meta, traces_test(j).U);
    end
    t_eval = toc(t0_eval) / nT;
    
    t_total = t_gen + t_eval;
    n_passes = 11; % 1 FixedPU + 10 A2C seeds
    t_amortized = t_eval + (t_gen / n_passes);
    
    fprintf('Trace generation (channel + CQI feedback):  %.4f s / trace (%.1f%% of combined)\n', t_gen, 100 * t_gen / t_total);
    fprintf('Policy evaluation (evalPolicy_v17_g1):      %.4f s / trace (%.1f%% of combined)\n', t_eval, 100 * t_eval / t_total);
    fprintf('Combined preflight rate (gen + eval):       %.4f s / trace (ratio vs 0.095: %.2fx)\n', t_total, t_total / 0.095);
    fprintf('Steady-state evaluation rate (no gen):      %.4f s / trace (ratio vs 0.095: %.2fx)\n', t_eval, t_eval / 0.095);
    fprintf('Amortized G1 rate (1 gen per 11 evals):     %.4f s / trace (ratio vs 0.095: %.2fx)\n', t_amortized, t_amortized / 0.095);
catch ME
    fprintf('G1 analysis error: %s\n', ME.message);
end
fprintf('========================================================================================\n\n');
