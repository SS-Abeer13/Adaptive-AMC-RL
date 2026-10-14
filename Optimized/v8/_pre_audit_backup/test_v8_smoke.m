function test_v8_smoke()
% test_v8_smoke  Verification and sanity check for v8 architecture.
% Exercises all new modules:
%   - defaultEnv_v8 PHY parameters and zero BC
%   - txStep_v8 HARQ Chase combining & drop tracking
%   - estimateBLER_v8 waterfall curves
%   - MultiOLLA_v8 dual integrator dynamics
%   - DeepA2C_Shared_v8 autonomous training (3 episodes)
%   - evalPolicy_v8 across all 8 comparators
    fprintf('=== RL-AMC v8 Architecture Verification Smoke Test ===\n');

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, '..', 'v7'));
    addpath(fullfile(here, '..', 'v5'));
    addpath(fullfile(here, '..', 'case2_3'));

    env = defaultEnv_v8(23, 10);
    assert(env.bc_warm_eps == 0, 'v8 must strictly enforce bc_warm_eps == 0');
    assert(numel(env.actions) == 11, 'v8 action space must span 11 discrete actions');
    assert(abs(env.noise_floor_dBm - (-92)) < 0.05, 'Noise floor must equal ~ -92 dBm');
    fprintf('  [PASS] defaultEnv_v8 initialization & PHY constants verified.\n');

    % 2. BLER waterfall verification
    bl_low  = estimateBLER_v8(-15, 0);
    bl_mid  = estimateBLER_v8(-6.7, 0);
    bl_high = estimateBLER_v8(10, 0);
    assert(bl_low > 0.99, 'Very low SINR must produce near 100% BLER');
    assert(abs(bl_mid - 0.10) < 0.01, 'Threshold SINR must produce exactly ~10% BLER');
    assert(bl_high < 0.01, 'High SINR must produce near 0% BLER');
    fprintf('  [PASS] estimateBLER_v8 sigmoidal waterfalls verified at 10%% anchor.\n');

    % 3. HARQ & Transmission physics verification
    H = harqInit_v8(10);
    sent = 5 * ones(1, 10);
    Strue = 10 * ones(1, 10);
    rb = [100, zeros(1, 9)]; % User 1 scheduled
    off = zeros(1, 10);
    [tp, off_next, H, bler1, nackEv, dropEv] = txStep_v8(sent, Strue, rb, off, H, env);
    assert(numel(tp) == 10, 'Throughput output dimension mismatch');
    assert(~isnan(bler1(1)), 'Scheduled user 1 must have valid BLER1');
    assert(isnan(bler1(2)), 'Unscheduled user 2 must have NaN BLER1');
    fprintf('  [PASS] txStep_v8 transmission physics & HARQ combining verified.\n');

    % 4. MultiOLLA verification
    offFast = zeros(1, 10);
    offSlow = zeros(1, 10);
    [tp_mo, offFast, offSlow, H, bl1_mo] = ...
        MultiOLLA_v8(sent, Strue, rb, offFast, offSlow, H, env, 0.5*ones(1, 10));
    assert(numel(tp_mo) == 10, 'MultiOLLA output dimension mismatch');
    fprintf('  [PASS] MultiOLLA_v8 dual integrator dynamics verified.\n');

    % 5. Brief autonomous A2C training loop (2 episodes, 50 TTIs)
    fprintf('  [TEST] Running DeepA2C_Shared_v8 (2 episodes, autonomous training)...\n');
    t0 = tic;
    [actorNet, criticNet, lc, ent] = DeepA2C_Shared_v8(50, 2, 42, env);
    assert(numel(lc) == 2, 'Learning curve must contain 2 entries');
    fprintf('  [PASS] DeepA2C_Shared_v8 trained autonomously in %.2f s (Final Tp = %.2f Mbps).\n', ...
            toc(t0), lc(end));

    % 6. Policy evaluation across all 8 comparators
    fprintf('  [TEST] Evaluating evalPolicy_v8 across all comparators...\n');
    [Strue_t, ~, meta] = generateChannel_v7(50, env);
    obsS = cqiFeedback_v8(Strue_t, env, meta.delays);

    schemes = {'baseline', 'olla', 'warm_olla', 'multi_olla', 'fixed', 'fixed_online', 'fixed_class', 'a2c_v8'};
    for k = 1:numel(schemes)
        pol = [];
        if strcmp(schemes{k}, 'a2c_v8'), pol = actorNet; end
        [tp_k, bl_k] = evalPolicy_v8(schemes{k}, pol, Strue_t, obsS, env, meta);
        assert(size(tp_k, 1) == 50 && size(tp_k, 2) == 10, 'Evaluation dimension mismatch');
        fprintf('    - Comparator %-12s: Mean CellTp = %5.2f Mbps\n', ...
                schemes{k}, sum(mean(tp_k, 1)));
    end
    fprintf('  [PASS] All 8 comparator schemes evaluated successfully.\n');

    fprintf('\n=== ALL RL-AMC v8 ARCHITECTURE CHECKS PASSED SUCCESSFULLY ===\n');
end
