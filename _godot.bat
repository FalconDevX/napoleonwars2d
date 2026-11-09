@echo off
rem Pomocniczy skrypt: znajduje Godota 4.7.2 (albo sciaga go do folderu godot\),
rem a przy pierwszym uruchomieniu importuje zasoby projektu.
rem Ustawia zmienne GODOT (okienkowy) i GODOT_CON (konsolowy). Wywolywany przez graj/serwer/edytor.bat.
set "GVER=4.7.2-stable"
set "GDIR=%~dp0godot"
set "GODOT="
set "GODOT_CON="

for %%D in ("%GDIR%" "C:\game" "C:\Lalka") do (
    if not defined GODOT if exist "%%~D\Godot_v%GVER%_win64.exe" if exist "%%~D\Godot_v%GVER%_win64_console.exe" (
        set "GODOT=%%~D\Godot_v%GVER%_win64.exe"
        set "GODOT_CON=%%~D\Godot_v%GVER%_win64_console.exe"
    )
)

if not defined GODOT (
    echo Nie znaleziono Godota %GVER% - pobieram ^(ok. 70 MB, tylko za pierwszym razem^)...
    if not exist "%GDIR%" mkdir "%GDIR%"
    curl -L --fail --progress-bar -o "%GDIR%\godot.zip" "https://github.com/godotengine/godot/releases/download/%GVER%/Godot_v%GVER%_win64.exe.zip"
    if errorlevel 1 (
        echo Pobieranie nie powiodlo sie. Sprawdz internet albo pobierz recznie z godotengine.org
        exit /b 1
    )
    tar -xf "%GDIR%\godot.zip" -C "%GDIR%"
    del "%GDIR%\godot.zip"
    set "GODOT=%GDIR%\Godot_v%GVER%_win64.exe"
    set "GODOT_CON=%GDIR%\Godot_v%GVER%_win64_console.exe"
)

if not exist "%GODOT%" (
    echo Rozpakowanie Godota nie powiodlo sie.
    exit /b 1
)

rem Pierwsze uruchomienie po sklonowaniu: brak cache .godot - import zasobow.
if not exist "%~dp0.godot\imported" (
    echo Pierwsze uruchomienie - importuje zasoby gry ^(chwile potrwa^)...
    "%GODOT_CON%" --headless --path "%~dp0." --import
)
exit /b 0
