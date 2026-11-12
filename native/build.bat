@echo off
rem Buduje rozszerzenie C++ (bin\wings_native.windows.template_release.x86_64.dll) kompilatorem MinGW przez CMake i Ninja.
rem Wymaga: MinGW-w64 g++ (np. C:\msys64\mingw64\bin w PATH), CMake, Ninja, Python (generator godot-cpp).
setlocal
cd /d "%~dp0"
if not exist "..\extern\godot-cpp\CMakeLists.txt" (
    echo Brak extern\godot-cpp - uruchom: git submodule update --init
    exit /b 1
)
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=g++ -DGODOTCPP_TARGET=template_release || exit /b 1
cmake --build build --parallel || exit /b 1
echo Gotowe: bin\wings_native*.dll
