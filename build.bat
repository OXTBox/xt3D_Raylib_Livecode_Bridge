@echo off
rem xt3d build. Close LiveCode first. Double-click it, or run it from any command prompt.
rem Copies the sources to a Windows work folder, compiles xt3d.dll there, and places
rem the DLL and xt3d.lcb in <work>\extension for LiveCode. The window stays open at the end.
rem
rem   XT3D_SRC     folder holding xt3d_shim.c, xt3d_generated.inc, xt3d.lcb
rem                (default: this file's folder if they are there, else the WSL project folder)
rem   XT3D_WORK    work folder                (default C:\xt3d)
rem   XT3D_RAYLIB  prebuilt raylib folder     (default <work>\raylib-6.2_win64_msvc16)
rem   XT3D_NOPAUSE set to 1 to skip the closing pause (for scripted builds)
setlocal
if "%XT3D_WORK%"=="" set "XT3D_WORK=C:\xt3d"
if "%XT3D_RAYLIB%"=="" set "XT3D_RAYLIB=%XT3D_WORK%\raylib-6.2_win64_msvc16"
if "%XT3D_SRC%"=="" (
  if exist "%~dp0xt3d_shim.c" (set "XT3D_SRC=%~dp0") else set "XT3D_SRC=\\wsl$\Ubuntu\home\igame3d\projects\xt3D_Raylib_Livecode_Bridge\"
)
if not "%XT3D_SRC:~-1%"=="\" set "XT3D_SRC=%XT3D_SRC%\"

rem --- compiler: use cl if already set up, otherwise find Visual Studio and set it up
where cl >nul 2>nul
if not errorlevel 1 goto :havecl
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "VSDIR="
if exist "%VSWHERE%" for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if "%VSDIR%"=="" (
  echo ERROR: Visual Studio with "Desktop development with C++" was not found.
  goto :fail
)
echo === Setting up the Visual Studio x64 compiler
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul
where cl >nul 2>nul
if errorlevel 1 (
  echo ERROR: vcvars64.bat ran but cl is still not available.
  goto :fail
)
:havecl

if not exist "%XT3D_RAYLIB%\lib\raylib.lib" (
  echo ERROR: "%XT3D_RAYLIB%\lib\raylib.lib" not found. Set XT3D_RAYLIB to your raylib folder.
  goto :fail
)
if not exist "%XT3D_WORK%" mkdir "%XT3D_WORK%"

rem --- sources
if /i "%XT3D_SRC%"=="%XT3D_WORK%\" goto :compile
echo === Copying sources from %XT3D_SRC%
for %%f in (xt3d_shim.c xt3d_generated.inc xt3d.lcb) do (
  copy /Y "%XT3D_SRC%%%f" "%XT3D_WORK%\%%f" >nul
  if errorlevel 1 (
    echo ERROR: could not copy %%f from "%XT3D_SRC%". Set XT3D_SRC to the folder that holds it.
    goto :fail
  )
)

:compile
cd /d "%XT3D_WORK%"
for %%f in (xt3d_shim.c xt3d_generated.inc xt3d.lcb) do if not exist "%%f" (
  echo ERROR: %XT3D_WORK%\%%f is missing.
  goto :fail
)
echo === Compiling xt3d.dll
cl /nologo /O2 /MD /LD /TC xt3d_shim.c /I "%XT3D_RAYLIB%\include" /Fe:xt3d.dll /link "%XT3D_RAYLIB%\lib\raylib.lib" opengl32.lib gdi32.lib winmm.lib user32.lib shell32.lib
if errorlevel 1 (
  echo.
  echo ERROR: compile failed. Nothing was installed.
  goto :fail
)
dumpbin /exports xt3d.dll | findstr /c:"xt3d_Version" >nul
if errorlevel 1 (
  echo ERROR: xt3d.dll was built but does not export xt3d_Version.
  goto :fail
)

if not exist "extension\code\x86_64-win32" mkdir "extension\code\x86_64-win32"
echo === Installing into %XT3D_WORK%\extension
copy /Y xt3d.lcb "extension\xt3d.lcb" >nul
if errorlevel 1 (
  echo ERROR: could not copy xt3d.lcb.
  goto :fail
)
copy /Y xt3d.dll "extension\code\x86_64-win32\xt3d.dll" >nul
if errorlevel 1 (
  echo ERROR: could not copy xt3d.dll. Is LiveCode still running?
  goto :fail
)
for /f %%n in ('dumpbin /exports "extension\code\x86_64-win32\xt3d.dll" ^| findstr /c:"xt3d_" ^| find /c /v ""') do set COUNT=%%n
echo.
echo OK: %XT3D_WORK%\extension\code\x86_64-win32\xt3d.dll exports %COUNT% xt3d functions.
echo Next: in LiveCode, Tools - Extension Builder - open %XT3D_WORK%\extension\xt3d.lcb - Test.
echo       ^(the copy inside "extension", not the one beside it^)
if not "%XT3D_NOPAUSE%"=="1" pause
endlocal
exit /b 0

:fail
echo.
echo Build stopped. Nothing after the error above was done.
if not "%XT3D_NOPAUSE%"=="1" pause
endlocal
exit /b 1
