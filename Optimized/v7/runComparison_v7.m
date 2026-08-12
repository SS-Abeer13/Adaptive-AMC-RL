function results = runComparison_v7(opts)
% runComparison_v7  Comparison harness: calibrate, train, evaluate, report.
    if nargin < 1, opts = struct(); end
    g = @(f,d) get_def(opts, f, d);

    Nopt     = g('N', 10);
    simTime  = g('simTime', 200);
    ep_tab   = g('ep_tab', 300);
    ep_deep  = g('ep_deep', 300);
    n_seeds  = g('n_seeds', 5);
    n_eval   = g('n_eval', 30);
    baseSeed = g('base_seed', 42);
    traceSeedBase = g('trace_seed_base', 9000);
    nCalib   = g('n_calib', 6);

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, '..', 'v5'));
    addpath(fullfile(here, '..', 'case2_3'));

    env = defaultEnv_v7(23, Nopt);
    for f = {'hetero','burst_on','burst_IM_dB','burst_dwell_calm', ...
             'burst_dwell_burst','speed_switch','harq_on','harq_max_retx', ...
             'harq_comb_dB','state_tier','olla_warm_ttis','actions', ...
             'sigma_meas','speed','cqi_delay','delay_hom','use_gpu', ...
             'train_sched_weights','bc_warm_eps','fixed_cands'}
        if isfield(opts, f{1}) && ~isempty(opts.(f{1})), env.(f{1}) = opts.(f{1}); end
    end
    eval_scheds = g('eval_schedulers', {'pf','rr','eq'});

    fprintf('========================================================================\n');
    fprintf('  v7 comparison  |  N=%d  hetero=%.2f  burst=%d(+%g dB)  harq=%d  tier=%s\n', ...
            env.N, env.hetero, env.burst_on, env.burst_IM_dB, env.harq_on, env.state_tier);
    fprintf('  seeds=%d  traces=%d  ep_tab=%d  ep_deep=%d  simTime=%d  warm_ttis=%d\n', ...
            n_seeds, n_eval, ep_tab, ep_deep, simTime, env.olla_warm_ttis);
    fprintf('  started %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'));
    fprintf('========================================================================\n');

    % Phase 0: calibrate fixed-offset comparators
    env = calibrateFixedClass_v7(env, nCalib, simTime);

    % Phase 1: training
    fprintf('PHASE 1 -- Training (%d seeds x 3 algorithms)\n', n_seeds);
    QLs = cell(1,n_seeds); ACs = cell(1,n_seeds); A2Cs = cell(1,n_seeds);
    lc_ql = zeros(ep_tab, n_seeds); lc_ac = zeros(ep_tab, n_seeds);
    lc_dac = zeros(ep_deep, n_seeds); ent_dac = zeros(ep_deep, n_seeds);
    for s = 1:n_seeds
        fprintf('  seed %d/%d (%s)\n', s, n_seeds, datestr(now,'HH:MM:SS'));
        t0 = tic;
        [QLs{s}, lc_ql(:,s)] = QL_Shared_v7(simTime, ep_tab, baseSeed + s, env);
        fprintf('    [Q-Learn ] %7.1f s   final cellTp = %5.2f\n', toc(t0), lc_ql(end,s));
        t0 = tic;
        [ACs{s}, ~, lc_ac(:,s)] = AC_Shared_v7(simTime, ep_tab, baseSeed + 100 + s, env);
        fprintf('    [Tab AC  ] %7.1f s   final cellTp = %5.2f\n', toc(t0), lc_ac(end,s));
        t0 = tic;
        [A2Cs{s}, ~, lc_dac(:,s), ent_dac(:,s)] = ...
            DeepA2C_Shared_v7(simTime, ep_deep, baseSeed + 200 + s, env);
        fprintf('    [Deep A2C] %7.1f s   final cellTp = %5.2f\n', toc(t0), lc_dac(end,s));
    end

    % Phase 2: held-out traces, identical for every scheme
    fprintf('PHASE 2 -- Evaluation on %d held-out traces\n', n_eval);
    traces = struct('SINR',[], 'obsS',[], 'meta',[]); traces(n_eval).SINR = [];
    for j = 1:n_eval
        rng(traceSeedBase + j);
        [Strue, ~, meta] = generateChannel_v7(simTime, env);
        obsS = cqiFeedback_v7(Strue, env, meta.delays);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta;
    end

    schemes = {'Baseline','OLLA','Fixed','FixedPU','QL v7','Tab AC v7','Deep A2C v7'};
    ptypes  = {'baseline','olla','fixed','fixed_class','ql','ac','a2c'};
    K = numel(schemes);
    detK = 4;

    for sc = 1:numel(eval_scheds)
        envE = env; envE.scheduler = eval_scheds{sc};
        M = init_metrics(K, n_seeds, n_eval);
        for j = 1:n_eval
            mt = traces(j).meta;
            for k = 1:K
                if k <= detK, ns = 1; else, ns = n_seeds; end
                for s = 1:ns
                    pol = [];
                    if k==5, pol=QLs{s}; elseif k==6, pol=ACs{s}; elseif k==7, pol=A2Cs{s}; end
                    rng(77000 + 100*j + 10*k + s);
                    [tp, bl, ce] = evalPolicy_v7(ptypes{k}, pol, ...
                                        traces(j).SINR, traces(j).obsS, envE, mt);
                    b0 = min(env.burn_in, size(tp,1)-1);
                    tpB = tp(b0+1:end,:); blB = bl(b0+1:end,:); ceB = ce(b0+1:end,:);
                    bu  = mt.burst(b0+1:end);
                    pu = mean(tpB, 1);
                    M.cell_tp{k}(s,j) = sum(pu);
                    M.edge_tp{k}(s,j) = min(pu);
                    ok = ~isnan(blB);
                    if any(ok(:)), M.bler{k}(s,j) = mean(blB(ok)); else, M.bler{k}(s,j) = NaN; end
                    M.jain{k}(s,j) = sum(pu)^2 / (env.N * max(sum(pu.^2), eps));
                    M.cqie{k}(s,j) = mean(ceB(:));
                    if any(bu),  M.tp_burst{k}(s,j) = sum(mean(tpB(bu,:), 1));
                    else,        M.tp_burst{k}(s,j) = NaN; end
                    if any(~bu), M.tp_calm{k}(s,j)  = sum(mean(tpB(~bu,:), 1));
                    else,        M.tp_calm{k}(s,j)  = NaN; end
                end
            end
        end
        allM(sc) = M; %#ok<AGROW>
    end

    % Phase 3: report
    txt = header_txt(env, n_seeds, n_eval, ep_tab, ep_deep, simTime, traceSeedBase, baseSeed);
    pv = struct();
    for sc = 1:numel(eval_scheds)
        [tsec, pv_sc] = render_block(allM(sc), upper(eval_scheds{sc}), schemes, K, n_seeds, n_eval);
        txt = [txt tsec]; %#ok<AGROW>
        if sc == 1, pv = pv_sc; end
    end

    results.env = env; results.schemes = schemes; results.metrics = allM;
    results.eval_schedulers = eval_scheds; results.pvals = pv;
    results.learning = struct('ql',lc_ql,'ac',lc_ac,'dac',lc_dac,'ent',ent_dac);
    results.policies = struct('QL',{QLs},'AC',{ACs},'A2C',{A2Cs});
    results.opts = opts;

    tag = g('tag', 'run');
    outdir = fullfile(here, 'Dataset');
    if ~exist(outdir, 'dir'), mkdir(outdir); end
    mat_path = fullfile(outdir, sprintf('results_v7_%s.mat', tag));
    txt_path = fullfile(outdir, sprintf('results_v7_%s.txt', tag));
    if exist(mat_path, 'file') || exist(txt_path, 'file')
        stamp = datestr(now, 'yyyymmdd_HHMMSS');
        mat_path = fullfile(outdir, sprintf('results_v7_%s_%s.mat', tag, stamp));
        txt_path = fullfile(outdir, sprintf('results_v7_%s_%s.txt', tag, stamp));
    end
    save(mat_path, 'results', '-v7.3');
    fid = fopen(txt_path, 'w'); fprintf(fid, '%s', txt); fclose(fid);
    fprintf('  Saved:\n    %s\n    %s\n', mat_path, txt_path);
end


function v = get_def(s,f,d), if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end, end

function M = init_metrics(K, n_seeds, n_eval)
    for k = 1:K
        if k <= 4, ns = 1; else, ns = n_seeds; end
        M.cell_tp{k}=zeros(ns,n_eval); M.edge_tp{k}=zeros(ns,n_eval);
        M.bler{k}=zeros(ns,n_eval); M.jain{k}=zeros(ns,n_eval); M.cqie{k}=zeros(ns,n_eval);
        M.tp_burst{k}=nan(ns,n_eval); M.tp_calm{k}=nan(ns,n_eval);
    end
end

function txt = header_txt(env, n_seeds, n_eval, ep_tab, ep_deep, simTime, tsb, bs)
    txt = sprintf('================================================================\n');
    txt = [txt sprintf('v7 RESULTS  N=%d  hetero=%.2f  burst_on=%d(+%g dB, dwell %d/%d)\n', ...
        env.N, env.hetero, env.burst_on, env.burst_IM_dB, env.burst_dwell_calm, env.burst_dwell_burst)];
    txt = [txt sprintf('harq_on=%d(max %d, comb %.1f dB)  jakes=%d  speed_switch=%d  tier=%s\n', ...
        env.harq_on, env.harq_max_retx, env.harq_comb_dB, env.jakes, env.speed_switch, env.state_tier)];
    txt = [txt sprintf('seeds=%d  eval_traces=%d  ep_tab=%d  ep_deep=%d  simTime=%d\n', ...
        n_seeds, n_eval, ep_tab, ep_deep, simTime)];
    txt = [txt sprintf('BW=%g MHz  RB=%d  sigma_meas=%.2f dB  actions=%s\n', ...
        env.BW/1e6, env.total_RB, env.sigma_meas, mat2str(env.actions))];
    txt = [txt sprintf('olla: target=%.2f step=%.2f warm_ttis=%d  fixed=%+d  class_tab=%s\n', ...
        env.olla_target, env.olla_step_down, env.olla_warm_ttis, env.fixed_offset, ...
        mat2str(env.fixed_class_tab))];
    bce = 0; if isfield(env,'bc_warm_eps'), bce = env.bc_warm_eps; end
    txt = [txt sprintf('train_sched_weights=%s  bc_warm_eps=%d  fixed_cands=%s\n', ...
        mat2str(env.train_sched_weights, 2), bce, mat2str(env.fixed_cands))];
    txt = [txt sprintf('base_seed=%d  trace_seed_base=%d  saved %s\n', ...
        bs, tsb, datestr(now,'yyyy-mm-dd HH:MM:SS'))];
    txt = [txt sprintf('================================================================\n\n')];
    fprintf('%s', txt);
end

function [txt, pv] = render_block(M, lbl, schemes, K, n_seeds, n_eval)
    txt = sprintf('---- scheduler %s ----\n', lbl);
    tr = cell(1,K);
    for k = 1:K, tr{k} = mean(M.cell_tp{k}, 1); end
    mm = cellfun(@mean, tr);
    ci = cellfun(@(x) 1.96*std(x)/sqrt(numel(x)), tr);
    edge = zeros(1,K); bler = zeros(1,K); jain = zeros(1,K);
    tb = zeros(1,K); tc = zeros(1,K);
    for k = 1:K
        edge(k) = mean(mean(M.edge_tp{k},1));
        bler(k) = mean(M.bler{k}(:), 'omitnan');
        jain(k) = mean(M.jain{k}(:));
        tb(k)   = mean(M.tp_burst{k}(:), 'omitnan');
        tc(k)   = mean(M.tp_calm{k}(:),  'omitnan');
    end
    base = mm(1);
    [~, bi] = max(mm);

    hdr = sprintf('  %-12s | %16s | %8s | %7s | %7s | %6s | burst / calm Tp\n', ...
                  'Scheme','Cell Tp (Mbps)','d vs BL','EdgeTp','BLER1','Jain');
    sep = ['  ', repmat('-', 1, 86), newline];
    txt = [txt hdr sep]; fprintf('%s%s', hdr, sep);
    for k = 1:K
        if k == 1, dstr = '   (ref)'; else, dstr = sprintf('%+6.1f%%', 100*(mm(k)-base)/max(base,eps)); end
        mk = ' '; if k == bi, mk = '*'; end
        line = sprintf('  %-12s |%c%7.2f +/- %4.2f | %8s | %7.2f | %7.4f | %6.3f | %5.2f / %5.2f', ...
            schemes{k}, mk, mm(k), ci(k), dstr, edge(k), bler(k), jain(k), tb(k), tc(k));
        fprintf('%s\n', line); txt = [txt line newline]; %#ok<AGROW>
        if k == 4, fprintf('%s', sep); txt = [txt sep]; end %#ok<AGROW>
    end
    note = sprintf(['  (CI: trace-level n=%d; BLER1 = first-transmission BLER;\n' ...
                    '   burst/calm = cell Tp during interference bursts vs calm)\n'], n_eval);
    fprintf('%s', note); txt = [txt note];

    pv = struct();
    if exist('signrank','file') == 2
        refs = [2 3 4 6 1];
        names = {'OLLA   ','Fixed  ','FixedPU','TabAC  ','Baseline'};
        fields = {'a2c_vs_olla','a2c_vs_fixed','a2c_vs_fixedPU','a2c_vs_tabac','a2c_vs_base'};
        line = sprintf('  Wilcoxon (paired, n=%d traces), margin = A2C vs comparator:\n', n_eval);
        for q = 1:numel(refs)
            p = signrank(tr{7}, tr{refs(q)});
            pv.(fields{q}) = p;
            mrg = 100*(mean(tr{7}) - mean(tr{refs(q)})) / max(mean(tr{refs(q)}), eps);
            if mrg >= 0, dirw = 'WIN '; else, dirw = 'LOSS'; end
            note2 = ''; if q == 3, note2 = '   <-- pre-registered win condition'; end
            line = [line sprintf('    A2C vs %s %+6.1f%%  p=%.4g %s [%s]%s\n', ...
                    names{q}, mrg, p, stars(p), dirw, note2)]; %#ok<AGROW>
        end
        fprintf('%s\n', line); txt = [txt line newline];
    end
end

function s = stars(p)
    if      p < 0.001, s = '***';
    elseif  p < 0.01,  s = '**';
    elseif  p < 0.05,  s = '*';
    else,              s = '(n.s.)';
    end
end
