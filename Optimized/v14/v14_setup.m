% v14_setup  Paths, base options and environments for v14.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v14 = fullfile(root, 'Optimized', 'v14');
addpath(v14); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
ds = fullfile(v14, 'Dataset');
if ~exist(ds, 'dir'), mkdir(ds); end
if ~exist(fullfile(v14, 'logs'), 'dir'), mkdir(fullfile(v14, 'logs')); end

base = struct('N', 10, 'simTime', 200, 'ep_deep', 800, 'n_seeds', 5, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0, ...
              'mob_kappa', 1, 'crn', true, 'train_warm_ttis', 0, 'calib_warm', false, ...
              'actions', -4:2, ...
              'a2c', struct('lr_actor', 3e-4, 'lr_critic', 1e-3, 'ent_start', 0.03, 'ent_end', 0.001, 'n_step', 10, 'val_every', 50, 'n_val', 10));

E4 = struct('traffic', 'deadline', 'O2I_dB', 0, 'pkt_bits', 12000, 'pkt_period', 20, 'pkt_deadline', 10, ...
            'reward_kind', 'ontime_shaped', 'shape_c', 0.5, 'primary', 'ontime', ...
            'action_mode', 'resid', 'resid_actions', [-1 0 1], 'resid_pen', 0.02, 'resid_init_bias', 3.0, ...
            'feat_extra', {{'slack'}}, 'ctx_cue', 'slack', 'ctx_edges', [2 5]);

C = struct();

% Primary confirmation case (PLAN_v14.md Table C2)
C.Y0_base = E4;
C.Y0_base.pkt_bits = 12000; C.Y0_base.pkt_deadline = 10;
C.Y0_base.reward_kind = 'ontime_shaped';
C.Y0_base.a2c = base.a2c;
C.Y0_base.n_seeds = 10; C.Y0_base.n_eval = 500;
C.Y0_base.base_seed = 6042; C.Y0_base.trace_seed_base = 200000; C.Y0_base.crn_seed_base = 210000;

% Paired shaping test case (identical seeds and traces, unshaped ontime)
C.Y0_noshape = E4;
C.Y0_noshape.pkt_bits = 12000; C.Y0_noshape.pkt_deadline = 10;
C.Y0_noshape.reward_kind = 'ontime';
C.Y0_noshape.a2c = base.a2c;
C.Y0_noshape.n_seeds = 10; C.Y0_noshape.n_eval = 500;
C.Y0_noshape.base_seed = 6042; C.Y0_noshape.trace_seed_base = 200000; C.Y0_noshape.crn_seed_base = 210000;

% Robustness Grid Cells
C.Y1_lo_tight = E4;
C.Y1_lo_tight.pkt_bits = 8000; C.Y1_lo_tight.pkt_deadline = 6;
C.Y1_lo_tight.a2c = base.a2c;
C.Y1_lo_tight.n_seeds = 5; C.Y1_lo_tight.n_eval = 300;
C.Y1_lo_tight.base_seed = 7042; C.Y1_lo_tight.trace_seed_base = 220000; C.Y1_lo_tight.crn_seed_base = 230000;

C.Y2_lo_loose = E4;
C.Y2_lo_loose.pkt_bits = 8000; C.Y2_lo_loose.pkt_deadline = 14;
C.Y2_lo_loose.a2c = base.a2c;
C.Y2_lo_loose.n_seeds = 5; C.Y2_lo_loose.n_eval = 300;
C.Y2_lo_loose.base_seed = 8042; C.Y2_lo_loose.trace_seed_base = 240000; C.Y2_lo_loose.crn_seed_base = 250000;

C.Y3_hi_tight = E4;
C.Y3_hi_tight.pkt_bits = 16000; C.Y3_hi_tight.pkt_deadline = 6;
C.Y3_hi_tight.a2c = base.a2c;
C.Y3_hi_tight.n_seeds = 5; C.Y3_hi_tight.n_eval = 300;
C.Y3_hi_tight.base_seed = 9042; C.Y3_hi_tight.trace_seed_base = 260000; C.Y3_hi_tight.crn_seed_base = 270000;

C.Y4_hi_loose = E4;
C.Y4_hi_loose.pkt_bits = 16000; C.Y4_hi_loose.pkt_deadline = 14;
C.Y4_hi_loose.a2c = base.a2c;
C.Y4_hi_loose.n_seeds = 5; C.Y4_hi_loose.n_eval = 300;
C.Y4_hi_loose.base_seed = 10042; C.Y4_hi_loose.trace_seed_base = 280000; C.Y4_hi_loose.crn_seed_base = 290000;
