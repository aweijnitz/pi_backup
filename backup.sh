#!/bin/bash

# ___ CREDITS
# This script started from 
#   http://raspberrypi.stackexchange.com/questions/5427/can-a-raspberry-pi-be-used-to-create-a-backup-of-itself
# which in turn started from 
#   http://www.raspberrypi.org/phpBB3/viewtopic.php?p=136912 
#
# 2013-Sept-04
# Merged in later comments from the original thread (the pv exists check) and added the backup.log
#
# Add an entry to crontab to run regurlarly.
# Example: Update /etc/crontab to run backup.sh as root every night at 3am
# 01 4    * * *   root    /home/pi/scripts/backup.sh


# Setting up directories
SUBDIR=raspberrypi_backups
DIR=/mnt/500GB_USB_HD/backups/$SUBDIR

echo "____ BACKUP ON $(date +%Y/%m/%d_%H:%M:%S)" >> $DIR/backup.log
echo "Starting RaspberryPI backup process!" >> $DIR/backup.log

# First check if pv package is installed, if not, install it first
if dpkg -s pv | grep -q Status; then
   then
      echo "Package 'pv' is installed." >> $DIR/backup.log
   else
      echo "Package 'pv' is NOT installed." >> $DIR/backup.log
      echo "Installing package 'pv'. Please wait..." >> $DIR/backup.log
      apt-get -y install pv
fi


# Check if backup directory exists
if [ ! -d "$DIR" ];
   then
      echo "Backup directory $DIR doesn't exist, creating it now!" >> $DIR/backup.log
      mkdir $DIR
fi

# Create a filename with datestamp for our current backup (without .img suffix)
OFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S)"

# Create final filename, with suffix
OFILEFINAL=$OFILE.img

# First sync disks
sync; sync

# Shut down some services before starting backup process
echo "Stopping some services before backup." >> $DIR/backup.log
nginx -s stop
service couchdb stop
service cron stop

# Begin the backup process, should take about 1 hour from 8Gb SD card to HDD
echo "Backing up SD card to USB HDD." >> $DIR/backup.log
echo "This will take some time depending on your SD card size and read performance. Please wait..." >> $DIR/backup.log
SDSIZE=`blockdev --getsize64 /dev/mmcblk0`;
pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock

# Wait for DD to finish and catch result
RESULT=$?

# Start services again that where shutdown before backup process
echo "Start the stopped services again." >> $DIR/backup.log
service cron start
service couchdb start
nginx

# If command has completed successfully, delete previous backups and exit
if [ $RESULT = 0 ];
   then
      echo "Successful backup, previous backup files will be deleted." >> $DIR/backup.log
      rm -f $DIR/backup_*.tar.gz
      mv $OFILE $OFILEFINAL
      echo "Backup is being tarred. Please wait..." >> $DIR/backup.log
      tar zcf $OFILEFINAL.tar.gz $OFILEFINAL
      rm -rf $OFILEFINAL
      echo "RaspberryPI backup process completed! FILE: $OFILEFINAL.tar.gz" >> $DIR/backup.log
      exit 0
# Else remove attempted backup file
   else
      echo "Backup failed! Previous backup files untouched." >> $DIR/backup.log
      echo "Please check there is sufficient space on the HDD." >> $DIR/backup.log
      rm -f $OFILE
      echo "RaspberryPI backup process failed!" >> $DIR/backup.log
      exit 1
fi
