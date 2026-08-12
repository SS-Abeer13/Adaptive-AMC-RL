function env = defaultEnv_v7(caseId, N)
% defaultEnv_v7  v7 MDP environment defaults.
    if nargin < 1 || isempty(caseId), caseId = 23; end
    if nargin < 2 || isempty(N),      N = 10;      end

    % Radio / channel
    env.fc          = 2e9;
    env.hBS         = 25;
    env.hUE         = 1.5;
    env.txPower_dBm = 43;
    env.G_dBi       = 8;
    env.O2I_dB      = 20;
    env.IM_dB       = 6;
    env.NF_dB       = 9;
    env.BW          = 20e6;
    env.sigma_SF    = 6;
    env.d_corr      = 50;
    env.total_RB    = 100;
    env.T_tti       = 1e-3;

    % Fading (Jakes AR(1) per user)
    env.jakes = 1;
    env.rho_fading = 0.95;

    % Heterogeneous users
    env.hetero    = 1;
    env.speed_min = 3;
    env.speed_max = 30;
    env.delay_set = 2:8;
    env.delay_hom = 4;

    % Non-stationarity
    env.burst_on        = 1;
    env.burst_IM_dB     = 9;
    env.burst_dwell_calm  = 250;
    env.burst_dwell_burst = 120;
    env.speed_switch    = 1;

    % HARQ
    env.harq_on       = 1;
    env.harq_max_retx = 3;
    env.harq_comb_dB  = 2.5;

    % CQI feedback
    env.cqi_delay  = 4;
    env.sigma_meas = 1.0;

    % MDP
    env.bc_warm_eps  = 0;
    env.gamma        = 0.95;
    env.reward_scale = 30;
    env.reward_mode  = 'throughput';
    env.reward_agg   = 'cell';

    % CQI mapping (anchored at BLER=0.1)
    env.CQI_thresholds = [-Inf, -6.7, -5.0, -3.2, -1.5, 0.8, 2.0, 4.5, 6.8, ...
                          9.2, 11.5, 14.0, 16.3, 18.7, 20.5, 21.8];

    % State discretization
    env.SINR_bins = linspace(-10, 30, 20);
    env.max_CQI = 15; env.min_CQI = 1;
    env.max_delta = 5; env.min_delta = -5;
    env.actions = -3:3;
    env.off_edges = [-3, -1, 1, 3];
    env.trend_edges = [-1, 1];
    env.n_trend = 3;

    % State tier
    env.state_tier = 'B';

    % Steady-state scoring
    env.burn_in = 50;

    % OLLA
    env.olla_target      = 0.1;
    env.olla_step_down   = 0.5;
    env.olla_warm_passes = 0;
    env.olla_warm_ttis   = 0;

    % Fixed-offset comparators
    env.fixed_offset    = -1;
    env.fixed_class_tab = -1*ones(2,3);
    env.fixed_cands     = -4:2;

    % Scheduler
    env.pf_metric = 'reported';
    env.N = N; env.scheduler = 'pf'; env.mobility = 'rwp';
    env.areaSize = 1000; env.bsPos = [500, 500]; env.speed = 5;
    env.sched_list          = {'pf', 'rr', 'eq'};
    env.train_schedulers    = {'pf', 'rr', 'eq'};
    env.train_sched_weights = [0.50, 0.25, 0.25];
    env.caseId = caseId;
    env.use_gpu = false;
end
