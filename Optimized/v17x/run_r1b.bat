@echo off
setlocal
cd /d "%~dp0"
set "STAGES=r1b_ack"
call run_v17x_all.bat
