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
    ctx.root = root;
    ctx.v17 = v17;
    ctx.outdir = fullfile(v17, 'Dataset');
    
    try
        pf = feval(pf_fcn, ctx);
        
        if strcmp(pf.unit, 'eval')
            b = basis_eval;
        else
            b = basis_ep;
        end
        ratio = pf.sec_per_unit / b;
        
        % For projected time, consider 2 parfor workers where applicable
        % Training episodes run in parfor across seeds (2 workers -> 2x speedup)
        % Trace evaluations run in parallel chunks / workers
        proj_sec = pf.sec_per_unit * pf.n_units_total / 2; % 2 workers
        if strcmp(id, 'a3')
            proj_sec = pf.sec_per_unit * pf.n_units_total; % serial microbenchmark
        end
        proj_hr = proj_sec / 3600;
        total_proj_hours = total_proj_hours + proj_hr;
        
        fprintf('%-6s | %-8s | %10.4f s | %8.3f s | %7.2fx | %12d | %8.2f h\n', ...
            id, pf.unit, pf.sec_per_unit, b, ratio, pf.n_units_total, proj_hr);
            
        results.(id) = pf;
        results.(id).proj_hr = proj_hr;
        results.(id).ratio = ratio;
    catch ME
        fprintf('%-6s | ERROR: %s\n', id, ME.message);
    end
end

fprintf('----------------------------------------------------------------------------------------\n');
fprintf('TOTAL PROJECTED CAMPAIGN TIME: %.2f hours (%.2f days)\n', total_proj_hours, total_proj_hours/24);
fprintf('========================================================================================\n\n');
