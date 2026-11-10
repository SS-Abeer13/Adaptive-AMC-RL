@echo off
title v17x G10
cd /d "%~dp0"
if exist "Dataset\FINISHED_ALL.marker" del "Dataset\FINISHED_ALL.marker"
set "STAGES=g10"
set "V17X_NO_POOL=1"
call run_v17x_all.bat
