function results = runComparison_v6(caseId, opts)
% runComparison_v6  Rigorous comparison harness for the v6 (OLLA-relative) stack.
%
%   results = runComparison_v6(23)                    Case 2/3 (5 users, PF)
%   results = runComparison_v6(23, struct('N',10))    N-user study
%
%   opts: N, simTime, ep_tab, ep_deep, n_seeds, n_eval, base_seed,
%         eval_schedulers, cqi_delay, speed, train_schedulers,
%         olla_target, olla_step_down, olla_warm_passes, pf_metric, reward_agg
%
% Protocol identical to audited v5: n_seeds trainings on the SAME MDP;
% n_eval held-out traces identical across schemes; frozen greedy policies;
% mean +/- 95% CI; paired Wilcoxon (A2C vs Baseline / OLLA); steady-state
% scoring; robustness sweep over schedulers. v6 difference: all learners are
% OLLA-relative (action 0 == OLLA), see defaultEnv_v6.
% Unchanged helpers are reused from ../v5 (added to path below).

    if nargin < 2, opts = struct(); end
    g = @(f,d) get_def(opts, f, d);
    Nopt     = g('N', []);
    simTime  = g('simTime', 200);
    ep_tab   = g('ep_tab', 500);    % state gained an OLLA-offset dim -> more episodes
    ep_deep  = g('ep_deep', 500);
    n_seeds  = g('n_seeds', 3);
    n_eval   = g('n_eval', 20);
    baseSeed = g('base_seed', 42);

    env = defaultEnv_v6(caseId, Nopt);
    if isfield(opts,'cqi_delay')       && ~isempty(opts.cqi_delay),       env.cqi_delay = opts.cqi_delay;             end
    if isfield(opts,'speed')           && ~isempty(opts.speed),           env.speed = opts.speed;                     end
    if isfield(opts,'train_schedulers')&& ~isempty(opts.train_schedulers),env.train_schedulers = opts.train_schedulers; end
    if isfield(opts,'olla_target')     && ~isempty(opts.olla_target),     env.olla_target = opts.olla_target;         end
    if isfield(opts,'olla_step_down')  && ~isempty(opts.olla_step_down),  env.olla_step_down = opts.olla_step_down;   end
    if isfield(opts,'olla_warm_passes')&& ~isempty(opts.olla_warm_passes),env.olla_warm_passes = opts.olla_warm_passes; end
    if isfield(opts,'olla_warm_ttis')  && ~isempty(opts.olla_warm_ttis),  env.olla_warm_ttis = opts.olla_warm_ttis;   end
    if isfield(opts,'use_gpu')         && ~isempty(opts.use_gpu),         env.use_gpu = opts.use_gpu;                 end
    if isfield(opts,'pf_metric')       && ~isempty(opts.pf_metric),       env.pf_metric = opts.pf_metric;             end
    if isfield(opts,'reward_agg')      && ~isempty(opts.reward_agg),      env.reward_agg = opts.reward_agg;           end
    if isfield(opts,'actions')         && ~isempty(opts.actions),         env.actions = opts.actions;                 end
    if isfield(opts,'rho_fading')      && ~isempty(opts.rho_fading),      env.rho_fading = opts.rho_fading;           end
    if isfield(opts,'sigma_meas')      && ~isempty(opts.sigma_meas),      env.sigma_meas = opts.sigma_meas;           end
    if caseId == 1, eval_scheds = g('eval_schedulers', {'all'});
    else,           eval_scheds = g('eval_schedulers', {'pf','rr','eq'}); end

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, '..', 'v5'));        % unchanged helpers (generateChannel_v5, ...)
    addpath(fullfile(here, '..', 'case2_3'));   % createTBS_Table, tbsFromMCSandRB

    t0_total = tic;
    fprintf('\n');
    fprintf('========================================================================\n');
    fprintf('  v6 multi-user RL-AMC comparison (OLLA-relative encoding)\n');
    fprintf('------------------------------------------------------------------------\n');
    fprintf('  Case .................. %d\n', caseId);
    fprintf('  Users (N) ............. %d\n', env.N);
    fprintf('  Default scheduler ..... %s\n', upper(env.scheduler));
    fprintf('  Trained on (mix) ...... { %s }\n', strjoin(env.train_schedulers, ', '));
    fprintf('  Episodes (tabular) .... %d\n', ep_tab);
    fprintf('  Episodes (deep) ....... %d\n', ep_deep);
    fprintf('  TTIs per episode ...... %d\n', simTime);
    fprintf('  Seeds ................. %d\n', n_seeds);
    fprintf('  Held-out eval traces .. %d\n', n_eval);
    fprintf('  CQI delay (intervals) . %d\n', env.cqi_delay);
    fprintf('  CQI meas noise (dB) ... %.2f\n', env.sigma_meas);
    fprintf('  PF metric ............. %s\n', env.pf_metric);
    fprintf('  Reward aggregation .... %s\n', env.reward_agg);
    fprintf('  OLLA target/step ...... %.2f / %.2f dB (warm passes %d)\n', ...
            env.olla_target, env.olla_step_down, env.olla_warm_passes);
    fprintf('  Started at ............ %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf('========================================================================\n\n');

    % ---------- training (multi-seed, shared parameters) ----------
    QLs=cell(1,n_seeds); ACs=cell(1,n_seeds); A2Cs=cell(1,n_seeds);
    lc_ql=zeros(ep_tab,n_seeds); lc_ac=zeros(ep_tab,n_seeds);
    lc_dac=zeros(ep_deep,n_seeds); ent_dac=zeros(ep_deep,n_seeds);
    train_times = zeros(3, n_seeds);
    fprintf('PHASE 1 -- Training (%d seeds x 3 algorithms = %d runs)\n', n_seeds, 3*n_seeds);
    fprintf('------------------------------------------------------------------------\n');
    for s = 1:n_seeds
        sd = baseSeed + 1000*s;
        fprintf('  seed %d/%d (%s)\n', s, n_seeds, datestr(now,'HH:MM:SS'));
        tic; [QLs{s}, lc_ql(:,s)] = QL_Shared_v6(simTime, ep_tab, sd, env);
        train_times(1,s) = toc;
        fprintf('    [Q-Learn ]  %6.1f s    final cellTp = %5.2f Mbps\n', train_times(1,s), lc_ql(end,s));
        tic; [ACs{s}, ~, lc_ac(:,s)] = AC_Shared_v6(simTime, ep_tab, sd, env);
        train_times(2,s) = toc;
        fprintf('    [Tab AC  ]  %6.1f s    final cellTp = %5.2f Mbps\n', train_times(2,s), lc_ac(end,s));
        tic; [A2Cs{s}, ~, lc_dac(:,s), ent_dac(:,s)] = DeepA2C_Shared_v6(simTime, ep_deep, sd, env);
        train_times(3,s) = toc;
        fprintf('    [Deep A2C]  %6.1f s    final cellTp = %5.2f Mbps   final H = %5.3f\n', ...
                train_times(3,s), lc_dac(end,s), ent_dac(end,s));
    end
    fprintf('  Training total: %.1f min\n\n', sum(train_times(:))/60);

    % ---------- held-out evaluation traces ----------
    fprintf('PHASE 2 -- Evaluation on %d held-out traces under %d scheduler(s)\n', ...
            n_eval, numel(eval_scheds));
    fprintf('------------------------------------------------------------------------\n');
    traces = struct('SINR',[], 'obsS',[], 'dist',[]); traces(n_eval).SINR = [];
    for j = 1:n_eval
        rng(9000 + j);
        [Strue, dist, ~] = generateChannel_v5(simTime, env);
        [obsS, ~] = cqiFeedback_v5(Strue, env);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).dist = dist;
    end

    schemes = {'Baseline','OLLA','QL v6','Tab AC v6','Deep A2C v6'};
    ptypes  = {'baseline','olla','ql','ac','a2c'};
    K = numel(schemes);

    for sc = 1:numel(eval_scheds)
        envE = env; envE.scheduler = eval_scheds{sc};
        M = init_metrics(K, n_seeds, n_eval);
        for j = 1:n_eval
            for k = 1:K
                if k <= 2, ns = 1; else, ns = n_seeds; end
                for s = 1:ns
                    pol = [];
                    if k==3, pol=QLs{s}; elseif k==4, pol=ACs{s}; elseif k==5, pol=A2Cs{s}; end
                    rng(77000 + 100*j + 10*k + s);
                    [tp, bl, ce] = evalPolicy_v6(ptypes{k}, pol, traces(j).SINR, traces(j).obsS, envE);
                    b0 = min(env.burn_in, size(tp,1)-1);
                    tpB = tp(b0+1:end,:); blB = bl(b0+1:end,:); ceB = ce(b0+1:end,:);
                    pu = mean(tpB, 1);
                    M.cell_tp{k}(s,j) = sum(pu);
                    M.edge_tp{k}(s,j) = min(pu);
                    sm = tpB > 0;
                    if any(sm(:)), M.bler{k}(s,j) = mean(blB(sm)); else, M.bler{k}(s,j) = NaN; end
                    M.jain{k}(s,j) = sum(pu)^2 / (env.N * max(sum(pu.^2), eps));
                    M.cqie{k}(s,j) = mean(ceB(:));
                    if s==min(ns,2)
                        M.tp_field{k,j}   = tp;
                        M.bler_field{k,j} = bl;
                        M.dist_field{j}   = traces(j).dist;
                    end
                end
            end
        end
        allM(sc) = M; %#ok<AGROW>
    end
    M = allM(1);

    % ---------- stats: FULL metric table for EVERY evaluation scheduler ----------
    primary = upper(eval_scheds{1});
    txt = sprintf('================================================================\n');
    txt = [txt sprintf('v6 RESULTS (OLLA-relative)  case=%d  N=%d  primary scheduler=%s\n', caseId, env.N, primary)];
    txt = [txt sprintf('seeds=%d  eval_traces=%d  ep_tab=%d  ep_deep=%d  simTime=%d\n', ...
                       n_seeds, n_eval, ep_tab, ep_deep, simTime)];
    txt = [txt sprintf('cqi_delay=%d  sigma_meas=%.2f dB  trained_on={%s}\n', ...
                       env.cqi_delay, env.sigma_meas, strjoin(env.train_schedulers,','))];
    txt = [txt sprintf('pf_metric=%s  reward_agg=%s  olla: target=%.2f step=%.2f warm=%d\n', ...
                       env.pf_metric, env.reward_agg, env.olla_target, env.olla_step_down, env.olla_warm_passes)];
    txt = [txt sprintf('saved at %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'))];
    txt = [txt sprintf('================================================================\n\n')];

    pvals = nan(1,2); mm = []; bestIdx = [];
    for sc = 1:numel(eval_scheds)
        [tsec, mm_sc, bi_sc, pv_sc] = render_sched_block( ...
            allM(sc), upper(eval_scheds{sc}), schemes, K, caseId, n_seeds, n_eval);
        txt = [txt tsec newline]; %#ok<AGROW>
        if sc == 1, mm = mm_sc; bestIdx = bi_sc; pvals = pv_sc; end
    end
    M = allM(1);
    best_cell_idx = bestIdx.cell;
    baseTp = mm.cellTp(1);

    % Robustness
    if numel(eval_scheds) > 1
        fprintf('\n========================================================================\n');
        fprintf('  ROBUSTNESS - cell throughput (Mbps) by eval scheduler\n');
        fprintf('========================================================================\n');
        txt = [txt newline sprintf('Robustness (cell Tp, Mbps, by eval scheduler):\n')];
        hdr2 = sprintf('  %-13s', 'Scheme');
        for sc = 1:numel(eval_scheds)
            hdr2 = [hdr2 sprintf(' | %10s', upper(eval_scheds{sc}))]; %#ok<AGROW>
        end
        hdr2 = [hdr2 sprintf(' | %10s', 'min/max')];
        fprintf('%s\n', hdr2);
        sep2 = ['  ', repmat('-', 1, length(hdr2)-3), newline];
        fprintf('%s', sep2);
        txt = [txt hdr2 newline sep2];

        best_per_sched = zeros(1, numel(eval_scheds));
        for sc = 1:numel(eval_scheds)
            vals = zeros(1, K);
            for k = 1:K, vals(k) = mean(allM(sc).cell_tp{k}(:)); end
            [~, best_per_sched(sc)] = max(vals);
        end

        for k = 1:K
            ln = sprintf('  %-13s', schemes{k});
            vals_k = zeros(1, numel(eval_scheds));
            for sc = 1:numel(eval_scheds)
                v = mean(allM(sc).cell_tp{k}(:));
                vals_k(sc) = v;
                mk = ' '; if k == best_per_sched(sc), mk = '*'; end
                ln = [ln sprintf(' |%c%9.3f', mk, v)]; %#ok<AGROW>
            end
            ratio = min(vals_k) / max(max(vals_k), eps);
            ln = [ln sprintf(' | %9.2f%%', 100*ratio)]; %#ok<AGROW>
            fprintf('%s\n', ln); txt = [txt ln newline]; %#ok<AGROW>
            if k == 2
                fprintf('%s', sep2); txt = [txt sep2]; %#ok<AGROW>
            end
        end
        note2 = sprintf('  (* = best in column; min/max = scheduler robustness ratio, higher is better)\n');
        fprintf('%s\n', note2); txt = [txt note2 newline];
    end

    % Final verdict line
    winner = schemes{best_cell_idx};
    gain   = 100*(mm.cellTp(best_cell_idx) - baseTp) / max(baseTp, eps);
    elapsed_min = toc(t0_total)/60;
    verdict = sprintf('  VERDICT: best cell-Tp = %s (%.2f Mbps, %+.1f%% vs Baseline)   total runtime %.1f min', ...
                      winner, mm.cellTp(best_cell_idx), gain, elapsed_min);
    fprintf('========================================================================\n');
    fprintf('%s\n', verdict);
    fprintf('========================================================================\n\n');
    txt = [txt newline verdict newline];

    % ---------- figures: a SEPARATE set per evaluation scheduler ----------
    for sc = 1:numel(eval_scheds)
        lbl = upper(eval_scheds{sc});
        plot_kpi_bars(schemes, allM(sc), env, lbl);
        plot_vs_distance(schemes, allM(sc), traces, n_eval, lbl);
        plot_bler_vs_distance(schemes, allM(sc), traces, n_eval, lbl);
        % v6 policy heatmap (offset vs state around the OLLA reference): TODO;
        % v5 heatmap assumes the baseline-relative feature layout and is skipped.
    end
    plot_learning(lc_ql, lc_ac, lc_dac, ent_dac, simTime, env);

    % ---------- save ----------
    results.caseId = caseId; results.env = env; results.schemes = schemes;
    results.metrics = allM; results.eval_schedulers = eval_scheds;
    results.pvals_a2c_vs_baseline_olla = pvals;
    results.learning = struct('ql',lc_ql,'ac',lc_ac,'dac',lc_dac);
    results.entropy.dac = ent_dac;
    results.policies = struct('QL',{QLs},'AC',{ACs},'A2C',{A2Cs});
    results.opts = struct('N',env.N,'simTime',simTime,'ep_tab',ep_tab,'ep_deep',ep_deep, ...
                          'n_seeds',n_seeds,'n_eval',n_eval,'base_seed',baseSeed);
    % ---- collision-proof save (audit fix: never overwrite existing results) ----
    % opts.tag appends a run label; if the target name still exists, a
    % timestamp suffix is added. Saves into Dataset/ when that folder exists.
    tag = sprintf('case%d_N%d', caseId, env.N);
    usertag = g('tag', '');
    if ~isempty(usertag), tag = [tag '_' char(usertag)]; end
    outdir = here;
    if exist(fullfile(here, 'Dataset'), 'dir'), outdir = fullfile(here, 'Dataset'); end
    mat_path = fullfile(outdir, sprintf('results_v6_%s.mat', tag));
    txt_path = fullfile(outdir, sprintf('results_v6_%s.txt', tag));
    if exist(mat_path, 'file') || exist(txt_path, 'file')
        stamp = datestr(now, 'yyyymmdd_HHMMSS');
        mat_path = fullfile(outdir, sprintf('results_v6_%s_%s.mat', tag, stamp));
        txt_path = fullfile(outdir, sprintf('results_v6_%s_%s.txt', tag, stamp));
    end
    save(mat_path, 'results', '-v7.3');
    fid = fopen(txt_path, 'w'); fprintf(fid, '%s', txt); fclose(fid);
    fprintf('  Saved:\n');
    fprintf('    %s\n', mat_path);
    fprintf('    %s\n', txt_path);
    fprintf('  Figures created (per scheduler %s): KPI bars, Tp-vs-distance, BLER-vs-distance; plus one learning-curve figure\n\n', ...
            strjoin(eval_scheds, '/'));
end


% ===== helpers =====
function v = get_def(s,f,d), if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end, end

function [txt, mm, bestIdx, pvals] = render_sched_block(M, lbl, schemes, K, caseId, n_seeds, n_eval)
    txt = '';
    mm.cellTp=zeros(1,K); mm.cellCI=zeros(1,K); mm.edgeTp=zeros(1,K); mm.edgeCI=zeros(1,K);
    mm.bler=zeros(1,K); mm.jain=zeros(1,K); mm.cqie=zeros(1,K);
    for k = 1:K
        [mm.cellTp(k), mm.cellCI(k)] = mci(M.cell_tp{k}(:));
        [mm.edgeTp(k), mm.edgeCI(k)] = mci(M.edge_tp{k}(:));
        mm.bler(k) = mean(M.bler{k}(:), 'omitnan');
        mm.jain(k) = mean(M.jain{k}(:));
        mm.cqie(k) = mean(M.cqie{k}(:));
    end
    baseTp = mm.cellTp(1);
    [~, bci] = max(mm.cellTp); [~, bei] = max(mm.edgeTp);
    [~, bji] = max(mm.jain);   [~, bbi] = min(mm.bler);
    bestIdx = struct('cell',bci,'edge',bei,'jain',bji,'bler',bbi);

    banner = sprintf(['\n========================================================================\n', ...
        '  RESULTS - Case %d, scheduler %s, mean over %d seeds x %d traces (95%% CI)\n', ...
        '========================================================================\n'], caseId, lbl, n_seeds, n_eval);
    fprintf('%s', banner);
    txt = [txt sprintf('---- scheduler %s ----\n', lbl)];

    hdr = sprintf('  %-12s | %18s | %8s | %18s | %8s | %7s | %8s\n', ...
                  'Scheme','Cell Tp (Mbps)','d vs BL','Edge Tp (Mbps)','BLER','Jain','CQIerr');
    sep = ['  ', repmat('-', 1, length(hdr)-3), newline];
    fprintf('%s%s', hdr, sep); txt = [txt hdr sep];
    for k = 1:K
        if baseTp > eps, delta = 100*(mm.cellTp(k)-baseTp)/baseTp; else, delta = 0; end
        if k == 1, dstr = '   (ref)'; else, dstr = sprintf('%+6.1f%%', delta); end
        mc=' '; if k==bci, mc='*'; end
        me=' '; if k==bei, me='*'; end
        mb=' '; if k==bbi, mb='*'; end
        mj=' '; if k==bji, mj='*'; end
        line = sprintf('  %-12s |%c%7.2f +/- %5.2f | %8s |%c%7.2f +/- %5.2f |%c%7.4f |%c%6.3f | %8.3f', ...
            schemes{k}, mc, mm.cellTp(k), mm.cellCI(k), dstr, me, mm.edgeTp(k), mm.edgeCI(k), ...
            mb, mm.bler(k), mj, mm.jain(k), mm.cqie(k));
        fprintf('%s\n', line); txt = [txt line newline];
        if k == 2, fprintf('%s', sep); txt = [txt sep]; end
    end
    note = sprintf('  (* = best in column)\n'); fprintf('%s\n', note); txt = [txt note newline];

    pvals = nan(1,2); a2c_tr = mean(M.cell_tp{5}, 1);
    if exist('signrank','file') == 2
        pvals(1) = signrank(a2c_tr, M.cell_tp{1}(1,:));
        pvals(2) = signrank(a2c_tr, M.cell_tp{2}(1,:));
        line = sprintf('  Wilcoxon (paired): A2C vs Baseline  p=%.4g %s   |   A2C vs OLLA  p=%.4g %s', ...
                       pvals(1), sig_stars(pvals(1)), pvals(2), sig_stars(pvals(2)));
    else
        line = '  Wilcoxon unavailable (Statistics Toolbox missing); rely on 95% CI overlap';
    end
    fprintf('%s\n', line); txt = [txt line newline];
end

function s = sig_stars(p)
    if      p < 0.001, s = '***';
    elseif  p < 0.01,  s = '**';
    elseif  p < 0.05,  s = '*';
    else,              s = '(n.s.)';
    end
end

function M = init_metrics(K, n_seeds, n_eval)
    for k = 1:K
        if k <= 2, ns = 1; else, ns = n_seeds; end
        M.cell_tp{k}=zeros(ns,n_eval); M.edge_tp{k}=zeros(ns,n_eval);
        M.bler{k}=zeros(ns,n_eval); M.jain{k}=zeros(ns,n_eval); M.cqie{k}=zeros(ns,n_eval);
    end
    M.tp_field   = cell(K, n_eval);
    M.bler_field = cell(K, n_eval);
    M.dist_field = cell(1, n_eval);
end

function [m,ci] = mci(x)
    x = x(~isnan(x)); n = numel(x); m = mean(x);
    if n > 1, ci = 1.96*std(x)/sqrt(n); else, ci = 0; end
end

function plot_kpi_bars(schemes, M, env, lbl)
    if nargin < 4 || isempty(lbl), lbl = upper(env.scheduler); end
    K = numel(schemes); mt=zeros(1,K); ct=zeros(1,K); mb=zeros(1,K); mj=zeros(1,K);
    for k = 1:K
        [mt(k),ct(k)] = mci(M.cell_tp{k}(:));
        mb(k) = mean(M.bler{k}(:),'omitnan'); mj(k) = mean(M.jain{k}(:));
    end
    sup = sprintf('v6 KPIs  |  Case %d  |  N=%d  |  scheduler=%s', env.caseId, env.N, lbl);
    figure('Position',[60 60 1200 420],'Name',sprintf('v6 KPIs (%s)', lbl),'Color','w');
    subplot(1,3,1); bar(mt, 'FaceColor',[0.20 0.45 0.75]); hold on;
    errorbar(1:K,mt,ct,'k.','LineWidth',1.3);
    for k = 1:K
        text(k, mt(k)+ct(k)+0.02*max(mt), sprintf('%.2f', mt(k)), ...
             'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');
    end
    set(gca,'XTickLabel',schemes,'XTickLabelRotation',30,'FontSize',10);
    ylabel('Cell Tp (Mbps)'); title('Cell throughput (95% CI)'); grid on;
    yl = ylim; ylim([0 yl(2)*1.12]);

    subplot(1,3,2); bar(mb, 'FaceColor',[0.85 0.40 0.30]); hold on;
    yline(0.1,'k--','target','LineWidth',1.2,'LabelHorizontalAlignment','left');
    for k = 1:K
        text(k, mb(k)+0.005, sprintf('%.3f', mb(k)), ...
             'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');
    end
    set(gca,'XTickLabel',schemes,'XTickLabelRotation',30,'FontSize',10);
    ylabel('Mean BLER (served TTIs)'); title('Block error rate'); grid on;

    subplot(1,3,3); bar(mj, 'FaceColor',[0.30 0.65 0.30]);
    ylim([0 1.05]);
    for k = 1:K
        text(k, mj(k)+0.02, sprintf('%.3f', mj(k)), ...
             'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');
    end
    set(gca,'XTickLabel',schemes,'XTickLabelRotation',30,'FontSize',10);
    ylabel('Jain index'); title(sprintf('Fairness (N=%d users)', env.N)); grid on;

    sgtitle(sup, 'FontWeight','bold','FontSize',12);
end

function plot_learning(lc_ql, lc_ac, lc_dac, ent_dac, simTime, env)
    spe = simTime*env.N;
    sup = sprintf('v6 Learning curves  |  Case %d  |  N=%d  |  scheduler=%s', ...
                  env.caseId, env.N, upper(env.scheduler));
    figure('Position',[60 60 1050 440],'Name','v6 learning curves','Color','w');

    subplot(1,2,1); hold on; grid on;
    h1 = shaded(spe*(1:size(lc_ql,1)),  lc_ql,  [0.85 0.15 0.15]);
    h2 = shaded(spe*(1:size(lc_ac,1)),  lc_ac,  [0.15 0.30 0.85]);
    h3 = shaded(spe*(1:size(lc_dac,1)), lc_dac, [0.10 0.65 0.20]);
    xlabel('Environment steps (= simTime x N x episode)','FontSize',10);
    ylabel('Cell Tp per interval (Mbps)','FontSize',10);
    title('Mean +/- 1 std over seeds','FontSize',11);
    legend([h1 h2 h3], {'Q-Learning','Tabular AC','Deep A2C'}, 'Location','best');

    subplot(1,2,2); hold on; grid on;
    mu = mean(ent_dac, 2); sd = std(ent_dac, 0, 2);
    x = 1:numel(mu);
    fill([x fliplr(x)], [mu'+sd' fliplr(mu'-sd')], [0.1 0.65 0.2], ...
         'FaceAlpha', 0.15, 'EdgeColor', 'none');
    plot(x, mu, 'Color', [0.1 0.65 0.2], 'LineWidth', 1.6);
    xlabel('Episode','FontSize',10); ylabel('Policy entropy (nats)','FontSize',10);
    title('Deep A2C entropy schedule','FontSize',11);

    sgtitle(sup, 'FontWeight','bold','FontSize',12);
end

function hline = shaded(x, Y, c)
    mu = mean(Y,2).'; sd = std(Y,0,2).';
    fill([x fliplr(x)], [mu+sd fliplr(mu-sd)], c, 'FaceAlpha',0.15, 'EdgeColor','none');
    hline = plot(x, mu, 'Color', c, 'LineWidth', 1.6);
end

function plot_vs_distance(schemes, M, traces, n_eval, lbl)
    if nargin < 5 || isempty(lbl), lbl = ''; end
    K = numel(schemes); d_all = [];
    for j = 1:n_eval, d_all = [d_all; traces(j).dist(:)]; end %#ok<AGROW>
    edges = linspace(min(d_all), max(d_all), 26); ctr = (edges(1:end-1)+edges(2:end))/2;
    cols   = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    styles = {'--', '-.', '-', '-', '-'};
    figure('Position',[60 60 1050 460],'Name',sprintf('v6 Tp vs distance (%s)', lbl),'Color','w');
    hold on; grid on;
    handles = gobjects(1, K);
    for k = 1:K
        dv=[]; tv=[];
        for j = 1:n_eval
            tp = M.tp_field{k,j}; if isempty(tp), continue; end
            dv=[dv; traces(j).dist(:)]; tv=[tv; tp(:)]; %#ok<AGROW>
        end
        sm = tv > 0; b = nan(1,numel(ctr));
        for q = 1:numel(ctr)
            in = sm & dv>=edges(q) & dv<edges(q+1);
            if any(in), b(q) = mean(tv(in)); end
        end
        handles(k) = plot(ctr, b, styles{k}, 'Color', cols{k}, 'LineWidth', 1.9);
    end
    xlabel('Distance from BS (m)','FontSize',10);
    ylabel('Served throughput (Mbps)','FontSize',10);
    title(sprintf('Throughput vs distance  |  scheduler=%s  (held-out, served TTIs)', lbl), ...
          'FontWeight','bold','FontSize',11);
    legend(handles, schemes, 'Location','best','FontSize',10);
end

function plot_bler_vs_distance(schemes, M, traces, n_eval, lbl)
    if nargin < 5 || isempty(lbl), lbl = ''; end
    K = numel(schemes);
    if ~isfield(M,'bler_field') || isempty(M.bler_field), return; end
    d_all = [];
    for j = 1:n_eval, d_all = [d_all; traces(j).dist(:)]; end %#ok<AGROW>
    edges = linspace(min(d_all), max(d_all), 26); ctr = (edges(1:end-1)+edges(2:end))/2;
    cols   = {[0 0 0],[0.5 0.5 0.5],[0.85 0.15 0.15],[0.15 0.3 0.85],[0.1 0.65 0.2]};
    styles = {'--', '-.', '-', '-', '-'};
    figure('Position',[60 60 1050 460],'Name',sprintf('v6 BLER vs distance (%s)', lbl),'Color','w');
    hold on; grid on; handles = gobjects(1, K);
    for k = 1:K
        dv=[]; bv=[];
        for j = 1:n_eval
            bl = M.bler_field{k,j}; if isempty(bl), continue; end
            dv=[dv; traces(j).dist(:)]; bv=[bv; bl(:)]; %#ok<AGROW>
        end
        b = nan(1,numel(ctr));
        for q = 1:numel(ctr)
            in = dv>=edges(q) & dv<edges(q+1);
            if any(in), b(q) = mean(bv(in)); end
        end
        handles(k) = plot(ctr, b, styles{k}, 'Color', cols{k}, 'LineWidth', 1.9);
    end
    yline(0.1,'k--','target','LineWidth',1.1,'LabelHorizontalAlignment','left');
    xlabel('Distance from BS (m)','FontSize',10);
    ylabel('Mean BLER','FontSize',10); ylim([0 1]);
    title(sprintf('BLER vs distance  |  scheduler=%s  (held-out)', lbl), ...
          'FontWeight','bold','FontSize',11);
    legend(handles, schemes, 'Location','best','FontSize',10);
end
