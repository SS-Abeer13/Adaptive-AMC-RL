@echo off
rem ======================================================================
rem run_v17x_all.bat -- headless runner for the Checkpoint-5 stages
rem   G1 -> W1 -> NR1 -> G6a/b/c -> G10 -> A1/A3 -> A6   (approved order, Checkpoint 5b)
rem Restarts MATLAB after a crash; every stage and unit is checkpointed, so a
rem restart skips completed work. Never prints FINISHED unless MATLAB wrote
rem Dataset\FINISHED_ALL.marker (every requested stage done, no error marker).
rem
rem Exit codes: 0 finished | 2 halted (error marker) | 3 paused by the 1.5x rule
rem             4 gave up after MAX_RESTARTS native crashes | 5 unexpected
rem Options (set before calling, or edit the defaults below):
rem   MATLAB_EXE     path to matlab.exe
rem   STAGES         e.g. g1,w1,g6a,g6b,g6c,nr1,g10,a1,a3   (default: all, in this order)
rem   N_WORKERS      parfor workers (default 2; 4 ran out of memory in v17 M1)
rem   G6B_PROFILE    full (default, decided) or lite (defined, not used)
rem   G10_CELLS      default G2_hi_d10,G3_lo_d18 (the two pre-registered cells)
rem   V17X_SELFTEST  1, 2 or 3: dummy stages that test restart/halt/pause logic
rem   V17X_SMOKE     1 = tiny sizes, folders Dataset_smoke / logs_smoke
rem ======================================================================
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

if not defined MATLAB_EXE set "MATLAB_EXE=C:\Program Files\MATLAB\R2023a\bin\matlab.exe"
if not defined MAX_RESTARTS set "MAX_RESTARTS=60"
if not defined RESTART_WAIT_S set "RESTART_WAIT_S=60"
if not defined N_WORKERS set "N_WORKERS=2"
if not defined G6B_PROFILE set "G6B_PROFILE=full"

set "DS=Dataset"
set "LG=logs"
if defined V17X_SELFTEST if not "%V17X_SELFTEST%"=="0" (
    set "DS=Dataset_selftest"
    set "LG=logs_selftest"
)
if defined V17X_SMOKE if "%V17X_SMOKE%"=="1" (
    set "DS=Dataset_smoke"
    set "LG=logs_smoke"
)
if not exist "%LG%" mkdir "%LG%"
if not exist "%DS%" mkdir "%DS%"

rem Lock file to prevent duplicate runner instances
set "LOCKFILE=%DS%\runner.lock"
if exist "%LOCKFILE%" (
    tasklist /FI "IMAGENAME eq MATLAB.exe" 2>nul | findstr /i "MATLAB.exe" >nul
    if not errorlevel 1 (
        echo [%date% %time%] ERROR: Another runner instance is already active (MATLAB is running). Refusing to start.
        exit /b 1
    )
)
echo [%date% %time%] runner active > "%LOCKFILE%"

if not exist "%MATLAB_EXE%" (
    echo ERROR: MATLAB not found at "%MATLAB_EXE%". Set MATLAB_EXE.
    echo [%date% %time%] MATLAB not found > "%DS%\ERROR_runner.txt"
    if exist "%LOCKFILE%" del "%LOCKFILE%"
    exit /b 5
)

rem Launch watchdog in background if not already active
if exist "%~dp0watchdog_v17x.ps1" (
    start "v17x watchdog" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watchdog_v17x.ps1" -BaseDir "%~dp0" -LogsDir "%LG%" -DataDir "%DS%"
)

set /a N=0
set /a PN=%RESTART_WAIT_S%+1

:loop
set /a N+=1
echo [%date% %time%] launch !N! (STAGES=%STAGES% workers=%N_WORKERS% G6B_PROFILE=%G6B_PROFILE%) >> "%LG%\restarts_v17x.txt"
"%MATLAB_EXE%" -batch "run_v17x_all" -logfile "%LG%\matlab_batch_!N!.log"
set "RC=!ERRORLEVEL!"
echo [%date% %time%] launch !N! exit code !RC! >> "%LG%\restarts_v17x.txt"

if "!RC!"=="0" (
    if exist "%DS%\FINISHED_ALL.marker" goto :finished
    goto :unexpected
)
if "!RC!"=="2" goto :halted
if "!RC!"=="3" goto :paused
if !N! GEQ %MAX_RESTARTS% goto :giveup
echo [%date% %time%] MATLAB exited with code !RC!; restarting in %RESTART_WAIT_S% s (completed work is skipped)
rem ping is used instead of timeout because timeout fails when stdin is redirected
ping -n !PN! 127.0.0.1 >nul
goto :loop

:finished
echo [%date% %time%] ALL REQUESTED STAGES FINISHED. See %DS%\STATUS.txt
if exist "%LOCKFILE%" del "%LOCKFILE%"
exit /b 0

:halted
echo [%date% %time%] HALTED. A stage failed twice or is not implemented. See %DS%\HALTED.marker and %DS%\ERROR_*.txt
echo No finished marker was written.
if exist "%LOCKFILE%" del "%LOCKFILE%"
exit /b 2

:paused
echo [%date% %time%] PAUSED by the 1.5x rule. Read %DS%\PAUSED_*.txt; to continue create APPROVE_^<stage^>.txt in %DS% and rerun this file.
if exist "%LOCKFILE%" del "%LOCKFILE%"
exit /b 3

:giveup
echo [%date% %time%] GAVE UP after !N! launches without a clean exit. See %LG%\restarts_v17x.txt and %LG%\matlab_batch_*.log
echo [%date% %time%] gave up after !N! launches > "%DS%\ERROR_runner.txt"
if exist "%LOCKFILE%" del "%LOCKFILE%"
exit /b 4

:unexpected
echo [%date% %time%] MATLAB exited with code 0 but no FINISHED_ALL.marker exists. Not reporting success.
echo [%date% %time%] exit 0 without finished marker > "%DS%\ERROR_runner.txt"
if exist "%LOCKFILE%" del "%LOCKFILE%"
exit /b 5
