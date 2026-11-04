function stage_g6c(ctx) %#ok<INUSD>
% stage_g6c  NOT IMPLEMENTED (stub). G6 evaluation on the M1 traces, REPRO, REPLCMP over 10 comparators, seed-level CIs, verdict row.
% Spec (frozen): paper/proposals/G6_calibration_budget_prereg.md, §3, §4 and §7.
% Interface: function stage_g6c(ctx): do all work through ctx.unit(name, @() ...) so
% that every unit is checkpointed; call ctx.hb('...') between chunks (client only, never
% inside parfor); throw an error on any failed check. No return value.
    error('v17x:notImplemented', 'stage g6c is not implemented yet. Implement it from paper/proposals/G6_calibration_budget_prereg.md (§3, §4 and §7) following the interface in Optimized/v17x/README_v17x_runner.md');
end
