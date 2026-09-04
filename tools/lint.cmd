@echo off
REM GDScript 语法/风格护栏（可选）。未安装 gdtoolkit 时给出指引并以 0 退出，不阻塞流程。
REM 安装：pip install gdtoolkit
setlocal
cd /d "%~dp0.."
where gdlint >nul 2>&1
if errorlevel 1 (
  echo [lint] 未安装 gdtoolkit，跳过。安装：pip install gdtoolkit
  exit /b 0
)
gdlint scripts tests
exit /b %errorlevel%
