@echo off
echo ========================================
echo   Import Worlds
echo ========================================
echo.

set GODOT=
where godot 2>nul && set GODOT=godot
if "%GODOT%"=="" (
    if exist "C:\Program Files\Godot\Godot_v4.4.1-stable_win64.exe" (
        set GODOT="C:\Program Files\Godot\Godot_v4.4.1-stable_win64.exe"
    )
)
if "%GODOT%"=="" (
    echo Cannot find Godot. Add to PATH or edit this script.
    pause
    exit /b 1
)

echo Using: %GODOT%
echo.

for /d %%D in (world\stitched\*) do (
    echo Importing: %%~nxD
    %GODOT% --headless --path "%~dp0" --script res://scripts/editor/import_stitched_world.gd -- --source "world/stitched/%%~nxD"
    echo.
)

echo ========================================
echo   Done!
echo ========================================
pause
