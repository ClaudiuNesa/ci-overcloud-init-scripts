@echo off

set JOB=%1
set CONF=%2
set CONSOLELOG=%3

C:\Python27\python.exe %JOB% --config-file=%CONF% > %CONSOLELOG% 2>&1
