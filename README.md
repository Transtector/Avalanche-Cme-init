Cme-init
==============

Core monitoring engine (CME) intialization package.  This package is called from `systemd` (`rc.local`)
as the last step in the CME bootup process.  The package is responsible for monitoring the hardware
RESET button as well as controlling the STATUS LED (red/green, solid/blinking) to indicate the state
of the CME system.

This package runs under Python version: 3.5+ and requires RPi.GPIO installed to a Python
virtual environment in `/root/Cme-init/cmeinit_venv/`.

Look in `requirements.txt` to find additional dependent packages. 

