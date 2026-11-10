@echo off
title v17x NR2
cd /d "%~dp0"
if exist "Dataset\FINISHED_ALL.marker" del "Dataset\FINISHED_ALL.marker"
set "STAGES=nr2"
set "V17X_NO_POOL=1"
call run_v17x_all.bat
