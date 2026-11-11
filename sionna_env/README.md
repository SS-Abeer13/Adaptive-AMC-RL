# sionna_env

Plan 2 Prototype: Gymnasium-style single-cell 5G NR environment with a multi-process HARQ manager.

## Scope & Capabilities (Task D)

- **Single-cell environment (`SingleCellEnv`)**:
  - $N = 10$ active users in a single gNodeB cell.
  - Stochastic 3GPP channels: 3GPP TR 38.901 TDL (models A–E) with Doppler shifts for user speeds $3\dots 30\text{ m/s}$ (speed classes 1, 2, 3: $< 10\text{ m/s}$, $10-20\text{ m/s}$, $20-30\text{ m/s}$).
  - CQI reports with feedback delay ($D_{\text{cqi}} \ge 0$ slots) and measurement noise ($\sigma_{\text{cqi}}$ dB).
  - Two traffic modes:
    - `deadline`: Poisson/burst arrivals, finite payload, deadline slack, expiration drops.
    - `full_buffer`: Infinite backlogged traffic.
- **Multi-Process HARQ Manager (`HARQManager`)**:
  - 8 parallel Stop-and-Wait HARQ processes per user.
  - RTT feedback delay of 8 slots (or configurable, including $\text{RTT} = 0$).
  - Stored MCS / TBS retained across retransmissions.
  - Chase combining (HARQ-CC) in the effective-SINR domain: $\Gamma_{\text{combined}} = \sum_k \gamma_k$ (linear scale).
  - At most 3 retransmissions (max 4 attempts total: 1 initial + up to 3 retries).
  - Both Proportional Fair (PF) running average throughput update definitions:
    - `'scheduling_time'`: updated at slot $t$ with scheduled bits.
    - `'ack_time'`: updated at slot $t$ with delivered (ACKed) bits.
  - Strict bit conservation invariant verified every slot:
    $$\text{delivered\_bits} + \text{dropped\_bits} + \text{in\_flight\_bits} + \text{queued\_bits} == \text{offered\_bits}$$
  - Direct reduction to Sionna's per-slot instantaneous ACK model when $\text{RTT} = 0$ and 1 process.

## Performance Benchmark

- **Environment setup:** 10 users, 51 resource blocks, TDL-A channel fading, CQI reporting delay 2 slots, 8 HARQ processes/user, RTT 8 slots.
- **Measured execution speed:** **$\approx 0.79\text{ ms per slot}$** on a single CPU thread (~1265 slots/second).

## Running Tests

```bash
pytest sionna_env/tests -v
```
All 13 unit tests pass.
