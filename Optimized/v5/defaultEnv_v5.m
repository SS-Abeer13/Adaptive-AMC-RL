function env = defaultEnv_v5(caseId, N)
% defaultEnv_v5  Single source of truth for the merged v5 MDP.
%
%   env = defaultEnv_v5(1)        single-user radial sweep (Case 1)
%   env = defaultEnv_v5(23)       5-user random-waypoint + PF (Cases 2/3)
%   env = defaultEnv_v5(23, 50)   N-user shared-parameter study
%
% v5 merges the two v4 lines:
%   * baseline-relative CQI encoding (from case2_3 v4): the action is an
%     OFFSET from the CQI that a fixed mapping would pick on the *observed*
%     (delayed+noisy) SINR. Offset 0 == the baseline exactly, so a learner
%     starts "at" the baseline and only has to learn a correction.
%   * imperfect CQI + calibrated BLER + citable channel + unified reward +
%     all A2C training fixes + rigorous multi-seed evaluation (from
%     optimized/v4). No imitation bonus, no bias init, no warmup blend.
%
% Every quantity that defines the MDP lives here so QL / Tab-AC / Deep A2C
% are trained on the identical problem (audit fix C4). Only optimizer
% hyper-parameters differ per algorithm.

    if nargin < 1 || isempty(caseId), caseId = 23; end

    % ---- Radio / channel (3GPP TR 38.901 UMa NLOS, see generateChannel_v5)
    env.fc          = 2e9;     % carrier (Hz)
    env.hBS         = 25;      % BS height (m)
    env.hUE         = 1.5;     % UE height (m)
    env.txPower_dBm = 43;
    env.G_dBi       = 8;
    env.O2I_dB      = 20;
    env.IM_dB       = 6;       % interference margin (honest "SINR", audit C6)
    env.NF_dB       = 9;
    env.BW          = 10e6;
    env.sigma_SF    = 6;       % shadow-fading std (dB)
    env.d_corr      = 50;      % SF decorrelation distance (m)
    env.rho_fading  = 0.95;    % AR(1) fast-fading correlation per interval
    env.total_RB    = 110;

    % ---- CQI feedback imperfection (audit fix C2)
    env.cqi_delay   = 4;       % feedback delay in scheduling intervals
    env.sigma_meas  = 1.0;     % SINR measurement noise std (dB)

    % ---- MDP (identical for all learners)
    env.gamma        = 0.95;
    env.reward_scale = 30;     % Mbps normalization
    env.reward_mode  = 'throughput';

    % ---- CQI mapping
    env.CQI_thresholds = [-Inf, -6.7, -4.7, -2.3, 0.2, 2.4, 4.3, 5.9, 8.1, ...
                          10.3, 11.7, 14.1, 16.3, 18.7, 21.0, 22.7];

    % ---- State discretization (tabular learners)
    env.SINR_bins = linspace(-10, 30, 20);
    env.max_CQI = 15; env.min_CQI = 1;
    env.max_delta = 5; env.min_delta = -5;
    env.actions = [-2, -1, 0, 1, 2];   % offset from baseline CQI (v5)

    % ---- Observed SINR-trend feature (continuous for deep, 3-bin for tabular)
    env.trend_edges = [-1, 1];
    env.n_trend     = 3;

    % ---- Steady-state scoring: ignore first burn_in intervals
    env.burn_in = 50;

    % ---- OLLA baseline
    env.olla_target    = 0.1;
    env.olla_step_down = 0.5;

    switch caseId
        case 1
            env.N = 1; env.scheduler = 'all'; env.mobility = 'radial';
            env.areaSize = 1000; env.bsPos = [0, 0];
            env.speed = 5; env.d0 = 35; env.cellRadius = 700;
            env.train_schedulers = {'all'};
            env.train_sched_weights = 1;
            env.sched_list = {'all'};          % observable regime list
        otherwise
            if nargin < 2 || isempty(N), N = 5; end
            env.N = N; env.scheduler = 'pf'; env.mobility = 'rwp';
            env.areaSize = 1000; env.bsPos = [500, 500]; env.speed = 5;
            % Scheduler domain randomization: trainers sample one of these per
            % episode so the policy is not overfit to one served-user
            % distribution. The regime is OBSERVABLE in the state (see
            % schedContext_v5) so one policy can specialize per regime instead
            % of averaging. Weighted toward PF (the deployment-primary) so PF
            % performance is preserved while RR/EQ robustness is gained.
            env.sched_list         = {'pf', 'rr', 'eq'};
            env.train_schedulers   = {'pf', 'rr', 'eq'};
            env.train_sched_weights= [0.50, 0.25, 0.25];
    end
    env.caseId = caseId;
end
