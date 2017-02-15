#!/bin/bash

# Sets up a CME system.  Hostname, hosts, networking interfaces
# and additional files are copied from the folder where this script
# runs to /etc, /etc/network and other destinations.

# Before running this script, export SETUP to the URL used
# for supplying this and additional files to curl.

echo
echo "  This script is intended to set up a CME device with all system components."
echo "  The CME device must be manually rebooted after the script runs and a SETUP"
echo "  environment variable MUST indiate the server where this script came from."
echo
echo "  For example,"
echo
echo "    $ export SETUP=https://s3.amazonaws.com/transtectorpublicdownloads/Cme/cme_system"
echo
read -n1 -rsp "    CTRL-C to exit now, any other key to continue..." < "$(tty 0>&2)"
echo


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
curl -o /etc/hostname ${SETUP}/hostname
/etc/init.d/hostname.sh

# Set hosts file with new hostname and our git01 server
curl -o /etc/hosts ${SETUP}/hosts

# Add a branded message of the day
curl -o /etc/motd ${SETUP}/motd
echo "  ...done with hostname, hosts, and motd"


# Set up networking
echo 
echo "  Setting up CME device networking..."
cp /etc/network/interfaces /etc/network/interfaces.ORIG
curl -o /etc/network/interfaces_static ${SETUP}/interfaces_static
curl -o /etc/network/interfaces_dhcp ${SETUP}/interfaces_dhcp

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
curl -O ${SETUP}/id_rsa
curl -O ${SETUP}/id_rsa.pub
echo "  ...SSH keys added for CUSCSGIT01.smiths.net access"
cd


# We add the certificate of authority from our GIT01 docker registry
# so the CME device can easily pull docker images.
echo
echo "  Adding a certificate of authority for Transtector Docker registry..."
mkdir -p /etc/docker/certs.d/cuscsgit01.smiths.net\:5000
cd /etc/docker/certs.d/cuscsgit01.smiths.net\:5000
curl -O ${SETUP}/ca.crt
echo "   ...CA added for CUSCSGIT01:5000 Docker registry access" 
cd


# Install the Cme-init service unit file.  This is what
# will start Cme-init program when system boots.
echo
echo "  Installing the cmeinit.service module..."
cd /lib/systemd/system/
curl -O ${SETUP}/cmeinit.service
systemctl daemon-reload
systemctl enable cmeinit
echo "  ...done with cmeinit.service"
cd


# Set up Cme-init
CMEINIT_VERSION=0.1.0
CMEINIT=1510-000-v${CMEINIT_VERSION}-SWARE-CME_INIT.tgz

echo
echo "  Setting up Cme-init..."
mkdir Cme-init
pushd Cme-init
python -m venv cmeinit_venv
source cmeinit_venv/bin/activate
curl -O ${SETUP}/${CMEINIT}
tar -xvzf ${CMEINIT}
rm ${CMEINIT}
pip install --no-index -f wheelhouse cmeinit
rm -rf wheelhouse
curl -O ${SETUP}/cme-docker-fifo.sh # adds the docker FIFO script to Cme-init/
popd
echo "  ...done with Cme-init"

# Setup the Cme (recovery) API
CME_VERSION=0.1.0
CME=1500-000-v${CME_VERSION}-SWARE-CME_RECOVERY.tgz

echo
echo "  Setting up Cme (recovery)..."
mkdir Cme
pushd Cme
python -m venv cme_venv
source cme_venv/bin/activate
curl -O ${SETUP}/${CME}
tar -xvzf ${CME}
rm ${CME}
pip install --no-index -f wheelhouse cme
rm -rf wheelhouse
popd

echo
echo "   CME system setup complete - please reboot."
