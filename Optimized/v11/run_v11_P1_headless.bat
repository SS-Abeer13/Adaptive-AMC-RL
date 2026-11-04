@echo off
title RL-AMC v11-P1 campaign (headless MATLAB, auto-restart)
set ROOT=D:\Adaptive AMC A2C+QL\Optimized\v11
echo Started %date% %time%
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v11_P1_resume.m')" -logfile "%ROOT%\logs\matlab_P1_batch.log"
set /a TRY=1
:loop
findstr /C:"V11-P1 CAMPAIGN finished" "%ROOT%\Dataset\fill_summary_v11_P1.txt" >nul 2>&1 && goto done
if %TRY% GEQ 6 goto done
set /a TRY+=1
echo MATLAB exited before the campaign finished - restart %TRY% at %time% >> "%ROOT%\logs\restarts_P1.txt"
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v11_P1_resume.m')" -logfile "%ROOT%\logs\matlab_P1_batch_r%TRY%.log"
goto loop
:done
echo Finished %date% %time%
