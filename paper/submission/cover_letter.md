[Date]

To the Editor-in-Chief,
IEEE Transactions on Machine Learning in Communications and Networking

**Submission: "A Residual Deep RL Policy for Link Adaptation Beats Calibrated Rules but Not a Supervised One-Step Learner: A Pre-Registered Simulation Study"**

Dear Editor,

We submit the above manuscript for consideration as a regular paper in IEEE TMLCN.

**What the paper asks.** Many studies report that deep reinforcement learning (RL) improves link adaptation over outer-loop link adaptation (OLLA). A learner, however, usually sees more than OLLA does. We ask what deep RL adds once it is compared with schemes that use the same gNB-observable cues: rules calibrated on those cues, rules designed from them, and a simpler learner trained on them.

**What it finds.** In one simulated multi-user NR-like cell with multi-process HARQ, for deadline traffic:
- a residual actor-critic policy on a non-oracle base rule, confirmed in a pre-registered replication on fresh traces and seeds, beats hand-designed state rules and, robustly across training seeds, the strongest calibrated table;
- a supervised one-step model of transmission success, a gradient-boosted classifier trained only on ACK/NACK logged under exploration, beats that RL policy: by 3.40 % of on-time packets with the same action set, and by 7.58 % when free to choose any offset;
- a pre-registered replication found the same across four calibration draws and, retrained per cell, at two neighbouring operating points;
- against OLLA alone the gain of the RL policy looks large, but rules calibrated on the learner's cues remove most of it; on full-buffer goodput the RL policy does worse than one calibrated offset.

We state the limits plainly. There is one simulator, and the tested points allow at most one retransmission before the deadline. The supervised learner needs exploration logging, whose cost we did not measure. The comparison of learners is not matched in action set or training budget. The one-step controls were added by amendment after the RL result was known, and their replication is the confirmatory test.

**Why TMLCN.** The contribution is methodological as much as empirical. It is an evaluation protocol for machine learning in the radio access network: calibrated same-information comparators, controls that compare a deep policy with a simpler learner on the same features, common random numbers, disjoint splits, seed-level inference, pre-registered decision rules and wording, and multiplicity accounting over all 104 cases and 179 scheme evaluations of the project. Failed predictions, withdrawn results, a recorded deviation and three simulation pitfalls are reported. We believe this fits the journal's interest in rigorous and reproducible ML for communications.

**Artefacts.** The simulator, traces and seeds, per-trace and per-seed results, calibrated tables, the one-step models and their exploration logs, the case registry, analysis scripts and the frozen pre-registration texts with their hashes will be released under [Zenodo DOI — to be inserted]. Every number in the manuscript is generated from these files.

**Declarations.**
- The manuscript is original, has not been published, and is not under consideration elsewhere. [If posted: a preprint is available at arXiv:[ID] with the IEEE notice on its first page.]
- Conflicts of interest: [none / to be completed].
- Funding: [to be completed].
- AI-assistance: disclosed in the Acknowledgments, following IEEE policy.

**Suggested reviewer profiles** (we leave the choice of individuals to the Editor):
1. Link adaptation and HARQ in 5G NR system-level simulation.
2. Reinforcement learning and contextual bandits for radio resource management, including evaluation and baseline design.
3. Statistical evaluation of ML methods: seed variance, hierarchical resampling, multiple testing, pre-registration.
4. O-RAN systems and learned control placement (DU/dApp/xApp), with testbed experience.

[Optional: researchers we ask to be excluded, with a reason — to be completed by the authors.]

Thank you for considering our work.

Sincerely,
[Corresponding author name, affiliation, e-mail, ORCID]
on behalf of all authors
