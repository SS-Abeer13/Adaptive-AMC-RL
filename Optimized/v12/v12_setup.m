% v12_setup  Paths, base options and the two pre-registered v12 replication cases.
% v12 = v11 core (renamed) + crn_seed_base option + EDF scheduler. See PLAN_v12_replication.md.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v12 = fullfile(root, 'Optimized', 'v12');
addpath(v12); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
ds = fullfile(v12, 'Dataset');
if ~exist(ds, 'dir'), mkdir(ds); end
if ~exist(fullfile(v12, 'logs'), 'dir'), mkdir(fullfile(v12, 'logs')); end
% Base = identical to v10/v11 base (the recipe that produced E4c).
base = struct('N', 10, 'simTime', 200, 'ep_deep', 800, 'n_seeds', 5, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0, ...
              'mob_kappa', 1, 'crn', true, 'train_warm_ttis', 0, 'calib_warm', false, ...
              'actions', -4:2, ...
              'a2c', struct('lr_actor', 3e-4, 'lr_critic', 1e-3, 'ent_start', 0.03, 'ent_end', 0.001, 'n_step', 10));
% E4 deadline environment, copied verbatim from v10_setup / v11_setup (do not edit).
E4 = struct('traffic', 'deadline', 'O2I_dB', 0, 'pkt_bits', 12000, 'pkt_period', 20, 'pkt_deadline', 10, ...
            'reward_kind', 'ontime', 'primary', 'ontime', ...
            'feat_extra', {{'slack'}}, 'ctx_cue', 'slack', 'ctx_edges', [2 5]);
C = struct();
% ---- R1_pf: PRIMARY replication of v10 E4c (pre-registered, PLAN_v12_replication.md section 3) ----
% Same environment, comparators, action space (offset), reward (on-time), training recipe and
% scheduler (PF) as E4c. New: 10 training seeds (base_seed 1042 -> seeds 1243-1252; v10 used 243-247),
% 500 evaluation traces (seeds 20001-20500; v10 used 9001-9300), CRN draws 30001-30500 (v10: 50001+).
% Validation-based selection OFF (a2c.val_every = 0), exactly as in E4c.
C.R1_pf = E4;
C.R1_pf.n_seeds = 10; C.R1_pf.n_eval = 500;
C.R1_pf.base_seed = 1042; C.R1_pf.trace_seed_base = 20000; C.R1_pf.crn_seed_base = 30000;
% ---- R2_edf: SECONDARY check - everything (calibration, training, evaluation) under EDF ----
C.R2_edf = E4;
C.R2_edf.n_seeds = 5; C.R2_edf.n_eval = 300;
C.R2_edf.base_seed = 2042; C.R2_edf.trace_seed_base = 21000; C.R2_edf.crn_seed_base = 31000;
C.R2_edf.sched_list = {'pf', 'rr', 'eq', 'edf'};
C.R2_edf.train_schedulers = {'pf', 'rr', 'eq', 'edf'};
C.R2_edf.train_sched_weights = [0 0 0 1];
C.R2_edf.eval_schedulers = {'edf'};
