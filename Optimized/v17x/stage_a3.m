function stage_a3(ctx) %#ok<INUSD>
% stage_a3  NOT IMPLEMENTED (stub). Inference wall time per decision and per TTI.
% Spec (frozen): paper/proposals/checkpoint5_list.md, prompt A3.
% Interface: function stage_a3(ctx): do all work through ctx.unit(name, @() ...) so
% that every unit is checkpointed; call ctx.hb('...') between chunks (client only, never
% inside parfor); throw an error on any failed check. No return value.
    error('v17x:notImplemented', 'stage a3 is not implemented yet. Implement it from paper/proposals/checkpoint5_list.md (prompt A3) following the interface in Optimized/v17x/README_v17x_runner.md');
end
