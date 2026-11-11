@echo off
rem Uruchamia wersje przegladarkowa gry The Thin Line (build\web) na lokalnym serwerze i otwiera ja w przegladarce.
rem Najpierw trzeba ja wyeksportowac: Godot --headless --path . --export-release "Web" build/web/index.html
setlocal
if not exist "%~dp0build\web\index.html" (
    echo Brak build\web\index.html - najpierw wyeksportuj wersje Web.
    pause
    exit /b 1
)
start "" "http://127.0.0.1:8765/index.html"
python -m http.server 8765 --bind 127.0.0.1 --directory "%~dp0build\web"
