# Backup script for Raspberry Pi
This script does an image backup of the Pi SD card using dd. It is not the most efficient method, but it creates a complete backup and it's easy to restore in case of complete card failure.

## Installation
- Clone this repo into the folder where you keep your housekeeping scripts.
- Modify the DIR variable to point to your destination
- Update services stop and start sections to reflect your installated services
- Make executable. ```chmod +x backup.sh```
- Update crontab to run each it each night.

___Example___

Update /etc/crontab to run backup.sh as root every night at 3am

```01 3    * * *   root    /home/pi/scripts/backup.sh```

The backup took a little more than an hour on my first run (SD card to USB HDD).


## CREDITS
This script started from
   <http://raspberrypi.stackexchange.com/questions/5427/can-a-raspberry-pi-be-used-to-create-a-backup-of-itself>
 which in turn started from
   <http://www.raspberrypi.org/phpBB3/viewtopic.php?p=136912>


__2013-Sept-04__

Merged in later comments from the original thread (the pv exists check) and added the backup.log

