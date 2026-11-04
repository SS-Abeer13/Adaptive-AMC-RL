function stage_nr1(ctx) %#ok<INUSD>
% stage_nr1  NOT IMPLEMENTED (stub). Residual A2C on a non-oracle (Fixed) base at RTT 8: calib check, 10 seeds, eval.
% Spec (frozen): paper/proposals/NR1_nonoracle_residual_prereg.md, §3 and §6a.
% Interface: function stage_nr1(ctx): do all work through ctx.unit(name, @() ...) so
% that every unit is checkpointed; call ctx.hb('...') between chunks (client only, never
% inside parfor); throw an error on any failed check. No return value.
    error('v17x:notImplemented', 'stage nr1 is not implemented yet. Implement it from paper/proposals/NR1_nonoracle_residual_prereg.md (§3 and §6a) following the interface in Optimized/v17x/README_v17x_runner.md');
end
