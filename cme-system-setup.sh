#!/bin/bash

# Sets up a CME system.  Hostname, hosts, networking interfaces
# and additional files are copied from the folder where this script
# runs to /etc, /etc/network and other destinations.

# This script requires some env variables to be setup in order to
# retrieve the installation files and versioned Cme applications.

VERSION="${VERISON:-1.0.0}"
SETUP="${SETUP:-https://s3.amazonaws.com/transtectorpublicdownloads/Cme}"

clear
echo
echo "    This script is intended to set up a CME device with all system components."
echo "    The CME device must be manually rebooted after the script runs.  The script"
echo "    allows several environment variables be set in order to retrieve the"
echo "    installation files and versioned application packages."
echo
echo "    Prior to running this script, you can export these environment variables:"
echo
echo "        VERSION - give a default version used if package version is not set"
echo "            default: ${VERSION}"
echo
echo "        SETUP - provide a URL that can be used by curl"
echo "            default: ${SETUP}"
echo
echo "        CME_INIT_VERSION - Cme-init (supervisor/launcher) program version"
echo
echo "        CME_API_RECOVERY_VERSION - API application for recovery mode"
echo "        CME_HW_RECOVERY_VERSION  - HARDWARE application for recovery mode"
echo "        CME_WEB_RECOVERY_VERSION - WEB application for recovery mode"
echo
echo "        CME_API_VERSION - API application for normal mode"
echo "        CME_HW_VERSION  - HARDWARE application for normal mode"
echo "        CME_WEB_VERSION - WEB application for normal mode"
echo
read -n1 -rsp "    CTRL-C to exit now, any other key to continue..." < "$(tty 0>&2)"
echo
clear

# SOFTWARE PART NUMBERS - these set by Transtector
CME_INIT_PN=1500-004
CME_API_PN=1500-005
CME_HW_PN=1500-006
CME_WEB_PN=1500-007


# CME Base Packages - these are essentially the base software
# that get installed to Cme device and will form the "recovery
# mode" base layer.  The application layer packages cannot
# easily be used to upgrade these packages on the end user equipment.
CME_INIT_VERSION="${CME_INIT_VERSION:-$VERSION}"
CME_API_RECOVERY_VERSION="${CME_API_RECOVERY_VERSION:-$VERSION}"
CME_HW_RECOVERY_VERSION="${CME_HW_RECOVERY_VERSION:-$VERSION}"
CME_WEB_RECOVERY_VERSION="${CME_WEB_RECOVERY_VERSION:-$VERSION}"

# CME Base Packages - package filenames
CME_INIT=${CME_INIT_PN}-v${CME_INIT_VERSION}-SWARE-CME_INIT.tgz
CME_API_RECOVERY=${CME_API_PN}-v${CME_API_RECOVERY_VERSION}-SWARE-CME_API.tgz
CME_HW_RECOVERY=${CME_HW_PN}-v${CME_HW_RECOVERY_VERSION}-SWARE-CME_HW.tgz
CME_WEB_RECOVERY=${CME_WEB_PN}-v${CME_WEB_RECOVERY_VERSION}-SWARE-CME_WEB.tgz


# CME Application Layers - these are just like the packages above but
# have been wrapped with a Docker container and made into a Docker image
# that can be loaded directly into the target device.  Note the ".pkg.tgz"
# suffix to distinguish them from the base packages.
CME_API_VERSION="${CME_API_VERSION:-$VERSION}"
CME_HW_VERSION="${CME_HW_VERSION:-$VERSION}"
CME_WEB_VERSION="${CME_WEB_VERSION:-$VERSION}"

# Application layers - package filenames
CME_API=${CME_API_PN}-v${CME_API_VERSION}-SWARE-CME_API.pkg.tgz
CME_HW=${CME_HW_PN}-v${CME_HW_VERSION}-SWARE-CME_HW.pkg.tgz
CME_WEB=${CME_WEB_PN}-v${CME_WEB_VERSION}-SWARE-CME_WEB.pkg.tgz

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

# Add GPIO support
export GPIO_STATUS_SOLID=5
export GPIO_STATUS_GREEN=6
export GPIO_STANDBY=19

# Set STATUS solid/blink
status_solid() {
        echo $GPIO_STATUS_SOLID > /sys/class/gpio/export
        echo "out" > /sys/class/gpio/gpio$GPIO_STATUS_SOLID/direction
        echo $1 > /sys/class/gpio/gpio$GPIO_STATUS_SOLID/value
}

# Set STATUS green/red
status_green(){
        echo $GPIO_STATUS_GREEN > /sys/class/gpio/export
        echo "out" > /sys/class/gpio/gpio$GPIO_STATUS_GREEN/direction
        echo $1 > /sys/class/gpio/gpio$GPIO_STATUS_GREEN/value
}

# STANDBY (powers down if we've got correct power control installed)
standby() {
        status_solid "0"
        status_green "0"
        echo $GPIO_STANDBY > /sys/class/gpio/export
        echo "out" > /sys/class/gpio/gpio$GPIO_STANDBY/direction
        echo "1" > /sys/class/gpio/gpio$GPIO_STANDBY/value
        sleep 1
        shutdown -h now
}


# Add some useful docker run functions

# Interactively run the cme-api docker (arg1, arg2)
#	arg1: image name:tag (e.g., cmeapi:0.1.0)
#	arg2: optional command to run in container
#		instead of 'cmeapi' (e.g., /bin/bash)
docker-cmeapi() {
	docker run -it --rm --net=host --privileged --name cme-api \
		--volumes-from cme-web \
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

EOF
source .bashrc


# Set hostname
echo
echo "  Setting up hostname, hosts, message of the day (motd) and issue..."
cat <<'EOF' > /etc/hostname
cme

EOF

# Set hosts file with new hostname and our git01 server
cat <<'EOF' > /etc/hosts
10.252.64.224	cuscsgit01	cuscsgit01.smiths.net

127.0.0.1	localhost
127.0.1.1	cme

EOF

# Add a branded message of the day
cat <<'EOF' > /etc/motd

Transtector CME (Raspbian/Debian GNU/Linux)

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.

EOF

# Add the IP address for eth0 to /etc/issue
cat <<'EOF' > /etc/issue
Raspbian GNU/Linux 8 \n \l
IP Address: \4{eth0}

EOF

# set the kernel hostname
/etc/init.d/hostname.sh

echo "  ...done with hostname, hosts, motd, and issue"


# Set up networking
echo 
echo "  Setting up CME device networking..."
cp /etc/network/interfaces /etc/network/interfaces.ORIG

# Static networking (default)
cat <<'EOF' > /etc/network/interfaces_static
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0

iface eth0 inet static
	address 192.168.1.30
	netmask 255.255.255.0
	gateway 192.168.1.1
	dns-nameservers 8.8.4.4 8.8.8.8

EOF

# DHCP networking
cat <<'EOF' > /etc/network/interfaces_dhcp
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

EOF

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

# Private CME client key
cat <<'EOF' > id_rsa
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAogauSTqZDiNh2uhm376SYPEqCvJQpwWY8tOnall137JqECEq
qeZ+tZRNn+Ao+ioeNnJHldSIrPkd3hsEZ7+kQbjD2EvmFsnKKkxz43e59al+K0vR
clxO9ab2YSkwy2dY+coMokECWOe7fml5QIAzdcN+Im8Uqq78ADSvKpcogEwKYfpr
7Qp+lZfDcXbA/nzGESSeLJdv2M/nBhvkD9armWOx8WPNezAP/QBrqgb9H18WI1rf
DKQwnrrz87S3pfmOZx5zw/9Y+PTgRuwc2jN3jqRSGCesG79nkuQbNjuzmHaF349O
i8fYAWRjxtjuNa6Mu8/Cbhilp4eHUG4+6CjIBQIDAQABAoIBAFy7oCKvVAxAefA1
VTO3ucWcIaj0OO7vCDPqqYX3v7wRPB0RLn7hOiIoyCi5vho34uTckVYSt0rwpYSK
SAItMBChdA2mmwDt6zQ8X5OP4bHVmS2kjjJ63IJCVf8T+SZhdw438vUmafaCYtAe
A9TDyzAafGWu19A8qGRhwuOIchjDA3DbGi9HnfmVvrGfgjElMi6DDs6+Muqo9ZqD
2XCaMZFRJXk4z4xBB7YYB4GOmUrpFubM6yfR9KXA2X0zYuq8S3zN6OpPYavoU9Zl
j1EQ3BTXKInfZJEXjGhL2MisuNq/RsGm3f1PTUWQVqXtPsKr1+QKAbP4IBTLogEO
BRgzXL0CgYEA0YoEjtd4oXuUJAvOYMSr3DMaWrhYJQSkfF2uK+Kbdd4CdyIJLaYh
/8OHrcWvZBdlMZjw74Xh3aVl7IrAMax7sM63o7EfPFifiHYDcoHWEBWOmuUjDuNV
iYBTn6gHiufv2euytgGa03+DlIldnIUcyYA3gFp+nbWruDYxTK5QGh8CgYEAxfOz
T/6h2J2+9gETbX797eApOfm5ajRUCZNSkB4VDMx8OyDUSfPU9Wa67UKvD8GBTzW1
qN5gxxHWYc6g432DeWj4xlb5OmGm/hpZq1ubBQDmuQO4lk9kg2OxF5JzyPqeIDlp
S9h/dcGGMvH4Z04e/TZTl9/JiGttkNAFxYp+oVsCgYA/QTLvDAzWcr/dwdKjU7ut
1Z93E39IbYZaJM2XYekcQ9DqtdOffC93Tkd/JdY0mPtrZYgWRoxQpMWICrrKRA9y
6HR3bdjIFtjSEQ4pWxiL8nYCPHnA3M/NmnekEs10GWBGoOhqGUHr5uqJxI4F2gk+
qv4WOTtP0K/uBC4Nv/FecQKBgQCRKpe8OVL9ZSmOhNl3eiLEGJiDMLSdwwRCBW0N
zVHIkgkk331vQkZRNOYuarGxD0pCCXRQA8zbECS0k3B/hCMvnSCba1rYSpbJUA+k
T8iOUcvhsG3kpRJkHG7Zh4grwkbGAPRML9fBRougvrxZHfwx225QOUg1J/swsK0a
4ebdcwKBgDoyC1VoKac7E4xumsdpLbfNdRluOjr/MBRuyjlvi0pBr9qSVv0E7A2f
t63V6hq3nqCaQZs69Jp1s5TGhLe6kuHXq77BomMwcl5UzmqxoVQbKO+GimbJUyQY
uN5Mis9LeogPT1td+RQh9vu/pJTYtExo5P4ty6Dk9ChxkGSGsniN
-----END RSA PRIVATE KEY-----
EOF

# Public CME client key
cat <<'EOF' > id_rsa.pub
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCiBq5JOpkOI2Ha6GbfvpJg8SoK8lCnBZjy06dqWXXfsmoQISqp5n61lE2f4Cj6Kh42ckeV1Iis+R3eGwRnv6RBuMPYS+YWycoqTHPjd7n1qX4rS9FyXE71pvZhKTDLZ1j5ygyiQQJY57t+aXlAgDN1w34ibxSqrvwANK8qlyiATAph+mvtCn6Vl8NxdsD+fMYRJJ4sl2/Yz+cGG+QP1quZY7HxY817MA/9AGuqBv0fXxYjWt8MpDCeuvPztLel+Y5nHnPD/1j49OBG7BzaM3eOpFIYJ6wbv2eS5Bs2O7OYdoXfj06Lx9gBZGPG2O41roy7z8JuGKWnh4dQbj7oKMgF root@cme
EOF

echo "  ...SSH keys added for CUSCSGIT01.smiths.net access"
cd


# We add the certificate of authority from our GIT01 docker registry
# so the CME device can easily pull docker images.
echo
echo "  Adding a certificate of authority for Transtector Docker registry..."
mkdir -p /etc/docker/certs.d/cuscsgit01.smiths.net\:5000
cd /etc/docker/certs.d/cuscsgit01.smiths.net\:5000

cat <<'EOF' > ca.crt
-----BEGIN CERTIFICATE-----
MIIGJTCCBA2gAwIBAgIJAKYCgcSXs4owMA0GCSqGSIb3DQEBCwUAMIGoMQswCQYD
VQQGEwJVUzETMBEGA1UECAwKU29tZS1TdGF0ZTEcMBoGA1UECgwTU21pdGhzIElu
dGVyY29ubmVjdDEUMBIGA1UECwwLVHJhbnN0ZWN0b3IxHjAcBgNVBAMMFWN1c2Nz
Z2l0MDEuc21pdGhzLm5ldDEwMC4GCSqGSIb3DQEJARYhamFtZXMuYnJ1bm5lckBz
bWl0aHNtaWNyb3dhdmUuY29tMB4XDTE2MTAwNzE2MjI0OVoXDTE3MTAwNzE2MjI0
OVowgagxCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApTb21lLVN0YXRlMRwwGgYDVQQK
DBNTbWl0aHMgSW50ZXJjb25uZWN0MRQwEgYDVQQLDAtUcmFuc3RlY3RvcjEeMBwG
A1UEAwwVY3VzY3NnaXQwMS5zbWl0aHMubmV0MTAwLgYJKoZIhvcNAQkBFiFqYW1l
cy5icnVubmVyQHNtaXRoc21pY3Jvd2F2ZS5jb20wggIiMA0GCSqGSIb3DQEBAQUA
A4ICDwAwggIKAoICAQC5KPApU+XC55watTsjZTmDIijk+pdbe3GDL5HJggrFaF2i
Fhsij/v96i9YoykP/QE3VuOGyDSNYX7c6WsePWahLrffN/S4lSu/3yCPFvZ4o/RN
Nnu6R40v1dymZaUwwc2qbSlwZtcz6QhZ0uzCxEWPEQV604ehvsmKtEklC6qmQhaf
xe8ObYlmRw77579mEuQZceg7pbEz+/CwXZxhPlEMLY9EmZkkCzASnQCCtMrx2U9G
m+T9GsgRmDsVvYsYdyZivZofhhYTTtYt8Nl9ToIwuJU7X9Gm7FjNrqkFUgOUvzkl
UgwaXfpIMr2x3j9sv0jKhVh0ZJ77xaYFayC0hB0mzBGtjA7a3ml8EeTJjI5cWI9X
a6DGKoX46sWwFT3ZonlqkowzPOqY8BMDFQbkn2uq5Esyz5/CstoUi2/bicgwyXjU
GpmdUGUzUG75lilQQv75B1EaUx8oOGcLDk2qHMLB2sMPZ54MnRaSwDpRVHTNIa/e
Sz65PS5NIzytA002JOKwONVMbL3CFlAePG7/HA79cKMw+eMl8egGg4HBu12V1Ats
MCVTFQtSaJBH0M6nUOgNX2Xmh7S01eyMF+Dh+u2wWcWW42J2x/aRtCwKwpbOxcPv
FbW4muZjMjLHUV510wgYNAbpPZCYp07faN2ge4WRCeXytH8swakA6Lb4fSe3sQID
AQABo1AwTjAdBgNVHQ4EFgQU42BCB2SGBwfW4SClFckcYakzlLUwHwYDVR0jBBgw
FoAU42BCB2SGBwfW4SClFckcYakzlLUwDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0B
AQsFAAOCAgEAguM7ZAO/xzPht8/fCEln5BDoVnUQ19VRCLi451SEilzaCLV0WoGc
D9AjCl5z4QRg3KBdp8xD7I3MlFiqo97bsPMupXLzjWeKdLXx3FkULXWnx25lyb2C
7HSuCePkhvyexU1zCWOetBuz0fjrvWH1G6eMl+00nAiwkpspyKvec5ueorH8lOEb
qX+oqvdU8XJanflpnEe6S6/s0GKMWGwQNPrQKUBxY97hxBSTZypws1/zS8p6edg3
M4oXx9nGbPvHeBkh82LQFF5ilM+atT4tEpnX3/NQyE++o1EtGmZYg3Ph6QZ2+EPs
SL266dbdnpM+Np06AClkFOCb12T2JgO7DLKxNvKsig9sWhHS1y14oCaU9TZ3PiY5
MSheZTXJPdpLziH5lgzu6488NccRUR8vKJ6mYZ1GSUeKEptU+nzamFNTEZYBCgYV
NHrpHCQ8GMrmlLHqRug/4DkDURSdqL+vJQdX+IBoTUcS4W3sjtiH5fjYkHBKdDRZ
7Q2DVdUKRXzTx4bWDgT5u0rat7qauEw53k0Ra+YS7cpwpb00d4nXo2OOTeQSiys6
ydccYlvGmCniXJ9+BZSlBG4i9gwGyxL97+PM/WkIPKJvS0ixm0jb+m72o8pTozU8
dJgRLENHI9aTFWqs99NoiWeP6MrRxzA6taI6BtQLxRtUK4EV3Jqnpjw=
-----END CERTIFICATE-----
EOF
cd
echo "   ...CA added for CUSCSGIT01:5000 Docker registry access" 


# Install the Cme-init service unit file.  This is what
# will start Cme-init program when system boots.
echo
echo "  Installing the cmeinit.service module..."
cd /lib/systemd/system/
cat <<'EOF' > cmeinit.service
[Unit]
Description=CME System Service
After=multi-user.target

[Service]
Type=idle
Environment=VIRTUAL_ENV=/root/Cme-init/cmeinit_venv
Environment=PATH=$VIRTUAL_ENV/bin:/usr/sbin:/usr/bin:/sbin:/bin
WorkingDirectory=/root/Cme-init
ExecStart=/root/Cme-init/cmeinit_venv/bin/python -m cmeinit
TimeoutStopSec=6

[Install]
WantedBy=multi-user.target

EOF
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
curl -sSO ${SETUP}/${CME_INIT}
tar -xvzf ${CME_INIT}
rm ${CME_INIT}
pip install --no-index -f wheelhouse cmeinit
rm -rf wheelhouse

# Add cme-docker-fifo for running system commands from dockers
cat <<'EOF' > cme-docker-fifo.sh
#!/bin/bash

IN=/tmp/cmehostinput
OUT=/tmp/cmehostoutput

function cleanup {
	rm -f $IN
	rm -f $OUT
}
trap cleanup EXIT

if [[ ! -p $IN ]]; then
	mkfifo $IN
fi

if [[ ! -p $OUT ]]; then
	mkfifo $OUT
fi

cleanup

while true
do
	if read line <$IN; then
		args=(${line})

		case ${args[0]} in

			quit) break ;;

			date|shutdown|reboot|systemctl|ntpq) ${args[@]} | tee $OUT ;;

			*) printf "unknown: %s" "${args[0]}" | tee $OUT ;;
		esac
	fi
done

EOF
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
curl -sSO ${SETUP}/${CME_API_RECOVERY}
tar -xvzf ${CME_API_RECOVERY}
rm ${CME_API_RECOVERY}
pip install --no-index -f wheelhouse cmeapi
rm -rf wheelhouse
popd


# Setup the Cme-hw layer (recovery)
echo
echo "  Setting up Cme-hw (recovery)..."
mkdir Cme-hw
pushd Cme-hw
python -m venv cmehw_venv
source cmehw_venv/bin/activate
curl -sSO ${SETUP}/${CME_HW_RECOVERY}
tar -xvzf ${CME_HW_RECOVERY}
rm ${CME_HW_RECOVERY}
pip install --no-index -f wheelhouse cmehw
rm -rf wheelhouse
popd



# Setup the Cme-web application (recovery)
echo
echo "  Setting up Cme-web (recovery)..."
mkdir /www
pushd /www
curl -sSO ${SETUP}/${CME_WEB_RECOVERY}
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
