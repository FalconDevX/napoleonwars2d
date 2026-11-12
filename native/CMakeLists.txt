# Rozszerzenie C++ gry Wings of Empire: szybka pętla żołnierzy (SoldierKernel).
# Budowanie (Windows, MinGW + Ninja):  native\build.bat   ->  bin/wings_native.windows.template_release.x86_64.dll
cmake_minimum_required(VERSION 3.17)
project(wings_native LANGUAGES CXX)

set(GODOTCPP_TARGET "template_release" CACHE STRING "")
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../extern/godot-cpp ${CMAKE_BINARY_DIR}/godot-cpp)

add_library(wings_native SHARED
    src/register_types.cpp
    src/soldier_kernel.cpp
)
target_link_libraries(wings_native PRIVATE godot-cpp)
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

set_target_properties(wings_native PROPERTIES
    CXX_STANDARD 17
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
    PREFIX ""
    OUTPUT_NAME "wings_native${GODOTCPP_SUFFIX}"
    LIBRARY_OUTPUT_DIRECTORY "$<1:${CMAKE_CURRENT_SOURCE_DIR}/../bin>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_CURRENT_SOURCE_DIR}/../bin>"
)
if(MINGW)
    # bez zależności od bibliotek MinGW obok gry: wszystko wkompilowane statycznie
    target_link_options(wings_native PRIVATE -static -static-libgcc -static-libstdc++)
endif()
target_compile_options(wings_native PRIVATE -O2)
