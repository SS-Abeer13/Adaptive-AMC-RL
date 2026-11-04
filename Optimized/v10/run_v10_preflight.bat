@echo off
title RL-AMC v10 preflight (headless MATLAB)
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('D:\Adaptive AMC A2C+QL\Optimized\v10\fill_v10_preflight.m')" -logfile "D:\Adaptive AMC A2C+QL\Optimized\v10\logs\matlab_preflight.log"
