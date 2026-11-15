@echo off
title v17x r1c
setlocal
cd /d "%~dp0"
set "STAGES=r1c"
set "V17X_NO_POOL=1"
call run_v17x_all.bat
