@echo off
setlocal
cd /d "%~dp0"
if exist ".venv\Scripts\python.exe" goto run
where py >nul 2>nul
if not errorlevel 1 (
  py -3 -m venv .venv
) else (
  python -m venv .venv
)
if errorlevel 1 goto failed
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 goto failed
:run
start "" ".venv\Scripts\pythonw.exe" "%~dp0spotify_bridge.py"
echo Spotify companion runs in the background. Closing this window does not unlink it.
echo Your bridge key is in %%LOCALAPPDATA%%\Altair\Spotify\bridge.key
timeout /t 2 /nobreak >nul
if exist "%LOCALAPPDATA%\Altair\Spotify\bridge.key" type "%LOCALAPPDATA%\Altair\Spotify\bridge.key"
echo.
pause
exit /b
:failed
echo Install Python 3.10 or newer from python.org, then run this file again.
pause
exit /b 1
