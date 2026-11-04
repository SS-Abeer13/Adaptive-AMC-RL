% fill_v9_campaign  Full corrected v9 campaign (internal review of 19 Oct 2026):
%   mob_kappa = 1 (physical mobility time scale), common random numbers,
%   UCB bandit baselines, matched steady state, RR/EQ, regime sweep, and
%   re-runs of every result reported in the v8 paper.
% Progress: logs/fill_v9.log ; numbers: Dataset/fill_summary_v9.txt
v9_setup;
logf = fullfile(v9, 'logs', 'fill_v9.log');
diary off; if exist(logf, 'file'), delete(logf); end
diary(logf);
sumf = fullfile(ds, 'fill_summary_v9.txt');
fid = fopen(sumf, 'w');
fprintf(fid, 'V9 CAMPAIGN started %s | MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
fclose(fid);
T0 = tic;

% ---- point list: {tag, overrides, analyses} ----
P = cell(0, 3);
P(end+1, :) = {'gp_O',        struct(),                                                         'stats,actions,sweep,sanity'};
P(end+1, :) = {'steady_match', struct('simTime', 1000, 'ep_deep', 150, 'n_seeds', 5, 'olla_warm_ttis', 1000, 'train_warm_ttis', 1000, 'calib_warm', true), 'stats'};
P(end+1, :) = {'steady_cold',  struct('simTime', 1000, 'ep_deep', 150, 'n_seeds', 5, 'olla_warm_ttis', 1000), 'stats'};
P(end+1, :) = {'rr_O',        struct('eval_schedulers', {{'rr'}}, 'train_sched_weights', [0 1 0]), 'stats,actions'};
P(end+1, :) = {'eq_O',        struct('eval_schedulers', {{'eq'}}, 'train_sched_weights', [0 0 1]), 'stats,actions'};
P(end+1, :) = {'burst6_O',    struct('burst_IM_dB', 6),  'stats'};
P(end+1, :) = {'burst12_O',   struct('burst_IM_dB', 12), 'stats'};
P(end+1, :) = {'h0_O',        struct('hetero', 0),       'stats'};
P(end+1, :) = {'h05_O',       struct('hetero', 0.5),     'stats'};
P(end+1, :) = {'gp_A',        struct('state_tier', 'A'), 'stats,actions'};
P(end+1, :) = {'gp_B',        struct('state_tier', 'B'), 'stats,actions'};
P(end+1, :) = {'pen_O',       struct('lambda_retx', 0.05, 'lambda_drop', 0.5), 'stats,actions'};
P(end+1, :) = {'pen_A',       struct('lambda_retx', 0.05, 'lambda_drop', 0.5, 'state_tier', 'A'), 'stats'};
P(end+1, :) = {'pen_B',       struct('lambda_retx', 0.05, 'lambda_drop', 0.5, 'state_tier', 'B'), 'stats'};
P(end+1, :) = {'orig_O',      struct('lambda_retx', 0.05, 'lambda_drop', 0.5, 'sched_on_ref', false), 'stats,sanity'};
P(end+1, :) = {'orig_A',      struct('lambda_retx', 0.05, 'lambda_drop', 0.5, 'sched_on_ref', false, 'state_tier', 'A'), 'stats'};
P(end+1, :) = {'orig_B',      struct('lambda_retx', 0.05, 'lambda_drop', 0.5, 'sched_on_ref', false, 'state_tier', 'B'), 'stats,sanity'};

for p = 1:size(P, 1)
    tag = P{p, 1};
    fprintf('\n######## %s | %s | elapsed %.1f min ########\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
    fid = fopen(sumf, 'a'); fprintf(fid, '\nSTEP|%s|start|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60); fclose(fid);
    try
        o = base; ov = P{p, 2}; fn = fieldnames(ov);
        for q = 1:numel(fn), o.(fn{q}) = ov.(fn{q}); end
        o.save_tag = tag;
        runComparison_v9(o);
        f = fullfile(ds, ['results_v9_' tag '.mat']);
        fid = fopen(sumf, 'a');
        an = P{p, 3};
        fill_stats_v9(f, tag, fid);
        if contains(an, 'actions')
            tg = []; if contains(an, 'sweep'), tg = [0.1 0.2 0.3 0.4 0.5]; end
            fill_actions_sweep_v9(f, tag, fid, 30, tg);
        end
        if contains(an, 'sanity'), fill_sanity2_v9(f, tag, fid); end
        fprintf(fid, 'STEP|%s|done|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
        fclose(fid);
    catch ME
        fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); fclose(fid);
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
end

% ---- behaviour-cloning diagnostic (goodput and penalised reward) ----
for rw = {'gp', 'pen'}
    tag = ['bcdiag_' rw{1}];
    fprintf('\n######## %s | %s | elapsed %.1f min ########\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
    fid = fopen(sumf, 'a'); fprintf(fid, '\nSTEP|%s|start|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
    try
        o = base; if strcmp(rw{1}, 'pen'), o.lambda_retx = 0.05; o.lambda_drop = 0.5; end
        fprintf(fid, 'BCTAG|%s\n', tag);
        fill_bc_diag_v9(o, 5, 150, 300, 100, fid);
    catch ME
        fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
    fclose(fid);
end

% ---- longer training with the original scheduler input (G4) ----
tag = 'orig_O_long1500';
fprintf('\n######## %s | %s | elapsed %.1f min ########\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60);
fid = fopen(sumf, 'a'); fprintf(fid, '\nSTEP|%s|start|%s|elapsed_min=%.1f\n', tag, datestr(now, 'HH:MM:SS'), toc(T0)/60); fclose(fid);
try
    o = base; o.lambda_retx = 0.05; o.lambda_drop = 0.5; o.sched_on_ref = false;
    o.ep_deep = 1500; o.n_seeds = 3; o.save_tag = tag;
    runComparison_v9(o);
    fid = fopen(sumf, 'a'); fill_stats_v9(fullfile(ds, ['results_v9_' tag '.mat']), tag, fid); fclose(fid);
catch ME
    fid = fopen(sumf, 'a'); fprintf(fid, 'ERROR|%s|%s\n', tag, ME.message); fclose(fid);
    disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
end

fid = fopen(sumf, 'a');
fprintf(fid, '\nV9 CAMPAIGN finished %s | total %.1f min\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), toc(T0)/60);
fclose(fid);
fprintf('\n######## ALL DONE | %s | elapsed %.1f min ########\n', datestr(now, 'HH:MM:SS'), toc(T0)/60);
diary off;
