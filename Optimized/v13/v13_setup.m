% v13_setup  Paths, base options and environments for v13.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v13 = fullfile(root, 'Optimized', 'v13');
addpath(v13); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
ds = fullfile(v13, 'Dataset');
if ~exist(ds, 'dir'), mkdir(ds); end
if ~exist(fullfile(v13, 'logs'), 'dir'), mkdir(fullfile(v13, 'logs')); end

base = struct('N', 10, 'simTime', 200, 'ep_deep', 800, 'n_seeds', 5, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0, ...
              'mob_kappa', 1, 'crn', true, 'train_warm_ttis', 0, 'calib_warm', false, ...
              'actions', -4:2, ...
              'a2c', struct('lr_actor', 3e-4, 'lr_critic', 1e-3, 'ent_start', 0.03, 'ent_end', 0.001, 'n_step', 10));

E4 = struct('traffic', 'deadline', 'O2I_dB', 0, 'pkt_bits', 12000, 'pkt_period', 20, 'pkt_deadline', 10, ...
            'reward_kind', 'ontime', 'primary', 'ontime', ...
            'feat_extra', {{'slack'}}, 'ctx_cue', 'slack', 'ctx_edges', [2 5]);

C = struct();
% ---- Reference v12 environments for Stage 0 Headroom check ----
C.R1_pf = E4;
C.R1_pf.n_seeds = 10; C.R1_pf.n_eval = 500;
C.R1_pf.base_seed = 1042; C.R1_pf.trace_seed_base = 20000; C.R1_pf.crn_seed_base = 30000;

C.R2_edf = E4;
C.R2_edf.n_seeds = 5; C.R2_edf.n_eval = 300;
C.R2_edf.base_seed = 2042; C.R2_edf.trace_seed_base = 21000; C.R2_edf.crn_seed_base = 31000;
C.R2_edf.sched_list = {'pf', 'rr', 'eq', 'edf'};
C.R2_edf.train_schedulers = {'pf', 'rr', 'eq', 'edf'};
C.R2_edf.train_sched_weights = [0 0 0 1];
C.R2_edf.eval_schedulers = {'edf'};

% ---- Stage 1 pre-registered cases (Table S1.5 in PLAN_v13.md) ----
C.X1_pf = E4;
C.X1_pf.action_mode = 'resid';
C.X1_pf.a2c = base.a2c;
C.X1_pf.a2c.val_every = 50; C.X1_pf.a2c.n_val = 10;
C.X1_pf.n_seeds = 10; C.X1_pf.n_eval = 500;
C.X1_pf.base_seed = 3042; C.X1_pf.trace_seed_base = 40000; C.X1_pf.crn_seed_base = 41000;

C.X1_edf = E4;
C.X1_edf.action_mode = 'resid';
C.X1_edf.a2c = base.a2c;
C.X1_edf.a2c.val_every = 50; C.X1_edf.a2c.n_val = 10;
C.X1_edf.n_seeds = 10; C.X1_edf.n_eval = 500;
C.X1_edf.base_seed = 4042; C.X1_edf.trace_seed_base = 42000; C.X1_edf.crn_seed_base = 43000;
C.X1_edf.sched_list = {'pf', 'rr', 'eq', 'edf'};
C.X1_edf.train_schedulers = {'pf', 'rr', 'eq', 'edf'};
C.X1_edf.train_sched_weights = [0 0 0 1];
C.X1_edf.eval_schedulers = {'edf'};

C.X2_pf_shaped = E4;
C.X2_pf_shaped.action_mode = 'resid';
C.X2_pf_shaped.reward_kind = 'ontime_shaped';
C.X2_pf_shaped.a2c = base.a2c;
C.X2_pf_shaped.a2c.val_every = 50; C.X2_pf_shaped.a2c.n_val = 10;
C.X2_pf_shaped.n_seeds = 10; C.X2_pf_shaped.n_eval = 500;
C.X2_pf_shaped.base_seed = 5042; C.X2_pf_shaped.trace_seed_base = 44000; C.X2_pf_shaped.crn_seed_base = 45000;
