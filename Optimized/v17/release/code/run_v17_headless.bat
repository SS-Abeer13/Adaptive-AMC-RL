@echo off
title RL-AMC v17 campaign (headless MATLAB, auto-restart)
set ROOT=D:\Adaptive AMC A2C+QL\Optimized\v17
echo Started %date% %time%
set /a TRY=0
:loop
findstr /C:"V17 CAMPAIGN finished" "%ROOT%\Dataset\fill_summary_v17.txt" >nul 2>&1 && goto done
if %TRY% GEQ 40 goto done
set /a TRY+=1
echo v17 start %TRY% at %date% %time% >> "%ROOT%\logs\restarts_v17.txt"
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v17_resume.m')" -logfile "%ROOT%\logs\matlab_v17_%TRY%.log"
goto loop
:done
echo Finished %date% %time%
