# © Broadcom. All Rights Reserved.
# The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2-Clause

# Red Hat Enterprise Linux 8

%{ if boot_iso }
### Installs from Red Hat Subscription Manager
rhsm --organization=${rhsm_org} --activation-key=${rhsm_key}
%{ else }
### Installs for DVD
cdrom
%{ endif }

### Performs the kickstart installation in text mode.
### By default, kickstart installations are performed in graphical mode.
text

### Accepts the End User License Agreement.
eula --agreed

### Sets the language to use during installation and the default language to use on the installed system.
lang ${vm_guest_os_language}

### Sets the default keyboard type for the system.
keyboard ${vm_guest_os_keyboard}

### Configure network information for target system and activate network devices in the installer environment (optional)
### --onboot	  enable device at a boot time
### --device	  device to be activated and / or configured with the network command
### --bootproto	  method to obtain networking configuration for device (default dhcp)
### --noipv6	  disable IPv6 on this device
${network}

### Lock the root account.
rootpw --lock

### The selected profile will restrict root login.
### Add a user that can login and escalate privileges.
user --name=${build_username} --iscrypted --password=${build_password_encrypted} --groups=wheel

### Configure firewall settings for the system.
### --enabled	reject incoming connections that are not in response to outbound requests
### --ssh		allow sshd service through the firewall
firewall --enabled --ssh

### Sets up the authentication options for the system.
### The SSDD profile sets sha512 to hash passwords. Passwords are shadowed by default
### See the manual page for authselect-profile for a complete list of possible options.
authselect select sssd

### Sets the state of SELinux on the installed system.
### Defaults to enforcing.
selinux --permissive

### Sets the system time zone.
timezone ${vm_guest_os_timezone}

### Partitioning
zerombr
clearpart --all --initlabel
autopart

### Modifies the default set of services that will run under the default runlevel.
services --enabled=NetworkManager,sshd

### Do not configure X on the installed system.
skipx

### Packages selection.
%packages --ignoremissing --excludedocs
@^minimal-environment

# Ensure the VMware tools are installed for full functionality.
# This package provides the vmxnet3 driver and other VM-specific tools.
@vmware-guest
%end

### Post-installation commands.
%post --log=/var/log/kickstart-post.log

# This sets xtrace mode, which will print each command to the log file before it is executed.
set -x

/usr/sbin/subscription-manager register --username ${rhsm_username} --password ${rhsm_password} --autosubscribe --force
/usr/sbin/subscription-manager repos --enable "codeready-builder-for-rhel-8-x86_64-rpms"
# This retry loop is critical for addressing intermittent timing issues.
# It attempts to run `dnf install` up to 5 times with a 10-second delay
# if the command fails, which gives the subscription-manager and Red Hat CDN
# time to synchronize.
RETRY_COUNT=0
MAX_RETRIES=5
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm; then
    SUCCESS=true
    break
  else
    echo "dnf install failed. Retrying in 10 seconds..."
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT+1))
  fi
done

if [ "$SUCCESS" = false ]; then
  echo "dnf install failed after $MAX_RETRIES attempts. Exiting."
  exit 1
fi

# free up space, only need @vmware-guest
dnf remove -y linux-firmware

dnf install -y sudo open-vm-tools
%{ if additional_packages != "" ~}
dnf install -y ${additional_packages}
%{ endif ~}
echo "${build_username} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${build_username}
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers
%end

### Reboot after the installation is complete.
### --eject attempt to eject the media before rebooting.
reboot --eject
