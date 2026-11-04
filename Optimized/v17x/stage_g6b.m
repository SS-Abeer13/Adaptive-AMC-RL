function stage_g6b(ctx) %#ok<INUSD>
% stage_g6b  NOT IMPLEMENTED (stub). G6 combined comparator (36 cells): coordinate ascent, 4 starts, run to convergence, sanity check, SHA-256 of the tables.
% Spec (frozen): paper/proposals/G6_calibration_budget_prereg.md, §2.3 and §7.
% Interface: function stage_g6b(ctx): do all work through ctx.unit(name, @() ...) so
% that every unit is checkpointed; call ctx.hb('...') between chunks (client only, never
% inside parfor); throw an error on any failed check. No return value.
    error('v17x:notImplemented', 'stage g6b is not implemented yet. Implement it from paper/proposals/G6_calibration_budget_prereg.md (§2.3 and §7) following the interface in Optimized/v17x/README_v17x_runner.md');
end
