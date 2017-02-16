#!/bin/bash

# Run this script to build the Cme-init (initialization and supervisory
# layer) distribution tarball that can be downloaded to a CME device
# and installed.

# Set project source directory
SRC=Cme-init

# Read the VERSION file to use in the created archive name
VERSION=$(<${SRC}/VERSION)
ARCHIVE=1500-000-v$VERSION-SWARE-CME_INIT.tgz

# Point PIP env paths to wheelhouse
export WHEELHOUSE=dist/wheelhouse
export PIP_WHEEL_DIR=dist/wheelhouse
export PIP_FIND_LINKS=dist/wheelhouse

# Make the temp directories
mkdir srcdist  # source files copied here for the build
mkdir -p dist/${WHEELHOUSE} # PIP stores the built wheels here

# Copy source files over to srcdist/
# Note: this is to avoid wheel adding a bunch of files and
# directories that are not needed in the distribution.
pushd srcdist
cp -R ${SRC}/cmeinit/ .
cp ${SRC}/VERSION .
cp ${SRC}/setup.py .


# Activate the Cme-init venv
source ${SRC}/cmeinit_venv/bin/activate

# Generate the wheels for the application.
# These will show up in WHEELHOUSE
pip wheel .

# Copy the top-level VERSION file
cp srcdist/VERSION dist

# Wheels are built - done with srcdist/
popd
rm -rf srcdist

# Now generate the archive of the wheels
pushd dist

tar -czvf ../${ARCHIVE} .

# Done with the built distribution
popd
rm -rf dist

echo "Done!"
