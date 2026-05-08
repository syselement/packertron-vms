powershell.exe -ExecutionPolicy Bypass -Command "& { C:\tmp\startup.ps1 *>&1 | Tee-Object -FilePath C:\tmp\startup_script_output.log -Append }"
