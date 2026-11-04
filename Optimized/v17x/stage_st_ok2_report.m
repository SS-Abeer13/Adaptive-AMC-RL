function stage_st_ok2_report(ctx) %#ok<INUSD>
% Self-test: a report that FAILS; the stage must stay done and the run must still finish.
    error('v17x:selftest', 'deliberate report failure');
end
