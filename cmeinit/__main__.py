# CME initialization script to handle the STATUS LED and
# RESET functionality.  This script runs at boot from rc.local
# and requires the associated virtual environment to be
# activated.
import signal, os, sys, glob, time, subprocess, threading
from datetime import datetime

import RPi.GPIO as GPIO
import semver

from .common import Config, Logging
from .common.Reboot import restart


# set by the cleanup callback on SIGTERM
# and shutsdown hardware loop
SHUTDOWN_FLAG = False

# set in main
LOGGER = None

# Set the GPIO pin numbers
GPIO_STATUS_SOLID = 5 # Write 1/True for solid, 0/False for blinking
GPIO_STATUS_GREEN = 6 # Write 1/True for green, 0/False for red
GPIO_N_RESET = 16 # Read 0/Low/False (falling edge) to detect reset button pushed
GPIO_STANDBY = 19 # Write 1/True to shutdown power (using power control MCU)


def InitializeGPIO():
	# Use Broadcom GPIO numbering
	GPIO.setmode(GPIO.BCM)

	# Setup the GPIO hardware and initialize the outputs
	GPIO.setup(GPIO_STATUS_SOLID, GPIO.OUT, initial=False) # Start w/blinking
	GPIO.setup(GPIO_STATUS_GREEN, GPIO.OUT, initial=True) # Start w/green
	GPIO.setup(GPIO_N_RESET, GPIO.IN, pull_up_down=GPIO.PUD_UP) # Detect falling edge
	GPIO.setup(GPIO_STANDBY, GPIO.OUT, initial=False) # Start w/power on

	# Add the reset falling edge detector; bouncetime of 50 ms means subsequent edges are ignored for 50 ms.
	GPIO.add_event_detect(GPIO_N_RESET, GPIO.FALLING, callback=reset, bouncetime=50)


def SetupSignaling():
	# SIGTERM signal handler - called at shutdown (see common/Reboot.py)
	# This lets us reboot/halt from other code modules without having
	# GPIO included in them. Note that there are some issues with
	# SIGTERM under systemd and therefore we must also listen for
	# SIGHUP for cleanup as well.
	signal.signal(signal.SIGTERM, cleanup)
	signal.signal(signal.SIGHUP, cleanup)


def reset(ch):
	''' Hardware reset button callback

		Software edge debounce - check level after 50 ms
		and return if still HIGH (false trigger).
	'''
	time.sleep(0.05)
	if GPIO.input(GPIO_N_RESET) == GPIO.HIGH:
		return

	# Else once we get here we're rebooting and nothing can stop us!
	LOGGER.info("Reset detected")

	# on reset detect, set STATUS BLINKING/GREEN
	GPIO.output(GPIO_STATUS_GREEN, True)
	GPIO.output(GPIO_STATUS_SOLID, False)

	# get start time
	reset_start_seconds = time.time()
	elapsed_seconds = 0

	# when reset button is released, we'll have
	# updated these Booleans (maybe)
	recovery_mode = False
	factory_reset = False
	power_off = False

	# Wait for reset button release and measure the time that takes.
	# This loop stops if any of these:
	# 	Reset button released (GPIO_N_RESET == GPIO.HIGH)
	# 	Button held long enough to trigger power off/standby
	while GPIO.input(GPIO_N_RESET) == GPIO.LOW and not power_off:

		elapsed_seconds = time.time() - reset_start_seconds

		# blink red after RESET_REBOOT_SECONDS
		if elapsed_seconds > Config.RECOVERY.RESET_REBOOT_SECONDS:
			if not recovery_mode:
				LOGGER.info("Reset to recovery mode signal detected")
				recovery_mode = True
				GPIO.output(GPIO_STATUS_GREEN, False)

		# solid red after RESET_RECOVERY_SECONDS
		if elapsed_seconds > Config.RECOVERY.RESET_RECOVERY_SECONDS:
			if not factory_reset:
				LOGGER.info("Reset factory defaults signal detected")
				factory_reset = True
				GPIO.output(GPIO_STATUS_SOLID, True)

		# power off/standby after RESET_FACTORY_SECONDS
		if elapsed_seconds > Config.RECOVERY.RESET_FACTORY_SECONDS:
			LOGGER.info("Reset power off/standby signal detected")

			power_off = True
			recovery_mode = False
			factory_reset = False

		# sleep just a bit
		time.sleep(0.02)

	# trigger a reboot if we're not powering off
	# there is a short delay on the reboot to let
	# us clean up cleanly
	restart(power_off=power_off, recovery_mode=recovery_mode, factory_reset=factory_reset, LOGGER=LOGGER)


def cleanup(signum=None, frame=None):
	''' Exit gracefully - set LED status RED/BLINKING then clean up and exit.  
		cleanup() is primarily called indirectly by detecting the SIGTERM
		signal sent by the system at shutdown (see common/Reboot.py).  Note
		that the Cme-init program must signal the general "running" state
		before the power off signal will be detected by the MCU.
	'''
	global SHUTDOWN_FLAG
	if SHUTDOWN_FLAG: # we've already received SIGTERM and set this
		return

	SHUTDOWN_FLAG = True

	LOGGER.info("CME system cleanup")

	GPIO.output(GPIO_STATUS_GREEN, False) # red
	GPIO.output(GPIO_STATUS_SOLID, False) # blinking

	# stop/remove any running images (sends SIGTERM)
	_stop_remove_containers()

	if os.path.isfile(Config.PATHS.POWEROFF_FILE):
		os.remove(Config.PATHS.POWEROFF_FILE)
		
		# shutdown - must be held for at least 150 ms
		LOGGER.info("CME sending system halt signal")
		GPIO.output(GPIO_STANDBY, True)
		time.sleep(0.15)

	GPIO.cleanup()
	LOGGER.info("CME system software exiting")


def main(argv=None):
	''' Main program entry point '''

	# process arguments if any to override Config
	if not argv:
		argv = sys.argv[1:]

	# setup logging
	global LOGGER
	LOGGER = Logging.GetLogger('cmeinit', {
		'REMOVE_PREVIOUS': True,
		'PATH': os.path.join(Config.PATHS.LOGDIR, 'cme-boot.log'),
		'SIZE': (1024 * 10),
		'COUNT': 1,
		'LEVEL': 'INFO',
		'FORMAT': '%(asctime)s %(levelname)-8s [%(name)s] %(message)s', 
		'DATE': '%Y-%m-%d %H:%M:%S',
		'CONSOLE': '--console' in argv
	})
	LOGGER.info("CME system starting")

	# delete any previous uploaded files (that were not installed)
	for f in glob.glob(Config.PATHS.UPLOADS + '/*'):
		try:
			os.remove(f)
		except:
			pass

	# setup the GPIO
	InitializeGPIO()

	# set signaling for clean shutdowns
	SetupSignaling()


	# STAGE 1.  RECOVERY MODE (Green Blinking)
	#
	# If recovery mode is requested, we'll just
	# bypass the updates installation and modules
	# bootup stages and go directly to the
	# recovery startup stage.
	recovery_mode = False
	if os.path.isfile(Config.PATHS.RECOVERY_FILE):
		LOGGER.info("Recovery mode boot requested")
		try:
			os.remove(Config.PATHS.RECOVERY_FILE)
		except:
			pass
		recovery_mode = True
	else:
		LOGGER.info("Normal boot mode requested")


	# STAGE 2.  SOFTWARE UPDATE (Green Blinking)
	#
	# If not booting to recovery mode, this stage
	# looks at the software updates folder and
	# manipulates the installed docker images if
	# images are found there.
	if not recovery_mode:
		LOGGER.info("Checking for updates")

		update_dir = Config.PATHS.UPDATE
		update_glob = Config.UPDATES.UPDATE_GLOB

		packages = glob.glob(os.path.join(update_dir, update_glob))

		for package in packages:
			pkg_name = os.path.basename(package)
			LOGGER.info("Update found: {0}".format(pkg_name))
			error_msg = _load_docker(package)
			if error_msg:
				LOGGER.error("Error loading update: {0}".format(error_msg))
			else:
				LOGGER.info("Update loaded: {0}".format(pkg_name))
			# remove update package file regardless of success or failure
			os.remove(package)
		
		if not packages:
			LOGGER.info("No updates found")

	else:
		LOGGER.info("Update stage bypassed (Recovery mode)")


	# STAGE 3.  MODULE LAUNCH (Green Solid)
	#
	# The Cme and Cme-hw dockers are launched here.
	# A parallel loop is started to watch them and
	# shuts down if either terminates abnormally.
	if not recovery_mode:
		LOGGER.info("Launching modules")

		# remove any existing containers
		_stop_remove_containers()

		# get docker images
		docker_images = _list_docker_images()

		cmeweb = docker_images.get('cmeweb')
		cmeapi = docker_images.get('cmeapi')
		cmehw = docker_images.get('cmehw')

		# only launch if we have all images
		if cmeweb and cmeapi and cmehw:

			# launch the cme-docker-fifo (this call should not block)
			fifo = os.path.join(os.getcwd(), 'cme-docker-fifo.sh')
			LOGGER.info("Lauching {0}".format(fifo))
			fifo_p = subprocess.Popen([fifo], stdout=subprocess.PIPE)

			# launch Cme-web, but don't wait (it's just a volume container)
			_launch_docker(cmeweb)

			# Create threads and launch docker containers
			t_cmeapi = threading.Thread(target=_launch_docker, args=(cmeapi, ))
			t_cmeapi.start()

			t_cmehw = threading.Thread(target=_launch_docker, args=(cmehw, ))
			t_cmehw.start()

			# set the pretty green light
			GPIO.output(GPIO_STATUS_GREEN, True)
			GPIO.output(GPIO_STATUS_SOLID, True)

			# wait for dockers to stop
			t_cmeapi.join()
			t_cmehw.join()

			if fifo_p:
				LOGGER.info("Terminating {0}".format(fifo))
				fifo_p.terminate()

			LOGGER.warning("Application module(s) exiting")

		else:
			LOGGER.warning("Application modules not found")
	else:
		LOGGER.info("Module launch stage bypassed (Recovery mode)")


	# STAGE 4.  RECOVERY LAUNCH (Red Solid)
	#
	# If we've made it here, then the application layer has stopped
	# and we need to launch the recovery mode API layer.
	global SHUTDOWN_FLAG
	if SHUTDOWN_FLAG:
		return # cleanup() has set the shutdown flag - nothing more to do

	LOGGER.info("Launching recovery module")
	GPIO.output(GPIO_STATUS_GREEN, False)
	GPIO.output(GPIO_STATUS_SOLID, True)

	# Launch hardware layer - don't wait...
	subprocess.Popen(["cd /root/Cme-hw; source cmehw_venv/bin/activate; python -m cmehw"], shell=True, executable='/bin/bash')
	
	# This blocks until cme exits
	subprocess.run(["cd /root/Cme-api; source cmeapi_venv/bin/activate; python -m cmeapi"], shell=True, executable='/bin/bash')

	# That's it we're done here - let main() call return
	# to the __main__ program loop below and exit cleanly.


# Routine for threaded launch of docker image (image = [ name, tag ])
def _launch_docker(image):

	# common command line
	cmd = ['docker', 'run', '-d', '--privileged', '--name']

	if image[0] == 'cmeapi':
		cmd.extend(['cme-api', '--net=host' ])
		cmd.extend(['-v', '/data:/data' ])
		cmd.extend(['--volumes-from', 'cme-web'])
		cmd.extend(['-v', '/etc/network:/etc/network' ])
		cmd.extend(['-v', '/etc/ntp.conf:/etc/ntp.conf' ])
		cmd.extend(['-v', '/etc/localtime:/etc/localtime' ])
		cmd.extend(['-v', '/tmp/cmehostinput:/tmp/cmehostinput' ])
		cmd.extend(['-v', '/tmp/cmehostoutput:/tmp/cmehostoutput' ])
		cmd.extend(['-v', '/media/usb:/media/usb' ])
		cmd.extend([ image[0] + ':' + image[1] ])

	if image[0] == 'cmehw':
		cmd.extend(['cme-hw' ])
		cmd.extend(['-v', '/data:/data' ])
		cmd.extend(['--device=/dev/spidev0.0:/dev/spidev0.0' ])
		cmd.extend(['--device=/dev/spidev0.1:/dev/spidev0.1' ])
		cmd.extend(['--device=/dev/mem:/dev/mem' ])
		cmd.extend([ image[0] + ':' + image[1] ])

	if image[0] == 'cmeweb':
		cmd.extend(['cme-web' ])
		cmd.extend([ image[0] + ':' + image[1] ])

	# Run docker image (detached, -d) and collect container ID
	LOGGER.info("Launching module {0}".format(' '.join(cmd)))
	ID = subprocess.run(cmd, stdout=subprocess.PIPE).stdout.decode().strip()

	# cmeweb is just a volume container - run it and return
	# without worrying about watching the process.
	if image[0] == 'cmeweb': return

	# Wait for the (detached) container to stop running
	LOGGER.info("Launched {0}".format(cmd))
	LOGGER.info("Waiting for {0} to terminate".format(ID))
	subprocess.run(['docker', 'wait', ID ])  # <--- this should block while container runs!

	LOGGER.info("Module ID {0} terminated".format(ID))

	# If _any_ container stops (gets here), then stop/remove all containers
	_stop_remove_containers()


# Load a docker image from update folder 
def _load_docker(package):
	if not os.path.isfile(package):
		return "{} is not a valid package".format(package)

	p_load = subprocess.run(['docker', 'load'], stdin=open(package), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
	return p_load.stderr.decode()


# List available docker images
def _list_docker_images():
	cmeapi = None
	cmehw = None
	cmeweb = None

	images = subprocess.run(['docker', 'images'], stdout=subprocess.PIPE).stdout.decode().rstrip().split('\n')
	for image in images[1:]:
		img = image.split()
		cmeapi = _parse_image('cmeapi', cmeapi, img)
		cmehw = _parse_image('cmehw', cmehw, img)
		cmeweb = _parse_image('cmeweb', cmeweb, img)

	# each image returned as [ <image_name>, <image_tag> ]
	return { 'cmeapi': cmeapi, 'cmehw': cmehw, 'cmeweb': cmeweb }


# Stop and remove application docker containers
def _stop_remove_containers():
	LOGGER.info("Stopping and removing any module containers")
	containers = subprocess.run(['docker', 'ps', '-aq'], stdout=subprocess.PIPE).stdout.decode().rstrip().split('\n')

	for container in containers:
		if container:
			subprocess.run(['docker', 'stop', container ])
			subprocess.run(['docker', 'rm', container ]) # note volumes (/www) are not deleted


# Filter a docker image by type and version tag; newest/greatest version is used
def _parse_image(name, current_image, new_image):
	if not new_image[0] == name:
		return current_image

	try:
		semver.parse(new_image[1])
	except ValueError as e:
		return current_image

	if not current_image or semver.match(new_image[1], '>=' + current_image[1]):
		return [ new_image[0], new_image[1] ]

	return current_image



if __name__ == "__main__":
	
	try:
		main()

	except KeyboardInterrupt:
		LOGGER.info("Avalanche (Cme-init) shutdown requested ... exiting")

	except Exception as e:
		LOGGER.info("Avalanche (Cme-init) has STOPPED on exception {0}".format(e))

	finally:
		cleanup()


