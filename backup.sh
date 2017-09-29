#!/bin/bash

# ___ CREDITS
# This script started from 
#   http://raspberrypi.stackexchange.com/questions/5427/can-a-raspberry-pi-be-used-to-create-a-backup-of-itself
# which in turn started from 
#   http://www.raspberrypi.org/phpBB3/viewtopic.php?p=136912 
#
# Users of this script can just modify the below marked values (stopService,startservice function and directory to
# store the backup
#
# 2013-Sept-04
# Merged in later comments from the original thread (the pv exists check modified) and added the backup.log
#
# 2013-Sept-05
# Remved tar compression, since it takes FOREVER to complete and I don't need it.
#
# 2014-Feb-12
# Merged in comments from http://www.raspberrypi.org/forum/viewtopic.php?f=63&t=12079&p=494488
# Moved interesting variables to top of script
# Added options around updates and gzips
#
# Add an entry to crontab to run regurlarly.
# Example: Update /etc/crontab to run backup.sh as root every night at 3am
# 01 4    * * *   root    /home/pi/scripts/backup.sh


# ======================== CHANGE THESE VALUES ========================
function stopServices {
	echo -e "${purple}Stopping services before backup${NC}" | tee -a $DIR/backup.log
	service sendmail stop
	service cron stop
	service ssh stop
	pkill deluged
	pkill deluge-web
	service deluge-daemon stop
	ervice btsync stop
	service apache2 stop
	service samba stop
}

function startServices {
	echo -e "${purple}Starting the stopped services${NC}" | tee -a $DIR/backup.log
	service samba start
	service apache2 start
	service btsync start
	service deluge-daemon start
	service ssh start
	service cron start
	service sendmail start
}


# Setting up directories
SUBDIR=bkp/sweethome.net/juno
MOUNTPOINT=/LOLA/tom
DIR=$MOUNTPOINT/$SUBDIR
RETENTIONPERIOD=15 # days to keep old backups
POSTPROCESS=0 # 1 to use a postProcessSucess function after successfull backup
GZIP=1 # whether to gzip the backup or not
STARTSTOPSERVICE=0 # wether to bounce serices or not

# Function which tries to mount MOUNTPOINT
function mountMountPoint {
	# mount all drives in fstab (that means MOUNTPOINT needs an entry there)
	mount -a
}


function postProcessSucess {
	# Update Packages and Kernel
	echo -e "${yellow}Update Packages and Kernel${NC}" | tee -a $DIR/backup.log
	apt-get update
	apt-get upgrade -y
	apt-get autoclean

	echo -e "${yellow}Update Raspberry Pi Firmware${NC}" | tee -a $DIR/backup.log
	rpi-update
	ldconfig
		
	# Reboot now
	echo -e "${yellow}Reboot now ...${NC}" | tee -a $DIR/backup.log
	reboot
}

# =====================================================================


# Setting up echo fonts
red='\e[0;31m'
green='\e[0;32m'
cyan='\e[0;36m'
yellow='\e[1;33m'
purple='\e[0;35m'
NC='\e[0m' #No Color

# Check if mount point is mounted, if not quit!
if grep -q "$MOUNTPOINT" /proc/mounts; then
	echo -e "${yellow}Destination is not mounted; attempting to mount ... ${NC}"
	mountMountPoint
	if ! grep -q "$MOUNTPOINT" /proc/mounts; then
		echo -e "${red}Unable to mount $MOUNTPOINT; Aborting! ${NC}"
		exit 1
	fi
	echo -e "${green}Mounted $MOUNTPOINT; Continuing backup${NC}"
fi


#LOGFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S).log"

# Check if backup directory exists
if [ ! -d "$DIR" ]; then
	mkdir $DIR
	echo -e "${yellow}Backup directory $DIR didn't exist, I created it${NC}"  | tee -a $DIR/backup.log
fi

echo -e "${green}Starting RaspberryPI backup process!${NC}" | tee -a $DIR/backup.log
echo "____ BACKUP ON $(date +%Y/%m/%d_%H:%M:%S)" | tee -a $DIR/backup.log
echo ""


# Create a filename with datestamp for our current backup
OFILE="$DIR/backup_$(hostname)_$(date +%Y%m%d_%H%M%S)".img


# First sync disks
sync; sync

# Shut down some services before starting backup process
[[ $STARTSTOPSERVICE = 1 ]] && stopServices

# Begin the backup process, should take about 45 minutes hour from 8Gb SD card to HDD
echo -e "${green}Backing up SD card to img file on HDD${NC}" | tee -a $DIR/backup.log
if [ $GZIP = 1 ]; then
	echo -e "${green}Gzipping backup${NC}"
	OFILE=$OFILE.gz # append gz at file
	dd if=/dev/mmcblk0 bs=1M | gzip > $OFILE
else
	echo -e "${green}No backup compression${NC}"
	dd if=/dev/mmcblk0 of=$OFILE bs=1M
fi

# Wait for DD to finish and catch result
BACKUP_SUCCESS=$?

# Start services again that where shutdown before backup process
[[ $STARTSTOPSERVICE = 1 ]] && startServices

# If command has completed successfully, delete previous backups and exit
if [ $BACKUP_SUCCESS =  0 ]; then
	echo -e "${green}RaspberryPI backup process completed! FILE: $OFILE${NC}" | tee -a $DIR/backup.log
	echo -e "${yellow}Removing backups older than $RETENTIONPERIOD days${NC}" | tee -a $DIR/backup.log
	find $DIR -maxdepth 1 -name "*.img" -o -name "*.gz" -mtime +$RETENTIONPERIOD -exec rm {} \;
	echo -e "${cyan}If any backups older than $RETENTIONPERIOD days were found, they were deleted${NC}" | tee -a $DIR/backup.log

 
	if [ $POSTPROCESS = 1 ]; then
		postProcessSucess
	fi
	exit 0
else 
	# Else remove attempted backup file
	echo -e "${red}Backup failed!${NC}" | tee -a $DIR/backup.log
	rm -f $OFILE
	echo -e "${purple}Last backups on HDD:${NC}" | tee -a $DIR/backup.log
	find $DIR -maxdepth 1 -name "*.img" -exec ls {} \;
	exit 1
fi
