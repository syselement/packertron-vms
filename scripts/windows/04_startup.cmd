@rem Launch 04_startup.ps1 on first boot and tee its output to a log.
@rem Placed in the Startup folder by the win-srv-2025 Packer build.
@rem
@rem Docs:
@rem   README.md  templates/vmware/win-srv-2025/README.md
@rem
@rem Run: Windows runs this from the Startup folder; not meant to be run by hand.

powershell.exe -ExecutionPolicy Bypass -Command "& { C:\tmp\startup.ps1 *>&1 | Tee-Object -FilePath C:\tmp\startup_script_output.log -Append }"
