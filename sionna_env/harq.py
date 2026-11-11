"""
HARQ Manager for Sionna Environment.

Implements multi-process Stop-and-Wait Hybrid ARQ for 3GPP NR:
  - 8 HARQ processes per user (process IDs 0..7)
  - RTT feedback delay of 8 slots (or configurable, including RTT=0)
  - Stored MCS / TBS retained across retransmissions
  - Chase combining (HARQ-CC) in the effective-SINR domain:
      gamma_combined = sum_k gamma_k (linear scale)
  - At most 3 retransmissions (max 4 attempts total: 1 initial + up to 3 retries)
  - Both Proportional Fair (PF) throughput average update definitions:
      1) 'scheduling_time': updated at slot t with scheduled transmission bits
      2) 'ack_time': updated at slot t with delivered (ACKed) bits
  - Strict bit conservation accounting:
      offered_bits == delivered_bits + dropped_bits + in_flight_bits
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Tuple, Union
import numpy as np
import torch


class ProcessState(Enum):
    IDLE = 0
    IN_FLIGHT = 1
    RETRY = 2


@dataclass
class HARQProcess:
    user_id: int
    process_id: int
    state: ProcessState = ProcessState.IDLE
    attempt: int = 0                  # 1 for initial, 2 for 1st retry, ..., up to 4
    mcs: int = 0                      # Stored MCS index
    tbs: int = 0                      # Stored transport block size in bits
    packet_bits: int = 0              # Useful payload bits
    tx_slot: int = -1                 # Slot when current attempt was transmitted
    ack_slot: int = -1                # Slot when ACK/NACK feedback arrives
    deadline: Optional[int] = None    # Packet deadline (slot number), if deadline traffic
    sinr_history_lin: List[float] = field(default_factory=list)
    combined_sinr_lin: float = 0.0
    combined_sinr_db: float = -100.0

    def reset(self):
        self.state = ProcessState.IDLE
        self.attempt = 0
        self.mcs = 0
        self.tbs = 0
        self.packet_bits = 0
        self.tx_slot = -1
        self.ack_slot = -1
        self.deadline = None
        self.sinr_history_lin.clear()
        self.combined_sinr_lin = 0.0
        self.combined_sinr_db = -100.0


@dataclass
class SlotFeedback:
    slot: int
    acked_transmissions: List[Tuple[int, int, int]] = field(default_factory=list)   # (user_id, process_id, bits)
    nacked_transmissions: List[Tuple[int, int, int]] = field(default_factory=list)  # (user_id, process_id, attempt)
    dropped_transmissions: List[Tuple[int, int, int]] = field(default_factory=list) # (user_id, process_id, bits)
    delivered_bits_per_user: np.ndarray = field(default_factory=lambda: np.zeros(10))
    dropped_bits_per_user: np.ndarray = field(default_factory=lambda: np.zeros(10))


class HARQManager:
    """Multi-process HARQ Manager with Chase combining and configurable PF smoothing."""

    def __init__(
        self,
        num_users: int = 10,
        num_processes: int = 8,
        rtt: int = 8,
        max_retries: int = 3,
        pf_mode: str = "ack_time",
        beta: float = 0.98,
        pa=None,
    ):
        """
        Args:
            num_users: Number of active users (default 10).
            num_processes: Number of parallel HARQ processes per user (default 8).
            rtt: Feedback round-trip time in slots (default 8).
            max_retries: Maximum number of retransmissions allowed (default 3, so max 4 attempts).
            pf_mode: 'ack_time' (delivered bits on ACK) or 'scheduling_time' (scheduled bits at TX).
            beta: Smoothing factor for PF running average rate.
            pa: Optional Sionna PHYAbstraction instance for evaluating BLER.
        """
        assert num_users > 0
        assert num_processes >= 1
        assert rtt >= 0
        assert max_retries >= 0
        assert pf_mode in ("ack_time", "scheduling_time")

        self.num_users = num_users
        self.num_processes = num_processes
        self.rtt = rtt
        self.max_retries = max_retries
        self.max_attempts = max_retries + 1
        self.pf_mode = pf_mode
        self.beta = beta
        self.pa = pa

        # Processes: num_users x num_processes
        self.processes: List[List[HARQProcess]] = [
            [HARQProcess(user_id=u, process_id=p) for p in range(num_processes)]
            for u in range(num_users)
        ]

        # PF average rate tracking (in bits/slot)
        self.r_avg = np.ones(num_users, dtype=np.float64)

        # Global bit conservation ledgers
        self.offered_bits = 0
        self.delivered_bits = 0
        self.dropped_bits = 0

        # Current slot index
        self.current_slot = 0

    def reset(self):
        for u in range(self.num_users):
            for p in range(self.num_processes):
                self.processes[u][p].reset()
        self.r_avg = np.ones(self.num_users, dtype=np.float64)
        self.offered_bits = 0
        self.delivered_bits = 0
        self.dropped_bits = 0
        self.current_slot = 0

    def add_offered_bits(self, bits: int):
        """Record newly generated/offered traffic bits into the system."""
        assert bits >= 0
        self.offered_bits += bits

    def get_in_flight_bits(self) -> int:
        """Sum of useful bits in all active (IN_FLIGHT or RETRY) HARQ processes."""
        total = 0
        for u in range(self.num_users):
            for p in range(self.num_processes):
                proc = self.processes[u][p]
                if proc.state != ProcessState.IDLE:
                    total += proc.packet_bits
        return total

    def check_conservation(self, queued_bits: int = 0) -> bool:
        """
        Verify the exact bit conservation invariant:
            delivered_bits + dropped_bits + in_flight_bits + queued_bits == offered_bits
        """
        in_flight = self.get_in_flight_bits()
        lhs = self.delivered_bits + self.dropped_bits + in_flight + queued_bits
        rhs = self.offered_bits
        return lhs == rhs

    def get_occupancy(self, user_id: int) -> int:
        """Return number of non-idle HARQ processes for user_id (0 <= occupancy <= num_processes)."""
        count = 0
        for proc in self.processes[user_id]:
            if proc.state != ProcessState.IDLE:
                count += 1
        return count

    def has_available_process(self, user_id: int) -> bool:
        """True if user has an idle process for new transmission."""
        return self.get_occupancy(user_id) < self.num_processes

    def get_idle_process_id(self, user_id: int) -> Optional[int]:
        """Return first idle process ID for user_id, or None if all are busy."""
        for p in range(self.num_processes):
            if self.processes[user_id][p].state == ProcessState.IDLE:
                return p
        return None

    def get_retry_processes(self, user_id: int) -> List[int]:
        """Return process IDs that are waiting for retransmission."""
        return [
            p for p in range(self.num_processes)
            if self.processes[user_id][p].state == ProcessState.RETRY
        ]

    def schedule_transmission(
        self,
        user_id: int,
        process_id: int,
        mcs: int,
        tbs: int,
        packet_bits: int,
        sinr_eff_db: float,
        slot: int,
        deadline: Optional[int] = None,
    ) -> HARQProcess:
        """
        Schedule a new transmission or retransmission on the specified process.

        Chase combining logic:
            - If initial attempt: combined_sinr_lin = sinr_lin
            - If retransmission: combined_sinr_lin += sinr_lin
              Stored MCS and TBS are preserved.
        """
        assert 0 <= user_id < self.num_users
        assert 0 <= process_id < self.num_processes
        proc = self.processes[user_id][process_id]
        assert proc.state in (ProcessState.IDLE, ProcessState.RETRY), f"Process {process_id} not schedulable ({proc.state})"

        sinr_lin = 10.0 ** (sinr_eff_db / 10.0)

        if proc.state == ProcessState.IDLE:
            # Initial transmission
            proc.attempt = 1
            proc.mcs = mcs
            proc.tbs = tbs
            proc.packet_bits = packet_bits
            proc.deadline = deadline
            proc.sinr_history_lin = [sinr_lin]
            proc.combined_sinr_lin = sinr_lin
            proc.combined_sinr_db = sinr_eff_db
        else:
            # Retransmission: reuse stored mcs and tbs
            proc.attempt += 1
            proc.sinr_history_lin.append(sinr_lin)
            proc.combined_sinr_lin += sinr_lin
            proc.combined_sinr_db = 10.0 * np.log10(max(1e-12, proc.combined_sinr_lin))

        proc.state = ProcessState.IN_FLIGHT
        proc.tx_slot = slot
        proc.ack_slot = slot + self.rtt

        return proc

    def compute_bler(self, proc: HARQProcess) -> float:
        """Evaluate BLER for the process at its combined effective SINR with stored MCS."""
        if self.pa is not None:
            snr_t = torch.tensor([proc.combined_sinr_db], dtype=torch.float32)
            bler_t = self.pa.get_bler(
                mcs_index=proc.mcs,
                mcs_table_index=1,
                mcs_category=1, # PDSCH
                cb_size=max(24, proc.tbs),
                snr_eff=snr_t,
            )
            return float(bler_t.item())
        else:
            # Analytic 3GPP NR AWGN threshold approximation:
            # -6.5 dB for MCS 0 up to ~21.5 dB for MCS 28 (~1.0 dB per MCS step)
            gamma_th_db = -6.5 + 1.0 * float(proc.mcs)
            margin = proc.combined_sinr_db - gamma_th_db
            # Sigmoid transition: margin > 0 -> low BLER, margin < 0 -> high BLER
            bler = 1.0 / (1.0 + np.exp(margin * 1.5))
            return float(np.clip(bler, 0.0, 1.0))

    def step(
        self,
        slot: int,
        scheduled_bits_this_slot: Optional[np.ndarray] = None,
        force_ack: Optional[Dict[Tuple[int, int], bool]] = None,
        rng: Optional[np.random.Generator] = None,
    ) -> SlotFeedback:
        """
        Advance HARQ manager state at slot:
          1. Process arriving ACKs/NACKs (where ack_slot == slot).
          2. Check deadline expiration for active processes.
          3. Update PF throughput averages according to pf_mode.
        """
        self.current_slot = slot
        fb = SlotFeedback(slot=slot)
        fb.delivered_bits_per_user = np.zeros(self.num_users, dtype=np.float64)
        fb.dropped_bits_per_user = np.zeros(self.num_users, dtype=np.float64)

        if rng is None:
            rng = np.random.default_rng()

        # 1. Process feedback arriving at this slot
        for u in range(self.num_users):
            for p in range(self.num_processes):
                proc = self.processes[u][p]
                if proc.state == ProcessState.IN_FLIGHT and proc.ack_slot == slot:
                    # Check deadline expiration first
                    if proc.deadline is not None and slot > proc.deadline:
                        # Expired while in flight -> dropped
                        self.dropped_bits += proc.packet_bits
                        fb.dropped_bits_per_user[u] += proc.packet_bits
                        fb.dropped_transmissions.append((u, p, proc.packet_bits))
                        proc.reset()
                        continue

                    # Determine ACK or NACK
                    if force_ack is not None and (u, p) in force_ack:
                        is_ack = force_ack[(u, p)]
                    else:
                        bler = self.compute_bler(proc)
                        is_ack = bool(rng.random() >= bler)

                    if is_ack:
                        # Successful transmission
                        self.delivered_bits += proc.packet_bits
                        fb.delivered_bits_per_user[u] += proc.packet_bits
                        fb.acked_transmissions.append((u, p, proc.packet_bits))
                        proc.reset()
                    else:
                        # Transmission failed (NACK)
                        if proc.attempt < self.max_attempts:
                            # Schedule for retransmission
                            proc.state = ProcessState.RETRY
                            fb.nacked_transmissions.append((u, p, proc.attempt))
                        else:
                            # Maximum attempts exhausted -> drop packet
                            self.dropped_bits += proc.packet_bits
                            fb.dropped_bits_per_user[u] += proc.packet_bits
                            fb.dropped_transmissions.append((u, p, proc.packet_bits))
                            proc.reset()

        # 2. Check deadline expiration for waiting RETRY processes
        for u in range(self.num_users):
            for p in range(self.num_processes):
                proc = self.processes[u][p]
                if proc.state == ProcessState.RETRY:
                    if proc.deadline is not None and slot >= proc.deadline:
                        self.dropped_bits += proc.packet_bits
                        fb.dropped_bits_per_user[u] += proc.packet_bits
                        fb.dropped_transmissions.append((u, p, proc.packet_bits))
                        proc.reset()

        # 3. Update Proportional Fair throughput averages
        if self.pf_mode == "scheduling_time":
            if scheduled_bits_this_slot is not None:
                r_instant = scheduled_bits_this_slot
            else:
                r_instant = np.zeros(self.num_users, dtype=np.float64)
            self.r_avg = self.beta * self.r_avg + (1.0 - self.beta) * r_instant
        elif self.pf_mode == "ack_time":
            r_instant = fb.delivered_bits_per_user
            self.r_avg = self.beta * self.r_avg + (1.0 - self.beta) * r_instant

        return fb
