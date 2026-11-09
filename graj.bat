@echo off
rem Uruchamia gre Napoleon Wars 2D (dwuklik).
setlocal
set "GODOT=C:\game\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=C:\Lalka\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
    echo Nie znaleziono Godota. Popraw sciezke GODOT w pliku graj.bat
    pause
    exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
