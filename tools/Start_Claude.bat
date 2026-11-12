@echo off
rem Start_Claude.bat - after a restart: open Windows Terminal on WSL Ubuntu in ~/projects
rem (where you start Claude by hand) and start Claude Code, continuing the last conversation.
rem
rem   Double-click:            continue the last conversation (claude --continue)
rem   Start_Claude.bat new     start a fresh conversation (faster, uses less memory;
rem                            the projects' CLAUDE.md files and Claude's memory carry over)
rem   Start_Claude.bat pick    choose from earlier conversations (claude --resume)
rem
rem Nothing else needs starting: Claude starts the LIB_MCP standalones by itself.
rem Open LiveCode, LM Studio or the xt3d bench only when you want to use them.

set "MODE=--continue"
if /i "%~1"=="new"  set "MODE="
if /i "%~1"=="pick" set "MODE=--resume"

set "PROJECT=/home/igame3d/projects"

where wt >nul 2>nul
if errorlevel 1 goto :nowt
start "" wt.exe new-tab --title "Claude Code" wsl.exe -d Ubuntu --cd %PROJECT% -e bash -lic "claude %MODE% && exec bash || exec bash"
exit /b 0

:nowt
rem no Windows Terminal: use a plain console window
start "Claude Code" wsl.exe -d Ubuntu --cd %PROJECT% -e bash -lic "claude %MODE% && exec bash || exec bash"
pause
exit /b 0
