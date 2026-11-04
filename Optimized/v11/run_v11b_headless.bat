@echo off
title RL-AMC v11b campaign (headless MATLAB, auto-restart)
set ROOT=D:\Adaptive AMC A2C+QL\Optimized\v11
set /a TRY=0
:loop
findstr /C:"V11B CAMPAIGN finished" "%ROOT%\Dataset\fill_summary_v11.txt" >nul 2>&1 && goto done
if %TRY% GEQ 6 goto done
set /a TRY+=1
echo v11b start %TRY% at %date% %time% >> "%ROOT%\logs\restarts_v11b.txt"
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "cd('%ROOT%'); fill_v11b_campaign" -logfile "%ROOT%\logs\matlab_v11b_%TRY%.log"
goto loop
:done
echo Finished %date% %time%
