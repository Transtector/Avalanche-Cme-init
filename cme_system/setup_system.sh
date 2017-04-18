#!/bin/bash

# Sets up a CME system.  Hostname, hosts, networking interfaces
# and additional files are copied from the folder where this script
# runs to /etc, /etc/network and other destinations.

# This script requires some env variables to be setup in order to
# retrieve the installation files and versioned Cme applications.

echo
echo "  This script is intended to set up a CME device with all system components."
echo "  The CME device must be manually rebooted after the script runs.  The script"
echo "  allows several environment variables be set in order to retrieve the"
echo "  installation files and versioned application packages."
echo
echo "  Prior to running this script, you can export these environment variables:"
echo
echo "    VERSION - give a default version used if package version is not set"
echo "        $ export VERSION=1.0.0"
echo
echo "    SETUP - provide a URL that can be used by curl"
echo "        $ export SETUP=https://s3.amazonaws.com/transtectorpublicdownloads/Cme"
echo
echo "    CME_INIT_VERSION - identify the Cme-init program version to install"
echo "        $ export CME_INIT_VERSION=1.0.0"
echo
echo "    CME_API_RECOVERY_VERSION - identify the Cme-api program installed for recovery mode operation"
echo "        $ export CME_API_RECOVERY_VERSION=1.0.0"
echo
echo "    CME_WEB_RECOVERY_VERSION - identify the Cme-web application installed for recovery mode operation"
echo "        $ export CME_WEB_RECOVERY_VERSION=1.0.0"
echo
echo "    CME_API_VERSION - identify the application layer API program version"
echo "        $ export CMEAPI_VERSION=1.0.0"
echo
echo "    CME_HW_VERSION - identify the application layer hardware program version"
echo "        $ export CME_HW_VERSION=1.0.0"
echo
echo "    CME_WEB_VERSION - identify the web application  version"
echo "        $ export CME_WEB_VERSION=1.0.0"
echo
read -n1 -rsp "    CTRL-C to exit now, any other key to continue..." < "$(tty 0>&2)"
echo

# SOFTWARE PART NUMBERS - these set by Transtector
CME_INIT_PN=1500-004
CME_API_PN=1500-005
CME_HW_PN=1500-006
CME_WEB_PN=1500-007

# Default version
VERSION="${VERISON:-1.0.0}"

# Set some default values

# Download URL
SETUP="${SETUP:-https://s3.amazonaws.com/transtectorpublicdownloads/Cme}"

# CME Base Packages - these are essentially the base software
# that get installed to Cme device and will form the "recovery
# mode" base layer.  The application layer packages cannot
# easily be used to upgrade these packages on the end user equipment.
CME_INIT_VERSION="${CME_INIT_VERSION:-$VERSION}"
CME_API_RECOVERY_VERSION="${CME_API_RECOVERY_VERSION:-$VERSION}"
CME_WEB_RECOVERY_VERSION="${CME_WEB_RECOVERY_VERSION:-$VERSION}"

# CME Base Packages - package filenames
CME_INIT=${CME_INIT_PN}-v${CME_INIT_VERSION}-SWARE-CME_INIT.tgz
CME_API_RECOVERY=${CME_API_PN}-v${CME_API_RECOVERY_VERSION}-SWARE-CME_API.tgz
CME_WEB_RECOVERY=${CME_WEB_PN}-v${CME_WEB_RECOVERY_VERSION}-SWARE-CME_WEB.tgz


# CME Application Layers - these are just like the packages above but
# have been wrapped with a Docker container and made into a Docker image
# that can be loaded directly into the target device.  Note the "_pkg.tgz"
# suffix to distinguish them from the base packages.
CME_API_VERSION="${CME_API_VERSION:-$VERSION}"
CME_HW_VERSION="${CME_HW_VERSION:-$VERSION}"
CME_WEB_VERSION="${CME_WEB_VERSION:-$VERSION}"

# Application layers - package filenames
CME_API=${CME_API_PN}-v${CME_API_VERSION}-SWARE-CME_API_pkg.tgz
CME_HW=${CME_HW_PN}-v${CME_HW_VERSION}-SWARE-CME_HW_pkg.tgz
CME_WEB=${CME_WEB_PN}-v${CME_WEB_VERSION}-SWARE-CME_WEB_pkg.tgz



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

# Interactively run the cme-api docker (arg1, arg2)
#	arg1: image name:tag (e.g., cmeapi:0.1.0)
#	arg2: optional command to run in container
#		instead of 'cmeapi' (e.g., /bin/bash)
docker-cmeapi() {
	docker run -it --rm --net=host --privileged --name cme-api \
		-v /data:/data -v /etc/network:/etc/network \
		-v /etc/ntp.conf:/etc/ntp.conf \
		-v /etc/localtime:/etc/localtime \
		-v /tmp/cmehostinput:/tmp/cmehostinput \
		-v /tmp/cmehostoutput:/tmp/cmehostoutput \
		-v /media/usb:/media/usb $1 $2
}

# Runs the cme-hw docker (arg1, arg2)
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

# Runs the cme-web docker (arg1, arg2)
#	arg1: image name:tag (e.g., cmeweb:0.1.0)
#	arg2: optional command to run in containter
#		instead of '/bin/bash'
docker-cmeweb() {
	docker run -it --rm $1 $2
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
curl -sSO ${SETUP_SYSTEM}/${CME_INIT}
tar -xvzf ${CME_INIT}
rm ${CME_INIT}
pip install --no-index -f wheelhouse cmeinit
rm -rf wheelhouse
curl -sSO ${SETUP_SYSTEM}/cme-docker-fifo.sh # adds the docker FIFO script to Cme-init/
chmod u+x cme-docker-fifo.sh
popd
echo "  ...done with Cme-init"


# Setup the Cme-api layer (recovery)
echo
echo "  Setting up Cme-api (recovery)..."
mkdir Cme-api
pushd Cme-api
python -m venv cmeapi_venv
source cmeapi_venv/bin/activate
curl -sSO ${SETUP_SYSTEM}/${CME_API_RECOVERY}
tar -xvzf ${CME_API_RECOVERY}
rm ${CME_API_RECOVERY}
pip install --no-index -f wheelhouse cmeapi
rm -rf wheelhouse
popd


# Setup the Cme-web application (recovery)
echo
echo "  Setting up Cme-web (recovery)..."
mkdir /www
pushd /www
curl -sSO ${SETUP_SYSTEM}/${CME_WEB_RECOVERY}
tar -xvzf ${CME_WEB_RECOVERY}
rm ${CME_WEB_RECOVERY}
popd


# Setup the Cme API docker
echo
echo "  Loading Cme API docker..."
curl -sS ${SETUP}/${CME_API} | docker load
echo "  ...done loading Cme API docker"


# Setup the Cme-hw docker
echo
echo "  Loading Cme-hw docker..."
curl -sS ${SETUP}/${CME_HW} | docker load
echo "  ...done loading Cme-hw docker"


# Setup the Cme-web docker
echo
echo "  Loading Cme-web docker..."
curl -sS ${SETUP}/${CME_WEB} | docker load
echo "  ...done loading Cme-web docker"


echo
echo "  Note the network settings are currently:"
echo "    (cat /etc/network/interfaces)"
echo
cat /etc/network/interfaces
echo
echo "   CME system setup complete - please reboot."
echo
