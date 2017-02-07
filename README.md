Cme-init
==============

Core monitoring engine (CME) intialization package.  

This package is run from `systemd` as a service.  It runs under Python 3.5+.


Manual Installation
-----------------------

Clone package repository into `/root/Cme-init/` on the target device

```bash
root@cme-dev[~:501] $ git clone git@10.252.64.224:Avalanche/Cme-init.git
```

Change into the newly cloned directory and create a virtual environment

```bash
root@cme-dev[~:502] $ cd Cme-init
root@cme-dev[~/Cme-init:503] $ pyvenv cmeinit_venv
```

Activate the environment and install the requirements using `pip`

```bash
root@cme-dev[~/Cme-init:504] $ source cmeinit_venv/bin/activate
root@cme-dev[~/Cme-init:505] $ pip install -f requirements.txt
```

Move the service unit file, `cmeinit.service` to the systemd services folder and enable it

```bash
root@cme-dev[~/Cme-init:506] $ mv cmeinit.service /lib/systemd/service/cmeinit.service
root@cme-dev[~/Cme-init:507] $ systemctl daemon-reload
root@cme-dev[~/Cme-init:508] $ systemctl enable cmeinit.service
```
