@echo off
title Worm Rider - remove loader
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Play-WormRider.ps1" -RestoreOnly
pause
