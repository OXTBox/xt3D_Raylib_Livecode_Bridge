@echo off
rem xt3d build: run from the "x64 Native Tools Command Prompt for VS 2022", with LiveCode closed.
rem Compiles the shim, checks the DLL, and copies the DLL and xt3d.lcb into the extension folder.
setlocal
cd /d "%~dp0"
set RAYLIB=raylib-6.2_win64_msvc16

if not exist "%RAYLIB%\lib\raylib.lib" (
  echo ERROR: %RAYLIB%\lib\raylib.lib not found. Edit the RAYLIB line in build.bat.
  exit /b 1
)

echo === Compiling xt3d.dll
cl /nologo /O2 /MD /LD /TC xt3d_shim.c /I "%RAYLIB%\include" /Fe:xt3d.dll /link "%RAYLIB%\lib\raylib.lib" opengl32.lib gdi32.lib winmm.lib user32.lib shell32.lib
if errorlevel 1 (
  echo.
  echo ERROR: compile failed. Nothing was copied.
  exit /b 1
)

dumpbin /exports xt3d.dll | findstr /c:"xt3d_Version" >nul
if errorlevel 1 (
  echo ERROR: xt3d.dll was built but does not export xt3d_Version.
  exit /b 1
)

if not exist "extension\code\x86_64-win32" mkdir "extension\code\x86_64-win32"

echo === Copying into extension\
copy /Y xt3d.lcb "extension\xt3d.lcb" >nul
if errorlevel 1 (
  echo ERROR: could not copy xt3d.lcb.
  exit /b 1
)
copy /Y xt3d.dll "extension\code\x86_64-win32\xt3d.dll" >nul
if errorlevel 1 (
  echo ERROR: could not copy xt3d.dll. Is LiveCode still running?
  exit /b 1
)

for /f %%n in ('dumpbin /exports "extension\code\x86_64-win32\xt3d.dll" ^| findstr /c:"xt3d_" ^| find /c /v ""') do set COUNT=%%n
echo.
echo OK: extension\code\x86_64-win32\xt3d.dll exports %COUNT% xt3d functions.
echo Now open  %CD%\extension\xt3d.lcb  in LiveCode's Extension Builder and click Test.
endlocal
