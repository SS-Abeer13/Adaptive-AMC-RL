function stage_g10(ctx) %#ok<INUSD>
% stage_g10  NOT IMPLEMENTED (stub). Load x deadline grid with per-cell recalibration of every comparator.
% Spec (frozen): paper/proposals/G10_operating_grid_prereg.md, §2, §5 and §7.
% Interface: function stage_g10(ctx): do all work through ctx.unit(name, @() ...) so
% that every unit is checkpointed; call ctx.hb('...') between chunks (client only, never
% inside parfor); throw an error on any failed check. No return value.
    error('v17x:notImplemented', 'stage g10 is not implemented yet. Implement it from paper/proposals/G10_operating_grid_prereg.md (§2, §5 and §7) following the interface in Optimized/v17x/README_v17x_runner.md');
end
