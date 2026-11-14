@echo off
setlocal
cd /d "%~dp0"
set "STAGES=r3_nr2diag,r1_gbt,r2_rule,r5_seeds"
call run_v17x_all.bat
