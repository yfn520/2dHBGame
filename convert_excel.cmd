@echo off
chcp 65001 >nul
echo ========================================
echo   Excel → JSON 配置表转换工具
echo ========================================
echo.
python tools/excel_to_json.py
echo.
echo ========================================
echo   完成！
echo ========================================
pause
