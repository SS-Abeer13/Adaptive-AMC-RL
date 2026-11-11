"""
Unit tests for the HARQ Manager (Task D3).

D3 Requirements:
  1. ACK arrives exactly RTT slots after the transmission.
  2. Process occupancy never exceeds 8.
  3. A retransmission's effective SINR equals the combined SINR (Chase combining).
  4. Bits are conserved (delivered + dropped + in_flight = offered).
  5. With RTT 0 and one process the manager reduces to Sionna's per-slot ACK behaviour.
  6. Verify both PF-average definitions (scheduling-time vs ACK-time).
"""

import numpy as np
import pytest
from sionna_env.harq import HARQManager, ProcessState


def test_ack_timing():
    """Requirement 1: ACK arrives exactly RTT slots after transmission."""
    rtt = 8
    mgr = HARQManager(num_users=10, num_processes=8, rtt=rtt, max_retries=3)
    user_id = 0
    t_tx = 15

    # Schedule initial transmission at slot 15
    p_id = mgr.get_idle_process_id(user_id)
    assert p_id == 0
    proc = mgr.schedule_transmission(
        user_id=user_id,
        process_id=p_id,
        mcs=12,
        tbs=2000,
        packet_bits=2000,
        sinr_eff_db=10.0,
        slot=t_tx,
    )
    assert proc.tx_slot == t_tx
    assert proc.ack_slot == t_tx + rtt  # Exactly 23

    # Step through slots 15 to 22: process must remain in flight, no ACK/NACK received
    for s in range(t_tx, t_tx + rtt):
        fb = mgr.step(slot=s)
        assert len(fb.acked_transmissions) == 0
        assert len(fb.nacked_transmissions) == 0
        assert proc.state == ProcessState.IN_FLIGHT

    # At slot t_tx + rtt = 23, ACK arrives
    fb = mgr.step(slot=t_tx + rtt, force_ack={(user_id, p_id): True})
    assert len(fb.acked_transmissions) == 1
    assert fb.acked_transmissions[0] == (user_id, p_id, 2000)
    assert proc.state == ProcessState.IDLE
    assert fb.delivered_bits_per_user[user_id] == 2000


def test_process_occupancy_limit():
    """Requirement 2: Process occupancy never exceeds 8."""
    max_proc = 8
    mgr = HARQManager(num_users=10, num_processes=max_proc, rtt=8, max_retries=3)
    user_id = 2

    # Schedule 8 transmissions consecutively
    for i in range(max_proc):
        assert mgr.has_available_process(user_id)
        p_id = mgr.get_idle_process_id(user_id)
        assert p_id == i
        mgr.schedule_transmission(
            user_id=user_id,
            process_id=p_id,
            mcs=10,
            tbs=1500,
            packet_bits=1500,
            sinr_eff_db=8.0,
            slot=i,
        )
        assert mgr.get_occupancy(user_id) == i + 1

    # At 8 processes occupied, user cannot be scheduled for a new transmission
    assert mgr.get_occupancy(user_id) == 8
    assert not mgr.has_available_process(user_id)
    assert mgr.get_idle_process_id(user_id) is None


def test_chase_combining_effective_sinr():
    """Requirement 3: A retransmission's effective SINR equals the combined SINR."""
    rtt = 4
    mgr = HARQManager(num_users=10, num_processes=8, rtt=rtt, max_retries=3)
    user_id = 1
    p_id = 0

    # Transmission 1: SINR1 = 6.0 dB
    sinr1_db = 6.0
    sinr1_lin = 10.0 ** (sinr1_db / 10.0)
    proc = mgr.schedule_transmission(
        user_id=user_id,
        process_id=p_id,
        mcs=14,
        tbs=3000,
        packet_bits=3000,
        sinr_eff_db=sinr1_db,
        slot=0,
    )
    assert proc.attempt == 1
    assert pytest.approx(proc.combined_sinr_lin, rel=1e-6) == sinr1_lin
    assert pytest.approx(proc.combined_sinr_db, abs=1e-6) == sinr1_db

    # Step to slot 4, NACK transmission 1 -> enters RETRY state
    fb = mgr.step(slot=4, force_ack={(user_id, p_id): False})
    assert len(fb.nacked_transmissions) == 1
    assert proc.state == ProcessState.RETRY

    # Transmission 2 (Retransmission 1): SINR2 = 9.0 dB
    sinr2_db = 9.0
    sinr2_lin = 10.0 ** (sinr2_db / 10.0)
    expected_comb_lin = sinr1_lin + sinr2_lin
    expected_comb_db = 10.0 * np.log10(expected_comb_lin)

    proc = mgr.schedule_transmission(
        user_id=user_id,
        process_id=p_id,
        mcs=14,
        tbs=3000,
        packet_bits=3000,
        sinr_eff_db=sinr2_db,
        slot=5,
    )
    assert proc.attempt == 2
    # Verify stored MCS is preserved
    assert proc.mcs == 14
    assert proc.tbs == 3000
    # Verify combined effective SINR equals sum of linear SINRs
    assert pytest.approx(proc.combined_sinr_lin, rel=1e-6) == expected_comb_lin
    assert pytest.approx(proc.combined_sinr_db, abs=1e-6) == expected_comb_db


def test_bit_conservation():
    """Requirement 4: Bits are conserved (delivered + dropped + in flight = offered)."""
    mgr = HARQManager(num_users=4, num_processes=8, rtt=4, max_retries=2)
    rng = np.random.default_rng(20261111)

    total_offered = 0
    # Simulate 50 slots with random packet arrivals, transmissions, and outcomes
    for s in range(50):
        # Generate some offered traffic
        for u in range(4):
            if rng.random() < 0.6 and mgr.has_available_process(u):
                bits = int(rng.integers(500, 2500))
                mgr.add_offered_bits(bits)
                total_offered += bits
                p_id = mgr.get_idle_process_id(u)
                mgr.schedule_transmission(
                    user_id=u,
                    process_id=p_id,
                    mcs=int(rng.integers(2, 20)),
                    tbs=bits,
                    packet_bits=bits,
                    sinr_eff_db=float(rng.uniform(0.0, 15.0)),
                    slot=s,
                )

        # Step slot
        mgr.step(slot=s, rng=rng)

        # Reschedule any RETRY processes
        for u in range(4):
            retries = mgr.get_retry_processes(u)
            for p_id in retries:
                mgr.schedule_transmission(
                    user_id=u,
                    process_id=p_id,
                    mcs=0, # unused, retained from stored
                    tbs=0, # unused, retained from stored
                    packet_bits=0,
                    sinr_eff_db=float(rng.uniform(2.0, 18.0)),
                    slot=s + 1,
                )

        # Invariant check at every slot
        assert mgr.check_conservation(), (
            f"Conservation violated at slot {s}: "
            f"offered={mgr.offered_bits}, "
            f"delivered={mgr.delivered_bits}, "
            f"dropped={mgr.dropped_bits}, "
            f"in_flight={mgr.get_in_flight_bits()}"
        )

    # Let remaining in-flight processes finish
    for s in range(50, 80):
        mgr.step(slot=s, rng=rng)
        # Reschedule retries
        for u in range(4):
            retries = mgr.get_retry_processes(u)
            for p_id in retries:
                mgr.schedule_transmission(
                    user_id=u,
                    process_id=p_id,
                    mcs=0,
                    tbs=0,
                    packet_bits=0,
                    sinr_eff_db=15.0,
                    slot=s,
                )
        assert mgr.check_conservation()

    assert mgr.offered_bits == total_offered
    assert mgr.delivered_bits + mgr.dropped_bits + mgr.get_in_flight_bits() == mgr.offered_bits


def test_sionna_per_slot_reduction():
    """Requirement 5: With RTT 0 and one process, manager reduces to Sionna's per-slot ACK behaviour."""
    mgr = HARQManager(num_users=2, num_processes=1, rtt=0, max_retries=0)
    user_id = 0

    # In slot t=0, transmit
    p_id = mgr.get_idle_process_id(user_id)
    assert p_id == 0
    mgr.schedule_transmission(
        user_id=user_id,
        process_id=0,
        mcs=10,
        tbs=1000,
        packet_bits=1000,
        sinr_eff_db=12.0,
        slot=0,
    )
    # With RTT 0, ack_slot is 0
    assert mgr.processes[user_id][0].ack_slot == 0

    # In the same slot t=0, step evaluates feedback immediately
    fb = mgr.step(slot=0, force_ack={(user_id, 0): True})
    assert len(fb.acked_transmissions) == 1
    assert fb.acked_transmissions[0] == (user_id, 0, 1000)
    # Process is freed immediately, ready for next slot
    assert mgr.processes[user_id][0].state == ProcessState.IDLE
    assert mgr.has_available_process(user_id)


def test_pf_average_definitions():
    """Requirement 6: Verify both PF-average definitions (scheduling-time vs ACK-time)."""
    beta = 0.90
    rtt = 4

    # 1. Scheduling-time PF
    mgr_sched = HARQManager(num_users=2, num_processes=8, rtt=rtt, pf_mode="scheduling_time", beta=beta)
    # Transmission of 1000 bits at slot 0
    mgr_sched.schedule_transmission(0, 0, 10, 1000, 1000, 10.0, slot=0)
    sched_bits = np.array([1000.0, 0.0])
    mgr_sched.step(slot=0, scheduled_bits_this_slot=sched_bits)
    # Scheduling-time updates R_avg immediately at slot 0: beta * 1.0 + (1 - beta) * 1000
    expected_r0 = beta * 1.0 + (1.0 - beta) * 1000.0
    assert pytest.approx(mgr_sched.r_avg[0], rel=1e-5) == expected_r0
    assert pytest.approx(mgr_sched.r_avg[1], rel=1e-5) == beta * 1.0

    # 2. ACK-time PF
    mgr_ack = HARQManager(num_users=2, num_processes=8, rtt=rtt, pf_mode="ack_time", beta=beta)
    mgr_ack.schedule_transmission(0, 0, 10, 1000, 1000, 10.0, slot=0)
    # At slot 0, no ACK has arrived yet -> instant rate is 0
    mgr_ack.step(slot=0)
    assert pytest.approx(mgr_ack.r_avg[0], rel=1e-5) == beta * 1.0 + (1.0 - beta) * 0.0

    # Step to slot 4 where ACK arrives
    for s in range(1, 4):
        mgr_ack.step(slot=s)

    # At slot 4, ACK arrives
    fb = mgr_ack.step(slot=4, force_ack={(0, 0): True})
    assert fb.delivered_bits_per_user[0] == 1000.0
    # In slot 4, R_avg updates with 1000 delivered bits
    # Prior R_avg had decayed by beta^4
    prev_r = 1.0 * (beta ** 4)
    expected_r4 = beta * prev_r + (1.0 - beta) * 1000.0
    assert pytest.approx(mgr_ack.r_avg[0], rel=1e-5) == expected_r4


def test_max_retries_drop():
    """At most 3 retransmissions (max 4 attempts); drop after attempt 4 fails."""
    mgr = HARQManager(num_users=1, num_processes=1, rtt=2, max_retries=3)
    u = 0

    # Attempt 1 (initial)
    mgr.add_offered_bits(1000)
    mgr.schedule_transmission(u, 0, 8, 1000, 1000, 5.0, slot=0)
    mgr.step(0)
    mgr.step(1)
    fb = mgr.step(2, force_ack={(u, 0): False}) # NACK attempt 1
    assert mgr.processes[u][0].state == ProcessState.RETRY
    assert mgr.processes[u][0].attempt == 1

    # Attempt 2 (Retry 1)
    mgr.schedule_transmission(u, 0, 8, 1000, 1000, 5.0, slot=3)
    mgr.step(3)
    mgr.step(4)
    fb = mgr.step(5, force_ack={(u, 0): False}) # NACK attempt 2
    assert mgr.processes[u][0].state == ProcessState.RETRY
    assert mgr.processes[u][0].attempt == 2

    # Attempt 3 (Retry 2)
    mgr.schedule_transmission(u, 0, 8, 1000, 1000, 5.0, slot=6)
    mgr.step(6)
    mgr.step(7)
    fb = mgr.step(8, force_ack={(u, 0): False}) # NACK attempt 3
    assert mgr.processes[u][0].state == ProcessState.RETRY
    assert mgr.processes[u][0].attempt == 3

    # Attempt 4 (Retry 3 - maximum allowed)
    mgr.schedule_transmission(u, 0, 8, 1000, 1000, 5.0, slot=9)
    mgr.step(9)
    mgr.step(10)
    fb = mgr.step(11, force_ack={(u, 0): False}) # NACK attempt 4 -> DROP!
    assert len(fb.dropped_transmissions) == 1
    assert fb.dropped_transmissions[0] == (u, 0, 1000)
    assert mgr.processes[u][0].state == ProcessState.IDLE
    assert mgr.dropped_bits == 1000
    assert mgr.delivered_bits == 0
    assert mgr.check_conservation()
