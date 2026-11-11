@echo off
rem xt3d build. Run from the "x64 Native Tools Command Prompt for VS 2022", with LiveCode closed.
rem Works from any folder, including \\wsl$\... : sources are copied to a Windows work folder,
rem compiled there, and the DLL and xt3d.lcb are placed in <work>\extension for LiveCode.
rem
rem   XT3D_WORK    work folder                (default C:\xt3d)
rem   XT3D_RAYLIB  prebuilt raylib folder     (default <work>\raylib-6.2_win64_msvc16)
setlocal
set "SRC=%~dp0"
if "%XT3D_WORK%"=="" set "XT3D_WORK=C:\xt3d"
if "%XT3D_RAYLIB%"=="" set "XT3D_RAYLIB=%XT3D_WORK%\raylib-6.2_win64_msvc16"

where cl >nul 2>nul
if errorlevel 1 (
  echo ERROR: cl not found. Open "x64 Native Tools Command Prompt for VS 2022" and run this again.
  exit /b 1
)
if not exist "%XT3D_RAYLIB%\lib\raylib.lib" (
  echo ERROR: "%XT3D_RAYLIB%\lib\raylib.lib" not found. Set XT3D_RAYLIB to your raylib folder.
  exit /b 1
)
if not exist "%XT3D_WORK%" mkdir "%XT3D_WORK%"

if /i "%SRC%"=="%XT3D_WORK%\" goto :compile
echo === Copying sources to %XT3D_WORK%
for %%f in (xt3d_shim.c xt3d_generated.inc xt3d.lcb) do (
  copy /Y "%SRC%%%f" "%XT3D_WORK%\%%f" >nul
  if errorlevel 1 (
    echo ERROR: could not copy %%f from "%SRC%".
    exit /b 1
  )
)

:compile
cd /d "%XT3D_WORK%"
echo === Compiling xt3d.dll
cl /nologo /O2 /MD /LD /TC xt3d_shim.c /I "%XT3D_RAYLIB%\include" /Fe:xt3d.dll /link "%XT3D_RAYLIB%\lib\raylib.lib" opengl32.lib gdi32.lib winmm.lib user32.lib shell32.lib
if errorlevel 1 (
  echo.
  echo ERROR: compile failed. Nothing was installed.
  exit /b 1
)
dumpbin /exports xt3d.dll | findstr /c:"xt3d_Version" >nul
if errorlevel 1 (
  echo ERROR: xt3d.dll was built but does not export xt3d_Version.
  exit /b 1
)

if not exist "extension\code\x86_64-win32" mkdir "extension\code\x86_64-win32"
echo === Installing into %XT3D_WORK%\extension
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
echo OK: %XT3D_WORK%\extension\code\x86_64-win32\xt3d.dll exports %COUNT% xt3d functions.
echo Next: in LiveCode, Tools - Extension Builder - open %XT3D_WORK%\extension\xt3d.lcb - Test.
echo       ^(the copy inside "extension", not the one beside it^)
endlocal
