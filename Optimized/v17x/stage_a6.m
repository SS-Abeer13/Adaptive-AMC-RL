function stage_a6(ctx) %#ok<INUSD>
% stage_a6  NOT IMPLEMENTED (stub). PF-timing demonstration: Baseline/OLLA/Fixed, ACK-time vs scheduling-time PF, 3 HARQ settings, 100 traces; gate test_equivalence_v17.
% Spec (frozen): paper/proposals/A6_pf_timing_prereg.md, §2 and §6.
% Interface: function stage_a6(ctx): all work through ctx.unit(name, @() ...); ctx.hb between chunks
% (client only, never inside parfor); error on any failed gate. Optional stage_a6_report(ctx) (common_rules.md R9).
    error('v17x:notImplemented', 'stage a6 is not implemented yet. Implement it from paper/proposals/A6_pf_timing_prereg.md (§2 and §6) following the interface in Optimized/v17x/README_v17x_runner.md');
end
