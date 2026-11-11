# Parameter Mapping: MATLAB Simulator vs. Sionna Environment

This document maps every model element between the reference MATLAB simulator (`defaultEnv_v17.m`, `generateChannel_v17.m`) and the Python/Sionna prototype environment (`sionna_env/`).

Status classification:
- **matches**: Parameter value or formulation is functionally identical or directly equivalent.
- **differs on purpose**: Value or design choice differs deliberately (e.g. 5G NR numerology vs. LTE numerology, carrier frequency choice, or fast CPU prototyping threshold).
- **is still to do**: Feature present in the MATLAB simulator that has not yet been ported or implemented in `sionna_env`.

---

## Parameter Mapping Table

| Model Element | MATLAB Value | Sionna Value | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **carrier** | 2.0 GHz (`env.fc = 2e9`) | 3.5 GHz default (`carrier_frequency = 3.5e9`), configurable to 2.0 GHz | differs on purpose | 5G NR mid-band n78 default in Sionna vs. legacy 2 GHz macrocell in MATLAB. Can be explicitly instantiated at 2.0 GHz. |
| **bandwidth** | 20 MHz (`env.BW = 20e6`) | 20 MHz (nominal channel bandwidth) | matches | Both model a standard 20 MHz single-carrier channel. |
| **number of resource blocks** | 100 RBs (`env.total_RB = 100`) | 51 PRBs (`num_rbs = 51`) | differs on purpose | MATLAB uses LTE numerology $\mu=0$ (15 kHz SCS, 100 RBs in 20 MHz). Sionna uses 5G NR standard numerology $\mu=1$ (30 kHz SCS, 51 PRBs in 20 MHz). |
| **path loss and shadowing** | 3GPP 3D UMa Macrocell ($PL = 13.54 + 39.08\log_{10}(d_{3D}) + 20\log_{10}(f_c/10^9) - 0.6(h_{UE}-1.5)$); Log-normal Shadow Fading ($\sigma_{SF}=6\text{ dB}$, $d_{corr}=50\text{ m}$) with RWP mobility | Deterministic base SINR array `base_sinr_db = np.linspace(2.0, 22.0, num_users)` | is still to do | MATLAB dynamically simulates 2D Random Waypoint mobility, 3D distance, path loss, and spatially correlated shadow fading. Sionna prototype uses static geometry base SINRs for $<2\text{ ms}$ CPU step times; full 3GPP TR 38.901 path loss/shadowing is available via Sionna but not yet enabled. |
| **per-user mean SNR** | $\approx 0\text{ to } 25\text{ dB}$ across cell radius ($10\text{ m}$ to $500\text{ m}$) | $2.0\text{ to } 22.0\text{ dB}$ linearly spaced across 10 users | matches | Both span the full range from cell-edge ($0\text{--}2\text{ dB}$) to cell-center ($22\text{--}25\text{ dB}$). |
| **speeds** | $3\text{ to } 30\text{ m/s}$ (`speed_min = 3`, `speed_max = 30`), heterogeneous per user | $3\text{ to } 30\text{ m/s}$ (`user_speeds = np.linspace(3, 30, 10)`) across 3 speed classes | matches | Identical velocity range covering pedestrian ($3\text{ m/s}$), urban ($15\text{ m/s}$), and vehicular ($30\text{ m/s}$). |
| **Doppler** | Jakes AR(1) fading: $\rho = J_0(2\pi f_d T_{\text{tti}})$ with $f_d = v f_c / c$ | 3GPP TR 38.901 TDL-A Sum-of-Sinusoids (SoS) with exact Doppler $\omega_d = 2\pi f_d$ and persistent phases | matches | Both reproduce the Clarke/Jakes autocorrelation $J_0(2\pi f_d \tau)$. Sionna environment maintains continuous phases across cache-batch boundaries without reset or decorrelation jumps. |
| **CQI delay and noise** | Delay `cqi_delay = 4` TTIs (or heterogeneous 2:8); Gaussian noise `sigma_meas = 1.0` dB | Delay `cqi_delay = 2` slots (configurable); Gaussian noise `cqi_noise_std = 1.0` dB | matches | Measurement noise standard deviation is identical (1.0 dB). Reporting delay is configurable in both simulators (default 2 vs 4 slots). |
| **interference** | 2-state Markov chain for non-stationary bursts (`burst_IM_dB = 9` dB, dwell times 250 / 120 TTIs) | Stationary thermal AWGN + multipath fading | is still to do | Non-stationary Markov interference burst process is not yet implemented in `SingleCellEnv`. |
| **BLER model** | Analytical AWGN look-up table `estimateBLER_v17(sinr_eff_true_dB, mcs)` | Piecewise linear/sigmoid AWGN threshold ($\gamma_{\text{th}} = -6.5 + 1.0 \times \text{MCS}$) | differs on purpose | Analytical threshold used in prototype for ultra-fast step execution ($\sim 1.5\text{ ms/slot}$). Sionna `PHYAbstraction.new_bler_table()` has been verified to generate exact 3GPP LDPC code-block BLER tables for future offline integration. |
| **HARQ combining** | Chase combining in effective-SINR domain with $+2.5\text{ dB}$ soft gain or linear $\sum \gamma_k$ | Chase combining in linear effective-SINR domain: $\Gamma_{\text{comb}} = \sum_{k=1}^m \gamma_k$ | matches | Exact energy accumulation in linear effective SINR: $\Gamma_{\text{comb, dB}} = 10\log_{10}(\sum 10^{\gamma_k/10})$. |
| **RTT** | `harq_rtt = 0` (legacy v9) or `8` TTIs (Phase 4 / HR1 evaluation) | `harq_rtt = 8` slots | matches | Matches the realistic 5G NR 8-slot round-trip time between transmission and ACK/NACK feedback delivery. |
| **processes** | `harq_nproc = 1` (legacy v9) or `8` parallel Stop-and-Wait processes (Phase 4 / HR1) | `num_processes = 8` parallel Stop-and-Wait processes per user | matches | Matches 3GPP 5G NR standard 8-process Stop-and-Wait HARQ architecture. |
| **PF definition** | Proportional Fair tracking supporting both `'acked'` and `'scheduled'` update modes | Both `'ack_time'` and `'scheduling_time'` modes supported in `HARQManager` via `pf_mode` | matches | Identical exponential moving average formulations with configurable smoothing factor $\beta = 0.98$. |
| **traffic** | Both `'full'` (full-buffer) and `'deadline'` (Poisson arrivals, fixed packet size, latency budget) | Both `'full_buffer'` and `'deadline'` traffic modes supported in `SingleCellEnv` | matches | Supports infinite backlog and finite-payload deadline queues with packet expiration and strict bit conservation. |
