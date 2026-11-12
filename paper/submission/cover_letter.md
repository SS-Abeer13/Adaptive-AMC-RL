[Date]

To the Editor-in-Chief,
IEEE Transactions on Machine Learning in Communications and Networking

**Submission: "When Does Deep Reinforcement Learning Help Link Adaptation? A Pre-Registered Evaluation Against Calibrated Rules"**

Dear Editor,

We submit the above manuscript for consideration as a regular paper in IEEE TMLCN.

**What the paper asks.** Many studies report that deep reinforcement learning (RL) improves link adaptation over outer-loop link adaptation (OLLA). A learner, however, usually sees more than OLLA does. We ask how much of the gain remains when the comparison also includes deterministic rules calibrated on the learner's own cues.

**What it finds.** In a simulated multi-user NR-like cell with multi-process HARQ:
- a residual actor-critic policy beats OLLA by a clear margin on deadline traffic;
- against rules re-calibrated on the same cues, most of that margin disappears, and the remainder of the pre-registered policy is not robust across training seeds;
- a residual policy on a non-oracle base rule, confirmed in a pre-registered replication on fresh traces and seeds, beats the strongest calibrated table robustly;
- on full-buffer goodput the learner adds nothing, although a pre-registered headroom analysis shows that one-step room existed.

**Why TMLCN.** The contribution is methodological as much as empirical. It is an evaluation protocol for machine learning in the radio access network: calibrated same-information comparators, common random numbers, disjoint splits, seed-level inference, pre-registered decision rules and wording, and multiplicity accounting over every case of the project. Failed predictions, withdrawn results and three simulation pitfalls are reported. We believe this fits the journal's interest in rigorous and reproducible ML for communications. The paper relates to recent TMLCN work on learned control in O-RAN.

**Artefacts.** The simulator, traces and seeds, per-trace and per-seed results, calibrated tables, the case registry, analysis scripts and the frozen pre-registration texts with their hashes will be released under [Zenodo DOI — to be inserted]. Every number in the manuscript is generated from these files.

**Declarations.**
- The manuscript is original, has not been published, and is not under consideration elsewhere. [If posted: a preprint is available at arXiv:[ID] with the IEEE notice on its first page.]
- Conflicts of interest: [none / to be completed].
- Funding: [to be completed].
- AI-assistance: disclosed in the Acknowledgments, following IEEE policy.

**Suggested reviewer profiles** (we leave the choice of individuals to the Editor):
1. Link adaptation and HARQ in 5G NR system-level simulation.
2. Reinforcement learning for radio resource management, including evaluation and baseline design.
3. Statistical evaluation of ML methods: seed variance, hierarchical resampling, multiple testing.
4. O-RAN systems and learned control placement (DU/dApp/xApp), with testbed experience.

[Optional: researchers we ask to be excluded, with a reason — to be completed by the authors.]

Thank you for considering our work.

Sincerely,
[Corresponding author name, affiliation, e-mail, ORCID]
on behalf of all authors
