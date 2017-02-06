# CME initialization script to handle the STATUS LED and
# RESET functionality.  This script runs at boot from rc.local
# and requires the associated virtual environment to be
# activated.
import sys, time, subprocess

import RPi.GPIO as GPIO

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

# REBOOT w/delay
def _reboot(delay=5):
	# trigger a reboot
	logger.info("CME rebooting in {0} seconds.".format(delay))	
	
	time.sleep(delay)
	subprocess.call(['reboot'])


# RESET detection callback
def reset(ch):
	global STOPPED

	# ignore subsequent button pushes
	if STOPPED:
		return

	# on reset detect, set STATUS BLINKING/GREEN
	GPIO.output(GPIO_STATUS_GREEN, True)
	GPIO.output(GPIO_STATUS_SOLID, False)

	# get start time
	reset_start_seconds = time.time()
	elapsed_seconds = 0

	# wait for button release or time exceeds (RESET_RECOVERY_SECONDS + 2)
	# for exhuberent button pressers
	while GPIO.input(GPIO_N_RESET) == GPIO.LOW and elapsed_seconds < (RESET_RECOVERY_SECONDS + 2):
		elapsed_seconds = time.time() - reset_start_seconds

		# blink red after RECOVERY seconds
		if elapsed_seconds > RESET_REBOOT_SECONDS:
			GPIO.output(GPIO_STATUS_GREEN, False)

		# solid red after FACTORY RESET seconds
		if elapsed_seconds > RESET_RECOVERY_SECONDS:
			GPIO.output(GPIO_STATUS_SOLID, True)

		time.sleep(0.02)

	if elapsed_seconds <= RESET_REBOOT_SECONDS:
		# simple reboot
		sys.stdout.write("\r\n\r\n{0:.2f} sec: Simple REBOOT detected!\r\n\r\n".format(elapsed_seconds))


	elif elapsed_seconds > RESET_RECOVERY_SECONDS:
		# factory defaults
		sys.stdout.write("\r\n\r\n{0:.2f} sec: REBOOT with FACTORY DEFAULTS!\r\n\r\n".format(elapsed_seconds))

	else:
		# recovery mode
		sys.stdout.write("\r\n\r\n{0:.2f} sec: REBOOT into RECOVERY!\r\n\r\n".format(elapsed_seconds))

	STOPPED = True

# Add the reset falling edge detector
GPIO.add_event_detect(GPIO_N_RESET, GPIO.FALLING, callback=reset)

spinners = "|/-\\"
spinner_i = 0

sys.stderr.write("\x1b[2J\x1b[H")
sys.stdout.write("\r\nStarting CME System...\r\n\r\n")

try:
	while not STOPPED:
		sys.stdout.write("\tRunning {0}\x1b[K\r".format(spinners[spinner_i]))
		sys.stdout.flush()
		spinner_i = (spinner_i + 1) % len(spinners)

		if not STOPPED:
			time.sleep(0.25)

finally:
	sys.stdout.write("\r\n\r\n...done!\r\n\r\n")
	GPIO.cleanup()

