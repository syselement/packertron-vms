cd .\ubuntu-24.04-x64-desktop\

packer init .
packer validate "ubuntu-24.04-x64-desktop.pkr.hcl"
packer build .

# Build 'vmware-iso.ubuntu2404_desktop' finished after 13 minutes 9 seconds.

==> Wait completed after 13 minutes 9 seconds

==> Builds finished. The artifacts of successful builds are:
--> vmware-iso.ubuntu2404_desktop: 'vmware' provider box: output/ubuntu-24.04-x64-desktop-template-vmware.box


---

# TO DO
# vagrant box add --name ubuntu2404-desktop-vmware .\output\ubuntu-24.04-x64-desktop-template-vmware.box

vagrant up --provider vmware_desktop


# Shut down VM
vagrant halt

# Restart VM
vagrant up

# Destroy VM
vagrant destroy -f