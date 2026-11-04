@echo off
title RL-AMC v11-P2 campaign (headless MATLAB, auto-restart)
set ROOT=D:\Adaptive AMC A2C+QL\Optimized\v11
echo Started %date% %time%
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v11_P2_resume.m')" -logfile "%ROOT%\logs\matlab_P2_batch.log"
set /a TRY=1
:loop
findstr /C:"V11-P2 CAMPAIGN finished" "%ROOT%\Dataset\fill_summary_v11_P2.txt" >nul 2>&1 && goto done
if %TRY% GEQ 6 goto done
set /a TRY+=1
echo MATLAB exited before the campaign finished - restart %TRY% at %time% >> "%ROOT%\logs\restarts_P2.txt"
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('%ROOT%\run_v11_P2_resume.m')" -logfile "%ROOT%\logs\matlab_P2_batch_r%TRY%.log"
goto loop
:done
echo Finished %date% %time%
