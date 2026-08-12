function U = measureActionUsage_v6(matfile, outfile)
% measureActionUsage_v6  Report the Deep A2C action-index distribution --- in
% particular the action-0 (== OLLA no-op) rate --- per evaluation scheduler,
% from a saved results_v6 .mat, WITHOUT retraining.
%
%   U = measureActionUsage_v6                              % newest *results_v6*.mat
%   U = measureActionUsage_v6('FINAL_results_v6_N10_d4_cameraready.mat')
%   U = measureActionUsage_v6('FINAL_results_v6_N10_d6_cameraready.mat')
%
% Why this matters (council catch): if A2C almost always selects action 0 it
% is merely relabelling OLLA; a genuine learned correction must show a
% materially lower action-0 rate in the conditions where A2C *beats* OLLA
% (e.g. PF@delay6) than where it loses (RR@4, EQ@4). Run this on the d4 and d6
% camera-ready files and compare.
%
% Method: regenerate the exact held-out traces (rng(9000+j)), re-evaluate the
% saved A2C policies with the same per-call RNG the harness used
% (rng(77000+100*j+10*5+s), k=5 for A2C), and tally the selected action index
% over post-burn-in TTIs. Requires the v6 eval to return its 4th output ACT.

    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(matfile)
        d = [dir(fullfile(here,'results_v6_*.mat')); dir(fullfile(here,'FINAL*results_v6*.mat'))];
        if isempty(d), error('measureActionUsage_v6: no *results_v6*.mat in %s', here); end
        [~, ix] = max([d.datenum]); matfile = fullfile(d(ix).folder, d(ix).name);
    elseif ~isfile(matfile)
        matfile = fullfile(here, matfile);
    end
    [~, stem] = fileparts(matfile);
    if nargin < 2 || isempty(outfile)
        outfile = fullfile(here, sprintf('actionUsage_%s.txt', stem));
    end

    addpath(fullfile(here, '..', 'v5'));
    addpath(fullfile(here, '..', 'case2_3'));
    S = load(matfile); R = S.results; env = R.env;
    simTime = R.opts.simTime; n_eval = R.opts.n_eval; n_seeds = R.opts.n_seeds;
    scheds  = R.eval_schedulers;
    A2C     = R.policies.A2C;
    A = env.actions; nA = numel(A); no_op = find(A == 0);
    b0 = min(env.burn_in, simTime-1);

    % ---- regenerate the exact held-out traces ----
    traces = struct('SINR',{},'obsS',{});
    for j = 1:n_eval
        rng(9000 + j);
        [Strue, ~, ~] = generateChannel_v5(simTime, env);
        [obsS, ~] = cqiFeedback_v5(Strue, env);
        traces(j).SINR = Strue; traces(j).obsS = obsS; %#ok<AGROW>
    end

    txt = sprintf('Deep A2C action usage  |  %s  |  N=%d  delay=%d  seeds=%d  traces=%d\n', ...
                  stem, env.N, env.cqi_delay, n_seeds, n_eval);
    txt = [txt sprintf('Action set = [%s];  action %d = 0 (== OLLA no-op)\n', ...
                       strtrim(sprintf('%d ', A)), no_op)];
    txt = [txt repmat('-',1,78) newline];
    hdr = sprintf('  %-6s |', 'Sched');
    for a = 1:nA, hdr = [hdr sprintf(' %+5d', A(a))]; end
    hdr = [hdr sprintf(' |  action0%%  deviate%%')];
    txt = [txt hdr newline repmat('-',1,78) newline];

    U = struct();
    for sc = 1:numel(scheds)
        envE = env; envE.scheduler = scheds{sc};
        counts = zeros(1, nA); tot = 0;
        for j = 1:n_eval
            for s = 1:n_seeds
                rng(77000 + 100*j + 10*5 + s);          % k=5 (a2c), matches harness
                [~,~,~,act] = evalPolicy_v6('a2c', A2C{s}, traces(j).SINR, traces(j).obsS, envE);
                aa = act(b0+1:end, :); aa = aa(:);
                for x = 1:nA, counts(x) = counts(x) + sum(aa == x); end
                tot = tot + numel(aa);
            end
        end
        pct = 100 * counts / max(tot, 1);
        lbl = upper(scheds{sc});
        U.(lbl).pct = pct; U.(lbl).action0 = pct(no_op); U.(lbl).deviate = 100 - pct(no_op);
        row = sprintf('  %-6s |', lbl);
        for a = 1:nA, row = [row sprintf(' %5.1f', pct(a))]; end %#ok<AGROW>
        row = [row sprintf(' |  %6.1f   %6.1f', pct(no_op), 100-pct(no_op))]; %#ok<AGROW>
        fprintf('%s\n', row); txt = [txt row newline]; %#ok<AGROW>
    end
    txt = [txt repmat('-',1,78) newline];
    txt = [txt 'Interpretation: a high action-0%% under a LOSING scheduler (RR@4, EQ@4) with a' newline];
    txt = [txt 'lower action-0%% under a WINNING one (PF, esp. delay 6) supports "real learned' newline];
    txt = [txt 'correction"; near-100%% everywhere would indicate a relabelled OLLA.' newline];

    fid = fopen(outfile, 'w'); fprintf(fid, '%s', txt); fclose(fid);
    fprintf('\nSaved %s\n', outfile);
end
