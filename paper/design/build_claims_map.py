"""Build and validate paper/design/claims_map.csv.

Checks (fail with exit code 1):
  1. every claim ID exists in ledger/claims_ledger.csv (or is a `lit:` / `slot:` tag);
  2. a ledger row whose status contains 'withdrawn', 'superseded' or 'NOT USABLE' is used only in
     Section VII (pitfalls and corrective findings) -- no withdrawn or superseded result may be
     presented as valid elsewhere;
  3. rows whose status is 'pending' must name their slot.
Also prints ledger claims that are not placed anywhere (information, not an error).

Run from paper/:  python3 -I design/build_claims_map.py
"""
import csv, sys

LEDGER = 'ledger/claims_ledger.csv'
OUT = 'design/claims_map.csv'

# contribution, element (section / float), claim ids, short statement, status, wording rule
ROWS = [
 # ---------------- Introduction
 ('C2', 'I; F1', 'R06 R03 R04 R34', 'Thesis numbers: primary scheme +11.96 % vs OLLA family, +1.58 % vs Context table (+0.95 pp), +1.87 % vs Fixed', 'final; W1 may change the OLLA number', 'Quote the warm-up gain vs OLLA if its CI does not overlap the cold one (W1 §3)'),
 ('C1', 'I; VIII-A', 'R33', 'A calibrated constant or context offset already reaches 83-86 % of the RL gain over OLLA in M1', 'final (derived)', '"Reaches", not "explains"; absolute on-time points'),
 ('C1', 'I; II; T1', 'lit:lit_matrix.csv', 'Comparator gap: of 23 learning-based LA papers, 0 / 3 / 13 / 7 have a calibrated-rule baseline (yes / partial / no / unclear); information parity 5 / 1 / 3 / 14', 'final', 'Neutral; "unclear" = abstract-only; settings differ from ours'),
 ('C1', 'II', 'lit:gap_analysis.md', 'LOLLA positioning (setting differences; Table V(a) observation ablation 254/185/171 Mbps, arXiv 2606.23110v1); Doherty et al. JOCN 2025 as methodological precedent', 'final', 'Never imply LOLLA gains are artefacts; reporting recommendation, not criticism'),
 # ---------------- System model
 ('-', 'III-A; T3', 'S01 S02 S17', 'Cell, channel, speeds 3-30 m/s (f_d about 20-200 Hz at 2 GHz)', 'final', ''),
 ('-', 'III-B; T3', 'S03 S04 S11', 'CQI delay 2-8 TTI, 1 dB noise, bursts, OLLA reference loop (target 10 %, 0.5 dB down-step)', 'final', 'Describe OLLA as target 10 %, not "step 0.1/0.9"'),
 ('-', 'III-C; T3', 'S05 S06', 'Chase combining, 3 retransmissions; RTT 0/1 and RTT 8/8 processes; retransmissions reuse MCS', 'final', ''),
 ('-', 'III-D; F2b', 'S07', 'PF averaged at scheduling time with the scheduled rate (alpha 0.05)', 'final', 'State the definition explicitly'),
 ('-', 'III-E; T3', 'S09 S10', 'Deadline traffic 12 kbit/20 TTI/10-TTI budget; 200-TTI traces, 50-TTI burn-in, 500 evaluation traces', 'final', ''),
 # ---------------- Method
 ('C2', 'IV-A', 'S13 S13a', 'Residual delta in {-1,0,+1} on the better of Fixed/FixedPU; FixedPU is a class oracle that the residual inherits', 'final', 'Call FixedPU a class oracle'),
 ('C2', 'IV-B', 'S14 H15', 'Potential-based shaping c = 0.5 (v14 paired test +0.23 %, 90 % CI [0.14, 0.32], RTT 0 under the older PF; the unshaped variant also won; not re-tested at RTT 8); opportunity-cost reward for goodput', 'final', ''),
 ('C2', 'IV-C', 'S15 S16', 'Shared A2C, 57-128-96-3, 20,099 parameters; hyper-parameters', 'final', ''),
 ('C4', 'IV-D; VIII-B', 'S16', 'About 19.9 k MACs per user-decision', 'final; A3 adds wall time', ''),
 # ---------------- Protocol
 ('C1', 'V-A', 'M01 M02 P03', '67 cases / 108 scheme evaluations (49 cases from v10); fresh disjoint seeds and traces per round', 'final', 'Both views: 67 project-wide, 7 cases / 18 evaluations superseded, 49 from v10'),
 ('C1', 'V-B; T2', 'P04 S12 S13a', 'Nine comparators (7 distinct in M1); calibration budgets 20 / 10 traces; information table', 'final; G6 may add rows', '"Calibrated rules built on the learner\'s cues" until G6'),
 ('C1', 'V-C', 'S10 P03', 'Calibration / validation / evaluation traces disjoint; CRN', 'final', ''),
 ('C1', 'V-D', 'P01 P02 G3a', 'Holm + CI rule; Claim A/B/WIN; fairness guard; hierarchical seed x trace bootstrap reported beside the trace-level test', 'final', ''),
 ('C1', 'V-E', 'R29 M03 M04 M06', 'Failed secondary predictions; 9 of 60 valid cases with a WIN; M1 survives Bonferroni over 972 tests (p about 8.8e-10)', 'final', 'Use the approved multiplicity paragraph (multiplicity.md §6)'),
 # ---------------- Results
 ('C2', 'VI-A; T4; F3', 'R01 R02 R03 R04 R05 R06 R07 R08 R10 R11', 'M1: primary scheme beats all nine comparators; margins vs each; ensemble +4.56 %', 'final; wording conditional on G6', 'C2 reads "beats all calibrated comparators" only if the G6 combined comparator is beaten (G6 §4)'),
 ('C2', 'VI-B; F4', 'R09 G3a G3b G3c', '9/10 seeds above best rule; sign-test p = 0.011; hierarchical 95 % CI [+0.62, +2.62] %; trace-only CIs about 2.3x narrower', 'final', 'Report both trace-level and seed-level intervals'),
 ('C2', 'VI-C', 'R12 R13 R34', 'Fairness guard clear (Jain -0.0025, edge5 +1.2 %); goodput 4.45 vs 4.36 Mbps; +0.95 pp absolute', 'final', ''),
 ('C3', 'VI-D', 'R16 R17 R18 R28 G3e S08b H13 H14 H18', 'M2: +0.43 % vs Context (hierarchical 95 % CI [-0.03, +0.87] %); HARQ-timing ablation (deadline margins +1.58 -> +0.43 % vs Context, goodput swings < 1 pp); earlier RTT-0 wins used the delivered-bits PF', 'final', 'Replication only; "holds under both PF variants" limited to RTT-0 deadline wins'),
 ('C3', 'VI-E', 'R19 R19a R20 R21', 'Goodput: -0.88 % / -1.73 % vs Fixed; residual policy bit-identical to FixedPU in 5000/5000 cells at RTT 8, not at RTT 0', 'final', 'Define "identical" as metric identity (R19a); no action-share numbers'),
 ('C3', 'VI-F; F5a', 'R26 R27', 'Headroom: hindsight +3.4 % over Fixed in M1; ensemble exceeds the static bound', 'final', ''),
 ('C2', 'VI-F; F5b', 'R25 R14 R15 G3d G3f', 'Training-limited at 800 episodes; 800-episode result fragile under seed resampling; offset-800 fails Claim B', 'final', 'Do not cite resid-800 as support'),
 ('C2', 'VI-G; F6', 'slot:W1', 'Cold vs 200-TTI warm-up margins', 'pending: W1', 'W1 §3 rules'),
 ('C2', 'VI-G; F6', 'slot:G6', 'Re-calibrated rules (500 traces) and combined slack x class x busy-HARQ comparator', 'pending: G6', 'G6 §4 wording table'),
 ('C2', 'VI-G; F6', 'slot:NR1', 'Residual on a non-oracle Fixed base at RTT 8', 'pending: NR1', 'NR1 §4'),
 ('C2', 'VI-G; F6', 'slot:G10', 'Load x deadline grid under v17', 'pending: G10', 'G10 §4'),
 ('C3', 'VI-H; F7', 'slot:G1', 'delta shares on scheduled new transmissions by state bin', 'pending: G1', 'No mechanism sentence without a bin with >= 5 % of decisions and a consistent seed pattern'),
 ('C4', 'VI-H; F7', 'slot:A1', 'Results by speed class', 'pending: A1', ''),
 # ---------------- Pitfalls
 ('C4', 'VII-A; T5', 'H01 H02 H03 H04 H06', 'Mobility time scale (v metres per TTI): +12.8 % gain withdrawn; v9: 0/18 wins, A2C -4.08 % vs OLLA', 'withdrawn result, diagnosis valid', 'Present as self-correction recorded in the registry'),
 ('C4', 'VII-B; T5', 'H07', 'Slot stealing under a shared per-user reward: 1.38 vs 2.92 Mbps, bimodal -3/+2; opportunity-cost reward fixes it', 'final', ''),
 ('C4', 'VII-C; F8; T5', 'H17 H17a R30 R31 S08', 'PF-average timing under multi-process HARQ: Baseline +39.6 % (6-trace diagnostic); 10-26 % across schemes (confounded); Jain 0.50 -> 0.42; bit-exact consistency after the fix', 'final; A6 gives the controlled figure', 'Never "40 % for every scheme" (conflicts.md F1)'),
 ('C4', 'VII-D', 'S08a R22 H05', 'The sign of "open-loop vs OLLA" depends on the PF definition (v9 +4.5 %; v17 OLLA +7 %)', 'final', 'Protocol-sensitivity example, not a contribution; goodput negative result uses v17 only'),
 ('C4', 'VII-E; T5', 'H08 H09 H10 H11 H13 H19', 'Withdrawn or superseded: v10 E4 partial win (+0.21 %, n.s.) and E4c exploratory; v11 0/10; v12 replication failed; v13 X1 failed; 7 cases / 18 evaluations superseded', 'superseded/withdrawn; reported as such', 'Concise; registry in the supplement'),
 ('C4', 'VII-F', 'S16 R32', 'Recommendations incl. complexity and compute reporting', 'final', 'Reporting recommendation, not a criticism of any paper'),
 # ---------------- Discussion and conclusion
 ('C3', 'VIII-C', 'S13a R05 S12 M05 H16', 'Limitations: class-oracle inheritance (agent still beats FixedPU by +2.70 %); calibration-budget asymmetry; M2 marginal; the only earlier load x deadline grid (v14, RTT 0, older PF) was operating-point specific', 'final; G6/NR1 may change', ''),
 ('C1', 'IX; App. D', 'R32', 'Compute and release (about 6.3 h active compute; code, data summaries, pre-registrations, registry)', 'final', 'Release DOI at submission'),
]

NOT_USED = {  # intentionally absent from the manuscript
    'R23': 'action shares count all users per TTI; withheld until G1',
    'R24': 'state table mixes retransmissions; withheld until G1',
    'H12': 'pre-v17 headroom gate (v12 traces); superseded by R26',
}

def main():
    led = {r['claim_id']: r for r in csv.DictReader(open(LEDGER, newline=''))}
    errs, used = [], set()
    out = []
    for contrib, elem, ids, stmt, status, rule in ROWS:
        for cid in ids.split():
            if cid.startswith(('lit:', 'slot:')):
                continue
            if cid not in led:
                errs.append(f'unknown ledger ID {cid} in "{elem}"'); continue
            used.add(cid)
            st = led[cid]['valid/superseded']
            bad = any(w in st for w in ('withdrawn', 'superseded', 'NOT USABLE'))
            in_pitfalls = elem.startswith('VII')
            if bad and not in_pitfalls:
                errs.append(f'{cid} has status "{st}" but is placed in "{elem}" (only Section VII allowed)')
        if status.startswith('pending') and not any(i.startswith('slot:') for i in ids.split()):
            errs.append(f'pending row without slot tag: {elem}')
        out.append(dict(contribution=contrib, element=elem, claim_ids=ids, statement=stmt, status=status, wording_rule=rule))
    with open(OUT, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys())); w.writeheader(); w.writerows(out)
    unplaced = [c for c in led if c not in used and c not in NOT_USED]
    for c in NOT_USED:
        if c in used: errs.append(f'{c} is declared NOT_USED but is placed')
    print(f'{len(out)} map rows, {len(used)} ledger claims placed of {len(led)}')
    print('unplaced ledger claims:', ' '.join(unplaced) or 'none (besides NOT_USED: ' + ' '.join(NOT_USED) + ')')
    if errs:
        print('ERRORS:'); [print('  ', e) for e in errs]; sys.exit(1)
    print('validation OK')

if __name__ == '__main__':
    main()
