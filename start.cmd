@echo off
TITLE NovaMine by NovaPE - server software for Minecraft: Bedrock Edition
cd /d %~dp0

:begin
echo.
echo Type "run" to start the server, or "exit" to quit.
set /p input="> "

if /I "%input%"=="run" (
    goto runserver
) else if /I "%input%"=="exit" (
    exit /b
) else (
    echo Invalid input.
    goto begin
)

:runserver
set PHP_BINARY=

where /q php.exe
if %ERRORLEVEL%==0 (
	set PHP_BINARY=php
)

if exist bin\php\php.exe (
	set PHPRC=""
	set PHP_BINARY=bin\php\php.exe
)

if "%PHP_BINARY%"=="" (
	echo Couldn't find a PHP binary in system PATH or "%~dp0bin\php"
	pause
	exit /b
)

if exist NovaMine.phar (
	set POCKETMINE_FILE=NovaMine.phar
) else if exist PocketMine-MP.phar (
	set POCKETMINE_FILE=PocketMine-MP.phar
) else (
	echo NovaMine.phar not found
	pause
	exit /b
)

if exist bin\mintty.exe (
	start "" bin\mintty.exe -o Columns=88 -o Rows=32 -o AllowBlinking=0 -o FontQuality=3 -o Font="Consolas" -o FontHeight=10 -o CursorType=0 -o CursorBlinks=1 -h error -t "NovaMine by NovaPE" -i bin/pocketmine.ico -w max %PHP_BINARY% %POCKETMINE_FILE% --enable-ansi %*
) else (
	%PHP_BINARY% %POCKETMINE_FILE% %* || echo Server crashed or stopped.
)

goto begin
