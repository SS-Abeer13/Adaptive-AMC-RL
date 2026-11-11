"""
Unit and integration tests for SingleCellEnv (Task D1, D3).

Tests:
  - Gymnasium API compliance (spaces, reset, step returns).
  - 10 users with speeds 3-30 m/s spanning speed classes 1, 2, 3.
  - Deadline traffic with packet arrivals, deadlines, and drops.
  - Full-buffer traffic with continuous transmissions.
  - Multi-process HARQ integration with RTT 8 and Chase combining.
  - Performance benchmark: measure execution time per slot.
"""

import time
import numpy as np
import pytest
import torch
from scipy.special import j0
from sionna_env.env import SingleCellEnv, ContinuousTDLChannel


def test_gymnasium_api():
    """Verify Gymnasium interface compliance and observation/action space shapes."""
    env = SingleCellEnv(num_users=10, traffic_type="deadline", episode_length=50, seed=42)
    obs, info = env.reset(seed=42)

    assert obs.shape == (10, 8)
    assert obs.dtype == np.float32
    assert "slot" in info
    assert env.observation_space.contains(obs)

    # Step with zero offset action
    action = np.zeros(10, dtype=np.float32)
    next_obs, reward, terminated, truncated, info = env.step(action)

    assert next_obs.shape == (10, 8)
    assert isinstance(reward, float)
    assert isinstance(terminated, bool)
    assert isinstance(truncated, bool)
    assert not terminated
    assert "delivered_bits" in info
    assert "dropped_bits" in info
    assert "total_offered" in info


def test_user_speeds_and_classes():
    """Verify 10 users have speeds between 3 and 30 m/s across the 3 speed classes."""
    env = SingleCellEnv(num_users=10, min_speed=3.0, max_speed=30.0)
    assert len(env.user_speeds) == 10
    assert env.user_speeds[0] == 3.0
    assert env.user_speeds[-1] == 30.0
    # Speed classes: 1 (<10 m/s), 2 (10-20 m/s), 3 (20-30 m/s)
    classes = env.user_speed_classes
    assert 1 in classes
    assert 2 in classes
    assert 3 in classes
    assert np.all(classes[env.user_speeds < 10.0] == 1)
    assert np.all(classes[(env.user_speeds >= 10.0) & (env.user_speeds <= 20.0)] == 2)
    assert np.all(classes[env.user_speeds > 20.0] == 3)


def test_deadline_traffic_run():
    """Run an entire episode with deadline traffic and assert bit conservation throughout."""
    env = SingleCellEnv(
        num_users=10,
        traffic_type="deadline",
        arrival_prob=0.5,
        deadline_slots=25,
        episode_length=60,
        seed=123,
    )
    obs, info = env.reset(seed=123)

    for slot in range(60):
        # Apply small random offset action in [-2, +1]
        action = np.random.uniform(-2.0, 1.0, size=10).astype(np.float32)
        obs, reward, terminated, truncated, info = env.step(action)
        assert env.harq.check_conservation(queued_bits=info["queued_bits"])

    assert terminated


def test_full_buffer_traffic_run():
    """Run an episode with full-buffer traffic."""
    env = SingleCellEnv(
        num_users=10,
        traffic_type="full_buffer",
        episode_length=50,
        seed=456,
    )
    obs, info = env.reset(seed=456)

    total_delivered = 0
    for slot in range(50):
        action = np.zeros(10, dtype=np.float32)
        obs, reward, terminated, truncated, info = env.step(action)
        total_delivered += info["delivered_bits"]

    assert total_delivered > 0
    assert terminated


def test_cqi_delay_and_noise():
    """Verify delayed and noisy CQI reporting mechanism."""
    cqi_delay = 3
    cqi_noise_std = 1.5
    env = SingleCellEnv(
        num_users=10,
        cqi_delay=cqi_delay,
        cqi_noise_std=cqi_noise_std,
        seed=789,
    )
    env.reset(seed=789)

    for _ in range(5):
        action = np.zeros(10, dtype=np.float32)
        env.step(action)

    rep_sinr = env._get_reported_cqi_sinr()
    target_idx = len(env.sinr_history) - 1 - cqi_delay
    delayed_true_sinr = env.sinr_history[target_idx]

    # Difference between reported and delayed true SINR should reflect noise
    diff = rep_sinr - delayed_true_sinr
    assert np.all(np.abs(diff) < 5.0 * cqi_noise_std)


def test_channel_time_correlation():
    """
    Verify channel slot-to-slot autocorrelation and cache-batch continuity (Task D follow-up 2).

    Requirements:
      - Primary case: Environment actual slot duration (0.5 ms at 30 kHz SCS) and carrier frequency (3.5 GHz).
      - Extra check: 1.0 ms slot duration at 2.0 GHz carrier frequency.
      - Speeds: 3, 15, and 30 m/s.
      - Estimate slot-to-slot autocorrelation over at least 200 slots (tested over 400 slots).
      - Compare with J_0(2*pi*f_d*tau) within a stated tolerance (tolerance = 0.05).
      - Check continuity across cache-batch boundaries (no reset or decorrelation jump).
      - The test must fail if the channel is redrawn per slot or per batch.
    """
    c = 299792458.0  # Speed of light [m/s]
    speeds = [3.0, 15.0, 30.0]
    batch_size = 50
    num_batches = 8
    num_slots = batch_size * num_batches  # 400 slots (>= 200 slots)
    tolerance = 0.05

    test_configs = [
        # (label, carrier_frequency, slot_duration_s)
        ("env_actual_3.5GHz_0.5ms", 3.5e9, 0.5e-3),  # Environment's actual: 3.5 GHz, 0.5 ms (30 kHz SCS)
        ("extra_check_2.0GHz_1.0ms", 2.0e9, 1.0e-3),  # Extra check: 2.0 GHz, 1.0 ms (15 kHz SCS)
    ]

    for label, fc, tau in test_configs:
        print(f"\n=== Running test_channel_time_correlation [{label}]: fc={fc/1e9:.1f} GHz, tau={tau*1e3:.1f} ms ===")
        gen = ContinuousTDLChannel(
            speeds=speeds,
            carrier_frequency=fc,
            model="A",
            delay_spread=30e-9,
            num_sinusoids=20,
            slot_duration_s=tau,
            seed=20261111,
        )

        # 1. Generate channel realizations across cache-batch boundaries
        batches = []
        for b in range(num_batches):
            h_b, _ = gen.generate_block(start_slot=b * batch_size, num_slots=batch_size)
            batches.append(h_b)

        # Concatenate across time to form continuous channel history: [3 users, 23 clusters, 400 slots]
        full_h = torch.cat(batches, dim=-1).numpy()

        for u, v in enumerate(speeds):
            fd = v * fc / c
            expected_j0 = float(j0(2.0 * np.pi * fd * tau))

            # Tap 0 complex channel trajectory across 400 slots
            tap0 = full_h[u, 0, :]
            p_avg = np.mean(np.abs(tap0) ** 2)

            # Estimate slot-to-slot autocorrelation over all slots
            r1_overall = float(np.mean(np.real(tap0[1:] * np.conj(tap0[:-1]))) / p_avg)

            # Verify against J0(2*pi*fd*tau) within stated tolerance
            diff = abs(r1_overall - expected_j0)
            print(f"[{label} CORRELATION] v={v:4.1f} m/s | fd={fd:6.1f} Hz | J0={expected_j0:.4f} | R1={r1_overall:.4f} | diff={diff:.4f}")
            assert diff <= tolerance, (
                f"[{label}] Autocorrelation mismatch for speed {v} m/s: "
                f"estimated R1={r1_overall:.4f}, expected J0={expected_j0:.4f}, diff={diff:.4f} > {tolerance}"
            )

            # 2. Check continuity across cache-batch boundaries (no reset or decorrelation jump)
            within_steps = []
            for b in range(num_batches):
                b_tap = tap0[b * batch_size : (b + 1) * batch_size]
                within_steps.extend(np.abs(np.diff(b_tap)))
            mean_within_step = float(np.mean(within_steps))

            boundary_steps = [
                float(np.abs(tap0[b * batch_size] - tap0[b * batch_size - 1]))
                for b in range(1, num_batches)
            ]
            mean_boundary_step = float(np.mean(boundary_steps))

            # Step size across cache-batch boundaries must be consistent with within-batch evolution
            step_ratio = mean_boundary_step / (mean_within_step + 1e-12)
            print(f"[{label} CONTINUITY] v={v:4.1f} m/s | within_step={mean_within_step:.4f} | boundary_step={mean_boundary_step:.4f} | ratio={step_ratio:.2f}")
            assert step_ratio < 1.6, f"[{label}] Boundary jump detected for v={v} m/s: ratio={step_ratio:.2f} >= 1.6"

            # Check exact mathematical identity across boundary:
            # A single call across boundary (slot idx-1 to idx) must match separate batch calls to numerical precision
            for b in range(1, num_batches):
                idx = b * batch_size
                h_direct, _ = gen.generate_block(start_slot=idx - 1, num_slots=2)
                assert np.allclose(tap0[idx - 1], h_direct[u, 0, 0].item(), atol=1e-5)
                assert np.allclose(tap0[idx], h_direct[u, 0, 1].item(), atol=1e-5)

    # 3. Negative check: Verify that redrawing per batch fails the continuity test
    # Simulate a channel redrawn at each batch boundary
    fc_neg, tau_neg = test_configs[0][1], test_configs[0][2]
    rng_neg = np.random.default_rng(999)
    redrawn_batches = []
    for _ in range(num_batches):
        indep_gen = ContinuousTDLChannel(
            speeds=[speeds[0]], carrier_frequency=fc_neg, model="A", slot_duration_s=tau_neg,
            seed=int(rng_neg.integers(1, 1000000)),
        )
        h_indep, _ = indep_gen.generate_block(start_slot=0, num_slots=batch_size)
        redrawn_batches.append(h_indep)

    redrawn_h = torch.cat(redrawn_batches, dim=-1).numpy()
    redrawn_tap0 = redrawn_h[0, 0, :]
    redrawn_boundary_steps = [
        float(np.abs(redrawn_tap0[b * batch_size] - redrawn_tap0[b * batch_size - 1]))
        for b in range(1, num_batches)
    ]
    redrawn_within_steps = []
    for b in range(num_batches):
        b_tap = redrawn_tap0[b * batch_size : (b + 1) * batch_size]
        redrawn_within_steps.extend(np.abs(np.diff(b_tap)))

    redrawn_step_ratio = np.mean(redrawn_boundary_steps) / np.mean(redrawn_within_steps)
    # Redrawn-per-batch channel produces a massive decorrelation jump (> 3x step ratio at boundaries)
    assert redrawn_step_ratio > 3.0, "Redrawn per batch should produce a significant decorrelation jump"

    # 4. Negative check: Verify that redrawing per slot fails the J0 autocorrelation test
    indep_per_slot = rng_neg.normal(0, 1, size=400) + 1j * rng_neg.normal(0, 1, size=400)
    r1_indep = np.mean(np.real(indep_per_slot[1:] * np.conj(indep_per_slot[:-1]))) / np.mean(np.abs(indep_per_slot) ** 2)
    j0_expected = float(j0(2.0 * np.pi * (speeds[0] * fc_neg / c) * tau_neg))
    assert abs(r1_indep - j0_expected) > 0.5, "Redrawn per slot should fail J0 autocorrelation test"


def test_measured_time_per_slot():
    """
    Measure and report execution time per slot both including and excluding channel generation.
    """
    num_slots = 300

    # 1. Benchmark including channel generation (slots advance across cache boundaries)
    env_inc = SingleCellEnv(
        num_users=10,
        traffic_type="deadline",
        episode_length=num_slots,
        cache_batch_size=50,
        seed=1001,
    )
    env_inc.reset(seed=1001)

    # Warmup
    for _ in range(20):
        env_inc.step(np.zeros(10, dtype=np.float32))

    t0 = time.perf_counter()
    for _ in range(num_slots):
        action = np.zeros(10, dtype=np.float32)
        env_inc.step(action)
    elapsed_inc_s = time.perf_counter() - t0
    ms_per_slot_inc = (elapsed_inc_s / num_slots) * 1000.0

    # 2. Benchmark excluding channel generation (pre-cached channel powers)
    env_exc = SingleCellEnv(
        num_users=10,
        traffic_type="deadline",
        episode_length=num_slots,
        cache_batch_size=1000,
        seed=1001,
    )
    env_exc.reset(seed=1001)

    # Warmup
    for _ in range(20):
        env_exc.step(np.zeros(10, dtype=np.float32))

    t0 = time.perf_counter()
    for _ in range(num_slots):
        action = np.zeros(10, dtype=np.float32)
        env_exc.step(action)
    elapsed_exc_s = time.perf_counter() - t0
    ms_per_slot_exc = (elapsed_exc_s / num_slots) * 1000.0

    print(f"\n[BENCHMARK] Measured time per slot (including channel generation): {ms_per_slot_inc:.3f} ms/slot")
    print(f"[BENCHMARK] Measured time per slot (excluding channel generation): {ms_per_slot_exc:.3f} ms/slot")

    # Assert both run well within practical simulation budgets
    assert ms_per_slot_inc < 20.0
    assert ms_per_slot_exc < 20.0
