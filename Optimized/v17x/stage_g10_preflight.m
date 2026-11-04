function pf = stage_g10_preflight(ctx) %#ok<INUSD>
% stage_g10_preflight  NOT IMPLEMENTED (stub). Must measure seconds per unit on 20 traces
% (or 20 episodes) and return struct('unit', 'eval' | 'episode', 'sec_per_unit', x,
% 'n_units_total', N, 'note', 'text'). The runner applies the 1.5x pause rule (common_rules.md R5).
    error('v17x:notImplemented', 'stage g10 is not implemented yet. Implement it from paper/proposals/G10_operating_grid_prereg.md (§2, §5 and §7) following the interface in Optimized/v17x/README_v17x_runner.md');
end
