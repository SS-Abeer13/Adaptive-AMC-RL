# Round 2 skeleton: takeaways and topic sentences

Approve or edit these. Each line is the first sentence of a paragraph, with numbers filled in from the macros.


## Abstract

Link adaptation chooses a modulation and coding scheme for every transmission, from delayed feedback and, for latency-sensitive traffic, before packet deadlines expire. Deep reinforcement learning (RL) is increasingly proposed for this task, but it is usually compared only with outer-loop link adaptation (OLLA). It is therefore unclear how much of its reported gain comes from learning itself. We ask how much of RL's advantage survives stronger comparators. In a system-level simulator with multi-process HARQ and deadline traffic, we compare a residual actor-critic policy with three rungs of comparators: OLLA, rules calibrated on the RL policy's own inputs, and a supervised one-step learner trained only on ACK/NACK feedback. All controllers face the same traces, every decision rule was fixed before its test, and results are reported across training seeds. RL clearly beats OLLA and modestly beats the calibrated rules. The supervised learner, however, delivers more packets on time than RL, even when both choose from the same actions. When HARQ delay leaves little room for retransmission, a one-step learner is a strong alternative to deep RL, and learned link adaptation should be benchmarked against one.


## 1 Introduction

**Takeaway:** Every downlink transmission in LTE and 5G New Radio (NR) needs a modulation and coding scheme (MCS).

- Outer-loop link adaptation (OLLA) is robust but blind to context, which is why LA attracts machine learning.
- A gain over OLLA, however, cannot be credited to learning alone.
- We answer this question with a comparator ladder, in which each rung gives the comparator more of what the RL policy has.
- The answer depends on the rung, and on the top rung RL loses.
- Three contributions: the comparator ladder (Sections 4-5), the evidence on when deep RL pays off (Section 6), and practical guidance (Section 7).

## 2 Related work

**Takeaway:** Learned link adaptation is rarely tested against a rule calibrated on the learner's own inputs, and other fields show why that matters.

- [Rule-based link adaptation.] Rule-based LA has been refined for two decades, so a fair baseline is more than plain OLLA.
- [Learned link adaptation.] Bandits, deep RL and supervised models have all been applied to LA, usually against OLLA.
- [The baseline gap.] Few of these studies separate the value of learning from the value of extra inputs.
- [Lessons from other fields.] Tuned heuristics have matched published learning results elsewhere.

## 3 System model and problem

**Takeaway:** With an RTT of 8 TTIs and a deadline of 10 TTIs, a packet gets at most one retransmission.


*Simulated cell*

- One single-cell simulator produces every result, so its limits bound every claim.

*HARQ timing and traffic*

- The HARQ timing leaves room for only one retransmission before the deadline.

*The decision problem*

- Every controller does the same thing: it adds an integer offset a to the OLLA-corrected CQI q_ref, and the result selects the MCS (Fig.

## 4 Controllers compared

**Takeaway:** Each rung of the ladder gives the comparator more of what the RL policy has.


*Rung 1: OLLA*

- OLLA is the industrial reference, and it starts cold.

*Rung 2: calibrated rules*

- Calibrated rules give the comparator the RL policy's inputs without any learning.

*The RL policy*

- The RL policy learns a residual correction from delayed rewards, starting from the calibrated Fixed offset b.
- Two RL variants isolate its design choices.

*Rung 3: a supervised one-step learner*

- The supervised learner asks one question for each candidate offset: if I send this MCS now, how likely is an ACK?
- This simplicity has two costs.

## 5 Evaluation protocol

**Takeaway:** Every comparison is paired on the same traces and judged across training seeds, and we state openly which tests came first.

- [Paired traces.] Two controllers always face the same channels and packet arrivals, so a comparison is a paired difference per trace.
- [Two levels of uncertainty.] A practitioner trains one policy, so a win must survive a change of training seed.
- [Pre-registration and the order of tests.] Every decision rule was frozen before its run, but the campaign was not planned in one piece.

## 6 Climbing the comparator ladder

**Takeaway:** RL's advantage shrinks at each rung of the ladder and turns into a loss at the top.


*Rung 1: RL against OLLA*

- Against OLLA, RL looks strong, but much of the gap is OLLA's slow start and a missing calibration.

*Rung 2: RL against calibrated rules*

- Once the rules are calibrated well, the original policy's win becomes a coin flip across seeds.
- A better-designed RL policy still beats the calibrated rules robustly, although it sees less.
- What the policy learned is a deadline-aware gamble.

*Rung 3: RL against a supervised one-step learner*

- A supervised one-step learner trained on ACK/NACK beats RL.
- [Is it the action set? No.] The full learner may choose offsets that the RL policy cannot reach, so we gave RL the same range (RL-full).
- [Is it one lucky fit? No.] We refitted the learner on four independent calibration draws.
- [What does it cost?] The learner wins by being more selective, not by taking more risk, but it needs exploration.

*Where RL does not help*

- RL adds nothing where a static offset already captures the decision.

## 7 Discussion

**Takeaway:** A gain over OLLA was never evidence for RL: at the tested points, accurate one-step estimation bought more than sequential credit assignment.


*Why does a myopic learner win?*

- When only one retransmission fits, link adaptation is close to a one-shot trade-off, and supervised learning estimates that trade-off directly.
- The horizon is not the whole story, however.

*What this means in practice*

- [Calibrate first.] The largest effect in this study came from the comparator, not from the learner.
- [Try a one-step learner before deep RL.] A supervised success model needs no reward design, and here it beat RL.
- [Where it would run.] A per-slot MCS decision must be ready before each slot's grant.

*Limitations*

- One simulator.
- Order of the tests.
- Unmatched learners.
- Tested conditions.
- Oracle information.
- Ten seeds.
- An evaluation fault.

## 8 Conclusion

**Takeaway:** The rung decides the verdict: RL beats OLLA, barely beats calibrated rules, and loses to a supervised one-step learner.

- For practitioners, the lesson is to calibrate the rules first and to try a one-step learner before deep RL.
