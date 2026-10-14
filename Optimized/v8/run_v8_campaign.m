% run_v8_campaign.m
% Execute full multi-condition campaign for RL-AMC v8.
addpath('Optimized/v8');
addpath('Optimized/v7');
addpath('Optimized/v5');
addpath('Optimized/case2_3');

fprintf('========================================================================\n');
fprintf('  STARTING RL-AMC v8 FULL EVALUATION CAMPAIGN\n');
fprintf('  Started: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('========================================================================\n\n');

base_opts = struct();
base_opts.N               = 10;
base_opts.simTime         = 200;
base_opts.ep_deep         = 50;
base_opts.n_seeds         = 2;
base_opts.n_eval          = 30;
base_opts.n_calib         = 4;
base_opts.eval_schedulers = {'pf', 'rr'};

% Point 1: Headline (Burst +9 dB, Hetero=1.0, PF & RR)
fprintf('>>> CAMPAIGN POINT 1: Headline (Burst +9 dB, Hetero=1.0) <<<\n');
opts1 = base_opts;
opts1.save_tag = 'headline';
opts1.burst_IM_dB = 9;
runComparison_v8(opts1);

% Point 2: Calm Baseline (Burst = 0 dB)
fprintf('\n>>> CAMPAIGN POINT 2: Calm Baseline (Burst = 0 dB) <<<\n');
opts2 = base_opts;
opts2.save_tag = 'calm';
opts2.burst_on = 0;
opts2.burst_IM_dB = 0;
runComparison_v8(opts2);

% Point 3: Severe Burst (+12 dB)
fprintf('\n>>> CAMPAIGN POINT 3: Severe Burst (+12 dB) <<<\n');
opts3 = base_opts;
opts3.save_tag = 'burst12dB';
opts3.burst_IM_dB = 12;
runComparison_v8(opts3);

% Point 4: Tier-A State Ablation (5 base features vs 17)
fprintf('\n>>> CAMPAIGN POINT 4: Tier-A State Ablation <<<\n');
opts4 = base_opts;
opts4.save_tag = 'tierA';
opts4.state_tier = 'A';
runComparison_v8(opts4);

% Point 5: Asymptotic Steady-State Horizon (1000 TTIs, Warm OLLA vs Deep A2C)
fprintf('\n>>> CAMPAIGN POINT 5: Asymptotic Steady-State Horizon (1000 TTIs) <<<\n');
opts5 = base_opts;
opts5.save_tag = 'steady1000';
opts5.simTime = 1000;
opts5.ep_deep = 25;
opts5.n_eval  = 15;
opts5.olla_warm_ttis = 1000;
runComparison_v8(opts5);

fprintf('\n========================================================================\n');
fprintf('  RL-AMC v8 FULL EVALUATION CAMPAIGN COMPLETE!\n');
fprintf('  Finished: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('========================================================================\n');
