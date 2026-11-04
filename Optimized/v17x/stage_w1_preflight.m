function pf = stage_w1_preflight(ctx) %#ok<INUSD>
% stage_w1_preflight  NOT IMPLEMENTED (stub). Must measure seconds per unit on 20 traces
% (or 20 episodes) and return struct('unit', 'eval' | 'episode', 'sec_per_unit', x,
% 'n_units_total', N, 'note', 'text'). The runner applies the 1.5x pause rule (common_rules.md R5).
    error('v17x:notImplemented', 'stage w1 is not implemented yet. Implement it from paper/proposals/W1_warmup_prereg.md (§6 and §6b) following the interface in Optimized/v17x/README_v17x_runner.md');
end
