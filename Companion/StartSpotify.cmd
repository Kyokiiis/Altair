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
".venv\Scripts\python.exe" -m pip install -r requirements.txt --target "%LOCALAPPDATA%\Altair\Spotify\dependencies" --upgrade
if errorlevel 1 goto failed
".venv\Scripts\python.exe" "%~dp0spotify_bridge.py" --install-startup
if errorlevel 1 goto failed
start "" ".venv\Scripts\pythonw.exe" "%LOCALAPPDATA%\Altair\Spotify\spotify_bridge.py"
echo Spotify companion runs in the background and starts at Windows sign-in.
echo In Altair, choose Connect Spotify. Volt pairs automatically.
echo Approve in your browser once. Reruns and restarts keep the saved link.
echo For other executors, the local key is in %%LOCALAPPDATA%%\Altair\Spotify\bridge.key

pause
exit /b
:failed
echo Install Python 3.10 or newer from python.org, then run this file again.
pause
exit /b 1
