@echo off
chcp 65001 >nul
echo ========================================
echo   场景导入工具
echo ========================================
echo.

REM 查找 Godot 4 可执行文件
set GODOT=
where godot 2>nul && set GODOT=godot
if "%GODOT%"=="" (
    if exist "C:\Program Files\Godot\Godot_v4.4.1-stable_win64.exe" (
        set GODOT="C:\Program Files\Godot\Godot_v4.4.1-stable_win64.exe"
    )
)
if "%GODOT%"=="" (
    echo 找不到 Godot，请确保 godot 在 PATH 中，或修改此脚本中的路径
    pause
    exit /b 1
)

echo 使用 Godot: %GODOT%
echo.

REM 导入所有 world/stitched/ 下的子目录
for /d %%D in (world\stitched\*) do (
    echo 导入: %%~nxD
    %GODOT% --headless --path "%~dp0" --script res://scripts/import_stitched_world.gd -- --source "world/stitched/%%~nxD"
    echo.
)

echo ========================================
echo   全部导入完成！
echo ========================================
pause
