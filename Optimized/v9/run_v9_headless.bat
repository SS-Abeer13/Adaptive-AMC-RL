@echo off
title RL-AMC v9 campaign (headless MATLAB)
echo Started %date% %time%
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('D:\Adaptive AMC A2C+QL\Optimized\v9\run_v9_all.m')" -logfile "D:\Adaptive AMC A2C+QL\Optimized\v9\logs\matlab_batch.log"
echo Finished %date% %time% (exit code %errorlevel%)
pause
