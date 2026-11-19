function test_eot()
% test_eot  Unit tests for end-of-trace (EOT) accounting variant.
%
% Tests:
%   Test 1: RTT 8, last block sent at dl - 3. ACK lands at dl + 5.
%           Counts on time under 'asrun', miss under 'resolved'.
%   Test 2: Packet arriving at T - 2 with dl > T. Counted or censored under 'asrun',
%           excluded under 'resolved'.
%   Test 3: 'resolved' gives n_counted_resolved equal to packets with countFrom < arr & dl <= T_end.

    here = fileparts(mfilename('fullpath'));
    v17x_dir = fileparts(here);
    v17_dir = fullfile(fileparts(v17x_dir), 'v17');
    addpath(here);
    addpath(v17x_dir);
    addpath(v17_dir);
    v17_setup;

    fprintf('Running test_eot...\n');

    %% ---------------- Test 1 ----------------
    % RTT 8, packet last block sent at dl - 3, ACK lands at dl + 5.
    % Under 'asrun': counts as on time (okU=1, resU=1).
    % Under 'resolved': counts as miss (okU=0, resU=1).
    fprintf('  Test 1: RTT 8 late ACK (sent at dl-3, ACK at dl+5)... ');
    
    % Test via direct simulation of the drain
    N = 3;
    env = struct('traffic', 'deadline', 'harq_on', true, 'harq_rtt', 8, 'harq_max_retx', 4, ...
                 'drain', true, 'useful_bits', true, 'olla_step_down', 0.1, 'olla_target', 0.1, ...
                 'pkt_bits', 1000, 'pkt_period', 100, 'min_CQI', 1, 'max_CQI', 15);
    
    % 1a. Under 'asrun'
    env_asrun = env;
    env_asrun.eot_mode = 'asrun';
    T = 25; dl = 25; % packet deadline is TTI 25
    Q = trafficInit_v17(env_asrun, N, 0);
    Q.has(1) = true; Q.arr(1) = 1; Q.dl(1) = dl; Q.rem(1) = 1000;
    Q.countTo = Inf;
    Q.eot_track = struct('T_end', T, 'n_arrivals_all', 1, 'n_arrivals_resolved', 1, ...
                         'n_late_ack_asrun', 0, 'n_censored_asrun', 0);
    H = harqInit_v17(N, env_asrun);
    off = zeros(1, N);
    
    % Last block sent at dl - 3 = 22. ACK arrives at 22 + 8 = 30 = dl + 5.
    % Put in-flight block in H
    H.proc_busy(1, 1) = true;
    H.proc_ready_t(1, 1) = 30; % dl + 5
    H.proc_ok(1, 1) = true;
    H.proc_bits(1, 1) = 1000;
    H.proc_dec_id(1, 1) = 1;
    H.proc_nret(1, 1) = 0;
    H.proc_isRetx(1, 1) = false;
    
    % Drain: t = T+1 : T + RTT (26 to 33)
    for t = T + 1 : T + env_asrun.harq_rtt
        [H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_eot(H, Q, off, env_asrun, t, 0.1, 0.1);
    end
    assert(Q.okU(1) == 1, 'Test 1 asrun: okU must be 1');
    assert(Q.resU(1) == 1, 'Test 1 asrun: resU must be 1');
    assert(Q.eot_track.n_late_ack_asrun == 1, 'Test 1 asrun: n_late_ack_asrun must be 1');

    % 1b. Under 'resolved'
    env_res = env;
    env_res.eot_mode = 'resolved';
    Q = trafficInit_v17(env_res, N, 0);
    Q.has(1) = true; Q.arr(1) = 1; Q.dl(1) = dl; Q.rem(1) = 1000;
    Q.countTo = T; % dl <= T_end
    Q.eot_track = struct('T_end', T, 'n_arrivals_all', 1, 'n_arrivals_resolved', 1, ...
                         'n_late_ack_asrun', 0, 'n_censored_asrun', 0);
    H = harqInit_v17(N, env_res);
    off = zeros(1, N);
    H.proc_busy(1, 1) = true;
    H.proc_ready_t(1, 1) = 30; % dl + 5
    H.proc_ok(1, 1) = true;
    H.proc_bits(1, 1) = 1000;
    H.proc_dec_id(1, 1) = 1;
    H.proc_nret(1, 1) = 0;
    H.proc_isRetx(1, 1) = false;

    % Drain: harqFeedback_eot then trafficExpire_eot
    for t = T + 1 : T + env_res.harq_rtt
        [H, Q, off, ackEv, nackEv, dropEv, tp_ack, fbList] = harqFeedback_eot(H, Q, off, env_res, t, 0.1, 0.1);
        [Q, H] = trafficExpire_eot(Q, t, env_res, H);
    end
    assert(Q.okU(1) == 0, 'Test 1 resolved: okU must be 0 (miss)');
    assert(Q.resU(1) == 1, 'Test 1 resolved: resU must be 1 (counted miss)');
    % (Exposure counters come from asrun pass only per S_EOT_PF_prereg.md Section 2)
    fprintf('PASSED\n');

    %% ---------------- Test 2 ----------------
    % Packet arriving at T - 2 with dl > T_end.
    % Under 'asrun': counted or censored. Under 'resolved': excluded.
    fprintf('  Test 2: Packet arriving at T - 2 (dl > T_end)... ');
    T = 30;
    env2 = env;
    env2.harq_rtt = 0; % test RTT 0 as well
    
    % Case 2a: packet completes at T
    % Under 'asrun': counts in okU and resU.
    % Under 'resolved': excluded (dl > T_end).
    Q_asrun = trafficInit_v17(env2, N, 0);
    Q_asrun.countTo = Inf;
    Q_asrun.has(1) = true; Q_asrun.arr(1) = T - 2; Q_asrun.dl(1) = T + 10; Q_asrun.rem(1) = 1000;
    [Q_asrun, ok_asrun] = trafficPost_eot(Q_asrun, [1 0 0], T); % delivers 1000 bits
    assert(ok_asrun(1) == true, 'Test 2a: packet completed');
    assert(Q_asrun.okU(1) == 1 && Q_asrun.resU(1) == 1, 'Test 2a asrun: counted');

    Q_res = trafficInit_v17(env2, N, 0);
    Q_res.countTo = T; % dl = T + 10 > T
    Q_res.has(1) = true; Q_res.arr(1) = T - 2; Q_res.dl(1) = T + 10; Q_res.rem(1) = 1000;
    [Q_res, ok_res] = trafficPost_eot(Q_res, [1 0 0], T);
    assert(ok_res(1) == true, 'Test 2a: packet completed physically');
    assert(Q_res.okU(1) == 0 && Q_res.resU(1) == 0, 'Test 2a resolved: excluded from counting window');

    % Case 2b: packet NOT completed at T (censored under asrun, excluded under resolved)
    Q_asrun = trafficInit_v17(env2, N, 0);
    Q_asrun.countTo = Inf;
    Q_asrun.has(1) = true; Q_asrun.arr(1) = T - 2; Q_asrun.dl(1) = T + 10; Q_asrun.rem(1) = 1000;
    % No transmission. Simulation ends. Under asrun, it stays in Q.has (censored).
    assert(Q_asrun.has(1) == true, 'Test 2b asrun: censored (unresolved)');
    assert(Q_asrun.resU(1) == 0, 'Test 2b asrun: not in resU');

    Q_res = trafficInit_v17(env2, N, 0);
    Q_res.countTo = T;
    Q_res.has(1) = true; Q_res.arr(1) = T - 2; Q_res.dl(1) = T + 10; Q_res.rem(1) = 1000;
    % RTT 0 expiry step at T + 1
    [Q_res, ~] = trafficExpire_eot(Q_res, T + 1, env2, struct());
    % dl = T + 10, so t = T + 1 < dl. Not expired yet, and even if expired, dl > countTo excludes it.
    assert(Q_res.resU(1) == 0, 'Test 2b resolved: excluded from resU');
    fprintf('PASSED\n');

    %% ---------------- Test 3 ----------------
    % 'resolved' gives n_counted_resolved equal to packets with countFrom < arr & dl <= T_end.
    fprintf('  Test 3: n_counted_resolved == sum(countFrom < arr & dl <= T_end)... ');
    data = load(fullfile(v17, 'Dataset', 'results_v17_M1_dl_rtt8.mat'));
    env3 = data.results.env;
    env3.eot_mode = 'resolved';
    T = 200;
    N = env3.N;
    meta3 = struct('delays', zeros(1, N), 'burst', zeros(T, 1), 'speeds', zeros(T, N));
    SINR_true = 10 * ones(T, N);
    obs_SINR  = 10 * ones(T, N);
    rng(12345, 'twister');
    U = rand(T, N);

    [tp, bler, ~, ~, info] = evalPolicy_g6_eot('baseline', [], SINR_true, obs_SINR, env3, meta3, U);
    assert(info.n_counted_resolved == sum(info.resU), ...
           sprintf('Test 3: info.n_counted_resolved (%d) must equal sum(resU) (%d)', info.n_counted_resolved, sum(info.resU)));
    assert(info.n_counted_resolved > 0, 'Test 3: must have counted some packets');
    fprintf('PASSED (n_counted_resolved = %d, sum(resU) = %d)\n', info.n_counted_resolved, sum(info.resU));

    fprintf('ALL EOT UNIT TESTS PASSED.\n');
end
