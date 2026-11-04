% diag_action_by_state_v17.m
% State-conditional action share analysis for M1 and M2 primary policies (Deep A2C v17)
% restricted to scheduled users' new transmissions (excluding retransmissions and unscheduled users).

clear; clc;
v17_setup;

cases = {'M1_dl_rtt8', 'M2_dl_rtt0'};
paperDir = fullfile(v17, 'paper');
if ~exist(paperDir, 'dir'), mkdir(paperDir); end
csvFile = fullfile(paperDir, 'table_action_by_state.csv');
fid = fopen(csvFile, 'w');
fprintf(fid, 'case_tag,condition_type,condition_bin,count,pct_act_minus1,pct_act_0,pct_act_plus1\n');

for cIdx = 1:numel(cases)
    tag = cases{cIdx};
    fprintf('\n=== Analyzing State-Conditional Actions for %s (New Transmissions Only) ===\n', tag);
    ov = C.(tag);
    o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    
    matPath = fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag));
    data = load(matPath);
    results = data.results;
    env = results.env;
    policies = results.policies.A2C;
    nSeeds = numel(policies);
    nEval = o.n_eval;
    trace_seed_base = o.trace_seed_base;
    crn_seed_base = o.crn_seed_base;
    simTime = o.simTime;
    
    % Pre-generate eval traces
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:nEval
        rng(trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(simTime, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(crn_seed_base + j);
        U = rand(simTime, env.N);
        traces(j).SINR = Strue;
        traces(j).obsS = obsS;
        traces(j).meta = meta;
        traces(j).U    = U;
    end
    
    slack_counts = zeros(3, 3); % [bin, action]
    busy_counts  = zeros(3, 3);
    
    envE = env;
    envE.scheduler = 'pf'; % evaluation scheduler
    
    t0 = tic;
    for s = 1:nSeeds
        pol = policies{s};
        L = pol.Learnables;
        Wa.w1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Weights"});
        Wa.b1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Bias"});
        Wa.w2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Weights"});
        Wa.b2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Bias"});
        isL3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Weights";
        Wa.w3 = extractdata(L.Value{isL3});
        isB3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Bias";
        Wa.b3 = extractdata(L.Value{isB3});
        
        for j = 1:nEval
            rng(77000 + 100*j + 10*8 + s);
            [~, ~, ~, ~, inf] = evalPolicy_v17('a2c_v17', Wa, ...
                                               traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
            log = inf.sch_log;
            if isempty(log), continue; end
            
            % log columns: [user, action, slack, is_retx, busy_procs]
            acts = log(:, 2);
            slacks = log(:, 3);
            is_retx = log(:, 4);
            busy = log(:, 5);
            
            for row = 1:size(log, 1)
                % RESTRICTION: Exclude retransmissions
                if is_retx(row) > 0, continue; end
                
                a = acts(row); % 1: -1, 2: 0, 3: +1
                if a < 1 || a > 3, continue; end
                
                % Slack bin: 1: <=2, 2: 3-5, 3: >5
                sl = slacks(row);
                if sl <= 2
                    sb = 1;
                elseif sl <= 5
                    sb = 2;
                else
                    sb = 3;
                end
                slack_counts(sb, a) = slack_counts(sb, a) + 1;
                
                % Busy bin: 1: 0, 2: 1-2, 3: >=3
                b = busy(row);
                if b == 0
                    bb = 1;
                elseif b <= 2
                    bb = 2;
                else
                    bb = 3;
                end
                busy_counts(bb, a) = busy_counts(bb, a) + 1;
            end
        end
        fprintf('  Seed %d/%d completed (elapsed: %.1fs)\n', s, nSeeds, toc(t0));
    end
    
    % Slack rows
    s_labels = {'<=2 TTIs', '3-5 TTIs', '>5 TTIs'};
    for sb = 1:3
        cnt = sum(slack_counts(sb, :));
        if cnt > 0
            p1 = 100 * slack_counts(sb, 1) / cnt;
            p2 = 100 * slack_counts(sb, 2) / cnt;
            p3 = 100 * slack_counts(sb, 3) / cnt;
            fprintf(fid, '%s,slack,%s,%d,%.2f,%.2f,%.2f\n', tag, s_labels{sb}, cnt, p1, p2, p3);
            fprintf('  Slack %-10s | N=%6d | -1: %5.2f%% |  0: %5.2f%% | +1: %5.2f%%\n', ...
                s_labels{sb}, cnt, p1, p2, p3);
        end
    end
    
    % Busy rows
    if isfield(env, 'harq_rtt') && env.harq_rtt > 0
        b_labels = {'0 busy (0%)', '1-2 busy (12-25%)', '>=3 busy (>=37.5%)'};
        for bb = 1:3
            cnt = sum(busy_counts(bb, :));
            if cnt > 0
                p1 = 100 * busy_counts(bb, 1) / cnt;
                p2 = 100 * busy_counts(bb, 2) / cnt;
                p3 = 100 * busy_counts(bb, 3) / cnt;
                fprintf(fid, '%s,busy_proc,%s,%d,%.2f,%.2f,%.2f\n', tag, b_labels{bb}, cnt, p1, p2, p3);
                fprintf('  Busy %-12s | N=%6d | -1: %5.2f%% |  0: %5.2f%% | +1: %5.2f%%\n', ...
                    b_labels{bb}, cnt, p1, p2, p3);
            end
        end
    else
        cnt = sum(busy_counts(1, :));
        if cnt > 0
            p1 = 100 * busy_counts(1, 1) / cnt;
            p2 = 100 * busy_counts(1, 2) / cnt;
            p3 = 100 * busy_counts(1, 3) / cnt;
            fprintf(fid, '%s,busy_proc,0 busy (instantaneous),%d,%.2f,%.2f,%.2f\n', tag, cnt, p1, p2, p3);
            fprintf('  Busy 0 (instant) | N=%6d | -1: %5.2f%% |  0: %5.2f%% | +1: %5.2f%%\n', ...
                cnt, p1, p2, p3);
        end
    end
end

fclose(fid);
fprintf('\nState-conditional action table successfully written to %s\n', csvFile);
