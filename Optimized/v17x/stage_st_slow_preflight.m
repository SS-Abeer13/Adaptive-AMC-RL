function pf = stage_st_slow_preflight(ctx) %#ok<INUSD>
% 0.3 s per evaluation is more than 1.5x the 0.095 s basis: must PAUSE.
    pf = struct('unit', 'eval', 'sec_per_unit', 0.30, 'n_units_total', 1000, 'note', 'self-test: deliberately slow');
end
