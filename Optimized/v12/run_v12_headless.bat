@echo off
title RL-AMC v12 replication (headless MATLAB, auto-restart)
set ROOT=D:\Adaptive AMC A2C+QL\Optimized\v12
echo Started %date% %time%
set /a TRY=0
:loop
findstr /C:"V12 CAMPAIGN finished" "%ROOT%\Dataset\fill_summary_v12.txt" >nul 2>&1 && goto done
if %TRY% GEQ 8 goto done
set /a TRY+=1
echo v12 start %TRY% at %date% %time% >> "%ROOT%\logs\restarts_v12.txt"
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v12_resume.m')" -logfile "%ROOT%\logs\matlab_v12_%TRY%.log"
goto loop
:done
echo Finished %date% %time%
