@echo off
title RL-AMC v13 campaign (headless MATLAB, auto-restart)
set ROOT=D:\Adaptive AMC A2C+QL\Optimized\v13
echo Started %date% %time%
set /a TRY=0
:loop
findstr /C:"V13 CAMPAIGN finished" "%ROOT%\Dataset\fill_summary_v13.txt" >nul 2>&1 && goto done
if %TRY% GEQ 12 goto done
set /a TRY+=1
echo v13 start %TRY% at %date% %time% >> "%ROOT%\logs\restarts_v13.txt"
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v13_resume.m')" -logfile "%ROOT%\logs\matlab_v13_%TRY%.log"
goto loop
:done
echo Finished %date% %time%
