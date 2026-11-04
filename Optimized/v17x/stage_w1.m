function stage_w1(ctx) %#ok<INUSD>
% stage_w1  NOT IMPLEMENTED (stub). Warm-up robustness of the M1 comparison. Units: comparators_det, bandit_seed_K (10), a2c_seed_K (10), ens, repro20, secondary_recal.
% Spec (frozen): paper/proposals/W1_warmup_prereg.md, §6 and §6b.
% Interface: function stage_w1(ctx): do all work through ctx.unit(name, @() ...) so
% that every unit is checkpointed; call ctx.hb('...') between chunks (client only, never
% inside parfor); throw an error on any failed check. No return value.
    error('v17x:notImplemented', 'stage w1 is not implemented yet. Implement it from paper/proposals/W1_warmup_prereg.md (§6 and §6b) following the interface in Optimized/v17x/README_v17x_runner.md');
end
