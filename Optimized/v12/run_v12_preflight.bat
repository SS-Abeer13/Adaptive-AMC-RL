@echo off
title RL-AMC v12 preflight (headless MATLAB)
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "run('D:\Adaptive AMC A2C+QL\Optimized\v12\fill_v12_preflight.m')" -logfile "D:\Adaptive AMC A2C+QL\Optimized\v12\logs\matlab_v12_preflight.log"
