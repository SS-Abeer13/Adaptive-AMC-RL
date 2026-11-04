@echo off
title RL-AMC v16 campaign (headless MATLAB, auto-restart)
set ROOT=D:\Adaptive AMC A2C+QL\Optimized\v16
echo Started %date% %time%
set /a TRY=0
:loop
findstr /C:"V16 CAMPAIGN finished" "%ROOT%\Dataset\fill_summary_v16.txt" >nul 2>&1 && goto done
if %TRY% GEQ 40 goto done
set /a TRY+=1
echo v16 start %TRY% at %date% %time% >> "%ROOT%\logs\restarts_v16.txt"
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v16_resume.m')" -logfile "%ROOT%\logs\matlab_v16_%TRY%.log"
goto loop
:done
echo Finished %date% %time%
