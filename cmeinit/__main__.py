# CME initialization script to handle the STATUS LED and
# RESET functionality.  This script runs at boot from rc.local
# and requires the associated virtual environment to be
# activated.
import logging, signal, sys, time, subprocess, threading
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

# Monitor this global in callbacks to know when the script is done
STOPPED = False

# How long to hold reset button?
RESET_REBOOT_SECONDS = 3 # <= this time: reboot; > this time: recovery or factory reset
RESET_RECOVERY_SECONDS = 6 # <= this time: recovery mode; > this time: factory reset


# Set up some basic logging
BOOT_LOG = '/data/log/cme-boot.log'
logger = logging.getLogger()
formatter = logging.Formatter('%(asctime)s %(levelname)-8s [%(name)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
sh = logging.StreamHandler()
fh = logging.handlers.RotatingFileHandler(BOOT_LOG, maxBytes=(1024 * 10), backupCount=1)
sh.setFormatter(formatter)
fh.setFormatter(formatter)
sh.setLevel(logging.DEBUG)
fh.setLevel(logging.DEBUG)
logger.addHandler(sh)
logger.addHandler(fh)


# RESET detection callback
def reset(ch):
	global STOPPED

	# ignore subsequent button pushes
	if STOPPED:
		return

	# These paths are also used in the Cme package (Cme/cme/Config.py), so be careful if changing!
	SETTINGS_FILE = '/data/settings.json'
	RECOVERY_FILE = '/data/.recovery'

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

	# wait for button release or time exceeds (RESET_RECOVERY_SECONDS + 2)
	# for exhuberent button pressers
	while GPIO.input(GPIO_N_RESET) == GPIO.LOW and elapsed_seconds < (RESET_RECOVERY_SECONDS + 2):
		elapsed_seconds = time.time() - reset_start_seconds

		# blink red after RECOVERY seconds
		if elapsed_seconds > RESET_REBOOT_SECONDS:
			recovery_mode = True
			GPIO.output(GPIO_STATUS_GREEN, False)

		# solid red after FACTORY RESET seconds
		if elapsed_seconds > RESET_RECOVERY_SECONDS:
			recovery_mode = False
			factory_reset = True
			GPIO.output(GPIO_STATUS_SOLID, True)

		# sleep just a bit
		time.sleep(0.02)

	# trigger a reboot on a delay so we have time to clean up
	restart(delay=5, recovery_mode=recovery_mode, factory_reset=factory_reset, settings_file=SETTINGS_FILE, recovery_file=RECOVERY_FILE, logger=None)

	STOPPED = True

# Add the reset falling edge detector
GPIO.add_event_detect(GPIO_N_RESET, GPIO.FALLING, callback=reset)



# exit gracefully
def cleanup(*args):
	global STOPPED
	STOPPED = True
	GPIO.cleanup()
	logger.info("CME system shutting down")
	sys.exit(0)

# SIGINT, SIGTERM signal handlers
signal.signal(signal.SIGINT, cleanup)
signal.signal(signal.SIGTERM, cleanup)


logger.info("CME system starting")

# Main loop
try:
	while not STOPPED:
		if not STOPPED:
			time.sleep(1)

except KeyboardInterrupt:
	cleanup()



