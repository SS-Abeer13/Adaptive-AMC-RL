@echo off
title RL-AMC v10 campaign (headless MATLAB, auto-restart)
set ROOT=D:\Adaptive AMC A2C+QL\Optimized\v10
echo Started %date% %time%
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v10_resume.m')" -logfile "%ROOT%\logs\matlab_batch.log"
set /a TRY=1
:loop
findstr /C:"V10 CAMPAIGN finished" "%ROOT%\Dataset\fill_summary_v10.txt" >nul 2>&1 && goto done
if %TRY% GEQ 6 goto done
set /a TRY+=1
echo MATLAB exited before the campaign finished - restart %TRY% at %time% >> "%ROOT%\logs\restarts.txt"
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v10_resume.m')" -logfile "%ROOT%\logs\matlab_batch_r%TRY%.log"
goto loop
:done
echo Finished %date% %time%
