@echo off
cd /d "%~dp0"
python motor_panel.py %*
if errorlevel 1 pause
