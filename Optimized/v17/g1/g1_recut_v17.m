% g1_recut_v17.m  -- G1 re-cut: residual-action shares on SCHEDULED NEW TRANSMISSIONS only.
%
% Spec: paper/analysis/G1_SPEC.md.  No training. Greedy re-evaluation of the stored
% v17 policies on the original evaluation traces (same seeds, same CRN draws).
%
% Run (author's PC, MATLAB R2023a), from Optimized\v17:
%   addpath('g1'); g1_recut_v17
% Optional before running:  G1_CASES = {'M1_dl_rtt8','M3_gp_rtt8','M2_dl_rtt0','M4_gp_rtt0'};
%
% Outputs (Optimized\v17\paper\g1\):
%   g1_action_by_state.csv   delta shares per state bin, with counts
%   g1_summary.txt           checks (equivalence, reproduction), overall shares, M3/M4 decision identity
%   g1_log_<tag>.mat         raw per-decision log (for G2 attribution later)

if ~exist('G1_CASES', 'var'), G1_CASES = {'M1_dl_rtt8', 'M3_gp_rtt8'}; end
v17_setup;
addpath(fullfile(v17, 'g1'));
outDir = fullfile(v17, 'paper', 'g1');
if ~exist(outDir, 'dir'), mkdir(outDir); end
csvF = fopen(fullfile(outDir, 'g1_action_by_state.csv'), 'w');
fprintf(csvF, 'case_tag,condition_type,condition_bin,n_decisions,pct_delta_minus1,pct_delta_0,pct_delta_plus1,pct_effective_nonzero,n_clipped\n');
sumF = fopen(fullfile(outDir, 'g1_summary.txt'), 'w');
fprintf(sumF, 'G1 re-cut, %s, MATLAB %s\n', datestr(now, 31), version);
COLS = {'user','act_idx','slack','is_retx','busy','t','delay','speed','burst','ref','b_i','sent','rem'};
ci = @(name) find(strcmp(COLS, name));

for cIdx = 1:numel(G1_CASES)
    tag = G1_CASES{cIdx};
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R = data.results; env = R.env; envE = env; envE.scheduler = 'pf';
    kA2C = find(strcmp(R.schemes, 'Deep A2C v17'));
    kPU  = find(strcmp(R.schemes, 'FixedPU (Oracle)'));
    pols = R.policies.A2C; nS = numel(pols); nE = o.n_eval; T = o.simTime;
    b0 = min(env.burn_in, T - 1);
    isDL = strcmpi(env.traffic, 'deadline');
    fprintf(sumF, '\n=== %s (A2C scheme index %d, FixedPU index %d, %d seeds, %d traces)\n', tag, kA2C, kPU, nS, nE);

    % ---- 1. regenerate evaluation traces exactly as runComparison_v17 L183-191
    traces = struct('SINR', {}, 'obsS', {}, 'meta', {}, 'U', {});
    for j = 1:nE
        rng(o.trace_seed_base + j);
        [Strue, ~, meta] = generateChannel_v17(T, env);
        obsS = cqiFeedback_v17(Strue, env, meta.delays);
        meta.trace_id = j;
        rng(o.crn_seed_base + j); U = rand(T, env.N);
        traces(j).SINR = Strue; traces(j).obsS = obsS; traces(j).meta = meta; traces(j).U = U;
    end

    % ---- 2. equivalence test: instrumented copy vs frozen evaluator (seed 1, traces 1-5)
    Wa = pols{1};   % dlnetwork, passed exactly as runComparison_v17 L305 does
    eqOK = true;
    for j = 1:5
        rng(77000 + 100*j + 10*kA2C + 1);
        [a1, b1, c1, d1] = evalPolicy_v17('a2c_v17', Wa, traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
        rng(77000 + 100*j + 10*kA2C + 1);
        [a2, b2, c2, d2] = evalPolicy_v17_g1('a2c_v17', Wa, traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
        eqOK = eqOK && isequal(a1, a2) && isequal(b1, b2) && isequal(c1, c2) && isequal(d1, d2);
    end
    fprintf(sumF, 'EQUIV|%s|instrumented_vs_frozen_bit_identical=%d\n', tag, eqOK);
    if ~eqOK, fclose(csvF); fclose(sumF); error('G1: instrumented evaluator differs from evalPolicy_v17 -- STOP'); end

    % ---- 3. FixedPU decisions (deterministic, once per trace)
    puLog = cell(1, nE);
    for j = 1:nE
        rng(77000 + 100*j + 10*kPU + 1);
        [~, ~, ~, ~, infP] = evalPolicy_v17_g1('fixed_class', [], traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
        puLog{j} = infP.sch_log;
    end

    % ---- 4. A2C decisions, all seeds x traces, plus reproduction check vs stored metrics
    Lc = cell(nS, nE); maxRepDiff = 0; nSame = 0; nCmp = 0;
    for s = 1:nS
        Wa = pols{s};
        for j = 1:nE
            rng(77000 + 100*j + 10*kA2C + s);
            [tp, ~, ~, ~, infA] = evalPolicy_v17_g1('a2c_v17', Wa, traces(j).SINR, traces(j).obsS, envE, traces(j).meta, traces(j).U);
            cellv = sum(mean(tp(b0+1:end, :), 1));
            maxRepDiff = max(maxRepDiff, abs(cellv - R.metrics.cell_tp{kA2C}(s, j)));
            lg = infA.sch_log;
            if isempty(lg), continue; end
            % decision identity vs FixedPU at the same (t, user), new transmissions only
            P = puLog{j};
            if ~isempty(P)
                [tf, loc] = ismember(lg(:, [ci('t') ci('user')]), P(:, [ci('t') ci('user')]), 'rows');
                m = tf & lg(:, ci('is_retx')) == 0 & P(max(loc,1), ci('is_retx')) == 0;
                nCmp = nCmp + sum(m);
                nSame = nSame + sum(lg(m, ci('sent')) == P(loc(m), ci('sent')));
            end
            Lc{s, j} = [s * ones(size(lg, 1), 1), j * ones(size(lg, 1), 1), lg];
        end
        fprintf('  %s seed %d/%d done\n', tag, s, nS);
    end
    L = vertcat(Lc{:}); clear Lc;
    fprintf(sumF, 'REPRO|%s|max_abs_diff_cell_goodput_vs_stored=%.3e (must be 0)\n', tag, maxRepDiff);
    fprintf(sumF, 'PUMATCH|%s|new_tx_decisions_at_same_(t,user)=%d|same_sent_cqi=%d|frac=%.6f\n', tag, nCmp, nSame, nSame / max(nCmp, 1));
    save(fullfile(outDir, sprintf('g1_log_%s.mat', tag)), 'L', 'COLS', 'tag', '-v7.3');

    % ---- 5. keep scheduled NEW transmissions only; compute effective delta
    X = L(:, 3:end);                         % drop seed, trace columns
    keep = X(:, ci('is_retx')) == 0 & X(:, ci('act_idx')) >= 1 & X(:, ci('act_idx')) <= 3;
    fprintf(sumF, 'COUNT|%s|logged_scheduled=%d|retx_dropped=%d|new_tx_kept=%d\n', tag, size(X, 1), sum(X(:, ci('is_retx')) ~= 0), sum(keep));
    X = X(keep, :);
    dIdx = X(:, ci('act_idx'));                              % 1,2,3 -> delta -1,0,+1
    baseC = max(env.min_CQI, min(env.max_CQI, X(:, ci('ref')) + X(:, ci('b_i'))));
    effD = X(:, ci('sent')) - baseC;                         % 0 when clipping cancels delta
    clipped = (dIdx ~= 2) & (effD == 0);

    % ---- 6. state bins (edges fixed in G1_SPEC.md before running)
    bins = {};
    bins{end+1} = {'all', 'all', true(size(dIdx))};
    dly = X(:, ci('delay'));
    bins{end+1} = {'cqi_delay_class', 'delay<=4 TTI', dly <= 4};
    bins{end+1} = {'cqi_delay_class', 'delay>=5 TTI', dly >= 5};
    for d = 2:8, bins{end+1} = {'cqi_delay', sprintf('%d TTI', d), dly == d}; end %#ok<AGROW>
    bu = X(:, ci('burst'));
    bins{end+1} = {'interference', 'calm', bu == 0};
    bins{end+1} = {'interference', 'burst', bu ~= 0};
    sp = X(:, ci('speed'));
    bins{end+1} = {'speed_class', '<10 m/s', sp < 10};
    bins{end+1} = {'speed_class', '10-20 m/s', sp >= 10 & sp <= 20};
    bins{end+1} = {'speed_class', '>20 m/s', sp > 20};
    if isDL
        fr = X(:, ci('slack')) / env.pkt_deadline;           % remaining-deadline fraction, 1 = fresh packet
        bins{end+1} = {'deadline_frac', '<=0.3', fr <= 0.3};
        bins{end+1} = {'deadline_frac', '0.3-0.6', fr > 0.3 & fr <= 0.6};
        bins{end+1} = {'deadline_frac', '>0.6', fr > 0.6};
        rb = X(:, ci('rem')) / env.pkt_bits;                 % remaining-bits fraction
        bins{end+1} = {'bits_frac', '<=0.5', rb <= 0.5};
        bins{end+1} = {'bits_frac', '>0.5', rb > 0.5};
    end
    if env.harq_rtt > 0
        bp = X(:, ci('busy'));
        bins{end+1} = {'busy_procs', '0', bp == 0};
        bins{end+1} = {'busy_procs', '1-2', bp >= 1 & bp <= 2};
        bins{end+1} = {'busy_procs', '>=3', bp >= 3};
    end
    for b = 1:numel(bins)
        m = bins{b}{3}; n = sum(m);
        if n == 0, continue; end
        fprintf(csvF, '%s,%s,%s,%d,%.2f,%.2f,%.2f,%.2f,%d\n', tag, bins{b}{1}, bins{b}{2}, n, ...
            100*mean(dIdx(m) == 1), 100*mean(dIdx(m) == 2), 100*mean(dIdx(m) == 3), ...
            100*mean(effD(m) ~= 0), sum(clipped(m)));
    end
end
fclose(csvF); fclose(sumF);
fprintf('G1 done. See %s\n', outDir);

