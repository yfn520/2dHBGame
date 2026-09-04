@echo off
REM 统一 headless 测试入口的便捷包装：python tools/run_tests.py %*
setlocal
cd /d "%~dp0.."
python tools/run_tests.py %*
exit /b %errorlevel%
