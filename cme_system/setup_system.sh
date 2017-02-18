#!/bin/bash

# Sets up a CME system.  Hostname, hosts, networking interfaces
# and additional files are copied from the folder where this script
# runs to /etc, /etc/network and other destinations.

# This script requires some env variables to be setup in order to
# retrieve the installation files and versioned Cme applications.

# SETUP - provide a URL that can be used by curl
# CMEINIT_VERSION - the version of the Cme-init program to install
# CME_VERSION - the API layer version that will be installed for recovery mode

echo
echo "  This script is intended to set up a CME device with all system components."
echo "  The CME device must be manually rebooted after the script runs.  The script"
echo "  requires several environment variables be set in order to retireve the"
echo "  installation files and versioned Cme application packages."
echo
echo "  Prior to running this script, export these environment variables:"
echo
echo "    SETUP - provide a URL that can be used by curl"
echo "        $ export SETUP=https://s3.amazonaws.com/transtectorpublicdownloads/Cme"
echo
echo "    CMEINIT_VERSION - identify the Cme-init program version to install"
echo "        $ export CMEINIT_VERSION=0.1.0"
echo
echo "    CME_RECOVERY_VERSION - identify the Cme program installed for recovery mode operation"
echo "        $ export CME_RECOVERY_VERSION=0.1.0"
echo
echo "    CME_VERSION - identify the application layer API program version"
echo "        $ export CME_VERSION=0.1.0"
echo
echo "    CMEHW_VERSION - identify the application layer hardware program version"
echo "        $ export CMEHW_VERSION=0.1.0"
echo
read -n1 -rsp "    CTRL-C to exit now, any other key to continue..." < "$(tty 0>&2)"
echo

# you must do `export CMEINIT_VERSION=0.1.0`
CMEINIT=1500-000-v${CMEINIT_VERSION}-SWARE-CME_INIT.tgz

# you must do `export CME_RECOVERY_VERSION=0.1.0`
CMERECOVERY=1510-000-v${CME_RECOVERY_VERSION}-SWARE-CME_RECOVERY.tgz

# you must do `export CME_VERSION=0.1.0`
CME=1520-000-v${CME_VERSION}-SWARE-CME_API.tgz

# you must do `export CMEHW_VERSION=0.1.0`
CMEHW=1530-000-v${CMEHW_VERSION}-SWARE-CME_HW.tgz

# to get the system setup files
SETUP_SYSTEM=${SETUP}/cme_system

# ensure we start at /root
export HOME=/root
cd

# Set bash to have a nice looking color prompt
cat <<'EOF' > .bashrc
# ~/.bashrc: executed by bash(1) for non-login shells.
red='\[\e[0;31m\]'
green='\[\e[0;32m\]'
cyan='\[\e[0;36m\]'
yellow='\[\e[1;33m\]'
purple='\[\e[0;35m\]'
NC='\[\e[0m\]' # no color - reset
bold=`tput bold`
normal=`tput sgr0`

# set a color prompt with user, hostname, path, and history
PS1="${green}\u${NC}@${yellow}\h${NC}[${purple}\w${NC}:${red}\!${NC}] \$ "
 
# colorize 'ls'
export LS_OPTIONS='--color=auto'
eval "`dircolors`"
alias ls='ls $LS_OPTIONS'

# Add some useful docker run functions

# Interactively run the cme docker (arg1, arg2)
#	arg1: image name:tag (e.g., cme:0.1.0)
#	arg2: optional command to run in container
#		instead of 'cme' (e.g., /bin/bash)
docker-cme() {
	docker run -it --rm --net=host --privileged --name cme \
		-v /data:/data -v /etc/network:/etc/network \
		-v /etc/ntp.conf:/etc/ntp.conf \
		-v /etc/localtime:/etc/localtime \
		-v /tmp/cmehostinput:/tmp/cmehostinput \
		-v /tmp/cmehostoutput:/tmp/cmehostoutput \
		-v /media/usb:/media/usb $1 $2
}

# Runs the cmehw docker (arg1, arg2)
#	arg1: image name:tag (e.g., cmehw:0.1.0)
#	arg2: optional command to run in containter
#		instead of 'cmehw' (e.g., /bin/bash)
docker-cmehw() {
	docker run -it --rm --privileged --name cme-hw \
		--device=/dev/spidev0.0:/dev/spidev0.0 \
		--device=/dev/spidev0.1:/dev/spidev0.1 \
		--device=/dev/mem:/dev/mem \
		-v /data:/data $1 $2
}

EOF
source .bashrc


# Set hostname
echo
echo "  Setting up hostname, hosts, and message of the day..."
curl -sSo /etc/hostname ${SETUP_SYSTEM}/hostname
/etc/init.d/hostname.sh

# Set hosts file with new hostname and our git01 server
curl -sSo /etc/hosts ${SETUP_SYSTEM}/hosts

# Add a branded message of the day
curl -sSo /etc/motd ${SETUP_SYSTEM}/motd
echo "  ...done with hostname, hosts, and motd"


# Set up networking
echo 
echo "  Setting up CME device networking..."
cp /etc/network/interfaces /etc/network/interfaces.ORIG
curl -sSo /etc/network/interfaces_static ${SETUP_SYSTEM}/interfaces_static
curl -sSo /etc/network/interfaces_dhcp ${SETUP_SYSTEM}/interfaces_dhcp

# This symlink sets network to use STATIC by default.  Replace
# interfaces_static with interfaces_dhcp to use DHCP instead.
rm /etc/network/interfaces
ln -s /etc/network/interfaces_static /etc/network/interfaces
echo "  ...networking set to STATIC IP address"


# We give each CME device an SSH key so it can easily access
# our code repository servers.
echo
echo "  Adding SSH keys for Transtector GIT server access..."
mkdir -p .ssh
cd .ssh
curl -sSO ${SETUP_SYSTEM}/id_rsa
curl -sSO ${SETUP_SYSTEM}/id_rsa.pub
echo "  ...SSH keys added for CUSCSGIT01.smiths.net access"
cd


# We add the certificate of authority from our GIT01 docker registry
# so the CME device can easily pull docker images.
echo
echo "  Adding a certificate of authority for Transtector Docker registry..."
mkdir -p /etc/docker/certs.d/cuscsgit01.smiths.net\:5000
cd /etc/docker/certs.d/cuscsgit01.smiths.net\:5000
curl -sSO ${SETUP_SYSTEM}/ca.crt
echo "   ...CA added for CUSCSGIT01:5000 Docker registry access" 
cd


# Install the Cme-init service unit file.  This is what
# will start Cme-init program when system boots.
echo
echo "  Installing the cmeinit.service module..."
cd /lib/systemd/system/
curl -sSO ${SETUP_SYSTEM}/cmeinit.service
systemctl daemon-reload
systemctl enable cmeinit
echo "  ...done with cmeinit.service"
cd


# Set up Cme-init
echo
echo "  Setting up Cme-init..."
mkdir Cme-init
pushd Cme-init
python -m venv cmeinit_venv
source cmeinit_venv/bin/activate
curl -sSO ${SETUP_SYSTEM}/${CMEINIT}
tar -xvzf ${CMEINIT}
rm ${CMEINIT}
pip install --no-index -f wheelhouse cmeinit
rm -rf wheelhouse
curl -sSO ${SETUP_SYSTEM}/cme-docker-fifo.sh # adds the docker FIFO script to Cme-init/
chmod u+x cme-docker-fifo.sh
popd
echo "  ...done with Cme-init"

# Setup the Cme (recovery) API
echo
echo "  Setting up Cme (recovery)..."
mkdir Cme
pushd Cme
python -m venv cme_venv
source cme_venv/bin/activate
curl -sSO ${SETUP_SYSTEM}/${CMERECOVERY}
tar -xvzf ${CMERECOVERY}
rm ${CMERECOVERY}
pip install --no-index -f wheelhouse cme
rm -rf wheelhouse
popd


# Setup the Cme API docker
echo
echo "  Loading Cme API docker..."
curl -sS ${SETUP}/${CME} | docker load
echo "  ...done loading Cme API docker"


# Setup the Cme-hw docker
echo
echo "  Loading Cme-hw docker..."
curl -sS ${SETUP}/${CMEHW} | docker load
echo "  ...done loading Cme-hw docker"

echo
echo "  Note the network settings are currently:"
echo "    (cat /etc/network/interfaces)"
echo
cat /etc/network/interfaces
echo
echo "   CME system setup complete - please reboot."
echo