#!/bin/bash
set -e

# Get the putS3 function
source $HOME/.bashrc

SRC=$(pwd)  # run from project source folder
APP=${SRC##*/}

CME_INIT_PN=1500-004

# Increment VERSION build number; the '123' in 1.0.0-123
VERSION=$(<${SRC}/VERSION)
IFS='-' read -ra PARTS <<< "${VERSION}"
BUILD_NUMBER=${PARTS[1]}
((BUILD_NUMBER++))
$(echo "${PARTS[0]}-${BUILD_NUMBER}" > ${SRC}/VERSION)
VERSION=$(<${SRC}/VERSION)

BASENAME=${CME_INIT_PN}-v${VERSION}-SWARE-CME_INIT

PACKAGE=${BASENAME}.tgz

# Stage 1.  Build and publish base (recovery) package
echo
echo "    Stage 1.  Building and publishing base package: ${PACKAGE} ..."
echo

# Build base image
build/build.sh 

echo
echo "    ... done building."
echo

# Publish base image to S3
cd build
putS3 ${PACKAGE} Cme
cd ..

# Add current system setup script
putS3 cme-system-setup.sh Cme

echo
echo "    ... done publishing."
echo


# Stage 2.  There is no stage 2 for CME_INIT...
echo
echo "    Stage 2.  Doing nothing - there is no stage 2 for CME_INIT ..."
echo

echo
echo "    ... All done!"
echo
