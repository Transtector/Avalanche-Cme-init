#!/bin/bash

# Run this script to build the Cme-init (initialization and supervisory
# layer) distribution tarball that can be downloaded to a CME device
# and installed.

# Requires Cme-init source folder
SRC=/root/Cme-init

# Source files copied to SRCDIST
SRCDIST=/root/srcdist

# System built to DIST
DIST=/root/dist

# Point PIP env paths to wheelhouse
export WHEELHOUSE=${DIST}/wheelhouse
export PIP_WHEEL_DIR=${DIST}/wheelhouse
export PIP_FIND_LINKS=${DIST}/wheelhouse

mkdir ${SRCDIST}
mkdir ${DIST}
mkdir ${WHEELHOUSE}

# Copy source files over to srcdist/
# Note: this is to avoid wheel adding a bunch of files and
# directories that are not needed in the distribution.
pushd ${SRCDIST}
cp -R ${SRC}/cmeinit/ .
cp ${SRC}/VERSION .
cp ${SRC}/setup.py .


# Activate the Cme-init venv
source ${SRC}/cmeinit_venv/bin/activate

# Generate the wheels for the application.
# These will show up in WHEELHOUSE
pip wheel .

# Copy the top-level VERSION file
cp ${SRCDIST}/VERSION ${DIST}/VERSION

# Wheels are built - done with srcdist/
popd
rm -rf ${SRCDIST}

# Now generate the archive of the wheels
pushd ${DIST}

# Read the VERSION file to use in the created archive name
VERSION=$(<VERSION)
ARCHIVE=1510-000-v$VERSION-SWARE-CME_INIT.tgz

tar -czvf ../${ARCHIVE} .

# Done with the built distribution
popd
rm -rf ${DIST}

echo "Done!"
exit 0