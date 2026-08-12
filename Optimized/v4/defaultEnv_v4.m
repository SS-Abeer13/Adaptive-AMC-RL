function env = defaultEnv_v4(caseId)
% defaultEnv_v4  Environment definition shared by ALL policies (audit fix C4).
%   env = defaultEnv_v4(1)   single-user radial sweep (Case 1)
%   env = defaultEnv_v4(23)  5-user random-waypoint + scheduler (Cases 2/3)
%
% Every quantity that defines the MDP (channel, feedback model, reward,
% discount) lives here so Q-Learning, Tabular AC and Deep A2C are trained on
% the *identical* problem. Only optimizer hyper-parameters may differ per
% algorithm.

    % ---- Radio / channel (3GPP TR 38.901 UMa NLOS, see generateChannel_v4)
    env.fc          = 2e9;     % carrier (Hz)
    env.hBS         = 25;      % BS height (m), 38.901 UMa default
    env.hUE         = 1.5;     % UE height (m)
    env.txPower_dBm = 43;      % eNB tx power over the carrier
    env.G_dBi       = 8;       % antenna gain
    env.O2I_dB      = 20;      % O2I penetration, 38.901 low-loss model
    env.IM_dB       = 6;       % interference margin for un-modelled inter-cell
                               % interference (makes "SINR" honest, audit C6)
    env.NF_dB       = 9;       % UE noise figure
    env.BW          = 10e6;    % 10 MHz
    env.sigma_SF    = 6;       % shadow-fading std (dB), UMa NLOS
    env.d_corr      = 50;      % SF decorrelation distance (m), 38.901 T7.5-6
    env.rho_fading  = 0.95;    % AR(1) coefficient of complex fast fading per
                               % scheduling interval (first-order Gauss-Markov
                               % abstraction of Clarke's model; gives temporally
                               % correlated SINR so delayed CQI is informative)
    env.total_RB    = 110;

    % ---- CQI feedback imperfection (audit fix C2: no genie observations)
    env.cqi_delay   = 4;       % feedback delay in scheduling intervals
                               % (v4.1: 2 -> 4; at delay 2 the baseline CQI was
                               % barely outdated and no scheme had headroom)
    env.sigma_meas  = 1.0;     % SINR measurement noise std (dB)

    % ---- MDP definition (identical for all learners, audit fix C4)
    env.gamma        = 0.95;
    env.reward_scale = 30;     % Mbps normalization; keeps deep gradients sane
    env.reward_mode  = 'throughput';

    % ---- CQI mapping
    env.CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, ...
                          10.3, 11.7, 14.1, 16.3, 18.7, 21.0, 22.7];

    % ---- State discretization (tabular learners)
    env.SINR_bins = linspace(-10, 30, 20);
    env.max_CQI = 15; env.min_CQI = 1;
    env.max_delta = 5; env.min_delta = -5;
    env.actions = [-2, -1, 0, 1, 2];

    % ---- Observed SINR trend feature (v4.1). dS = obs_SINR(t)-obs_SINR(t-1)
    % is observable (difference of two reports) and carries the drift that a
    % delayed CQI cannot: ALL learners receive it (continuous for the deep
    % agent, 3-bin extra table dimension for the tabular agents) so the
    % comparison stays information-equal.
    env.trend_edges = [-1, 1];   % dS < -1 | -1..1 | > 1  ->  bins 1/2/3
    env.n_trend     = 3;

    % ---- Steady-state scoring (v4.1): metrics ignore the first burn_in
    % intervals so OLLA convergence and PF/EMA transients don't bias any scheme
    env.burn_in = 50;

    % ---- OLLA baseline (industry-standard comparison point)
    env.olla_target    = 0.1;  % BLER target
    env.olla_step_down = 0.5;  % dB subtracted on NACK; step-up = down*t/(1-t)

    switch caseId
        case 1
            env.N = 1; env.scheduler = 'all'; env.mobility = 'radial';
            env.areaSize = 1000; env.bsPos = [0, 0];
            env.speed = 5; env.d0 = 35; env.cellRadius = 700;
        otherwise   % 2/3 multi-user
            env.N = 5; env.scheduler = 'pf'; env.mobility = 'rwp';
            env.areaSize = 1000; env.bsPos = [500, 500]; env.speed = 5;
    end
end
