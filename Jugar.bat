@echo off
rem Abre OpenAge-LAN directo desde el proyecto (sin exportar), con los últimos cambios.
set GODOT=%LOCALAPPDATA%\Temp\opencode\godot44\Godot_v4.4-stable_win64.exe
if not exist "%GODOT%" set GODOT=godot
start "" "%GODOT%" --path "%~dp0."
