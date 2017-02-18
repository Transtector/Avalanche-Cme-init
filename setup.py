import os
from setuptools import setup

# version (i.e., cme.firmware) is stored in the VERSION file in package root
with open(os.path.join(os.getcwd(), 'VERSION')) as f:
	version = f.readline().strip()

setup (
	name					= "cmeinit",
	version					= version,
	description				= "CME initialization and supervisory system",
	packages				= ['cmeinit', 'cmeinit.common'],
	include_package_data	= True,
	zip_safe				= False,
	install_requires		= ["semver", "RPi.GPIO"],
	entry_points			= {'console_scripts': ['cmeinit = cmeinit.__main__:main'] }
)
