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
# Add an entry to crontab to run regurlarly.
# Example: Update /etc/crontab to run backup.sh as root every night at 3am
# 01 4    * * *   root    /home/pi/scripts/backup.sh


# ======================== CHANGE THESE VALUES ========================
function stopServices {
    echo "Stopping some services before backup." >> $DIR/backup.log
    service cron stop
    service ssh stop
    service deluge-daemon stop
    service btsync stop
    service apache2 stop
    service samba stop
}

function startServices {
    echo "Start the stopped services again." >> $DIR/backup.log
    service samba start
    service apache2 start
    service btsync start
    service deluge-daemon start
    service ssh start
    service cron start
}


# Setting up directories
SUBDIR=raspberrypi_backups
MOUNTPOINT=/media/usbstick64gb
DIR=$MOUNTPOINT/$SUBDIR

# Function which tries to mount MOUNTPOINT
function mountMountPoint {
    # mount all drives in fstab (that means MOUNTPOINT needs an entry there)
    mount -a
}
function postBackupSucess {

}

#
function tarBackup {
    echo "Backup tarring skipped!" >> $DIR/backup.log
    return 0

    # first arguement ($1) is the file to beeing tarred

    # echo "Backup is being tarred. Please wait..." >> $DIR/backup.log
    # tar zcf $1.tar.gz $1 && rm -rf $1
    # return $?  # important to return 1 if successfull!
}
# =====================================================================


# Check if mount point is mounted, if not quit!
if ! mountpoint -q "$MOUNTPOINT" ; then
    echo "Destination is not mounted; attempting to mount"
    mountMountPoint
    if ! mountpoint -q "$MOUNTPOINT" ; then
        echo "Unable to mount $MOUNTPOINT; Aborting"
        exit 1
    fi
    echo "Mounted $MOUNTPOINT; Continuing backup"
fi

# Check if backup directory exists
if [ ! -d "$DIR" ];
then
    mkdir -p $DIR
    echo "Backup directory $DIR doesn't exist, created it now!" >> $DIR/backup.log
fi

echo "____ BACKUP ON $(date +%Y/%m/%d_%H:%M:%S)" >> $DIR/backup.log
echo "Starting RaspberryPI backup process!" >> $DIR/backup.log

# First check if pv package is installed, if not, install it first
if `dpkg -s pv | grep -q Status;`
then
    echo "Package 'pv' is installed." >> $DIR/backup.log
else
    echo "Package 'pv' is NOT installed." >> $DIR/backup.log
    echo "Installing package 'pv'. Please wait..." >> $DIR/backup.log
    apt-get -y install pv
fi



# Create a filename with datestamp for our current backup (without .img suffix)
OFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S)"

# Create final filename, with suffix
OFILEFINAL=$OFILE.img

# First sync disks
sync; sync

# Shut down some services before starting backup process
stopServices

# Begin the backup process, should take about 1 hour from 8Gb SD card to HDD
echo "Backing up SD card to USB HDD." >> $DIR/backup.log
echo "This will take some time depending on your SD card size and read performance. Please wait..." >> $DIR/backup.log
SDSIZE=`blockdev --getsize64 /dev/mmcblk0`;
pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock

# Wait for DD to finish and catch result
BACKUP_SUCCESS=$?

# Start services again that where shutdown before backup process
startServices

# If command has completed successfully, delete previous backups and exit
if [ $BACKUP_SUCCESS =  0 ];
then
    echo "Successful backup, previous backup files will be deleted." >> $DIR/backup.log
    rm -f $DIR/backup_*.img
    mv $OFILE $OFILEFINAL
    # tar file and remove $OFILEFINAL if succesfull
    tarBackup $OFILEFINAL
    RES_TAR=$?

    if [ $RES_TAR = 1 ];
    then
        echo "Backup Compression failed!" >> $DIR/backup.log
        echo "Please check there is sufficient space on the HDD." >> $DIR/backup.log
    fi
else 
    # Else remove attempted backup file
    echo "Backup failed! Previous backup files untouched." >> $DIR/backup.log
    echo "Please check there is sufficient space on the HDD." >> $DIR/backup.log
    rm -f $OFILE
fi

if [ $BACKUP_SUCCESS = 0 ];
then 
    echo "RaspberryPI backup process completed! FILE: $OFILEFINAL" >> $DIR/backup.log
    
    postProcessSuccess
    
    echo "____ BACKUP SCRIPT FINISHED $(date +%Y/%m/%d_%H:%M:%S)" >> $DIR/backup.log
    exit 0
else
    echo "RaspberryPI backup process failed!" >> $DIR/backup.log
    echo "____ BACKUP SCRIPT FINISHED $(date +%Y/%m/%d_%H:%M:%S)" >> $DIR/backup.log
    exit 1
fi
