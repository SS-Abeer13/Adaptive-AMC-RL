function env = defaultEnv_v13(caseId, N)
% defaultEnv_v13  v8 MDP environment defaults and physical parameters.
% Resolves all reviewer concerns:
%   - Complete 3GPP PHY specification (20 MHz, 100 RB, 2 GHz, -92 dBm noise)
%   - Zero behavior cloning on oracle (bc_warm_eps = 0)
%   - Expanded dynamic action range (-6 to +4)
%   - Configurable dual evaluation horizons (transient 200 vs steady-state 1000)
%   - Multi-offset OLLA baseline configuration
    if nargin < 1 || isempty(caseId), caseId = 23; end
    if nargin < 2 || isempty(N),      N = 10;      end

    % -------------------------------------------------------------
    % 1. Radio / 3GPP Macrocell Channel Physics
    % -------------------------------------------------------------
    env.fc          = 2e9;        % Carrier frequency: 2.0 GHz
    env.BW          = 20e6;       % Channel bandwidth: 20 MHz
    env.total_RB    = 100;        % 100 Resource Blocks (3GPP 20 MHz LTE/NR)
    env.scs         = 15e3;       % Subcarrier spacing: 15 kHz
    env.T_tti       = 1e-3;       % TTI duration: 1 ms (1 subframe)
    env.hBS         = 25;         % Base station antenna height: 25 m
    env.hUE         = 1.5;        % UE antenna height: 1.5 m
    env.txPower_dBm = 43;         % Macro BS total TX power: 43 dBm (20 W)
    env.G_dBi       = 8;          % BS antenna gain: 8 dBi
    env.O2I_dB      = 20;         % Outdoor-to-Indoor building penetration loss: 20 dB
    env.IM_dB       = 6;          % Implementation margin: 6 dB
    env.NF_dB       = 9;          % UE noise figure: 9 dB
    env.thermal_N0  = -174;       % Thermal noise density: -174 dBm/Hz
    % Noise floor = -174 + 10*log10(20e6) + 9 = -92.0 dBm
    env.noise_floor_dBm = env.thermal_N0 + 10*log10(env.BW) + env.NF_dB;
    env.sigma_SF    = 6;          % Log-normal shadow fading std: 6 dB
    env.d_corr      = 50;         % Shadow fading correlation distance: 50 m

    % -------------------------------------------------------------
    % 2. Small-Scale Fading & Doppler Dynamics (Jakes AR(1))
    % -------------------------------------------------------------
    env.jakes       = 1;          % Jakes innovation model enabled
    env.rho_fading  = 0.95;       % Nominal lag-1 correlation

    % -------------------------------------------------------------
    % 3. Heterogeneous Users
    % -------------------------------------------------------------
    env.hetero      = 1;          % Per-user heterogeneity enabled
    env.speed_min   = 3;          % Min speed: 3 m/s (pedestrian)
    env.speed_max   = 30;         % Max speed: 30 m/s (vehicular highway)
    env.delay_set   = 2:8;        % Uplink CQI delay set in TTIs
    env.delay_hom   = 4;          % Homogeneous reference delay

    % -------------------------------------------------------------
    % 4. Non-Stationary Dynamics (Markov Interference Bursts)
    % -------------------------------------------------------------
    env.burst_on          = 1;    % Non-stationary interference bursts enabled
    env.burst_IM_dB       = 9;    % Nominal burst intensity: +9 dB interference
    env.burst_dwell_calm  = 250;  % Mean calm dwell: 250 TTIs
    env.burst_dwell_burst = 120;  % Mean burst dwell: 120 TTIs
    env.speed_switch      = 1;    % Mid-trace velocity jumps enabled

    % -------------------------------------------------------------
    % 5. HARQ with Chase Combining
    % -------------------------------------------------------------
    env.harq_on       = 1;        % HARQ enabled
    env.harq_max_retx = 3;        % Max 3 retransmissions (4 total attempts)
    env.harq_comb_dB  = 2.5;      % Chase combining soft gain: +2.5 dB per retry
    env.harq_adaptive = 1;        % Adaptive tracking on retransmission enabled

    % -------------------------------------------------------------
    % 6. CQI Feedback & Measurement Model
    % -------------------------------------------------------------
    env.cqi_delay   = 4;          % Default CQI reporting latency: 4 TTIs
    env.sigma_meas  = 1.0;        % Feedback measurement Gaussian noise: 1.0 dB
    % 15-level CQI thresholds (anchored at 10% BLER AWGN).
    % AUDIT FIX (2026-09-29): CQI q is transmitted as MCS q-1 (txStep_v13), so
    % CQI q must require SINR >= the 10%-BLER threshold of MCS q-1, i.e.
    % CQI_thresholds(q) = th_MCS(q-1) for q = 2..15 (CQI 1 = MCS 0 fallback).
    % The previous 16-entry vector [-Inf, -6.7, -5.0, ..., 21.8] shifted every
    % CQI up by one level: with perfect CSI and action 0 the first-transmission
    % BLER averaged ~75% instead of <=10%, and the calibrated "best fixed
    % offset = -1" was simply undoing that shift. (Same defect in v6/v7.)
    env.CQI_thresholds = [-Inf, -5.0, -3.2, -1.5, 0.8, 2.0, 4.5, 6.8, ...
                          9.2, 11.5, 14.0, 16.3, 18.7, 20.5, 21.8];
    env.max_CQI     = 15;
    env.min_CQI     = 1;

    % -------------------------------------------------------------
    % 7. MDP Formulation & RL Hyperparameters
    % -------------------------------------------------------------
    env.bc_warm_eps   = 0;        % STRICTLY 0: No Behavior Cloning on Oracle!
    env.gamma         = 0.95;     % Discount factor
    env.reward_scale  = 30;       % Reward normalization divisor
    env.reward_mode   = 'scheduled_goodput'; % Per-user scheduled reward
    env.lambda_drop   = 0.5;      % Penalty for dropped packet after max retx
    env.lambda_retx   = 0.05;     % Penalty for retransmission slot consumption

    % Action space: expanded dynamic range for fast burst recovery
    env.actions       = -6:4;     % 11 discrete actions
    env.max_delta     = 6;
    env.min_delta     = -6;

    % State configuration
    env.state_tier    = 'B';      % Full state with temporal tracking
    env.state_dim     = 16;       % Tier-B single-frame state: 13 features + 3-way scheduler one-hot (x L_seq=3 frames stacked)

    % -------------------------------------------------------------
    % 8. Classical Link Adaptation Baselines (OLLA & Multi-OLLA)
    % -------------------------------------------------------------
    env.burn_in           = 50;   % Evaluation burn-in period
    env.olla_target       = 0.10; % Nominal 10% target BLER
    env.olla_step_down    = 0.50; % Down step dd = 0.5 dB
    env.olla_warm_ttis    = 0;    % Set to 1000 for steady-state evaluation
    % AUDIT FIX (anti-windup): OLLA offsets were unbounded. ~38% of user-TTIs
    % in this link budget sit below the MCS-0 decoding threshold, so the
    % integrator of an edge / faded user kept stepping down (-0.5 dB per NACK)
    % while pinned at CQI 1, and then needed tens of ACKs to recover. This
    % windup is what made Warm-OLLA look worst (1000 TTIs to wind up).
    % Practical OLLA implementations bound the offset; +/-10 dB here.
    % Set to Inf to reproduce the pre-audit (unbounded) behaviour.
    env.olla_off_lim      = 10;   % |OLLA offset| <= 10 dB
    env.multi_olla_fast   = 0.8;  % Multi-OLLA fast integrator step
    env.multi_olla_slow   = 0.2;  % Multi-OLLA slow integrator step

    % Fixed offset comparators
    env.fixed_offset      = -1;
    env.fixed_class_tab   = -1 * ones(2, 3);
    env.fixed_cands       = -5:3;

    % -------------------------------------------------------------
    % 9. Scheduler & Cell Geometry
    % -------------------------------------------------------------
    env.N                   = N;
    env.scheduler           = 'pf';
    env.mobility            = 'rwp';
    env.areaSize            = 1000;
    env.bsPos               = [500, 500];
    env.speed               = 5;
    env.pf_metric           = 'reported';
    env.sched_list          = {'pf', 'rr', 'eq'};
    env.train_schedulers    = {'pf', 'rr', 'eq'};
    env.train_sched_weights = [0.50, 0.25, 0.25];
    env.caseId              = caseId;
    env.use_gpu             = false;

    % -------------------------------------------------------------
    % 10. v9 corrections (internal review of the v8 draft, 2026-10-19)
    % -------------------------------------------------------------
    % Mobility time scale: v8/v7 moved users v metres per TTI (1000x the
    % TTI clock). v9: displacement per TTI = v * T_tti * mob_kappa.
    env.mob_kappa       = 1;      % 1 = physical time scale; 1000 reproduces v8
    % Common random numbers: identical Bernoulli outcome draws for every
    % scheme on a trace (one uniform per user per TTI).
    env.crn             = true;
    % Matched steady state: OLLA warm-up also during training / calibration.
    env.train_warm_ttis = 0;      % TTIs of pure-OLLA warm-up before each training episode
    env.calib_warm      = false;  % calibrate Fixed/FixedPU after olla_warm_ttis of warm-up
    env.calib_sched     = 'pf';   % scheduler used for calibration
    % Bandit baselines over the residual offsets (UCB1 on normalized goodput)
    env.bandit_c        = 1.0;

    % -------------------------------------------------------------
    % 11. v13 structural-advantage cases (defaults reproduce v9 exactly)
    % -------------------------------------------------------------
    % E2: periodic CQI reporting (sample-and-hold, deterministic per-user phase)
    env.cqi_period      = 1;      % 1 = report every TTI (v9)
    % Extra observable features appended to the A2C state (Tier O/A/B):
    %   'age'      TTIs since the last CQI report arrived (normalised by cqi_period)
    %   'dev'      report minus the user's long-run EMA of its reports (dB/10)
    %   'cellnack' cell-wide NACK EMA over all scheduled users (gNB-side)
    %   'slack'    deadline slack / D, packet-present flag, remaining-bits fraction
    env.feat_extra      = {};
    % E4: deadline traffic (one packet per user every pkt_period TTIs)
    env.traffic         = 'full';     % 'full' (v9) | 'deadline'
    env.pkt_bits        = 2000;       % packet size (bits)
    env.pkt_period      = 20;         % inter-arrival (TTIs)
    env.pkt_deadline    = 10;         % latency budget (TTIs, <= pkt_period)
    env.reward_kind     = 'goodput';  % 'goodput' (v9) | 'ontime'
    env.ontime_bonus    = 1.0;        % reward per packet delivered within its deadline
    env.miss_pen        = 1.0;        % penalty per packet that misses its deadline
    env.primary         = 'goodput';  % primary metric: 'goodput' (cell Mbps) | 'ontime' (on-time delivery ratio)
    % Same-information comparators (calibrated offline on the primary metric)
    env.olla_targets      = [0.01 0.03 0.10 0.20 0.30 0.50]; % OLLA target-BLER grid
    env.olla_target_tuned = 0.10;
    env.ctx_cue         = 'none';     % cue for the context-table comparator: 'none'|'age'|'dev'|'cellnack'|'slack'
    env.ctx_edges       = [];         % bin edges of the cue
    env.ctx_tab         = 0;          % per-bin offset (CQI steps on top of OLLA)
    env.ctx_offsets     = -4:2;       % candidate offsets for the table
    env.n_calib_ctx     = 10;         % calibration traces for target / table
    % A2C hyper-parameters (empty = v9 values)
    env.a2c             = struct();

    % -------------------------------------------------------------
    % 12. P1 target-BLER action space (README_v13.md). Default reproduces
    % v9/v10/v13-P0 exactly: action_mode = 'offset' is a no-op everywhere.
    % -------------------------------------------------------------
    env.action_mode     = 'offset';
    % Stage 1: Residual action mode & shaping (PLAN_v13.md S1.1, S1.3)
    env.resid_actions   = [-1 0 1];
    env.resid_pen       = 0.02;       % 2% of ontime_bonus
    env.resid_init_bias = 3.0;        % logit bias +3 on delta = 0
    env.base_rule_kind  = 'fixed';    % 'fixed' | 'fixed_class'
    env.shape_c         = 0.5;
   % 'offset' (v9/v10, A2C action = CQI offset) | 'target' (P1)
    env.target_set      = [0.01 0.03 0.10 0.20 0.30 0.50]; % OLLA target-BLER arms (action_mode = 'target')
    env.target_epoch    = 10;         % TTIs a chosen target is held for (semi-MDP decision epoch)
    env.target_class_tab = env.olla_target_tuned * ones(2, 3); % per-class tuned target (P1 comparator)
end
