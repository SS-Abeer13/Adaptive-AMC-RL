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
from sionna_env.env import SingleCellEnv


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


def test_measured_time_per_slot():
    """Measure and report execution time per slot with 10 users and HARQ manager."""
    num_slots = 300
    env = SingleCellEnv(
        num_users=10,
        traffic_type="deadline",
        episode_length=num_slots,
        seed=1001,
    )
    env.reset(seed=1001)

    t0 = time.perf_counter()
    for _ in range(num_slots):
        action = np.zeros(10, dtype=np.float32)
        env.step(action)
    elapsed_total_s = time.perf_counter() - t0

    ms_per_slot = (elapsed_total_s / num_slots) * 1000.0
    print(f"\n[BENCHMARK] Total time for {num_slots} slots: {elapsed_total_s*1000:.2f} ms")
    print(f"[BENCHMARK] Measured time per slot (10 users + HARQ): {ms_per_slot:.3f} ms/slot")

    # Must be reasonably fast on CPU (well under 20 ms per slot, target ~1-3 ms/slot)
    assert ms_per_slot < 20.0
