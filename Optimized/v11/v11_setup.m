% v11_setup  Paths, base options and the four structural-advantage cases.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v11 = fullfile(root, 'Optimized', 'v11');
addpath(v11); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
ds = fullfile(v11, 'Dataset');
% Base = v9 headline point (PF, Tier O, physical mobility, CRN), 5 seeds.
base = struct('N', 10, 'simTime', 200, 'ep_deep', 800, 'n_seeds', 5, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0, ...
              'mob_kappa', 1, 'crn', true, 'train_warm_ttis', 0, 'calib_warm', false, ...
              'actions', -4:2, ...
              'a2c', struct('lr_actor', 3e-4, 'lr_critic', 1e-3, 'ent_start', 0.03, 'ent_end', 0.001, 'n_step', 10));
% ---- case definitions (fixed before any v11 result was seen) ----
C = struct();
% E1 training fix: v9 headline environment, narrowed actions, longer training, slower entropy schedule
C.E1_train   = struct('ep_deep', 1500);
% E2 high speed + stale periodic CQI: 60-120 km/h, CQI delay 4-10 TTI, report every 5 TTI;
%    cues: report age and report deviation from the user's long-run mean
C.E2_stale   = struct('speed_min', 16.7, 'speed_max', 33.3, 'delay_set', 4:10, 'delay_hom', 7, ...
                      'cqi_period', 5, 'feat_extra', {{'age', 'dev'}}, 'ctx_cue', 'dev', 'ctx_edges', [-3 3]);
% E3 cell-wide interference cue: shorter, stronger bursts, longer CQI delay;
%    cue: gNB-side cell-wide NACK rate (pooled over all users)
C.E3_cellcue = struct('burst_IM_dB', 12, 'burst_dwell_calm', 150, 'burst_dwell_burst', 40, ...
                      'delay_set', 4:10, 'delay_hom', 7, ...
                      'feat_extra', {{'cellnack'}}, 'ctx_cue', 'cellnack', 'ctx_edges', [0.3 0.6]);
% E4 deadline traffic: one packet per user every 20 TTI, 10-TTI budget,
%    outdoor users (O2I 0 dB), 12 kbit packets; load fixed from an OLLA-only pilot (OLLA 0.80-0.87 on time)
%    primary metric = on-time delivery ratio; cue: deadline slack
C.E4_deadline = struct('traffic', 'deadline', 'O2I_dB', 0, 'pkt_bits', 12000, 'pkt_period', 20, 'pkt_deadline', 10, ...
                      'reward_kind', 'ontime', 'primary', 'ontime', ...
                      'feat_extra', {{'slack'}}, 'ctx_cue', 'slack', 'ctx_edges', [2 5]);
% ---- added 20 Oct 23:40, after v11/v11b (confirmatory follow-up, fixed before running) ----
% E4c: E4 unchanged, 300 evaluation traces (first 100 = the v11 traces)
C.E4c_deadline = C.E4_deadline; C.E4c_deadline.n_eval = 300;
% E5: mixed latency budgets, users alternate 4 / 10 TTI (URLLC-like + delay-tolerant);
%     A2C also sees its own budget; the context table gets budget class x slack (6 bins)
C.E5_mixed = C.E4_deadline; C.E5_mixed.pkt_deadline = repmat([4 10], 1, 5);
C.E5_mixed.feat_extra = {'slack', 'dline'}; C.E5_mixed.ctx_cue = 'dslack'; C.E5_mixed.n_eval = 300;

% ---- P1: target-BLER action space (README_v11.md, pre-registered 21 Oct 2026) ----
% T1_gp: E1 environment (goodput control) + action_mode = 'target'.
C.T1_gp = struct('action_mode', 'target', 'n_seeds', 5, 'n_eval', 300);
% T2_stale: E2 environment (stale/periodic CQI cue, unchanged from v10) + target action.
C.T2_stale = C.E2_stale; C.T2_stale.action_mode = 'target'; C.T2_stale.n_eval = 300;
% T4_deadline: E4 environment (on-time delivery, unchanged from v10) + target action.
C.T4_deadline = C.E4_deadline; C.T4_deadline.action_mode = 'target'; C.T4_deadline.n_eval = 300;

% ---- P2: PPO + GAE, trained alongside A2C under new tags (README_v11.md) ----
C.T1_gp_ppo      = C.T1_gp;      C.T1_gp_ppo.train_ppo      = true;
C.T2_stale_ppo   = C.T2_stale;   C.T2_stale_ppo.train_ppo   = true;
C.T4_deadline_ppo = C.T4_deadline; C.T4_deadline_ppo.train_ppo = true;

% ---- P4: GRU recurrent memory, trained alongside A2C (README_v11.md).
% Scope cut agreed before implementation: offset action space (not P1's
% target), A2C-style update (not P2's PPO) -- see README_v11.md P4. Re-test
% E2/E3 (v10's stale-CQI / cell-cue cases) with the new recurrent-memory
% cues added alongside each case's existing cue.
C.R2_stale  = C.E2_stale;  C.R2_stale.train_gru  = true;
C.R2_stale.feat_extra = [C.E2_stale.feat_extra, {'ack8', 'tsince', 'offtrend'}];
C.R2_stale.n_eval = 300;
C.R3_cellcue = C.E3_cellcue; C.R3_cellcue.train_gru = true;
C.R3_cellcue.feat_extra = [C.E3_cellcue.feat_extra, {'ack8', 'tsince', 'offtrend'}];
C.R3_cellcue.n_eval = 300;

% ---- P4b: R2/R3 re-run with reward_kind = 'oppcost' (v10b's fix for the
% offset-mode goodput-reward defect that collapsed A2C in R2_stale/
% R3_cellcue) -- requested 22 Oct 2026, to isolate whether proper credit
% assignment + recurrence closes GRU's remaining ~4-6% gap to Baseline.
C.R2_stale_opp  = C.R2_stale;  C.R2_stale_opp.reward_kind  = 'oppcost';
C.R3_cellcue_opp = C.R3_cellcue; C.R3_cellcue_opp.reward_kind = 'oppcost';
