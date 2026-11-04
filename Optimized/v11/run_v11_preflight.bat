@echo off
title RL-AMC v11 preflight (headless MATLAB)
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('D:\Adaptive AMC A2C+QL\Optimized\v11\fill_v11_preflight.m')" -logfile "D:\Adaptive AMC A2C+QL\Optimized\v11\logs\matlab_preflight.log"
