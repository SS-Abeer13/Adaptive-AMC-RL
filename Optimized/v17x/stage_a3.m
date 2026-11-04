function stage_a3(ctx)
% stage_a3  Inference wall time microbenchmark (prompt A3).
% Loads seed 1 of M1 policy, extracts actor weights, times 10^5 forward passes
% for N = 10 users with timeit. Times full evalPolicy_v17 trace (200 TTI)
% for A2C vs FixedPU. Reports median us per decision and per TTI, plus CPU model.

    addpath(ctx.v17);
    v17_setup;
    
    ctx.unit('timing', @() unit_timing(ctx));
end

% =========================================================================
function out = unit_timing(ctx)
    ctx.hbf('stage_a3: unit timing start');
    
    r_file = fullfile(ctx.v17, 'Dataset', 'results_v17_M1_dl_rtt8.mat');
    if ~exist(r_file, 'file')
        error('v17x:a3:noM1', 'Cannot find M1 results at %s', r_file);
    end
    S = load(r_file);
    r = S.results;
    env = r.env;
    
    % Seed 1 policy
    pol = r.policies.A2C{1};
    L = pol.Learnables;
    Wa.w1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Weights"});
    Wa.b1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Bias"});
    Wa.w2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Weights"});
    Wa.b2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Bias"});
    isL3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Weights";
    Wa.w3 = extractdata(L.Value{isL3});
    isB3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Bias";
    Wa.b3 = extractdata(L.Value{isB3});
    
    % Forward pass benchmark
    N = 10;
    n_in = 57;
    X = randn(n_in, N, 'single');
    
    f_pass = @() Wa.w3 * max(0, Wa.w2 * max(0, Wa.w1 * X + Wa.b1) + Wa.b2) + Wa.b3;
    
    % timeit gives median seconds per execution of f_pass (which computes N=10 decisions)
    t_pass_median_sec = timeit(f_pass);
    us_per_decision = (t_pass_median_sec / N) * 1e6;
    
    % Loop benchmark
    n_passes = 100000;
    if isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke
        n_passes = 1000;
    end
    ctx.hbf(sprintf('Running %d forward passes for N=%d users...', n_passes, N));
    t0 = tic;
    for it = 1:n_passes
        out_logits = Wa.w3 * max(0, Wa.w2 * max(0, Wa.w1 * X + Wa.b1) + Wa.b2) + Wa.b3; %#ok<NASGU>
    end
    dt_loop = toc(t0);
    us_per_decision_loop = (dt_loop / n_passes / N) * 1e6;
    
    % Full 200-TTI trace benchmark
    ctx.hbf('Timing full 200-TTI evaluation trace (A2C vs FixedPU)...');
    rng(500001);
    [Strue, ~, meta] = generateChannel_v17(200, env);
    obsS = cqiFeedback_v17(Strue, env, meta.delays);
    meta.trace_id = 1;
    rng(510001); U = rand(200, env.N);
    
    f_a2c = @() evalPolicy_v17('a2c_v17', pol, Strue, obsS, env, meta, U);
    f_fc  = @() evalPolicy_v17('fixed_class', [], Strue, obsS, env, meta, U);
    
    t_trace_a2c_sec = timeit(f_a2c);
    t_trace_fc_sec  = timeit(f_fc);
    
    us_per_tti_a2c = (t_trace_a2c_sec / 200) * 1e6;
    us_per_tti_fc  = (t_trace_fc_sec / 200) * 1e6;
    
    % CPU Model
    [~, cpu_raw] = system('wmic cpu get name');
    cpu_lines = splitlines(strtrim(cpu_raw));
    cpu_model = strtrim(cpu_lines{end});
    
    ctx.hbf(sprintf('A3 Timing Results (%s):', cpu_model));
    ctx.hbf(sprintf('  Forward pass: %.2f us/decision (timeit), %.2f us/decision (loop)', ...
        us_per_decision, us_per_decision_loop));
    ctx.hbf(sprintf('  Full 200-TTI trace: A2C = %.1f us/TTI (%.3f s/trace), FixedPU = %.1f us/TTI (%.3f s/trace)', ...
        us_per_tti_a2c, t_trace_a2c_sec, us_per_tti_fc, t_trace_fc_sec));
    
    data = struct('cpu_model', cpu_model, ...
                  'us_per_decision', us_per_decision, ...
                  'us_per_decision_loop', us_per_decision_loop, ...
                  'n_passes_loop', n_passes, ...
                  't_pass_median_sec', t_pass_median_sec, ...
                  't_trace_a2c_sec', t_trace_a2c_sec, ...
                  't_trace_fc_sec', t_trace_fc_sec, ...
                  'us_per_tti_a2c', us_per_tti_a2c, ...
                  'us_per_tti_fc', us_per_tti_fc);
              
    out_ds = fullfile(ctx.outdir, 'a3_timing.mat');
    save(out_ds, '-struct', 'data');
    
    paper_a3_dir = fullfile(ctx.root, 'paper', 'a3');
    if ~exist(paper_a3_dir, 'dir')
        mkdir(paper_a3_dir);
    end
    save(fullfile(paper_a3_dir, 'a3_timing.mat'), '-struct', 'data');
    
    rep_file = fullfile(ctx.outdir, 'REPORT_a3.txt');
    fid = fopen(rep_file, 'w');
    fprintf(fid, 'A3 INFERENCE WALL TIME REPORT (%s)\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'CPU Model: %s\n', cpu_model);
    fprintf(fid, 'Forward Pass (N=10, dim=57):\n');
    fprintf(fid, '  Median per decision: %.2f us\n', us_per_decision);
    fprintf(fid, '  Loop (%d passes) per decision: %.2f us\n', n_passes, us_per_decision_loop);
    fprintf(fid, 'Full 200-TTI Trace (10 users):\n');
    fprintf(fid, '  Deep A2C v17: %.1f us/TTI (%.3f s/trace)\n', us_per_tti_a2c, t_trace_a2c_sec);
    fprintf(fid, '  FixedPU (Oracle): %.1f us/TTI (%.3f s/trace)\n', us_per_tti_fc, t_trace_fc_sec);
    fprintf(fid, '  Ratio A2C / FixedPU: %.2fx\n', t_trace_a2c_sec / max(t_trace_fc_sec, 1e-6));
    fclose(fid);
    
    out = data;
end
