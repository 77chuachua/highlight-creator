@echo off
rem Debug launcher: run the studio from THIS checkout while using the engine
rem you already installed (venv + model + worker) and the ffmpeg that ships
rem with the repo.
rem
rem Why it exists: studio.bat sits inside the plugin and finds the engine next
rem to itself; here there is no engine beside the source, and ffmpeg is not on
rem PATH. Everything is spelled out instead of guessed.
rem
rem ASCII only + CRLF line endings on purpose: cmd reads an LF-only batch file
rem as a single line and every line after the first fails to run.
rem
rem Port 17322 so it can run beside the normal studio on 17321, and no idle
rem timeout so it does not vanish while you are editing. Extra arguments are
rem forwarded, so "--port 0" or "--idle-minutes 15" still override.
setlocal
set "HERE=%~dp0"
set "PLUGIN=%USERPROFILE%\HighlightCreator\voice_clone"
set "PY=%PLUGIN%\venv\Scripts\python.exe"
set "FFMPEG=%HERE%..\..\ffmpeg\ffmpeg.exe"

if not exist "%PY%" (
  echo [studio-debug] installed plugin not found:
  echo   %PLUGIN%
  echo [studio-debug] run tools\voice_clone\setup.bat once, then retry.
  exit /b 2
)
if not exist "%FFMPEG%" (
  echo [studio-debug] ffmpeg not found:
  echo   %FFMPEG%
  exit /b 2
)

rem Models and worker come from the installed plugin; studio.py/html come from
rem this folder, so edits take effect on the next launch.
set "HIGHLIGHT_STUDIO_PLUGIN=%PLUGIN%"
chcp 65001 >nul
echo [studio-debug] source: %HERE%
echo [studio-debug] engine: %PLUGIN%
echo [studio-debug] ffmpeg: %FFMPEG%
"%PY%" -X utf8 "%HERE%studio.py" --port 17322 --idle-minutes 0 --ffmpeg "%FFMPEG%" %*
exit /b %errorlevel%
