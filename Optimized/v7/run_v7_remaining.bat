@echo off
REM ===========================================================================
REM  run_v7_remaining.bat -- resume from burst09dB, skipping completed points
REM  (smoke, phase0, hetero 0.5/1.0, burst 6 already done)
REM
REM  Remaining (4 points, ~5-6 hours):
REM    burst 9    -- HEADLINE environment
REM    burst 12   -- upper bound on non-stationarity
REM    tierA      -- info-equal state ablation
REM    warm       -- converged-OLLA defense
REM    replicate  -- fresh-seed replication (the final checkpoint)
REM ===========================================================================

setlocal
cd /d "%~dp0"
if "%MATLAB_EXE%"=="" set "MATLAB_EXE=matlab"

echo === Resuming v7 campaign (burst 9 onwards). Log: logs\v7_master_log.txt
echo.

"%MATLAB_EXE%" -batch "run_v7_point('burst',9)"
"%MATLAB_EXE%" -batch "run_v7_point('burst',12)"
"%MATLAB_EXE%" -batch "run_v7_point('tierA')"
"%MATLAB_EXE%" -batch "run_v7_point('warm')"
"%MATLAB_EXE%" -batch "run_v7_point('replicate')"

:done
echo.
echo === v7 remaining campaign finished. Results in Dataset\
echo === Check burst09dB for headline result (A2C vs FixedPU, the decision point).
endlocal
