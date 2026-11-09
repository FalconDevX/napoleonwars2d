@echo off
rem Otwiera projekt Napoleon Wars 2D w edytorze Godota.
setlocal
set "GODOT=C:\game\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=C:\Lalka\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
    echo Nie znaleziono Godota. Popraw sciezke GODOT w pliku edytor.bat
    pause
    exit /b 1
)
start "" "%GODOT%" --editor --path "%~dp0."
