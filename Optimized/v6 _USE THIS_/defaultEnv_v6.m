function env = defaultEnv_v6(caseId, N)
% defaultEnv_v6  Single source of truth for the v6 MDP (OLLA-relative).
%
% v6 = post-audit v5 + one structural change that makes the comparison with
% OLLA information-equal instead of handicapping the learners:
%
%   OLLA-RELATIVE ACTION ENCODING. Every learner (QL / Tab-AC / Deep A2C)
%   carries the SAME per-user OLLA outer loop as the OLLA comparator
%   (offset updated on realized ACK/NACK of the sent CQI, only when
%   scheduled - exactly the feedback a real UE link adaptation loop has).
%   The reference CQI is baseCQI(obs_SINR + olla_off) and the action is an
%   offset from THAT reference:
%       action 0  ==  OLLA exactly.
%   So a learner starts AT OLLA performance and can only gain by learning
%   state-conditional (trend-aware) deviations that a scalar reactive
%   outer loop structurally cannot represent. Any win over OLLA is
%   therefore a genuine learned improvement, not a comparator handicap.
%   The OLLA offset is part of the state (continuous for deep, binned for
%   tabular), so all learners see the outer-loop state they act around.
%
% Inherited from the audited v5 (do NOT revert these):
%   * pf_metric='reported'  - PF schedules on reported-CQI rate, no genie CSI
%   * reward_agg='cell'     - cooperative per-TTI cell reward (kills the
%                             CQI-inflation prisoner's dilemma under honest PF)
%   * CQI_thresholds anchored to the BLER=0.1 points of estimateBLER_v5
%   * imperfect CQI (delay+noise), TR 38.901 channel, unified reward,
%     scheduler domain randomization with observable regime (v5.2)
%
% v6 code reuses the unchanged v5 helpers (generateChannel_v5, cqiFeedback_v5,
% baseCQI_v5, estimateBLER_v5, computeReward_v5, schedule_users_v5,
% trendBin_v5, argmaxNoOp_v5, schedContext_v5, sampleSched_v5, pfPotential_v5)
% via the path set up in runComparison_v6.

    if nargin < 1 || isempty(caseId), caseId = 23; end

    % ---- Radio / channel (3GPP TR 38.901 UMa NLOS, see generateChannel_v5)
    env.fc          = 2e9;
    env.hBS         = 25;
    env.hUE         = 1.5;
    env.txPower_dBm = 43;
    env.G_dBi       = 8;
    env.O2I_dB      = 20;
    env.IM_dB       = 6;
    env.NF_dB       = 9;
    env.BW          = 10e6;
    env.sigma_SF    = 6;
    env.d_corr      = 50;
    env.rho_fading  = 0.95;
    env.total_RB    = 110;

    % ---- CQI feedback imperfection
    env.cqi_delay   = 4;
    env.sigma_meas  = 1.0;

    % ---- MDP (identical for all learners)
    env.gamma        = 0.95;
    env.reward_scale = 30;
    env.reward_mode  = 'throughput';
    env.reward_agg   = 'cell';    % cooperative CTDE reward (audit fix)

    % ---- CQI mapping anchored to BLER=0.1 points (audit fix, completes C5)
    env.CQI_thresholds = [-Inf, -6.7, -5.0, -3.2, -1.5, 0.8, 2.0, 4.5, 6.8, ...
                          9.2, 11.5, 14.0, 16.3, 18.7, 20.5, 21.8];

    % ---- State discretization (tabular learners)
    env.SINR_bins = linspace(-10, 30, 20);
    env.max_CQI = 15; env.min_CQI = 1;
    env.max_delta = 5; env.min_delta = -5;
    env.actions = [-2, -1, 0, 1, 2];   % offset from the OLLA-corrected reference (v6)

    % ---- OLLA offset feature (v6): binned for tabular, off/5 for deep
    env.off_edges = [-3, -1, 1, 3];    % -> 5 bins: <<0, <0, ~0, >0, >>0 (dB)

    % ---- Observed SINR-trend feature
    env.trend_edges = [-1, 1];
    env.n_trend     = 3;

    % ---- Steady-state scoring
    env.burn_in = 50;

    % ---- OLLA (shared by the comparator AND every learner's inner loop)
    env.olla_target      = 0.1;
    env.olla_step_down   = 0.5;
    env.olla_warm_passes = 0;   % DEPRECATED (replay = test leakage); do not use
    env.olla_warm_ttis   = 0;   % >0: leakage-free warm-up on an INDEPENDENT
                                % prepended segment of this many TTIs (use this)

    % ---- PF scheduler metric (audit fix): reported-CQI rate, no genie CSI
    env.pf_metric = 'reported';

    switch caseId
        case 1
            env.N = 1; env.scheduler = 'all'; env.mobility = 'radial';
            env.areaSize = 1000; env.bsPos = [0, 0];
            env.speed = 5; env.d0 = 35; env.cellRadius = 700;
            env.train_schedulers = {'all'};
            env.train_sched_weights = 1;
            env.sched_list = {'all'};
        otherwise
            if nargin < 2 || isempty(N), N = 5; end
            env.N = N; env.scheduler = 'pf'; env.mobility = 'rwp';
            env.areaSize = 1000; env.bsPos = [500, 500]; env.speed = 5;
            env.sched_list         = {'pf', 'rr', 'eq'};
            env.train_schedulers   = {'pf', 'rr', 'eq'};
            env.train_sched_weights= [0.50, 0.25, 0.25];
    end
    env.caseId = caseId;
end
