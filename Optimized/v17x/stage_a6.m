function stage_a6(ctx)
% stage_a6  PF-timing demonstration for pitfall F8 (A6_pf_timing_prereg.md).
% Units:
%   equiv_test: runs test_equivalence_v17 (gate)
%   cell_<pfmode>_rtt<R>_np<P>: 6 cells across pfmode in {'acked','scheduled'}
%     and HARQ in {(rtt0, np1), (rtt8, np1), (rtt8, np8)}.
% Outputs:
%   fill_summary_v17pf.txt, a6_pf_timing.csv

    addpath(ctx.v17);
    v17_setup;
    
    % Unit 1: Equivalence test gate
    ctx.unit('equiv_test', @() unit_equiv_test(ctx));
    
    % 6 cell configurations
    pf_modes = {'acked', 'scheduled'};
    harq_configs = {
        struct('rtt', 0, 'np', 1), ...
        struct('rtt', 8, 'np', 1), ...
        struct('rtt', 8, 'np', 8)
    };
    
    n_traces = 100;
    if isfield(ctx.cfg, 'smoke') && ctx.cfg.smoke
        n_traces = 2;
    end
    
    cell_results = cell(numel(pf_modes), numel(harq_configs));
    
    for pm = 1:numel(pf_modes)
        pf_mode = pf_modes{pm};
        for hc = 1:numel(harq_configs)
            hcfg = harq_configs{hc};
            unit_name = sprintf('cell_%s_rtt%d_np%d', pf_mode, hcfg.rtt, hcfg.np);
            cell_results{pm, hc} = ctx.unit(unit_name, ...
                @() unit_run_cell(pf_mode, hcfg.rtt, hcfg.np, n_traces, ctx));
        end
    end
    
    % Write outputs
    write_a6_outputs(ctx, pf_modes, harq_configs, cell_results, n_traces);
end

% =========================================================================
function out = unit_equiv_test(ctx)
    ctx.hbf('stage_a6: running equivalence test test_equivalence_v17...');
    t0 = tic;
    % Run test_equivalence_v17
    run(fullfile(ctx.v17, 'test_equivalence_v17.m'));
    ctx.hbf(sprintf('stage_a6: equivalence test passed in %.1f s', toc(t0)));
    out = struct('equiv_ok', true, 'duration', toc(t0));
end

% =========================================================================
function out = unit_run_cell(pf_mode, rtt, np, n_traces, ctx)
    ctx.hbf(sprintf('Running A6 cell: pf=%s, rtt=%d, np=%d (%d traces)', ...
        pf_mode, rtt, np, n_traces));
    
    % Check seed disjointness
    seed_start = 800001; seed_end = 800000 + n_traces;
    crn_start  = 810001; crn_end  = 810000 + n_traces;
    assert(seed_start >= 800001 && seed_end <= 800100, 'A6 trace seeds out of range');
    assert(crn_start  >= 810001 && crn_end  <= 810100, 'A6 CRN seeds out of range');
    
    v17_setup;
    ov = C.M3_gp_rtt8;
    o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    
    env = defaultEnv_v17(42, o.N);
    env.traffic = 'full';
    env.drain = true;
    env.useful_bits = true;
    env.reward_kind = 'oppcost';
    env.primary = 'goodput';
    env.fixed_offset = -1;
    env.olla_target = 0.10;
    env.olla_step_down = 0.01;
    env.pf_avg = pf_mode;
    env.harq_rtt = rtt;
    env.harq_nproc = np;
    
    T = 200;
    if isfield(env, 'simTime'), T = env.simTime; end
    b0 = min(env.burn_in, T - 1);
    
    schemes = {'baseline', 'olla', 'fixed'};
    n_schemes = numel(schemes);
    
    goodput = zeros(n_schemes, n_traces);
    jain    = zeros(n_schemes, n_traces);
    edge5   = zeros(n_schemes, n_traces);
    
    for j = 1:n_traces
        rng(800000 + j, 'twister');
        [Strue, ~, meta] = generateChannel_v17(T, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(810000 + j, 'twister'); U = rand(T, env.N);
        
        for k = 1:n_schemes
            sch = schemes{k};
            rng(77000 + 100*j + 10*k + 1, 'twister');
            [tp, ~, ~, ~, ~] = evalPolicy_v17(sch, [], Strue, obsS, env, meta, U);
            pu = mean(tp(b0+1:end, :), 1);
            goodput(k, j) = sum(pu);
            if all(pu == 0)
                jain(k, j) = 0;
            else
                jain(k, j) = (sum(pu))^2 / (env.N * sum(pu.^2));
            end
            edge5(k, j) = prctile(pu, 5);
        end
    end
    
    out = struct('pf_mode', pf_mode, 'rtt', rtt, 'np', np, ...
                 'schemes', {schemes}, ...
                 'goodput', goodput, 'jain', jain, 'edge5', edge5);
end

% =========================================================================
function write_a6_outputs(ctx, pf_modes, harq_configs, cell_results, n_traces)
    schemes = {'Baseline', 'OLLA', 'Fixed'};
    
    % 1. Write a6_pf_timing.csv
    csv_file = fullfile(ctx.outdir, 'a6_pf_timing.csv');
    fid = fopen(csv_file, 'w');
    fprintf(fid, 'cell,pf_mode,rtt,nproc,scheme,goodput_mean,goodput_ci_lo,goodput_ci_hi,jain_mean,jain_ci_lo,jain_ci_hi,edge5_mean,edge5_ci_lo,edge5_ci_hi\n');
    
    for pm = 1:numel(pf_modes)
        pf_mode = pf_modes{pm};
        for hc = 1:numel(harq_configs)
            hcfg = harq_configs{hc};
            cr = cell_results{pm, hc};
            cname = sprintf('%s_rtt%d_np%d', pf_mode, hcfg.rtt, hcfg.np);
            
            for k = 1:numel(schemes)
                gp = cr.goodput(k, :);
                jn = cr.jain(k, :);
                ed = cr.edge5(k, :);
                
                [g_m, g_lo, g_hi] = mean_ci95(gp);
                [j_m, j_lo, j_hi] = mean_ci95(jn);
                [e_m, e_lo, e_hi] = mean_ci95(ed);
                
                fprintf(fid, '%s,%s,%d,%d,%s,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n', ...
                    cname, pf_mode, hcfg.rtt, hcfg.np, schemes{k}, ...
                    g_m, g_lo, g_hi, j_m, j_lo, j_hi, e_m, e_lo, e_hi);
            end
        end
    end
    fclose(fid);
    
    % Copy to paper/
    paper_csv = fullfile(ctx.root, 'paper', 'a6_pf_timing.csv');
    copyfile(csv_file, paper_csv);
    
    % Check Expectation E from A6 prereg:
    % E: under acked, 8 procs at RTT 8 gives goodput > 10% above 1 proc at RTT 8
    % for all 3 schemes, and Jain falls by > 0.02.
    % Under scheduled, the 8-process / 1-process ratio lies in [0.97, 1.03]
    % and |delta Jain| <= 0.02.
    
    % Index 2 is rtt8_np1, index 3 is rtt8_np8
    cr_ack_np1 = cell_results{1, 2};
    cr_ack_np8 = cell_results{1, 3};
    cr_sch_np1 = cell_results{2, 2};
    cr_sch_np8 = cell_results{2, 3};
    
    e_holds_acked = true(1, 3);
    e_holds_sched = true(1, 3);
    
    for k = 1:3
        ack_gp_np1 = mean(cr_ack_np1.goodput(k, :));
        ack_gp_np8 = mean(cr_ack_np8.goodput(k, :));
        ack_jn_np1 = mean(cr_ack_np1.jain(k, :));
        ack_jn_np8 = mean(cr_ack_np8.jain(k, :));
        
        gp_gain_ack = (ack_gp_np8 - ack_gp_np1) / ack_gp_np1;
        jn_diff_ack = ack_jn_np8 - ack_jn_np1;
        
        if ~(gp_gain_ack > 0.10 && jn_diff_ack < -0.02)
            e_holds_acked(k) = false;
        end
        
        sch_gp_np1 = mean(cr_sch_np1.goodput(k, :));
        sch_gp_np8 = mean(cr_sch_np8.goodput(k, :));
        sch_jn_np1 = mean(cr_sch_np1.jain(k, :));
        sch_jn_np8 = mean(cr_sch_np8.jain(k, :));
        
        sch_ratio = sch_gp_np8 / sch_gp_np1;
        sch_jn_diff = sch_jn_np8 - sch_jn_np1;
        
        if ~(sch_ratio >= 0.97 && sch_ratio <= 1.03 && abs(sch_jn_diff) <= 0.02)
            e_holds_sched(k) = false;
        end
    end
    
    all_E = all(e_holds_acked) && all(e_holds_sched);
    some_E = any(e_holds_acked) || any(e_holds_sched);
    
    if all_E
        verdict = 'Expectation E holds for ALL THREE schemes';
        wording = 'the timing of the PF average, not HARQ itself, accounts for the apparent gain in this diagnostic';
    elseif some_E
        verdict = 'Expectation E holds for SOME schemes';
        wording = 'the timing of the PF average effect varies by scheme';
    else
        verdict = 'Expectation E does NOT hold';
        wording = 'measured values differ from pre-registered expectation E';
    end
    
    % 2. Write fill_summary_v17pf.txt
    sum_file = fullfile(ctx.outdir, 'fill_summary_v17pf.txt');
    fid = fopen(sum_file, 'w');
    fprintf(fid, 'A6 PF-TIMING DEMONSTRATION SUMMARY (%s)\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Traces: %d\n', n_traces);
    fprintf(fid, 'VERDICT: %s\n', verdict);
    fprintf(fid, 'WORDING: %s\n\n', wording);
    
    fprintf(fid, '--- Paired Comparisons (RTT 8: 8 processes vs 1 process) ---\n');
    for k = 1:3
        sch = schemes{k};
        ack_np1 = mean(cr_ack_np1.goodput(k, :));
        ack_np8 = mean(cr_ack_np8.goodput(k, :));
        sch_np1 = mean(cr_sch_np1.goodput(k, :));
        sch_np8 = mean(cr_sch_np8.goodput(k, :));
        
        fprintf(fid, '%s:\n', sch);
        fprintf(fid, '  pf_avg=acked:      np1=%.3f, np8=%.3f, ratio=%.3f, dJain=%.3f\n', ...
            ack_np1, ack_np8, ack_np8/ack_np1, mean(cr_ack_np8.jain(k,:)) - mean(cr_ack_np1.jain(k,:)));
        fprintf(fid, '  pf_avg=scheduled:  np1=%.3f, np8=%.3f, ratio=%.3f, dJain=%.3f\n', ...
            sch_np1, sch_np8, sch_np8/sch_np1, mean(cr_sch_np8.jain(k,:)) - mean(cr_sch_np1.jain(k,:)));
    end
    fclose(fid);
    
    ctx.hbf(sprintf('A6 completed: %s', verdict));
end

% =========================================================================
function [m, ci_lo, ci_hi] = mean_ci95(x)
    n = numel(x);
    m = mean(x);
    if n <= 1
        ci_lo = m; ci_hi = m;
    else
        se = std(x) / sqrt(n);
        ci_lo = m - tinv(0.975, n - 1) * se;
        ci_hi = m + tinv(0.975, n - 1) * se;
    end
end
