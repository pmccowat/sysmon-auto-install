@echo off
echo ************************************************
echo *****   Sysmon/Winlogbeat Install Script   *****
echo ************************************************
::
:: Author: @cowbe0x004
::
echo.
echo ####################PRECHECK####################
timeout /t 5

:: directory of the install script, has a trailing \
set SYSMON_DIR=C:\ProgramData\sysmon
set SYSMON_CONF=sysmonconfig.xml
set SYSMON_BIN=C:\Source\sysmon

if not exist %SYSMON_BIN% (
	mkdir %SYSMON_BIN%
	)

echo.
echo [+] Checking powershell version...
@powershell if ($PSVersionTable.PSVersion.Major -ge 5) { Write-Host " [+] You are running Powershell version $PSVersionTable.PSVersion.Major"} else { Write-Host " [-] Powershell version $PSVersionTable.PSVersion.Major detected, please update to version 5 or above."; exit(1) }
if %errorlevel% NEQ 0 (
	goto end
	)

:: make sure script is ran with admin privileges.
echo.
echo [+] Checking for administrative privileges...

net session >nul 2>&1
if %errorLevel% NEQ 0 (
	echo [-] Please run script with administrative privileges. Script will exit.
	goto end
)

echo.
echo ####################SYSMON####################

:: download sysmon
@powershell Invoke-WebRequest -Uri "https://live.sysinternals.com/Sysmon64.exe" -OutFile "C:\Source\Sysmon\Sysmon64.exe"
@powershell Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Neo23x0/sysmon-config/master/sysmonconfig-export-block.xml" -OutFile "C:\Source\Sysmon\sysmonconfig.xml"
@powershell Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pmccowat/sysmon-auto-install/master/auto_update.bat" -OutFile "C:\Source\Sysmon\auto_update.bat"

xcopy %SYSMON_BIN%\sysmon64.exe %SYSMON_DIR% /q /y
xcopy %SYSMON_BIN%\%SYSMON_CONF% %SYSMON_DIR% /q /y
xcopy %SYSMON_BIN%\auto_update.bat %SYSMON_DIR% /q /y

schtasks /delete /TN "Update_Sysmon_Rules" /F

if not exist %SYSMON_DIR% (
	mkdir %SYSMON_DIR%
	)

sc query sysmon >nul
if "%errorlevel%" EQU "0" (
	echo.
	echo [+] Sysmon installed, removing...
	sysmon.exe -u
	)


sc query sysmon64 >nul
if "%errorlevel%" EQU "0" (
	echo.
	echo [+] Sysmon64 installed, removing...
	sysmon64.exe -u force
	)

sc query sysmon64 >nul
if "%errorlevel%" EQU "0" (
	echo.
	echo [+] Sysmon64 installed, removing...
	sysmon64.exe -u
	)

echo.
echo [+] Copying sysmon and config...

pushd %SYSMON_DIR%


echo [+] Installing sysmon and applying config...
sysmon64.exe -i -accepteula
::sc failure Sysmon64 actions= restart/10000/restart/10000// reset= 120
echo.
echo [+] Creating daily update task
:: add scheduler task to update sysmon config with start time based on when the task is added
setlocal
set hour=%time:~0,2%
set minute=%time:~3,2%
set /A minute+=2
if %minute% GTR 59 (
	set /A minute-=60
	set /A hour+=1
	)
if %hour%==24 set hour=00
if "%hour:~0,1%"==" " set hour=0%hour:~1,1%
if "%hour:~1,1%"=="" set hour=0%hour%
if "%minute:~1,1%"=="" set minute=0%minute%
set tasktime=%hour%:%minute%
::

SchTasks /create /tn "Update sysmon" /ru SYSTEM /rl HIGHEST /sc daily /tr "cmd.exe /c \"%SYSMON_DIR%\\auto_update.bat\"" /f /st %tasktime%

echo ####################PS LOGGING####################

echo.
::echo [+] Importing PS logging registries and applying config...
:: https://www.malwarearchaeology.com/logging. 
:: These settings will only change the local security policy.  It is best to set these in Group Policy default profile so all systems get the same settings.  
:: GPO will overwrite these settings!
::
::#######################################################################
::
:: SET THE LOG SIZE - What local size they will be
:: ---------------------
::
:: 540100100 will give you 7 days of local Event Logs with everything logging (Security and Sysmon)
:: 1023934464 will give you 14 days of local Event Logs with everything logging (Security and Sysmon)
:: Other logs do not create as much quantity, so lower numbers are fine
::
:: 20480000 ~= 20mb
:: 50480000 ~= 50mb
:: 256000100 ~= 250mb
::
wevtutil sl Security /ms:100480000
::
wevtutil sl Application /ms:20480000
::
wevtutil sl Setup /ms:20480000
::
wevtutil sl System /ms:20480000
::
wevtutil sl "Windows Powershell" /ms:256000100
::
wevtutil sl "Microsoft-Windows-PowerShell/Operational" /ms:256000100
::
::wevtutil sl "Microsoft-Windows-Sysmon/Operational" /ms:256000100
::
::#######################################################################
::
:: ---------------------------------------------------------------------
:: ENABLE The TaskScheduler log
:: ---------------------------------------------------------------------
::
wevtutil sl "Microsoft-Windows-TaskScheduler/Operational" /e:true

echo.
echo [+] Script finished.

goto end

:service_error
echo [-] Service failed to start. Script will exit.

:end
ping localhost

@powershell Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-4.5.4-1.msi -OutFile wazuh-agent.msi; ./wazuh-agent.msi /q WAZUH_MANAGER='siem.lochsandglens.com' WAZUH_REGISTRATION_SERVER='siem.lochsandglens.com' WAZUH_PROTOCOL='TCP' WAZUH_AGENT_GROUP='default' 
ping localhost
@powershell Invoke-WebRequest -Uri "https://live.sysinternals.com/Sysmon64.exe" -OutFile "C:\Source\Sysmon\Sysmon64.exe"
ping localhost

net start Wazuh