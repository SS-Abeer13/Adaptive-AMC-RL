% v17_setup  Paths, base options and the C2 cases of PLAN_v17.md (Stage C).
% v17 fixes the PF averaging artefact (pf_avg = 'scheduled'), adds end-of-trace
% feedback drain (drain = true), and re-runs the realistic-HARQ benchmark.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v17 = fullfile(root, 'Optimized', 'v17');
addpath(v17); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
ds = fullfile(v17, 'Dataset');
if ~exist(ds, 'dir'), mkdir(ds); end
if ~exist(fullfile(v17, 'logs'), 'dir'), mkdir(fullfile(v17, 'logs')); end

% Base configuration (Stage C1)
base = struct('N', 10, 'simTime', 200, 'ep_deep', 800, 'n_seeds', 10, 'n_eval', 500, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0, ...
              'mob_kappa', 1, 'crn', true, 'train_warm_ttis', 0, 'calib_warm', false, ...
              'actions', -4:2, ...
              'action_mode', 'resid', 'resid_actions', [-1 0 1], 'resid_pen', 0.02, 'resid_init_bias', 3.0, ...
              'pf_avg', 'scheduled', 'drain', true, 'useful_bits', true, 'use_parfor', true, 'n_workers', 2, ...
              'train_ppo', false, ...
              'train_a2c_offset', false, 'ep_deep_a2c_offset', 800, 'n_seeds_a2c_offset', 5, ...
              'train_a2c_resid_800', false, 'ep_deep_a2c_resid_800', 800, 'n_seeds_a2c_resid_800', 10, ...
              'a2c', struct('lr_actor', 3e-4, 'lr_critic', 1e-3, 'ent_start', 0.03, 'ent_end', 0.001, 'n_step', 10, 'val_every', 50, 'n_val', 10));

% Deadline traffic (v14 Y0 / v15 Z1 / v16 K1): 12 kbit packets every 20 TTI, 10-TTI budget
DL = struct('traffic', 'deadline', 'O2I_dB', 0, 'pkt_bits', 12000, 'pkt_period', 20, 'pkt_deadline', 10, ...
            'reward_kind', 'ontime_shaped', 'shape_c', 0.5, 'primary', 'ontime', ...
            'feat_extra', {{'slack', 'harqx'}}, 'ctx_cue', 'slack', 'ctx_edges', [2 5]);

% Goodput traffic (full buffer, v10 E1 environment)
GP = struct('traffic', 'full', 'reward_kind', 'oppcost', 'primary', 'goodput', ...
            'feat_extra', {{'harqx'}}, 'ctx_cue', 'none', 'ctx_edges', []);

C = struct();

% ---- M1-M4: v17 core cases (PLAN_v17 C2) ----
% M1: Deadline, RTT 8, 8 procs, primary = A2C-resid (3000 ep, 10 seeds)
C.M1_dl_rtt8 = DL;
C.M1_dl_rtt8.harq_rtt = 8; C.M1_dl_rtt8.harq_nproc = 8;
C.M1_dl_rtt8.ep_deep = 3000; C.M1_dl_rtt8.n_seeds = 10; C.M1_dl_rtt8.n_eval = 500;
C.M1_dl_rtt8.train_a2c_offset = true; C.M1_dl_rtt8.ep_deep_a2c_offset = 800; C.M1_dl_rtt8.n_seeds_a2c_offset = 10;
C.M1_dl_rtt8.train_a2c_resid_800 = true; C.M1_dl_rtt8.ep_deep_a2c_resid_800 = 800; C.M1_dl_rtt8.n_seeds_a2c_resid_800 = 10;
C.M1_dl_rtt8.base_seed = 20042; C.M1_dl_rtt8.trace_seed_base = 500000; C.M1_dl_rtt8.crn_seed_base = 510000;

% M2: Deadline, RTT 0, 1 proc, primary = A2C-resid (3000 ep, 10 seeds)
C.M2_dl_rtt0 = DL;
C.M2_dl_rtt0.harq_rtt = 0; C.M2_dl_rtt0.harq_nproc = 1;
C.M2_dl_rtt0.ep_deep = 3000; C.M2_dl_rtt0.n_seeds = 10; C.M2_dl_rtt0.n_eval = 500;
C.M2_dl_rtt0.train_a2c_resid_800 = true; C.M2_dl_rtt0.ep_deep_a2c_resid_800 = 800; C.M2_dl_rtt0.n_seeds_a2c_resid_800 = 10;
C.M2_dl_rtt0.base_seed = 21042; C.M2_dl_rtt0.trace_seed_base = 520000; C.M2_dl_rtt0.crn_seed_base = 530000;

% M3: Goodput, RTT 8, 8 procs, primary = A2C-resid (800 ep, 10 seeds)
C.M3_gp_rtt8 = GP;
C.M3_gp_rtt8.harq_rtt = 8; C.M3_gp_rtt8.harq_nproc = 8;
C.M3_gp_rtt8.ep_deep = 800; C.M3_gp_rtt8.n_seeds = 10; C.M3_gp_rtt8.n_eval = 500;
C.M3_gp_rtt8.train_a2c_offset = true; C.M3_gp_rtt8.ep_deep_a2c_offset = 800; C.M3_gp_rtt8.n_seeds_a2c_offset = 5;
C.M3_gp_rtt8.base_seed = 22042; C.M3_gp_rtt8.trace_seed_base = 540000; C.M3_gp_rtt8.crn_seed_base = 550000;

% M4: Goodput, RTT 0, 1 proc, primary = A2C-resid (800 ep, 10 seeds)
C.M4_gp_rtt0 = GP;
C.M4_gp_rtt0.harq_rtt = 0; C.M4_gp_rtt0.harq_nproc = 1;
C.M4_gp_rtt0.ep_deep = 800; C.M4_gp_rtt0.n_seeds = 10; C.M4_gp_rtt0.n_eval = 500;
C.M4_gp_rtt0.base_seed = 23042; C.M4_gp_rtt0.trace_seed_base = 560000; C.M4_gp_rtt0.crn_seed_base = 570000;
