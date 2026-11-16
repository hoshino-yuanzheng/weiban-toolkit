@echo off
setlocal
cd /d "%~dp0"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%PS%" (
    echo.
    echo  [X] Windows PowerShell not found.
    echo      This tool requires Windows PowerShell 5.1 or later.
    echo      Windows 10 / 11 include it by default.
    echo.
    pause
    exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0guide.ps1"

if errorlevel 1 (
    echo.
    echo  [X] The script exited with an error.
    echo      Please take a screenshot of this window.
)
echo.
pause
