@echo off
rem Runs install.ps1 - example: install.cmd -DbUser GRP_TEST -Workspace GRP
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
