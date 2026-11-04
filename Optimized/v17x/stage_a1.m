function stage_a1(ctx) %#ok<INUSD>
% stage_a1  NOT IMPLEMENTED (stub). Results by speed class (re-evaluation, writes per-user okU/resU, speed, delay).
% Spec (frozen): paper/proposals/checkpoint5_list.md, prompt A1.
% Interface: function stage_a1(ctx): do all work through ctx.unit(name, @() ...) so
% that every unit is checkpointed; call ctx.hb('...') between chunks (client only, never
% inside parfor); throw an error on any failed check. No return value.
    error('v17x:notImplemented', 'stage a1 is not implemented yet. Implement it from paper/proposals/checkpoint5_list.md (prompt A1) following the interface in Optimized/v17x/README_v17x_runner.md');
end
