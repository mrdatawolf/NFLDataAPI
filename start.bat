@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set MIN_NODE_MAJOR=18

echo == NFLDataAPI prelaunch check ==

where node >nul 2>nul
if errorlevel 1 (
  echo ERROR: Node.js is not installed or not on PATH.
  echo Install Node.js %MIN_NODE_MAJOR%+ from https://nodejs.org/ and re-run this script.
  pause
  exit /b 1
)

for /f "tokens=*" %%v in ('node -p "process.versions.node.split('.')[0]"') do set NODE_MAJOR=%%v
if !NODE_MAJOR! LSS %MIN_NODE_MAJOR% (
  echo ERROR: Node.js %MIN_NODE_MAJOR%+ is required. Found:
  node -v
  echo Install a newer Node.js from https://nodejs.org/ and re-run this script.
  pause
  exit /b 1
)
echo|set /p="Node OK: "
node -v

where npm >nul 2>nul
if errorlevel 1 (
  echo ERROR: npm was not found even though Node.js is installed. Reinstall Node.js from https://nodejs.org/.
  pause
  exit /b 1
)

if not exist ".env" (
  if exist ".env.example" (
    echo No .env found - creating one from .env.example
    copy /y ".env.example" ".env" >nul
  ) else (
    echo WARNING: no .env or .env.example found; the app will use its built-in defaults.
  )
)

set NEED_INSTALL=0
if not exist "node_modules" set NEED_INSTALL=1
if not exist "node_modules\.package-lock.json" set NEED_INSTALL=1
if not exist "node_modules\.bin\tsc.cmd" set NEED_INSTALL=1
if not exist "node_modules\.bin\vite.cmd" set NEED_INSTALL=1

if !NEED_INSTALL! EQU 1 (
  echo Installing dependencies ^(npm install^)...
  call npm install
  if errorlevel 1 (
    echo ERROR: npm install failed. See the output above for details.
    pause
    exit /b 1
  )
) else (
  echo Dependencies already installed
)

echo Building...
call npm run build
if errorlevel 1 (
  echo ERROR: Build failed. See the output above for details.
  pause
  exit /b 1
)

set PORT_VALUE=3002
if exist ".env" (
  for /f "usebackq tokens=1,* delims==" %%a in (`findstr /b /r "^APIPORT=" ".env"`) do set PORT_VALUE=%%b
)

echo == Starting NFLDataAPI on port !PORT_VALUE! ==

start "NFLDataAPI" cmd /k npm start

set TRIES=0
:waitloop
curl -s -o nul -w "%%{http_code}" http://localhost:!PORT_VALUE!/health > "%TEMP%\nfldata_health.txt" 2>nul
set /p HEALTH_CODE=<"%TEMP%\nfldata_health.txt"
if "!HEALTH_CODE!"=="200" (
  echo Server is up at http://localhost:!PORT_VALUE!
  start "" "http://localhost:!PORT_VALUE!"
  goto done
)
set /a TRIES+=1
if !TRIES! GEQ 60 (
  echo WARNING: server did not report healthy within 60s. It may still be starting ^(e.g. running the initial ingest^) - check the NFLDataAPI window for errors.
  goto done
)
timeout /t 1 >nul
goto waitloop

:done
del "%TEMP%\nfldata_health.txt" >nul 2>nul
endlocal
