% v16_setup  Paths, base options and the C2 cases of PLAN_v16.md (Stage C).
% v16 = the v15 core (copied, renamed). With harq_rtt = 0 / harq_nproc = 1
% it is bit-exact with v15 (test_equivalence_v16.m).
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v16 = fullfile(root, 'Optimized', 'v16');
addpath(v16); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
ds = fullfile(v16, 'Dataset');
if ~exist(ds, 'dir'), mkdir(ds); end
if ~exist(fullfile(v16, 'logs'), 'dir'), mkdir(fullfile(v16, 'logs')); end

% C1: A2C-resid is the primary RL scheme (delta in {-1,0,1}, resid_pen
% 0.02, bias +3); reward is oppcost for goodput, ontime_shaped for
% deadline (set per-traffic below). train_ppo = true trains "Deep PPO v16"
% alongside -- offset mode only (B2 fallback: DeepPPO_Shared_v15 had no
% resid AND no RTT support; RTT support was ported for v16, resid was not
% -- see README_v16 B2). train_a2c_offset = true additionally trains
% "Deep A2C v16 (offset)" -- the legacy action design, kept for continuity
% per C1/C2 -- as a third simultaneous scheme in the same
% runComparison_v16 call (resolves the README_v16 §3.3 gap: A2C-offset is
% now wired, not just flagged).
base = struct('N', 10, 'simTime', 200, 'ep_deep', 800, 'n_seeds', 10, 'n_eval', 500, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0, ...
              'mob_kappa', 1, 'crn', true, 'train_warm_ttis', 0, 'calib_warm', false, ...
              'actions', -4:2, ...
              'action_mode', 'resid', 'resid_actions', [-1 0 1], 'resid_pen', 0.02, 'resid_init_bias', 3.0, ...
              'train_ppo', true, 'ep_deep_ppo', 800, 'n_seeds_ppo', 5, ...
              'train_a2c_offset', true, 'ep_deep_a2c_offset', 800, 'n_seeds_a2c_offset', 5, ...
              'a2c', struct('lr_actor', 3e-4, 'lr_critic', 1e-3, 'ent_start', 0.03, 'ent_end', 0.001, 'n_step', 10, 'val_every', 50, 'n_val', 10));

% Deadline traffic (v14 Y0 / v15 Z1): 12 kbit packets every 20 TTI, 10-TTI
% budget, O2I 0 dB.
DL = struct('traffic', 'deadline', 'O2I_dB', 0, 'pkt_bits', 12000, 'pkt_period', 20, 'pkt_deadline', 10, ...
            'reward_kind', 'ontime_shaped', 'shape_c', 0.5, 'primary', 'ontime', ...
            'feat_extra', {{'slack', 'harqx'}}, 'ctx_cue', 'slack', 'ctx_edges', [2 5]);
% Goodput traffic (full buffer, v10 E1 environment): defaultEnv_v16's own
% defaults (env.traffic = 'full') already match E1; only reward/primary/
% feat_extra need setting here.
GP = struct('traffic', 'full', 'reward_kind', 'oppcost', 'primary', 'goodput', ...
            'feat_extra', {{'harqx'}}, 'ctx_cue', 'none', 'ctx_edges', []);

C = struct();

% ---- K1-K4: core cases (C2) ----
C.K1_dl_rtt8 = DL;
C.K1_dl_rtt8.harq_rtt = 8; C.K1_dl_rtt8.harq_nproc = 8;
C.K1_dl_rtt8.n_seeds = 10; C.K1_dl_rtt8.n_eval = 500;
C.K1_dl_rtt8.base_seed = 14042; C.K1_dl_rtt8.trace_seed_base = 400000; C.K1_dl_rtt8.crn_seed_base = 410000;

C.K2_dl_rtt0 = DL;
C.K2_dl_rtt0.harq_rtt = 0; C.K2_dl_rtt0.harq_nproc = 1;
C.K2_dl_rtt0.n_seeds = 10; C.K2_dl_rtt0.n_eval = 500;
C.K2_dl_rtt0.base_seed = 15042; C.K2_dl_rtt0.trace_seed_base = 420000; C.K2_dl_rtt0.crn_seed_base = 430000;

C.K3_gp_rtt8 = GP;
C.K3_gp_rtt8.harq_rtt = 8; C.K3_gp_rtt8.harq_nproc = 8;
C.K3_gp_rtt8.n_seeds = 10; C.K3_gp_rtt8.n_eval = 500;
C.K3_gp_rtt8.base_seed = 16042; C.K3_gp_rtt8.trace_seed_base = 440000; C.K3_gp_rtt8.crn_seed_base = 450000;

C.K4_gp_rtt0 = GP;
C.K4_gp_rtt0.harq_rtt = 0; C.K4_gp_rtt0.harq_nproc = 1;
C.K4_gp_rtt0.n_seeds = 10; C.K4_gp_rtt0.n_eval = 500;
C.K4_gp_rtt0.base_seed = 17042; C.K4_gp_rtt0.trace_seed_base = 460000; C.K4_gp_rtt0.crn_seed_base = 470000;

% ---- L1 / L3: training-length cases (A2C-resid only, 3000 episodes, no PPO) ----
C.L1_dl_rtt8_long = DL;
C.L1_dl_rtt8_long.harq_rtt = 8; C.L1_dl_rtt8_long.harq_nproc = 8;
C.L1_dl_rtt8_long.ep_deep = 3000; C.L1_dl_rtt8_long.train_ppo = false; C.L1_dl_rtt8_long.train_a2c_offset = false;
C.L1_dl_rtt8_long.n_seeds = 5; C.L1_dl_rtt8_long.n_eval = 300;
C.L1_dl_rtt8_long.base_seed = 18042; C.L1_dl_rtt8_long.trace_seed_base = 480000; C.L1_dl_rtt8_long.crn_seed_base = 485000;

C.L3_gp_rtt8_long = GP;
C.L3_gp_rtt8_long.harq_rtt = 8; C.L3_gp_rtt8_long.harq_nproc = 8;
C.L3_gp_rtt8_long.ep_deep = 3000; C.L3_gp_rtt8_long.train_ppo = false; C.L3_gp_rtt8_long.train_a2c_offset = false;
C.L3_gp_rtt8_long.n_seeds = 5; C.L3_gp_rtt8_long.n_eval = 300;
C.L3_gp_rtt8_long.base_seed = 19042; C.L3_gp_rtt8_long.trace_seed_base = 490000; C.L3_gp_rtt8_long.crn_seed_base = 495000;
