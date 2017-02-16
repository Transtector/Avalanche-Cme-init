#!/bin/bash

# Run this script to build the Cme-init (initialization and supervisory
# layer) distribution tarball that can be downloaded to a CME device
# and installed.

# Set project source directory
SRC=$(pwd)/Cme-init

# Read the VERSION file to use in the created archive name
VERSION=$(<${SRC}/VERSION)
ARCHIVE=1500-000-v$VERSION-SWARE-CME_INIT.tgz

# Point PIP env paths to wheelhouse
export WHEELHOUSE=dist/wheelhouse
export PIP_WHEEL_DIR=$WHEELHOUSE
export PIP_FIND_LINKS=$WHEELHOUSE

# Make the temp directories
mkdir srcdist  # source files copied here for the build
mkdir -p ${WHEELHOUSE} # PIP stores the built wheels here

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

popd
cp srcdist/VERSION dist # copy VERSION
rm -rf srcdist # done w/srcdist

# Now generate the archive of the wheels
pushd dist

tar -czvf ../${ARCHIVE} .

# Done with the built distribution
popd
rm -rf dist

echo "Done!"
