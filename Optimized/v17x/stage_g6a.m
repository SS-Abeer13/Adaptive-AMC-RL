function stage_g6a(ctx) %#ok<INUSD>
% stage_g6a  NOT IMPLEMENTED (stub). G6 single-cue rules re-calibrated by exhaustive search on 500 traces (Fixed, FixedPU separable + joint refinement, Context 343 tables, OLLA-tuned 30 settings).
% Spec (frozen): paper/proposals/G6_calibration_budget_prereg.md, §2.2 and §7.
% Interface: function stage_g6a(ctx): do all work through ctx.unit(name, @() ...) so
% that every unit is checkpointed; call ctx.hb('...') between chunks (client only, never
% inside parfor); throw an error on any failed check. No return value.
    error('v17x:notImplemented', 'stage g6a is not implemented yet. Implement it from paper/proposals/G6_calibration_budget_prereg.md (§2.2 and §7) following the interface in Optimized/v17x/README_v17x_runner.md');
end
