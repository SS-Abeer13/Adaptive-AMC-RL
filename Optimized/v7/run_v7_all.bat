@echo off
REM ===========================================================================
REM  run_v7_all.bat -- the full v7 campaign, headless, one fresh MATLAB
REM  process per experiment (anti-degradation / crash isolation).
REM
REM  Order (pre-registered in V7_DESIGN_PLAN.md):
REM    smoke      pipeline check (minutes) - aborts campaign if it fails
REM    phase0     calm homogeneous anchor (expect RL ~ OLLA)
REM    hetero 0.5 / 1.0   heterogeneity family
REM    burst 6 / 9 / 12   burst-intensity family (hetero=1)
REM    tierA      info-equal state ablation at the headline point
REM    warm       converged-OLLA defense at the headline point
REM    replicate  fresh-seed replication of the headline point
REM  ('headline' itself = burst 9, saved under tag burst09dB + replicate)
REM
REM  Usage:  run_v7_all.bat            (everything)
REM          run_v7_all.bat quick      (smoke + phase0 + headline only)
REM  Resumable: completed points are skipped automatically.
REM  Progress:  type logs\v7_master_log.txt
REM ===========================================================================

setlocal
cd /d "%~dp0"
if "%MATLAB_EXE%"=="" set "MATLAB_EXE=matlab"

echo === v7 campaign starting. Log: logs\v7_master_log.txt

"%MATLAB_EXE%" -batch "run_v7_point('smoke')"
if errorlevel 1 (
    echo !!! SMOKE TEST FAILED - fix the pipeline before burning compute.
    exit /b 1
)

if /i "%1"=="quick" (
    "%MATLAB_EXE%" -batch "run_v7_point('phase0')"
    "%MATLAB_EXE%" -batch "run_v7_point('headline')"
    goto done
)

"%MATLAB_EXE%" -batch "run_v7_point('phase0')"
"%MATLAB_EXE%" -batch "run_v7_point('hetero',0.5)"
"%MATLAB_EXE%" -batch "run_v7_point('hetero',1)"
"%MATLAB_EXE%" -batch "run_v7_point('burst',6)"
"%MATLAB_EXE%" -batch "run_v7_point('burst',9)"
"%MATLAB_EXE%" -batch "run_v7_point('burst',12)"
"%MATLAB_EXE%" -batch "run_v7_point('tierA')"
"%MATLAB_EXE%" -batch "run_v7_point('warm')"
"%MATLAB_EXE%" -batch "run_v7_point('replicate')"

:done
echo.
echo === v7 campaign finished. Results in Dataset\, log in logs\v7_master_log.txt
endlocal
