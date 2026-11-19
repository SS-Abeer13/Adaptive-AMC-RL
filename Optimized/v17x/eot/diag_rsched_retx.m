function res = diag_rsched_retx()
% diag_rsched_retx  Task 4 (D-RS): Frequency and impact of the retransmission
% scheduled-rate mismatch in RTT 8 training (DeepA2C_Shared_v17 lines 429-435).
% Evaluates calibration traces 60001-60100 using NR2 seed 1 acting greedily.

    here = fileparts(mfilename('fullpath'));
    v17x_dir = fileparts(here);
    v17_dir = fullfile(fileparts(v17x_dir), 'v17');
    addpath(here);
    addpath(fullfile(v17x_dir, 'nr1'));
    addpath(fullfile(v17x_dir, 'g6'));
    addpath(v17x_dir);
    addpath(v17_dir);
    v17_setup;

    % Load M1 base setup and NR2 policy
    tag = 'M1_dl_rtt8';
    ov = C.(tag); o = base; fn = fieldnames(ov);
    for k = 1:numel(fn), o.(fn{k}) = ov.(fn{k}); end
    data_m1 = load(fullfile(v17, 'Dataset', sprintf('results_v17_%s.mat', tag)));
    R_M1 = data_m1.results;
    env = R_M1.env;
    env.base_rule_force = 'fixed';
    env.fixed_offset = -2;
    env = selectBaseRule_v17n(env, 2, o.simTime);
    env.scheduler = 'pf';

    nr2_s1_mat = load(fullfile(v17x_dir, 'Dataset', 'ckpt', 'nr2', 'train_seed_1.mat'));
    pol_net = nr2_s1_mat.out.a2c;
    L = pol_net.Learnables;
    Wa.w1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Weights"});
    Wa.b1 = extractdata(L.Value{L.Layer == "fc1" & L.Parameter == "Bias"});
    Wa.w2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Weights"});
    Wa.b2 = extractdata(L.Value{L.Layer == "fc2" & L.Parameter == "Bias"});
    isL3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Weights";
    Wa.w3 = extractdata(L.Value{isL3});
    isB3 = (L.Layer == "logits" | L.Layer == "value") & L.Parameter == "Bias";
    Wa.b3 = extractdata(L.Value{isB3});

    nTraces = 100;
    tr_start = 60001;
    tr_end   = 60100;
    fprintf('Running D-RS diagnostic on calibration traces %d-%d...\n', tr_start, tr_end);

    tot_sched_ttis = 0;
    tot_diff_rsched = 0;
    tot_retx = 0;
    tot_retx_p_not_1 = 0;
    delta_Remas_all = [];
    tot_pf_comp_ttis = 0;
    tot_pf_user_change = 0;

    A = env.actions;
    minC = env.min_CQI; maxC = env.max_CQI;
    minD = -5; maxD = 5;
    ema = 0.05;
    N = env.N;
    L_seq = 3;
    if upper(env.state_tier) == 'A', nBase = 5; elseif upper(env.state_tier) == 'O', nBase = 10; else, nBase = 13; end
    nSingle = nBase + numel(env.sched_list) + nExtra_v17(env);
    nFeat = nSingle * L_seq;
    [~, sOneHot] = schedContext_v5(env.scheduler, env);
    ctx = single(repmat(sOneHot, 1, N));
    Pq = 1; if isfield(env, 'cqi_period'), Pq = max(1, round(env.cqi_period)); end

    for j = 1:nTraces
        tr_seed = 60000 + j;
        rng(tr_seed, 'twister');
        [Strue, ~, meta] = generateChannel_v17(o.simTime, env);
        obs_SINR = cqiFeedback_v17(Strue, env, meta.delays);

        burstObsM = zeros(o.simTime, N);
        for i = 1:N
            idx = max((1:o.simTime).' - meta.delays(i), 1);
            burstObsM(:, i) = double(meta.burst(idx));
        end

        ageM = cqiAge_v17(o.simTime, N, Pq);

        % Episode state initialization
        Q = trafficInit_v17(env, N, 0);
        H = harqInit_v17(N, env);
        off = zeros(1, N);
        R_emas_train = zeros(1, N); % trainer tracker
        R_emas_eval  = zeros(1, N); % evaluator tracker
        emaO = obs_SINR(1, :);
        cn = 0;
        nk = zeros(1, N);
        tsince = zeros(1, N);
        ack8 = zeros(1, N);
        offEma = zeros(1, N);
        prevRef = baseCQI_v17(obs_SINR(1, :) + off, env);
        histS = zeros(nSingle, N, L_seq, 'single');
        dec_counter = 0;

        for t = 1:o.simTime
            % 1. Feedback
            du = env.olla_step_down * env.olla_target / (1 - env.olla_target);
            dd = env.olla_step_down;
            [H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_v17(H, Q, off, env, t, du, dd);
            if isfield(env, 'olla_off_lim') && ~isempty(env.olla_off_lim)
                off = max(-env.olla_off_lim, min(env.olla_off_lim, off));
            end

            % 2. Traffic Pre
            [Q, H] = trafficPre_v17(Q, t, env, H);

            % 3. Cues & Action selection (NR2 greedy A2C)
            X = struct('age', ageM(t, :), 'dev', obs_SINR(t, :) - emaO, 'cn', cn, 'Q', Q, 't', t, ...
                       'ack8', ack8, 'tsince', tsince, 'offtrend', off - offEma, 'H', H);
            ref  = baseCQI_v17(obs_SINR(t, :) + off, env);
            dRef = max(minD, min(maxD, ref - prevRef));
            dS   = obs_SINR(t, :) - obs_SINR(max(t-1, 1), :);
            t0   = max(t-4, 1);
            slope4 = (obs_SINR(t, :) - obs_SINR(t0, :)) / max(t - t0, 1);

            s_now = stateFeat_v17(env.state_tier, ref, dRef, obs_SINR(t, :), dS, off, ...
                                 slope4, nk, H, meta.speeds(t, :), burstObsM(t, :), ...
                                 meta.delays, R_emas_train, ctx, featExtra_v17(env, X));
            histS(:, :, 2:L_seq) = histS(:, :, 1:L_seq-1);
            histS(:, :, 1) = s_now;
            S_temporal = reshape(permute(histS, [1, 3, 2]), nFeat, N);

            % Forward actor
            x1 = max(0, Wa.w1 * S_temporal + Wa.b1);
            x2 = max(0, Wa.w2 * x1 + Wa.b2);
            logits = Wa.w3 * x2 + Wa.b3;
            [~, aAll] = max(logits, [], 1);
            delta = env.resid_actions(aAll);
            sent = max(minC, min(maxC, ref - 2 + delta)); % Fixed -2 base rule

            % Scheduling
            pot = zeros(1, N);
            retxReady = any(H.proc_isRetx, 2)';
            hasFree = any(~H.proc_busy, 2)' & (Q.tx_rem > 0);
            elig = Q.has & (retxReady | hasFree);
            p_retx_user = zeros(1, N);
            for i = 1:N
                if ~elig(i), continue; end
                if retxReady(i)
                    p_retx = find(H.proc_isRetx(i, :), 1);
                    p_retx_user(i) = p_retx;
                    pot(i) = tbsFromMCSandRB_v17(H.proc_mcs(i, p_retx), env.total_RB) * 1e-3;
                else
                    pot(i) = tbsFromMCSandRB_v17(sent(i) - 1, env.total_RB) * 1e-3;
                end
            end
            dlv = inf(1, N); dlv(Q.has) = Q.dl(Q.has);

            % PF user selection with trainer R_emas vs evaluator R_emas
            rb_train = schedule_users_v17('pf', t, N, R_emas_train, pot, env.total_RB, dlv);
            rb_eval  = schedule_users_v17('pf', t, N, R_emas_eval, pot, env.total_RB, dlv);
            rb_train(~elig) = 0;
            rb_eval(~elig) = 0;

            u_train = find(rb_train > 0);
            u_eval  = find(rb_eval > 0);
            if any(elig)
                tot_pf_comp_ttis = tot_pf_comp_ttis + 1;
                if ~isequal(u_train, u_eval)
                    tot_pf_user_change = tot_pf_user_change + 1;
                end
            end

            % Run physical step with rb_train (training path)
            rb = rb_train;
            schedM = rb > 0;
            sch_u = find(schedM);

            cur_dec_ids = zeros(1, N);
            for i = find(schedM)
                if ~retxReady(i)
                    dec_counter = dec_counter + 1;
                    cur_dec_ids(i) = dec_counter;
                end
            end

            % Evaluator r_sched before harqTransmit:
            r_sched_eval = zeros(1, N);
            if ~isempty(sch_u)
                tot_sched_ttis = tot_sched_ttis + 1;
                if retxReady(sch_u)
                    tot_retx = tot_retx + 1;
                    p_tx = p_retx_user(sch_u);
                    if p_tx ~= 1
                        tot_retx_p_not_1 = tot_retx_p_not_1 + 1;
                    end
                    r_sched_eval(sch_u) = H.proc_tbs(sch_u, p_tx) * 1e-3;
                else
                    tx_mcs = max(0, min(14, sent(sch_u) - 1));
                    r_sched_eval(sch_u) = tbsFromMCSandRB_v17(tx_mcs, rb(sch_u)) * 1e-3;
                end
            end

            % Physical transmission
            [H, Q, bl1, isRetxTx] = harqTransmit_v17(sent, Strue(t, :), rb, H, Q, env, t, [], cur_dec_ids);

            % Trainer r_sched after harqTransmit (DeepA2C_Shared_v17.m lines 428-440):
            r_sched_train = zeros(1, N);
            if ~isempty(sch_u)
                if isRetxTx(sch_u)
                    retx_p = find(H.proc_isRetx(sch_u, :));
                    if ~isempty(retx_p)
                        r_sched_train(sch_u) = H.proc_tbs(sch_u, retx_p(1)) * 1e-3;
                    else
                        r_sched_train(sch_u) = tbsFromMCSandRB_v17(H.proc_mcs(sch_u, 1), rb(sch_u)) * 1e-3;
                    end
                else
                    tx_mcs = max(0, min(14, sent(sch_u) - 1));
                    r_sched_train(sch_u) = tbsFromMCSandRB_v17(tx_mcs, rb(sch_u)) * 1e-3;
                end

                if abs(r_sched_train(sch_u) - r_sched_eval(sch_u)) > 1e-9
                    tot_diff_rsched = tot_diff_rsched + 1;
                end
            end

            % Update both trackers
            R_emas_train = (1 - ema) * R_emas_train + ema * r_sched_train;
            R_emas_eval  = (1 - ema) * R_emas_eval  + ema * r_sched_eval;

            d_Remas = abs(R_emas_train - R_emas_eval);
            delta_Remas_all = [delta_Remas_all; d_Remas(:)]; %#ok<AGROW>

            prevRef = ref;
            tsince(rb > 0) = 0; tsince(rb == 0) = tsince(rb == 0) + 1;
            ack8(schedM) = 0.8 * ack8(schedM) + 0.2 * double(~isnan(bl1(schedM)));
            offEma = 0.9 * offEma + 0.1 * off;
            emaO = 0.98 * emaO + 0.02 * obs_SINR(t, :);
        end
    end

    % Aggregate stats
    share_diff_rsched  = tot_diff_rsched / max(1, tot_sched_ttis);
    share_retx_p_not_1 = tot_retx_p_not_1 / max(1, tot_retx);
    mean_dRemas        = mean(delta_Remas_all);
    p99_dRemas         = prctile(delta_Remas_all, 99);
    share_pf_change    = tot_pf_user_change / max(1, tot_pf_comp_ttis);

    fprintf('\n=== D-RS Retransmission Scheduled-Rate Mismatch Diagnostic ===\n');
    fprintf('Total scheduled TTIs:                      %d\n', tot_sched_ttis);
    fprintf('Scheduled TTIs where r_sched differed:     %d (%.2f%%)\n', tot_diff_rsched, 100 * share_diff_rsched);
    fprintf('Total retransmissions:                     %d\n', tot_retx);
    fprintf('Retransmissions on process p != 1:         %d (%.2f%%)\n', tot_retx_p_not_1, 100 * share_retx_p_not_1);
    fprintf('Mean |Delta R_emas|:                       %.4f Mbps\n', mean_dRemas);
    fprintf('99th percentile |Delta R_emas|:            %.4f Mbps\n', p99_dRemas);
    fprintf('Share of TTIs where PF user would change:  %d/%d (%.2f%%)\n', tot_pf_user_change, tot_pf_comp_ttis, 100 * share_pf_change);

    res = struct( ...
        'tot_sched_ttis', tot_sched_ttis, ...
        'tot_diff_rsched', tot_diff_rsched, ...
        'share_diff_rsched', share_diff_rsched, ...
        'tot_retx', tot_retx, ...
        'tot_retx_p_not_1', tot_retx_p_not_1, ...
        'share_retx_p_not_1', share_retx_p_not_1, ...
        'mean_dRemas', mean_dRemas, ...
        'p99_dRemas', p99_dRemas, ...
        'share_pf_change', share_pf_change ...
    );

    % Save results
    out_dir = fullfile(v17x_dir, 'Dataset', 'eot');
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    save(fullfile(out_dir, 'diag_rsched_retx.mat'), 'res');
    txt_file = fullfile(out_dir, 'diag_rsched_retx.txt');
    fid = fopen(txt_file, 'w');
    if fid > 0
        fprintf(fid, 'D-RS DIAGNOSTIC REPORT (traces 60001-60100)\n');
        fprintf(fid, 'share_diff_rsched=%.4f (%d/%d)\n', share_diff_rsched, tot_diff_rsched, tot_sched_ttis);
        fprintf(fid, 'share_retx_p_not_1=%.4f (%d/%d)\n', share_retx_p_not_1, tot_retx_p_not_1, tot_retx);
        fprintf(fid, 'mean_delta_Remas=%.4f\n', mean_dRemas);
        fprintf(fid, 'p99_delta_Remas=%.4f\n', p99_dRemas);
        fprintf(fid, 'share_pf_user_change=%.4f (%d/%d)\n', share_pf_change, tot_pf_user_change, tot_pf_comp_ttis);
        fclose(fid);
    end
end
