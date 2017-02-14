Cme-init/cme_system
=====================

The files in this folder are used to set up a new CME device.

Generally, the setup is performed by the `setup_system.sh` script
and the other files are retrieved by the script as need.

Put this script in a location accessible by the CME device
and run

```bash
$ curl -s https://<CME_HTTP_SERVER>/setup_system.sh | bash
```