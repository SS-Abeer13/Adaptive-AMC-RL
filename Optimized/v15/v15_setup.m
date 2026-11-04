% v15_setup  Paths, base options and environments for v15 (realistic HARQ RTT).
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v15 = fullfile(root, 'Optimized', 'v15');
addpath(v15); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
ds = fullfile(v15, 'Dataset');
if ~exist(ds, 'dir'), mkdir(ds); end
if ~exist(fullfile(v15, 'logs'), 'dir'), mkdir(fullfile(v15, 'logs')); end

base = struct('N', 10, 'simTime', 200, 'ep_deep', 800, 'n_seeds', 10, 'n_eval', 500, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0, ...
              'mob_kappa', 1, 'crn', true, 'train_warm_ttis', 0, 'calib_warm', false, ...
              'actions', -4:2, ...
              'a2c', struct('lr_actor', 3e-4, 'lr_critic', 1e-3, 'ent_start', 0.03, 'ent_end', 0.001, 'n_step', 10, 'val_every', 50, 'n_val', 10));

E4 = struct('traffic', 'deadline', 'O2I_dB', 0, 'pkt_bits', 12000, 'pkt_period', 20, 'pkt_deadline', 10, ...
            'reward_kind', 'ontime_shaped', 'shape_c', 0.5, 'primary', 'ontime', ...
            'action_mode', 'resid', 'resid_actions', [-1 0 1], 'resid_pen', 0.02, 'resid_init_bias', 3.0, ...
            'feat_extra', {{'slack', 'harqx'}}, 'ctx_cue', 'slack', 'ctx_edges', [2 5]);

C = struct();

% Primary confirmation case under realistic HARQ RTT (3GPP standard RTT = 8 TTIs)
C.Z1_rtt8 = E4;
C.Z1_rtt8.harq_rtt = 8; C.Z1_rtt8.harq_nproc = 8;
C.Z1_rtt8.pkt_bits = 12000; C.Z1_rtt8.pkt_deadline = 10; C.Z1_rtt8.pkt_period = 20;
C.Z1_rtt8.a2c = base.a2c;
C.Z1_rtt8.n_seeds = 10; C.Z1_rtt8.n_eval = 500;
C.Z1_rtt8.base_seed = 11042; C.Z1_rtt8.trace_seed_base = 300000; C.Z1_rtt8.crn_seed_base = 310000;

% Robustness Cell 1: Reduced RTT = 4 TTIs (e.g., TDD / short subframe)
C.Z2_rtt4 = E4;
C.Z2_rtt4.harq_rtt = 4; C.Z2_rtt4.harq_nproc = 8;
C.Z2_rtt4.pkt_bits = 12000; C.Z2_rtt4.pkt_deadline = 10; C.Z2_rtt4.pkt_period = 20;
C.Z2_rtt4.a2c = base.a2c;
C.Z2_rtt4.n_seeds = 10; C.Z2_rtt4.n_eval = 500;
C.Z2_rtt4.base_seed = 12042; C.Z2_rtt4.trace_seed_base = 320000; C.Z2_rtt4.crn_seed_base = 330000;

% Robustness Cell 2: RTT = 8 with loose deadline = 20 TTIs (multi-RTT recovery opportunity)
C.Z3_rtt8_loose = E4;
C.Z3_rtt8_loose.harq_rtt = 8; C.Z3_rtt8_loose.harq_nproc = 8;
C.Z3_rtt8_loose.pkt_bits = 12000; C.Z3_rtt8_loose.pkt_deadline = 20; C.Z3_rtt8_loose.pkt_period = 20;
C.Z3_rtt8_loose.a2c = base.a2c;
C.Z3_rtt8_loose.n_seeds = 10; C.Z3_rtt8_loose.n_eval = 500;
C.Z3_rtt8_loose.base_seed = 13042; C.Z3_rtt8_loose.trace_seed_base = 340000; C.Z3_rtt8_loose.crn_seed_base = 350000;
