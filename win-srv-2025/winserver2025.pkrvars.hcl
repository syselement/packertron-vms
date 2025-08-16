boot_wait = "2s"
box_output = "output/win2025_gui.box"
disk_size = "60960"

# Use Get-FileHash to generate the checksum
# Example: Get-FileHash .\26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso
iso_checksum = "D0EF4502E350E3C6C53C15B1B3020D38A5DED011BF04998E950720AC8579B23D"
iso_url = "C:/ISO/windows/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
# iso_url =  "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"

memsize = "8192"
numvcpus = "4"
ssh_password = "packer"
ssh_username = "Administrator"
vm_name = "Win2025VM"