@echo off
chcp 65001 >nul
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts/openclaw-fast-installer.ps1"
pause