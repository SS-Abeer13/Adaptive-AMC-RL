@echo off
title v17x ft
setlocal
cd /d "%~dp0"
set "STAGES=ft"
set "V17X_NO_POOL=1"
call run_v17x_all.bat
