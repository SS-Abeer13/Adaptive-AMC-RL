@echo off
title v17x campaign
cd /d "%~dp0"
set "STAGES=g6b,g6c,a1,a3,a6"
call run_v17x_all.bat
