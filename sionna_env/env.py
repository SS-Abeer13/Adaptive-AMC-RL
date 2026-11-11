"""
Gymnasium-style Single-Cell NR Environment for Sionna with Multi-Process HARQ (Task D1).

Environment characteristics:
  - Single gNodeB cell serving N = 10 users.
  - Stochastic 3GPP channel: TR 38.901 TDL (models A-E) or UMi with user speeds 3-30 m/s.
  - Delayed and noisy CQI feedback reports (reporting delay D_cqi >= 0, noise sigma).
  - Two traffic models:
      1) 'deadline': Poisson arrivals, finite payload, deadline slack, packet expiration.
      2) 'full_buffer': Infinite backlogged queue.
  - Multi-process HARQ manager: 8 processes per user, RTT = 8 slots, stored MCS,
    Chase combining in effective-SINR domain, at most 3 retries, both PF average modes.
  - Standard Gymnasium API: reset(), step(), observation_space, action_space.
"""

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple, Union
import numpy as np
import torch
import gymnasium as gym
from gymnasium import spaces

import sionna.phy.channel.tr38901 as tr38901
from sionna.sys.phy_abstraction import PHYAbstraction
from sionna_env.harq import HARQManager, ProcessState


# Standard 3GPP TS 38.214 Table 5.1.3.1-1: Modulation order (Qm) and target code rate x 1024
NR_MCS_TABLE_1 = [
    # MCS: (Qm, Coderate x 1024, Spectral efficiency)
    (2, 120, 0.2344),  # 0: QPSK, R=0.117
    (2, 157, 0.3066),  # 1: QPSK
    (2, 193, 0.3770),  # 2: QPSK
    (2, 251, 0.4902),  # 3: QPSK
    (2, 308, 0.6016),  # 4: QPSK
    (2, 379, 0.7402),  # 5: QPSK
    (2, 449, 0.8770),  # 6: QPSK
    (2, 526, 1.0273),  # 7: QPSK
    (2, 602, 1.1758),  # 8: QPSK
    (2, 679, 1.3262),  # 9: QPSK
    (4, 340, 1.3281),  # 10: 16QAM
    (4, 378, 1.4766),  # 11: 16QAM
    (4, 434, 1.6953),  # 12: 16QAM
    (4, 490, 1.9141),  # 13: 16QAM
    (4, 553, 2.1602),  # 14: 16QAM
    (4, 616, 2.4063),  # 15: 16QAM
    (4, 658, 2.5703),  # 16: 16QAM
    (6, 438, 2.5664),  # 17: 64QAM
    (6, 466, 2.7305),  # 18: 64QAM
    (6, 517, 3.0293),  # 19: 64QAM
    (6, 567, 3.3223),  # 20: 64QAM
    (6, 616, 3.6094),  # 21: 64QAM
    (6, 666, 3.9023),  # 22: 64QAM
    (6, 719, 4.2129),  # 23: 64QAM
    (6, 772, 4.5234),  # 24: 64QAM
    (6, 822, 4.8164),  # 25: 64QAM
    (6, 873, 5.1152),  # 26: 64QAM
    (6, 910, 5.3320),  # 27: 64QAM
    (6, 948, 5.5547),  # 28: 64QAM
]


def compute_nr_tbs(mcs: int, n_rb: int, n_symbols: int = 14) -> int:
    """Compute approximate 3GPP NR Transport Block Size (TBS) in bits."""
    if n_rb <= 0:
        return 0
    mcs = int(np.clip(mcs, 0, 28))
    qm, r1024, _ = NR_MCS_TABLE_1[mcs]
    coderate = r1024 / 1024.0
    # Approximate REs per RB: 12 subcarriers x (n_symbols - 2 DMRS) = 144 REs
    num_re = 12 * (n_symbols - 2) * n_rb
    num_info = num_re * qm * coderate
    # Round to byte multiple (at least 24 bits for CRC)
    tbs = int(max(24, int(np.round(num_info / 8.0) * 8)))
    return tbs


@dataclass
class Packet:
    arrival_slot: int
    bits: int
    deadline_slot: int


class SingleCellEnv(gym.Env):
    """
    Gymnasium environment simulating single-cell 5G NR downlink with 10 users,
    stochastic 3GPP TDL channels, delayed CQI feedback, and HARQ management.
    """

    metadata = {"render_modes": []}

    def __init__(
        self,
        num_users: int = 10,
        num_rbs: int = 51,
        slot_duration_ms: float = 0.5,
        channel_model: str = "A",
        min_speed: float = 3.0,
        max_speed: float = 30.0,
        traffic_type: str = "deadline",
        arrival_prob: float = 0.4,
        packet_size_bits: int = 4000,
        deadline_slots: int = 30,
        cqi_delay: int = 2,
        cqi_noise_std: float = 1.0,
        num_processes: int = 8,
        harq_rtt: int = 8,
        max_retries: int = 3,
        pf_mode: str = "ack_time",
        pf_beta: float = 0.98,
        episode_length: int = 200,
        seed: Optional[int] = None,
        use_sionna_phy: bool = False,
    ):
        super().__init__()

        self.num_users = num_users
        self.num_rbs = num_rbs
        self.slot_duration_ms = slot_duration_ms
        self.channel_model = channel_model
        self.min_speed = min_speed
        self.max_speed = max_speed
        self.traffic_type = traffic_type
        self.arrival_prob = arrival_prob
        self.packet_size_bits = packet_size_bits
        self.deadline_slots = deadline_slots
        self.cqi_delay = cqi_delay
        self.cqi_noise_std = cqi_noise_std
        self.episode_length = episode_length
        self.use_sionna_phy = use_sionna_phy

        # User speeds linearly spaced from min_speed (3 m/s) to max_speed (30 m/s)
        self.user_speeds = np.linspace(min_speed, max_speed, num_users)
        # Speed classes: 1 (<10 m/s), 2 (10-20 m/s), 3 (20-30 m/s)
        self.user_speed_classes = np.array(
            [1 if v < 10.0 else (2 if v <= 20.0 else 3) for v in self.user_speeds],
            dtype=np.int32,
        )

        # Base station path loss / geometry base SINRs (dB) across cell: 0 dB to 22 dB
        self.base_sinr_db = np.linspace(2.0, 22.0, num_users)

        # Instantiate optional Sionna PHYAbstraction
        self.pa = PHYAbstraction() if use_sionna_phy else None

        # Instantiate multi-process HARQ Manager
        self.harq = HARQManager(
            num_users=num_users,
            num_processes=num_processes,
            rtt=harq_rtt,
            max_retries=max_retries,
            pf_mode=pf_mode,
            beta=pf_beta,
            pa=self.pa,
        )

        # Per-user traffic queues (for deadline traffic)
        self.user_queues: List[List[Packet]] = [[] for _ in range(num_users)]

        # Delayed CQI history buffer: stores true SINR_dB per user for past slots
        self.sinr_history: List[np.ndarray] = []

        # TDL Channel generator (Sionna 3GPP TR 38.901)
        self.tdl = tr38901.TDL(
            model=channel_model,
            delay_spread=30e-9,
            carrier_frequency=3.5e9,
            min_speed=min_speed,
            max_speed=max_speed,
        )

        # Action space: offset a in {-4..+2} for each of the 10 users
        # Represented as Box[-4.0, 2.0] for RL continuous compatibility
        self.action_space = spaces.Box(
            low=-4.0, high=2.0, shape=(num_users,), dtype=np.float32
        )

        # Observation space: 10 users x 8 features per user = 80 features
        # Features:
        #   0: reported_cqi (normalized to [0, 1])
        #   1: true_sinr_db (normalized)
        #   2: queue_len (normalized)
        #   3: head_of_line_slack (normalized to [0, 1])
        #   4: busy_harq_fraction (0..1)
        #   5: has_retry_flag (0 or 1)
        #   6: pf_avg_throughput (normalized)
        #   7: speed_class (normalized: 1/3, 2/3, 1.0)
        self.observation_space = spaces.Box(
            low=-5.0, high=10.0, shape=(num_users, 8), dtype=np.float32
        )

        self.rng = np.random.default_rng(seed)
        self.current_slot = 0
        self.channel_block_idx = 0
        self.channel_powers = None

    def _generate_channel_block(self, num_slots: int = 500):
        """Generate a block of channel fading realizations using Sionna TDL."""
        h, _ = self.tdl(
            batch_size=self.num_users,
            num_time_steps=num_slots,
            sampling_frequency=1.0 / (self.slot_duration_ms * 1e-3),
        )
        # h shape: [num_users, 1, 1, 1, 1, num_paths, num_time_steps]
        # Instantaneous power = sum over multipath components
        p = torch.sum(torch.abs(h) ** 2, dim=(-2)).squeeze() # [num_users, num_time_steps]
        # Normalize average fading power to 1.0 per user
        p_mean = torch.mean(p, dim=-1, keepdim=True)
        p_norm = (p / (p_mean + 1e-12)).cpu().numpy()
        self.channel_powers = p_norm
        self.channel_block_idx = 0

    def reset(
        self,
        *,
        seed: Optional[int] = None,
        options: Optional[Dict[str, Any]] = None,
    ) -> Tuple[np.ndarray, Dict[str, Any]]:
        super().reset(seed=seed)
        if seed is not None:
            self.rng = np.random.default_rng(seed)

        self.current_slot = 0
        self.harq.reset()
        self.user_queues = [[] for _ in range(self.num_users)]
        self.sinr_history.clear()

        # Generate fresh channel fading block
        self._generate_channel_block(num_slots=self.episode_length + 20)

        # Warm up CQI history buffer for cqi_delay slots
        for s in range(self.cqi_delay + 1):
            fading_lin = self.channel_powers[:, s]
            fading_db = 10.0 * np.log10(np.maximum(1e-4, fading_lin))
            true_sinr = self.base_sinr_db + fading_db
            self.sinr_history.append(true_sinr)

        obs = self._build_observation()
        info = {"slot": 0, "offered_bits": 0, "delivered_bits": 0, "dropped_bits": 0}
        return obs, info

    def _get_reported_cqi_sinr(self) -> np.ndarray:
        """Fetch delayed and noisy SINR measurement for link adaptation."""
        target_idx = max(0, len(self.sinr_history) - 1 - self.cqi_delay)
        delayed_sinr = self.sinr_history[target_idx]
        noise = self.rng.normal(0.0, self.cqi_noise_std, size=self.num_users)
        reported_sinr = delayed_sinr + noise
        return reported_sinr

    def _sinr_to_base_mcs(self, sinr_db: np.ndarray) -> np.ndarray:
        """Map reported SINR to standard base MCS index [0..28]."""
        # Linear threshold mapping: approx 1.0 dB per MCS step above -6.5 dB
        raw_mcs = np.floor((sinr_db - (-6.5)) / 1.0).astype(np.int32)
        return np.clip(raw_mcs, 0, 28)

    def _build_observation(self) -> np.ndarray:
        """Construct the (num_users, 8) observation matrix."""
        rep_sinr = self._get_reported_cqi_sinr()
        true_sinr = self.sinr_history[-1]

        obs = np.zeros((self.num_users, 8), dtype=np.float32)
        for u in range(self.num_users):
            obs[u, 0] = rep_sinr[u] / 25.0                                    # reported SINR
            obs[u, 1] = true_sinr[u] / 25.0                                   # true SINR
            if self.traffic_type == "full_buffer":
                obs[u, 2] = 1.0                                               # infinite queue flag
                obs[u, 3] = 1.0                                               # full slack
            else:
                q_bits = sum(p.bits for p in self.user_queues[u])
                obs[u, 2] = min(5.0, q_bits / float(self.packet_size_bits))  # normalized queue
                if len(self.user_queues[u]) > 0:
                    slack = self.user_queues[u][0].deadline_slot - self.current_slot
                    obs[u, 3] = np.clip(slack / float(self.deadline_slots), 0.0, 1.0)
                else:
                    obs[u, 3] = 1.0

            obs[u, 4] = self.harq.get_occupancy(u) / float(self.harq.num_processes)
            obs[u, 5] = 1.0 if len(self.harq.get_retry_processes(u)) > 0 else 0.0
            obs[u, 6] = np.log1p(self.harq.r_avg[u]) / 10.0                  # PF average rate
            obs[u, 7] = self.user_speed_classes[u] / 3.0                     # Speed class

        return obs

    def step(
        self, action: np.ndarray
    ) -> Tuple[np.ndarray, float, bool, bool, Dict[str, Any]]:
        """
        Execute one slot (TTI):
          1. Traffic arrival (for deadline traffic).
          2. Link adaptation & MCS determination (base MCS + action offset).
          3. Proportional Fair scheduler & Retransmissions allocation.
          4. Transmission execution & Chase combining in HARQ manager.
          5. Channel advancement & CQI history buffer update.
          6. HARQ manager step & bit conservation check.
        """
        slot = self.current_slot
        action = np.asarray(action, dtype=np.float32).flatten()
        assert len(action) == self.num_users

        # 1. Traffic arrivals
        if self.traffic_type == "deadline":
            for u in range(self.num_users):
                if self.rng.random() < self.arrival_prob:
                    bits = self.packet_size_bits
                    pkt = Packet(
                        arrival_slot=slot,
                        bits=bits,
                        deadline_slot=slot + self.deadline_slots,
                    )
                    self.user_queues[u].append(pkt)
                    self.harq.add_offered_bits(bits)
        else: # full-buffer
            # Add virtual offered bits on demand
            pass

        # 2. Channel update & true SINR calculation for this slot
        if self.channel_block_idx >= self.channel_powers.shape[1]:
            self._generate_channel_block(num_slots=200)

        fading_lin = self.channel_powers[:, self.channel_block_idx]
        self.channel_block_idx += 1
        fading_db = 10.0 * np.log10(np.maximum(1e-4, fading_lin))
        true_sinr_db = self.base_sinr_db + fading_db
        self.sinr_history.append(true_sinr_db)

        # Determine reported base MCS + offset action
        rep_sinr = self._get_reported_cqi_sinr()
        base_mcs = self._sinr_to_base_mcs(rep_sinr)
        offset_action = np.round(action).astype(np.int32)
        target_mcs = np.clip(base_mcs + offset_action, 0, 28)

        # 3. Scheduling: Proportional Fair with Retransmissions Priority
        # Find users with pending retransmissions
        retry_users = [u for u in range(self.num_users) if len(self.harq.get_retry_processes(u)) > 0]
        # Eligible users for new transmission (must have data and available HARQ process)
        new_tx_users = []
        for u in range(self.num_users):
            has_data = (self.traffic_type == "full_buffer") or (len(self.user_queues[u]) > 0)
            if has_data and self.harq.has_available_process(u):
                new_tx_users.append(u)

        # Prioritize retransmission users first, then PF metric
        scheduled_users = []
        # Total available resource blocks in cell
        remaining_rbs = self.num_rbs

        # Schedule retries
        for u in retry_users:
            if remaining_rbs <= 0:
                break
            scheduled_users.append((u, "retry"))
            remaining_rbs -= int(np.ceil(self.num_rbs / 4.0))

        # Schedule new transmissions based on Proportional Fair metric r_ach / R_avg
        if remaining_rbs > 0 and len(new_tx_users) > 0:
            pf_metrics = []
            for u in new_tx_users:
                # Potential achievable rate
                tbs_est = compute_nr_tbs(target_mcs[u], max(4, remaining_rbs))
                metric = tbs_est / max(1.0, self.harq.r_avg[u])
                pf_metrics.append((metric, u))
            pf_metrics.sort(key=lambda x: x[0], reverse=True)

            # Schedule top user
            best_u = pf_metrics[0][1]
            scheduled_users.append((best_u, "new"))

        # 4. Transmit scheduled users
        sched_bits_per_user = np.zeros(self.num_users, dtype=np.float64)
        num_scheduled = len(scheduled_users)
        rbs_per_sched = max(4, self.num_rbs // max(1, num_scheduled))

        for u, mode in scheduled_users:
            if mode == "retry":
                # Retransmission: reuse stored mcs and process
                p_id = self.harq.get_retry_processes(u)[0]
                self.harq.schedule_transmission(
                    user_id=u,
                    process_id=p_id,
                    mcs=0, # unused in retry (retained from stored)
                    tbs=0, # unused in retry (retained from stored)
                    packet_bits=0,
                    sinr_eff_db=true_sinr_db[u],
                    slot=slot,
                )
                sched_bits_per_user[u] += self.harq.processes[u][p_id].tbs
            else:
                # New transmission
                p_id = self.harq.get_idle_process_id(u)
                if p_id is not None:
                    tbs = compute_nr_tbs(target_mcs[u], rbs_per_sched)
                    if self.traffic_type == "full_buffer":
                        payload_bits = tbs
                        deadline = None
                        self.harq.add_offered_bits(tbs)
                    else:
                        pkt = self.user_queues[u][0]
                        payload_bits = min(tbs, pkt.bits)
                        deadline = pkt.deadline_slot
                        # Pop or reduce packet in queue
                        if payload_bits >= pkt.bits:
                            self.user_queues[u].pop(0)
                        else:
                            pkt.bits -= payload_bits

                    self.harq.schedule_transmission(
                        user_id=u,
                        process_id=p_id,
                        mcs=target_mcs[u],
                        tbs=tbs,
                        packet_bits=payload_bits,
                        sinr_eff_db=true_sinr_db[u],
                        slot=slot,
                        deadline=deadline,
                    )
                    sched_bits_per_user[u] += tbs

        # 5. Advance HARQ manager state
        fb = self.harq.step(
            slot=slot,
            scheduled_bits_this_slot=sched_bits_per_user,
            rng=self.rng,
        )

        # 6. Check deadline drops in queue
        if self.traffic_type == "deadline":
            for u in range(self.num_users):
                surviving = []
                for pkt in self.user_queues[u]:
                    if slot >= pkt.deadline_slot:
                        self.harq.dropped_bits += pkt.bits
                        fb.dropped_bits_per_user[u] += pkt.bits
                    else:
                        surviving.append(pkt)
                self.user_queues[u] = surviving

        # Bit conservation verification
        queued_bits = sum(sum(p.bits for p in q) for q in self.user_queues)
        assert self.harq.check_conservation(queued_bits=queued_bits), "Bit conservation violated in env step!"

        # Reward = delivered bits - penalty for dropped bits
        slot_delivered = float(np.sum(fb.delivered_bits_per_user))
        slot_dropped = float(np.sum(fb.dropped_bits_per_user))
        reward = (slot_delivered - 1.5 * slot_dropped) / 1000.0

        self.current_slot += 1
        terminated = self.current_slot >= self.episode_length
        truncated = False

        obs = self._build_observation()
        info = {
            "slot": slot,
            "delivered_bits": slot_delivered,
            "dropped_bits": slot_dropped,
            "total_delivered": self.harq.delivered_bits,
            "total_dropped": self.harq.dropped_bits,
            "total_offered": self.harq.offered_bits,
            "in_flight_bits": self.harq.get_in_flight_bits(),
            "queued_bits": queued_bits,
            "scheduled_users": [u for u, _ in scheduled_users],
        }

        return obs, reward, terminated, truncated, info
