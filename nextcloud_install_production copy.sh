#!/bin/bash

# T&M Hansson IT AB © - 2023, https://www.hanssonit.se/
# GNU General Public License v3.0
# https://github.com/nextcloud/vm/blob/master/LICENSE

# Prefer IPv4 for apt
echo 'Acquire::ForceIPv4 "true";' >> /etc/apt/apt.conf.d/99force-ipv4

# Fix fancy progress bar for apt-get
# https://askubuntu.com/a/754653
if [ -d /etc/apt/apt.conf.d ]
then
    if ! [ -f /etc/apt/apt.conf.d/99progressbar ]
    then
        echo 'Dpkg::Progress-Fancy "1";' > /etc/apt/apt.conf.d/99progressbar
        echo 'APT::Color "1";' >> /etc/apt/apt.conf.d/99progressbar
        chmod 644 /etc/apt/apt.conf.d/99progressbar
    fi
fi

# Install curl if not existing
if [ "$(dpkg-query -W -f='${Status}' "curl" 2>/dev/null | grep -c "ok installed")" = "1" ]
then
    echo "curl OK"
else
    apt-get update -q4
    apt-get upgrade -y
    apt-get install curl -y
fi

true
SCRIPT_NAME="Ubuntu 22.04 LTS"
SCRIPT_EXPLAINER="This script is installing all requirements that are needed for Ubuntu 22.04 to run.
It's the first of two parts that are necessary to finish your customized Ubuntu 22.04 installation."
# shellcheck source=lib.sh
source <(curl -sL https://raw.githubusercontent.com/Altoyda/vm/master/lib.sh)
# source lib.sh

true
SCRIPT_NAME="Startup Configuration Menu"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Update the lib once during the startup script
# TODO: delete this again e.g. with NC 20.0.1
# download_script GITHUB_REPO lib #### removed in 21.0.0, delete it completely in a later version

# Must be root
root_check

# Get the correct keyboard layout switch
if [ "$KEYBOARD_LAYOUT" = "us" ]
then
    KEYBOARD_LAYOUT_SWITCH="ON"
else
    KEYBOARD_LAYOUT_SWITCH="OFF"
fi

# Get the correct timezone switch
if [ "$(cat /etc/timezone)" = "Etc/UTC" ]
then
    TIMEZONE_SWITCH="ON"
else
    TIMEZONE_SWITCH="OFF"
fi

# Get the correct apt-mirror
if [ "$REPO" = 'http://archive.ubuntu.com/ubuntu' ]
then
    MIRROR_SWITCH="ON"
else
    MIRROR_SWITCH="OFF"
fi

# Show a msg_box during the startup script
if [ -f "$SCRIPTS/nextcloud-startup-script.sh" ]
then
    msg_box "Running a server, it's important that certain things are correct.
In the following menu you will be asked to set up the most basic stuff of your server.

The script is smart, and have already pre-selected the values that you'd want to change based on the current settings."
fi

# Startup configurations
choice=$(whiptail --title "$TITLE" --checklist \
"Choose what you want to change.
$CHECKLIST_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Keyboard Layout" "(Change the keyboard layout from '$KEYBOARD_LAYOUT')" "$KEYBOARD_LAYOUT_SWITCH" \
"Timezone" "(Change the timezone from $(cat /etc/timezone))" "$TIMEZONE_SWITCH" \
"Locate Mirror" "(Change the apt-mirror from $REPO)" OFF 3>&1 1>&2 2>&3)

case "$choice" in
    *"Keyboard Layout"*)
        SUBTITLE="Keyboard Layout"
        msg_box "Current keyboard layout is $KEYBOARD_LAYOUT." "$SUBTITLE"
        if ! yesno_box_yes "Do you want to change keyboard layout?" "$SUBTITLE"
        then
            print_text_in_color "$ICyan" "Not changing keyboard layout..."
            sleep 1
        else
            # Change layout
            dpkg-reconfigure keyboard-configuration
            setupcon --force
            # Set locales
            run_script ADDONS locales
            input_box "Please try out all buttons (e.g: @ # \$ : y n) \
to find out if the keyboard settings were correctly applied.
If the keyboard is still wrong, you will be offered to reboot the server in the next step.

Please continue by hitting [ENTER]" "$SUBTITLE" >/dev/null
            if ! yesno_box_yes "Did the keyboard work as expected?\n\nIf you choose 'No' \
the server will be rebooted. After the reboot, please login as usual and run this script again." "$SUBTITLE"
            then
                reboot
            fi
        fi
    ;;&
    *"Timezone"*)
        SUBTITLE="Timezone"
        msg_box "Current timezone is $(cat /etc/timezone)" "$SUBTITLE"
        if ! yesno_box_yes "Do you want to change the timezone?" "$SUBTITLE"
        then
            print_text_in_color "$ICyan" "Not changing timezone..."
            sleep 1
        else
            if dpkg-reconfigure tzdata
            then
                # Change timezone in php and logging if the startup script not exists
                if ! [ -f "$SCRIPTS/nextcloud-startup-script.sh" ]
                then
                    # Change timezone in PHP
                    sed -i "s|;date.timezone.*|date.timezone = $(cat /etc/timezone)|g" "$PHP_INI"

                    # Change timezone for logging
                    nextcloud_occ config:system:set logtimezone --value="$(cat /etc/timezone)"
                    msg_box "The timezone was changed successfully." "$SUBTITLE"
                fi
            fi
        fi
    ;;&
    *"Locate Mirror"*)
        SUBTITLE="apt-mirror"
        print_text_in_color "$ICyan" "Downloading the Locate Mirror script..."
        run_script ADDONS locate_mirror
    ;;&
    *)
    ;;
esac
exit

# Is this run as a pure root user?
if is_root
then
    if [[ "$UNIXUSER" == "ncadmin" ]]
    then
        sleep 1
    else
        if [ -z "$UNIXUSER" ]
        then
            msg_box "You seem to be running this as the root user.
You must run this as a regular user with sudo permissions.

Please create a user with sudo permissions and the run this command:
sudo -u [user-with-sudo-permissions] sudo bash /var/scripts/nextcloud-startup-script.sh

We will do this for you when you hit OK."
       download_script STATIC adduser
       bash $SCRIPTS/adduser.sh "$SCRIPTS/nextcloud-startup-script.sh"
       rm $SCRIPTS/adduser.sh
       else
           msg_box "You probably see this message if the user 'ncadmin' does not exist on the system,
which could be the case if you are running directly from the scripts on Github and not the VM.

As long as the user you created have sudo permissions it's safe to continue.
This would be the case if you created a new user with the script in the previous step.

If the user you are running this script with is a user that doesn't have sudo permissions,
please abort this script and report this issue to $ISSUES."
            if yesno_box_yes "Do you want to abort this script?"
            then
                exit
            fi
        fi
    fi
fi


# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# Test RAM size (2GB min) + CPUs (min 1)
ram_check 2 Nextcloud
cpu_check 1 Nextcloud

# Check if dpkg or apt is running
is_process_running apt
is_process_running dpkg

# Check distribution and version
if ! version 22.04 "$DISTRO" 22.04.10
then
    msg_box "This script can only be run on Ubuntu 22.04 (server)."
    exit 1
fi

# Automatically restart services
# Restart mode: (l)ist only, (i)nteractive or (a)utomatically.
sed -i "s|#\$nrconf{restart} = .*|\$nrconf{restart} = 'a';|g" /etc/needrestart/needrestart.conf

# Check for flags
if [ "$1" = "" ]
then
    print_text_in_color "$ICyan" "Running in normal mode..."
    sleep 1
elif [ "$1" = "--provisioning" ] || [ "$1" = "-p" ]
then
    print_text_in_color "$ICyan" "Running in provisioning mode..."
    export PROVISIONING=1
    sleep 1
elif [ "$1" = "--not-latest" ]
then
    NOT_LATEST=1
    print_text_in_color "$ICyan" "Running in not-latest mode..."
    sleep 1
else
    msg_box "Failed to get the correct flag. Did you enter it correctly?"
    exit 1
fi

# Show explainer
if [ -z "$PROVISIONING" ]
then
    msg_box "$SCRIPT_EXPLAINER"
fi

# Create a placeholder volume before modifying anything
if [ -z "$PROVISIONING" ]
then
    if ! does_snapshot_exist "NcVM-installation" && yesno_box_no "Do you want to use LVM snapshots to be able to restore your root partition during upgrades and such?
Please note: this feature will not be used by this script but by other scripts later on.
For now we will only create a placeholder volume that will be used to let some space for snapshot volumes.
Be aware that you will not be able to use the built-in backup solution if you choose 'No'!
Enabling this will also force an automatic reboot after running the update script!"
    then
        check_free_space
        if [ "$FREE_SPACE" -ge 50 ]
        then
            print_text_in_color "$ICyan" "Creating volume..."
            sleep 1
            # Create a placeholder snapshot
            check_command lvcreate --size 5G --name "NcVM-installation" ubuntu-vg
        else
            print_text_in_color "$IRed" "Could not create volume because of insufficient space..."
            sleep 2
        fi
    fi
fi

# Fix LVM on BASE image
if grep -q "LVM" /etc/fstab
then
    if [ -n "$PROVISIONING" ] || yesno_box_yes "Do you want to make all free space available to your root partition?"
    then
    # Resize LVM (live installer is &%¤%/!
    # VM
    print_text_in_color "$ICyan" "Extending LVM, this may take a long time..."
    lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv

    # Run it again manually just to be sure it's done
    while :
    do
        lvdisplay | grep "Size" | awk '{print $3}'
        if ! lvextend -L +10G /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
        then
            if ! lvextend -L +1G /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
            then
                if ! lvextend -L +100M /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
                then
                    if ! lvextend -L +1M /dev/ubuntu-vg/ubuntu-lv >/dev/null 2>&1
                    then
                        resize2fs /dev/ubuntu-vg/ubuntu-lv
                        break
                    fi
                fi
            fi
        fi
    done
    fi
fi

# Install needed dependencies
install_if_not lshw
install_if_not net-tools
install_if_not whiptail
install_if_not apt-utils
install_if_not keyboard-configuration

# Nice to have dependencies
install_if_not bash-completion
install_if_not htop
install_if_not iputils-ping

# Download needed libraries before execution of the first script
mkdir -p "$SCRIPTS"
download_script GITHUB_REPO lib
download_script STATIC fetch_lib

# Set locales
run_script ADDONS locales

# # Create new current user
# download_script STATIC adduser
# bash "$SCRIPTS"/adduser.sh "nextcloud_install_production.sh"
# rm -f "$SCRIPTS"/adduser.sh

check_universe
check_multiverse

# Set timezone




# We don't want automatic updates since they might fail (we use our own script)
if is_this_installed unattended-upgrades
then
    apt-get purge unattended-upgrades -y
    apt-get autoremove -y
    rm -rf /var/log/unattended-upgrades
fi

# Create $SCRIPTS dir
if [ ! -d "$SCRIPTS" ]
then
    mkdir -p "$SCRIPTS"
fi

# Create $VMLOGS dir
if [ ! -d "$VMLOGS" ]
then
    mkdir -p "$VMLOGS"
fi

# Install needed network
install_if_not netplan.io

# APT over HTTPS
install_if_not apt-transport-https

# Install build-essentials to get make
install_if_not build-essential

# Install a decent text editor
install_if_not nano

# Install package for crontab
install_if_not cron

# Make sure sudo exists (needed in adduser.sh)
install_if_not sudo

# Make sure add-apt-repository exists (needed in lib.sh)
install_if_not software-properties-common

# Set dual or single drive setup
if [ -n "$PROVISIONING" ]
then
    choice="2 Disks Auto"
else
    msg_box "This server is designed to run with two disks, one for OS and one for DATA. \
This will get you the best performance since the second disk is using ZFS which is a superior filesystem.

Though not recommended, you can still choose to only run on one disk, \
if for example it's your only option on the hypervisor you're running.

You will now get the option to decide which disk you want to use for DATA, \
or run the automatic script that will choose the available disk automatically."

    choice=$(whiptail --title "$TITLE - Choose disk format" --nocancel --menu \
"How would you like to configure your disks?
$MENU_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"2 Disks Auto" "(Automatically configured)" \
"2 Disks Manual" "(Choose by yourself)" \
"1 Disk" "(Only use one disk /mnt/ncdata - NO ZFS!)" 3>&1 1>&2 2>&3)
fi

case "$choice" in
    "2 Disks Auto")
        run_script DISK format-sdb
        # Change to zfs-mount-generator
        run_script DISK change-to-zfs-mount-generator
        # Create daily zfs prune script
        run_script DISK create-daily-zfs-prune

    ;;
    "2 Disks Manual")
        run_script DISK format-chosen
        # Change to zfs-mount-generator
        run_script DISK change-to-zfs-mount-generator
        # Create daily zfs prune script
        run_script DISK create-daily-zfs-prune
    ;;
    "1 Disk")
        print_text_in_color "$IRed" "1 Disk setup chosen."
        sleep 2
    ;;
    *)
    ;;
esac

# Set DNS resolver
# https://unix.stackexchange.com/questions/442598/how-to-configure-systemd-resolved-and-systemd-networkd-to-use-local-dns-server-f
while :
do
    if [ -n "$PROVISIONING" ]
    then
        choice="Quad9"
    else
        choice=$(whiptail --title "$TITLE - Set DNS Resolver" --menu \
"Which DNS provider should this Nextcloud box use?
$MENU_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Quad9" "(https://www.quad9.net/)" \
"Cloudflare" "(https://www.cloudflare.com/dns/)" \
"Local" "($GATEWAY) - DNS on gateway" \
"Expert" "If you really know what you're doing!" 3>&1 1>&2 2>&3)
    fi

    case "$choice" in
        "Quad9")
            sed -i "s|^#\?DNS=.*$|DNS=9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9|g" /etc/systemd/resolved.conf
        ;;
        "Cloudflare")
            sed -i "s|^#\?DNS=.*$|DNS=1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001|g" /etc/systemd/resolved.conf
        ;;
        "Local")
            sed -i "s|^#\?DNS=.*$|DNS=$GATEWAY|g" /etc/systemd/resolved.conf
            systemctl restart systemd-resolved.service
            if network_ok
            then
                break
            else
                msg_box "Could not validate the local DNS server. Pick an Internet DNS server and try again."
                continue
            fi
        ;;
        "Expert")
            OWNDNS=$(input_box_flow "Please choose your own DNS server(s) with a space in between, e.g: $GATEWAY 9.9.9.9 (NS1 NS2)")
            sed -i "s|^#\?DNS=.*$|DNS=$OWNDNS|g" /etc/systemd/resolved.conf
            systemctl restart systemd-resolved.service
            if network_ok
            then
                break
                unset OWNDNS 
            else
                msg_box "Could not validate the local DNS server. Pick an Internet DNS server and try again."
                continue
            fi
        ;;
        *)
        ;;
    esac
    if test_connection
    then
        break
    else
        msg_box "Could not validate the DNS server. Please try again."
    fi
done

# Install VM-tools
if [ "$SYSVENDOR" == "VMware, Inc." ];
then
    install_if_not open-vm-tools
elif [[ "$SYSVENDOR" == "QEMU" || "$SYSVENDOR" == "Red Hat" ]];
then
    install_if_not qemu-guest-agent
    systemctl enable qemu-guest-agent
    systemctl start qemu-guest-agent
fi

# Cleanup
apt-get autoremove -y
apt-get autoclean
find /root "/home/$UNIXUSER" -type f \( -name '*.sh*' -o -name '*.html*' -o -name '*.tar*' -o -name '*.zip*' \) -delete

# Install virtual kernels for Hyper-V, (and extra for UTF8 kernel module + Collabora and OnlyOffice)
# Kernel 5.4
if ! home_sme_server
then
    if [ "$SYSVENDOR" == "Microsoft Corporation" ]
    then
        # Hyper-V
        install_if_not linux-virtual
        install_if_not linux-image-virtual
        install_if_not linux-tools-virtual
        install_if_not linux-cloud-tools-virtual
        install_if_not linux-azure
        # linux-image-extra-virtual only needed for AUFS driver with Docker
    fi
fi

# Add aliases
# Add alias for ls -al with directory colors
echo "alias ls='ls -al --color=auto'" >> /root/.bashrc
# Add alias for ls -al with directory colors for root
if [ -f /root/.bashrc ]
then
    if ! grep -q "alias ls='ls -al --color=auto'" /root/.bashrc
    then
        echo "alias ls='ls -al --color=auto'" >> /root/.bashrc
    fi
elif [ ! -f /root/.bashrc ]
then
    echo "alias ls='ls -al --color=auto'" > /root/.bashrc
fi

# Add alias for ls -al with directory colors for the user
if [ -f /home/$UNIXUSER/.bashrc ]
then
    if ! grep -q "alias ls='ls -al --color=auto'" /home/$UNIXUSER/.bashrc
    then
        echo "alias ls='ls -al --color=auto'" >> /home/$UNIXUSER/.bashrc
    fi
elif [ ! -f /home/$UNIXUSER/.bashrc ]
then
    echo "alias ls='ls -al --color=auto'" > /home/$UNIXUSER/.bashrc
fi
# Add alias for ls -al with directory colors for the user
if [ -f /home/$UNIXUSER/.bashrc ]
then
    if ! grep -q "alias ls='ls -al --color=auto'" /home/$UNIXUSER/.bashrc
    then
        echo "alias ls='ls -al --color=auto'" >> /home/$UNIXUSER/.bashrc
    fi
elif [ ! -f /home/$UNIXUSER/.bashrc ]
then
    echo "alias ls='ls -al --color=auto'" > /home/$UNIXUSER/.bashrc
fi

# Add alias for reboot
if [ -f /home/$UNIXUSER/.bashrc ]
then
    if ! grep -q "alias reboot='sudo reboot'" /home/$UNIXUSER/.bashrc
    then
        echo "alias reboot='sudo reboot'" >> /home/$UNIXUSER/.bashrc
    fi
elif [ ! -f /home/$UNIXUSER/.bashrc ]
then
    echo "alias reboot='sudo reboot'" > /home/$UNIXUSER/.bashrc
fi

# Add alias for shutdown
if [ -f /home/$UNIXUSER/.bashrc ]
then
    if ! grep -q "alias shutdown='sudo shutdown now'" /home/$UNIXUSER/.bashrc
    then
        echo "alias shutdown='sudo shutdown now'" >> /home/$UNIXUSER/.bashrc
    fi
elif [ ! -f /home/$UNIXUSER/.bashrc ]
then
    echo "alias shutdown='sudo shutdown now'" > /home/$UNIXUSER/.bashrc
fi

# Add alias for ls -al with directory colors for the root user
if [ -f /root/.bashrc ]
then
    if ! grep -q "alias ls='ls -al --color=auto'" /root/.bashrc
    then
        echo "alias ls='ls -al --color=auto'" >> /root/.bashrc
    fi
elif [ ! -f /root/.bashrc ]
then
    echo "alias ls='ls -al --color=auto'" > /root/.bashrc
fi

# Add alias for reboot for the root user
if [ -f /root/.bashrc ]
then
    if ! grep -q "alias reboot='reboot'" /root/.bashrc
    then
        echo "alias reboot='reboot'" >> /root/.bashrc
    fi
elif [ ! -f /root/.bashrc ]
then
    echo "alias reboot='reboot'" > /root/.bashrc
fi

# Add alias for shutdown for the root user
if [ -f /root/.bashrc ]
then
    if ! grep -q "alias shutdown='shutdown now'" /root/.bashrc
    then
        echo "alias shutdown='shutdown now'" >> /root/.bashrc
    fi
elif [ ! -f /root/.bashrc ]
then
    echo "alias shutdown='shutdown now'" > /root/.bashrc
fi

# Fix GRUB defaults
if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="maybe-ubiquity"' /etc/default/grub
then
    sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=|g" /etc/default/grub
fi

##############################################################################################################
# Grub
# Disable cloud-init with GRUB
if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="cloud-init=disabled"' /etc/default/grub
then
    sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=|g" /etc/default/grub
fi

# Disable cloud-init with Modifying the Kernel Commandline
if grep -q 'cloud-init=disabled' /etc/default/grub
then
    sed -i "s|cloud-init=.*||g" /etc/default/grub
fi

# Optimize performance tweaks
# sysctl.conf
if ! grep -Fxq "vm.overcommit_memory = 1" /etc/sysctl.conf
then
    echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
fi

if ! grep -Fxq "fs.file-max=100000" /etc/sysctl.conf
then
    echo 'fs.file-max=100000' >> /etc/sysctl.conf
fi
# /etc/security/limits.conf
if ! grep -Fxq "* soft nofile 100000" /etc/security/limits.conf
then
    echo '* soft nofile 100000' >> /etc/security/limits.conf
fi

if ! grep -Fxq "* hard nofile 100000" /etc/security/limits.conf
then
    echo '* hard nofile 100000' >> /etc/security/limits.conf
fi

# /etc/pam.d/common-session
if ! grep -Fxq "session required pam_limits.so" /etc/pam.d/common-session
then
    echo 'session required pam_limits.so' >> /etc/pam.d/common-session
fi

install_if_not tuned
install_if_not tuned-utils
install_if_not tuned-utils-systemtap
install_if_not preload

# Install Docker and Docker Composer
# Install using the Apt repository Before you install Docker Engine for the first time on a new host machine, 
# you need to set up the Docker repository. Afterward, you can install and update Docker from the repository.

# Set up Docker's Apt repository.
# Update the apt package index and install packages to allow apt to use a repository over HTTPS:

install_if_not apt-transport-https
install_if_not ca-certificates
install_if_not curl
install_if_not gnupg
install_if_not lsb-release

# Create the /etc/apt/keyrings directory with 0755 permissions
install -m 0755 -d /etc/apt/keyrings

# Download Docker's official GPG key and save it to /etc/apt/keyrings/docker.gpg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set the permissions of /etc/apt/keyrings/docker.gpg to a+r
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update the apt package index, and install the latest version of Docker Engine and containerd, or go to the next step to install a specific version:
apt-get update
install_if_not docker-ce
install_if_not docker-ce-cli
install_if_not containerd.io
install_if_not docker-buildx-plugin
install_if_not docker-compose-plugin

# Add User to Docker Group
usermod -aG docker $UNIXUSER
mkdir -p /home/$UNIXUSER/docker
chown -R $UNIXUSER:$UNIXUSER /home/$UNIXUSER/docker
chmod -R 775 /home/$UNIXUSER/docker

# Disable Snap
snap remove lxd
snap remove core20
snap remove snapd
apt-get purge snapd -y
apt-get autoremove --purge snapd -y

# file called nosnap.pref in the /etc/apt/preferences.d/
touch /etc/apt/preferences.d/nosnap.pref
echo "Package: snapd" >> /etc/apt/preferences.d/nosnap.pref
echo "Pin: release a=* " >> /etc/apt/preferences.d/nosnap.pref
echo "Pin-Priority: -10" >> /etc/apt/preferences.d/nosnap.pref



##############################################################################################################

# Force MOTD to show correct number of updates
if is_this_installed update-notifier-common
then
    sudo /usr/lib/update-notifier/update-motd-updates-available --force
fi

# It has to be this order:
# Download scripts
# chmod +x
# Set permissions for ncadmin in the change scripts

print_text_in_color "$ICyan" "Getting scripts from GitHub to be able to run the first setup..."

# Get needed scripts for first bootup
# download_script GITHUB_REPO nextcloud-startup-script
download_script STATIC instruction
download_script STATIC history
download_script NETWORK static_ip
# Moved from the startup script 2021-01-04
download_script LETS_ENC activate-tls
download_script STATIC update
download_script STATIC setup_secure_permissions_nextcloud
download_script STATIC change_db_pass
download_script STATIC nextcloud
download_script MENU menu
download_script MENU server_configuration
download_script MENU nextcloud_configuration
download_script MENU additional_apps
download_script MENU desec_menu

# Make $SCRIPTS excutable
chmod +x -R "$SCRIPTS"
chown root:root -R "$SCRIPTS"

# # Prepare first bootup
# check_command run_script STATIC change-ncadmin-profile
# check_command run_script STATIC change-root-profile

# Disable hibernation
print_text_in_color "$ICyan" "Disable hibernation..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Create a snapshot before modifying anything
check_free_space
if does_snapshot_exist "NcVM-installation" || [ "$FREE_SPACE" -ge 50 ]
then
    if does_snapshot_exist "NcVM-installation"
    then
        check_command lvremove /dev/ubuntu-vg/NcVM-installation -y
    fi
    if ! lvcreate --size 5G --snapshot --name "NcVM-startup" /dev/ubuntu-vg/ubuntu-lv
    then
        msg_box "The creation of a snapshot failed.
If you just merged and old one, please reboot your server once more.
It should work afterwards again."
        exit 1
    fi
fi

# Check network
if network_ok
then
    print_text_in_color "$IGreen" "Online!"
else
    print_text_in_color "$ICyan" "Setting correct interface..."
    [ -z "$IFACE" ] && IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
    # Set correct interface
    cat <<-SETDHCP > "/etc/netplan/01-netcfg.yaml"
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: true
      dhcp6: true
SETDHCP
    check_command netplan apply
    print_text_in_color "$ICyan" "Checking connection..."
    sleep 1
    set_systemd_resolved_dns "$IFACE"
    if ! nslookup github.com
    then
        msg_box "The script failed to get an address from DHCP.
You must have a working network connection to run this script.

You will now be provided with the option to set a static IP manually instead."

        # Run static_ip script
	bash /var/scripts/static_ip.sh
    fi
fi

# Check network again
if network_ok
then
    print_text_in_color "$IGreen" "Online!"
elif home_sme_server
then
    msg_box "It seems like the last try failed as well using LAN ethernet.

Since the Home/SME server is equipped with a Wi-Fi module, you will now be asked to enable it to get connectivity.

Please note: It's not recommended to run a server on Wi-Fi; using an ethernet cable is always the best."
    if yesno_box_yes "Do you want to enable Wi-Fi on this server?"
    then
        install_if_not network-manager
        nmtui
    fi
        if network_ok
        then
            print_text_in_color "$IGreen" "Online!"
	else
        msg_box "Network is NOT OK. You must have a working network connection to run this script.

Please contact us for support:
https://shop.hanssonit.se/product/premium-support-per-30-minutes/

Please also post this issue on: https://github.com/nextcloud/vm/issues"
        exit 1
        fi
else
    msg_box "Network is NOT OK. You must have a working network connection to run this script.

Please contact us for support:
https://shop.hanssonit.se/product/premium-support-per-30-minutes/

Please also post this issue on: https://github.com/nextcloud/vm/issues"
    exit 1
fi

# Run the startup menu
run_script MENU startup_configuration

true
SCRIPT_NAME="Nextcloud Startup Script"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh

# Get all needed variables from the library
ncdb
nc_update

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Nextcloud 21 is required
lowest_compatible_nc 21

# Add temporary fix if needed
if network_ok
then
    run_script STATIC temporary-fix-beginning
fi

# Import if missing and export again to import it with UUID
zpool_import_if_missing

# Cleanup 2
apt-get autoremove -y
apt-get autoclean

# Remove preference for IPv4
rm -f /etc/apt/apt.conf.d/99force-ipv4
apt-get update

# Reboot
if [ -z "$PROVISIONING" ]
then
    msg_box "Installation almost done, system will reboot when you hit OK.

After reboot, please login to run the setup script."
fi
sleep 5
reboot
