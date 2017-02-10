# CME initialization script to handle the STATUS LED and
# RESET functionality.  This script runs at boot from rc.local
# and requires the associated virtual environment to be
# activated.
import logging, logging.handlers, signal, os, sys, time, subprocess
from datetime import datetime

import RPi.GPIO as GPIO

from .common.Reboot import restart

# Use Broadcom GPIO numbering
GPIO.setmode(GPIO.BCM)

# Set the GPIO pin numbers
GPIO_STATUS_SOLID = 5 # Write 1/True for solid, 0/False for blinking
GPIO_STATUS_GREEN = 6 # Write 1/True for green, 0/False for red
GPIO_N_RESET = 16 # Read 0/Low/False (falling edge) to detect reset button pushed

# Setup the GPIO hardware and initialize the outputs
GPIO.setup(GPIO_STATUS_SOLID, GPIO.OUT, initial=False) # Start w/blinking
GPIO.setup(GPIO_STATUS_GREEN, GPIO.OUT, initial=True) # Start w/green
GPIO.setup(GPIO_N_RESET, GPIO.IN, pull_up_down=GPIO.PUD_UP) # Detect falling edge


# Set up some basic logging
from .common import Config


logger = logging.getLogger("cmeinit")
logger.setLevel(logging.DEBUG) # let handlers set real level
formatter = logging.Formatter('%(asctime)s %(levelname)-8s [%(name)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
sh = logging.StreamHandler(sys.stdout)
fh = logging.handlers.RotatingFileHandler(Config.BOOTLOG, maxBytes=(1024 * 10), backupCount=1)
sh.setFormatter(formatter)
fh.setFormatter(formatter)
sh.setLevel(logging.DEBUG)
fh.setLevel(logging.DEBUG)
logger.addHandler(sh)
logger.addHandler(fh)


# RESET detection callback
def reset(ch):

	# Software edge debounce - check level after 50 ms
	# and return if still HIGH (false trigger)
	time.sleep(0.05)
	if GPIO.input(GPIO_N_RESET) == GPIO.HIGH:
		return

	# Else once we get here we're rebooting and nothing can stop us!
	logger.info("Reset detected")

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

	# Wait for reset button release and measure the time that takes.
	# This loop stops if any of these:
	# 	Reset button released (GPIO_N_RESET == GPIO.HIGH)
	# 	Button held long enough to trigger factory reset
	while GPIO.input(GPIO_N_RESET) == GPIO.LOW or not factory_reset:
		elapsed_seconds = time.time() - reset_start_seconds

		# blink red after RECOVERY seconds
		if elapsed_seconds > Config.RESET_REBOOT_SECONDS:
			if not recovery_mode or factory_reset:
				logger.info("Reset to recovery mode detected")
				recovery_mode = True
				GPIO.output(GPIO_STATUS_GREEN, False)

		# solid red after FACTORY RESET seconds - this will end our while loop
		if elapsed_seconds > Config.RESET_RECOVERY_SECONDS:
			logger.info("Reset to factory defaults detected")
			recovery_mode = False
			factory_reset = True
			GPIO.output(GPIO_STATUS_SOLID, True)

		# sleep just a bit
		time.sleep(0.02)

	# trigger a reboot on a delay so we have time to clean up
	restart(delay=5, recovery_mode=recovery_mode, factory_reset=factory_reset, settings_file=Config.SETTINGS, recovery_file=Config.RECOVERY_FILE, logger=logger)
	cleanup()

# Add the reset falling edge detector; bouncetime of 50 ms means subsequent edges are ignored for 50 ms.
GPIO.add_event_detect(GPIO_N_RESET, GPIO.FALLING, callback=reset, bouncetime=50)



# exit gracefully - set LED status RED/BLINKING
# then clean up and exit
def cleanup(*args):
	GPIO.output(GPIO_STATUS_GREEN, False) # red
	GPIO.output(GPIO_STATUS_SOLID, False) # blinking
	GPIO.cleanup()
	logger.info("CME system shutting down")
	sys.exit(0)

# SIGINT, SIGTERM signal handlers
signal.signal(signal.SIGINT, cleanup)
signal.signal(signal.SIGTERM, cleanup)


logger.info("CME system starting")

# STAGE 1.  RECOVERY MODE (Green Blinking)
#
# If recovery mode is requested, we'll just
# bypass the updates installation and modules
# bootup stages and go directly to the
# recovery startup stage.
recovery_mode = False
if os.path.isfile(Config.RECOVERY_FILE):
	logger.info("Recovery mode boot requested")
	try:
		os.remove(Config.RECOVERY_FILE)
	except:
		pass
	recovery_mode = True
else:
	logger.info("Normal boot mode requested")



# STAGE 2.  SOFTWARE UPDATE (Green Blinking)
#
# If not booting to recovery mode, this stage
# looks at the software updates folder and
# maniuplates the installed docker images if
# images are found there.  Only one update at
# a time is allowed, but previous images are
# preserved for rollback.

# TODO: Implement the software udpates
if not recovery_mode:
	logger.info("Checking for software updates")

	logger.info("No software updates found")
else:
	logger.info("Software update stage bypassed (Recovery mode)")



# STAGE 3.  MODULE LAUNCH (Green Solid)
#
# The Cme and Cme-hw dockers are launched here.
# A parallel loop is started to watch them and
# shuts down if either terminates abnormally.
if not recovery_mode:
	logger.info("Launching software modules")
	GPIO.output(GPIO_STATUS_GREEN, True)
	GPIO.output(GPIO_STATUS_SOLID, True)

	# TODO: Implement the docker launcher
else:
	logger.info("Module launch stage bypassed (Recovery mode)")



# STAGE 3.  RECOVERY LAUNCH (Red Solid)
logger.info("Launching recovery module")
GPIO.output(GPIO_STATUS_GREEN, False)
GPIO.output(GPIO_STATUS_SOLID, True)

# This blocks until cme exits
subprocess.run(["cd /root/Cme; source cme_venv/bin/activate; python -m cme"], shell=True, executable='/bin/bash')

# That's it - we're done here.
cleanup()
