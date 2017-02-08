#!/bin/bash

# Sets up a CME system.  Hostname, hosts, networking interfaces
# and additional files are copied from the folder where this script
# runs to /etc, /etc/network and other destinations.

# Set hostname
cp hostname /etc/hostname
/etc/init.d/hostname.sh

# Set hosts file with new hostname and our git01 server
cp hosts /etc/hosts

# Add a branded message of the day
cp motd /etc/motd

# Set up networking
mv /etc/network/interfaces /etc/network/interfaces.ORIG
cp interfaces_* /etc/network/

# This symlink sets network to use DHCP by default.  Replace
# interfaces_dhcp with interfaces_static to use a static address instead.
ln -s /etc/network/interfaces_dhcp /etc/network/interfaces

# We give each CME device an SSH key so it can easily access
# our code repository servers.
mkdir ~/.ssh
cp id_* ~/.ssh/

# We add the certificate of authority from our GIT01 docker registry
# so the CME device can easily pull docker images.
mkdir -p /etc/docker/certs.d/cuscsgit01.smiths.net\:5000
cp ca.crt /etc/docker/certs.d/cuscsgit01.smiths.net\:5000/
 
# Finally, set bash to have a nice looking color prompt
cp .bashrc ~/.bashrc
source ~/.bashrc

echo "CME system setup complete.  Please reboot."
