@echo off
if not exist build mkdir build

pushd build

robocopy ..\assets .\assets /s > nul
robocopy ..\lib . /s > nul

set exeName=Jam

set flags=-out:%exeName%.exe -max-error-count:5

if "%1" == "release" (
    echo "RELEASE"
    set flags=%flags% -o:speed -subsystem:windows 
) else (
    set flags=%flags% -o:none -debug
)

del %exeName%.exe

odin build ..\src\game -debug -build-mode=dll -out="Game.dll" -max-error-count:5 && ^
odin run ..\src\platform_win32 %flags%

popd