% v10_setup  Paths, base options and the four structural-advantage cases.
root = 'D:\Adaptive AMC A2C+QL';
cd(root);
v10 = fullfile(root, 'Optimized', 'v10');
addpath(v10); addpath(fullfile(root, 'Optimized', 'v5')); addpath(fullfile(root, 'Optimized', 'case2_3'));
ds = fullfile(v10, 'Dataset');
% Base = v9 headline point (PF, Tier O, physical mobility, CRN), 5 seeds.
base = struct('N', 10, 'simTime', 200, 'ep_deep', 800, 'n_seeds', 5, 'n_eval', 100, 'n_calib', 20, ...
              'eval_schedulers', {{'pf'}}, 'train_sched_weights', [1 0 0], 'olla_off_lim', 10, ...
              'sched_on_ref', true, 'state_tier', 'O', 'lambda_retx', 0, 'lambda_drop', 0, ...
              'mob_kappa', 1, 'crn', true, 'train_warm_ttis', 0, 'calib_warm', false, ...
              'actions', -4:2, ...
              'a2c', struct('lr_actor', 3e-4, 'lr_critic', 1e-3, 'ent_start', 0.03, 'ent_end', 0.001, 'n_step', 10));
% ---- case definitions (fixed before any v10 result was seen) ----
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
% ---- added 20 Oct 23:40, after v10/v10b (confirmatory follow-up, fixed before running) ----
% E4c: E4 unchanged, 300 evaluation traces (first 100 = the v10 traces)
C.E4c_deadline = C.E4_deadline; C.E4c_deadline.n_eval = 300;
% E5: mixed latency budgets, users alternate 4 / 10 TTI (URLLC-like + delay-tolerant);
%     A2C also sees its own budget; the context table gets budget class x slack (6 bins)
C.E5_mixed = C.E4_deadline; C.E5_mixed.pkt_deadline = repmat([4 10], 1, 5);
C.E5_mixed.feat_extra = {'slack', 'dline'}; C.E5_mixed.ctx_cue = 'dslack'; C.E5_mixed.n_eval = 300;
