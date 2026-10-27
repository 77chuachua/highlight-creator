@echo off
rem Voice Studio launcher. The app starts this; it can also be run by hand.
rem ASCII only + CRLF line endings on purpose: cmd reads an LF-only batch
rem file as a single line and every line after the first fails to run.
setlocal
set "HERE=%~dp0"
set "PY=%HERE%..\venv\Scripts\python.exe"

if not exist "%PY%" (
  echo [studio] plugin python not found: "%PY%" 1>&2
  echo [studio] run setup.bat in the plugin root first. 1>&2
  exit /b 2
)

chcp 65001 >nul
"%PY%" -X utf8 "%HERE%studio.py" %*
exit /b %errorlevel%
