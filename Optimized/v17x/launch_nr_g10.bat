@echo off
title v17x NR-G10
cd /d "%~dp0"
if exist "Dataset\FINISHED_ALL.marker" del "Dataset\FINISHED_ALL.marker"
set "STAGES=nr_g10"
call run_v17x_all.bat
