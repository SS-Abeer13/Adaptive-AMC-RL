@echo off
title RL-AMC v10e campaign (headless MATLAB, auto-restart)
set ROOT=D:\Adaptive AMC A2C+QL\Optimized\v10
set /a TRY=0
:loop
findstr /C:"V10E CAMPAIGN finished" "%ROOT%\Dataset\fill_summary_v10.txt" >nul 2>&1 && goto done
if %TRY% GEQ 6 goto done
set /a TRY+=1
echo v10e start %TRY% at %date% %time% >> "%ROOT%\logs\restarts_v10e.txt"
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "cd('%ROOT%'); fill_v10e_campaign" -logfile "%ROOT%\logs\matlab_v10e_%TRY%.log"
goto loop
:done
echo Finished %date% %time%
