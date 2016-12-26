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
# Example: Update root's crontab by:
# $ sudo crontab -e 
# to run backup.sh as root every night at 4am
# 0 4 * * * /home/pi/scripts/backup.sh 2>&1 | /home/pi/scripts/uncolor.sh | /home/pi/scripts/timestamp.sh >> /path/to/your/backups/backup.log

# Make sure only root can run the script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# ======================== CHANGE THESE VALUES ========================
function stopServices {
    echo -e "${purple}${bold}Stopping services before backup${reset}"
    service smbd stop #samba
    service ssh stop
    service cron stop
    
    #service sendmail stop
    #pkill deluged
    #pkill deluge-web
    #service deluge-daemon stop
    #service btsync stop
    #service apache2 stop
    #service noip stop
    #service proftpd stop
    #service webmin stop
    #service xrdp stop
    #service ddclient stop
    #service apache2 stop
    #service samba stop
    #service avahi-daemon stop
    #service netatalk stop
}

function startServices {
    echo -e "${purple}${bold}Starting the stopped services${reset}"
    service smbd start #samba
    service ssh start
    service cron start
    #service apache2 start
    #service btsync start
    #service deluge-daemon start
    #service sendmail start
}

# Setting up directories
SUBDIR=raspberrypi_backups
MOUNTPOINT=/your/mount/point
DIR=$MOUNTPOINT/$SUBDIR
RETENTIONPERIOD=3 # days to keep old backups
POSTPROCESS=0 # 1 to use a postProcessSucess function after successfull backup
GZIP=1 # whether to gzip the backup or not
TRUNCATE=1 # whether truncate unallocated space in image or not

# Function which tries to mount MOUNTPOINT
function mountMountPoint {
    # mount all drives in fstab (that means MOUNTPOINT needs an entry there)
    mount -a
}

function postProcessSucess {
    # Update Packages and Kernel
    echo -e "${yellow}Update Packages and Kernel${reset}"
    apt-get update
    apt-get upgrade -y
    apt-get autoclean

    echo -e "${yellow}Update Raspberry Pi Firmware${reset}"
    rpi-update
    ldconfig

    # Reboot now
    echo -e "${yellow}Reboot now ...${reset}"
    reboot
}

# Function for truncating unallocated space
function truncateImage {
    SECTORSIZE=`blockdev --getss /dev/mmcblk0`;
    ENDSECTOR=`fdisk -l $OFILE | tail -n 2 | awk '{print $3}'`;
    echo -e "${green}${bold}Truncating image file...${reset}"
    echo -e "${green}Original size: $(du -sb $OFILE | awk '{print $1}') ($(du -h $OFILE | awk '{print $1}'))${reset}"
    truncate --size=$[$SECTORSIZE*($ENDSECTOR+1)] $OFILE
    echo -e "${green}Truncated size: $(du -sb $OFILE | awk '{print $1}') ($(du -h $OFILE | awk '{print $1}'))${reset}"
}

# =====================================================================

# Setting up echo fonts
red='\e[31m'
green='\e[32m'
cyan='\e[36m'
yellow='\e[33m'
purple='\e[35m'
default='\e[39m'
#bold=`tput bold`
#normal=`tput sgr0`
bold='\e[1m'
reset='\e[0m'

# Check if mount point is mounted, if not quit!
if [ ! mountpoint -q "$MOUNTPOINT" ]; then
    echo -e "${yellow}${bold}Destination is not mounted; attempting to mount ...${reset}"
    mountMountPoint
    
    if [ ! mountpoint -q "$MOUNTPOINT" ]; then
        echo -e "${red}${bold} Unable to mount $MOUNTPOINT; Aborting!${reset}"
        exit 1
    fi

    echo -e "${green}${bold}Mounted $MOUNTPOINT; Continuing backup${reset}"
fi

# Check if backup directory exists
if [ ! -d "$DIR" ];
then
    mkdir $DIR
	echo -e "${yellow}${bold}Backup directory $DIR didn't exist, I created it${reset}"
fi

echo -e "${green}${bold}Starting RaspberryPI backup process!${reset}"
echo "____ BACKUP ON $(date +%Y/%m/%d_%H:%M:%S)"
echo ""
# First check if pv package is installed, if not, install it first
PACKAGESTATUS=`dpkg -s pv | grep Status`;

if [[ $PACKAGESTATUS == S* ]]
then
    echo -e "${cyan}${bold}Package 'pv' is installed${reset}"
    echo ""
else
    echo -e "${yellow}${bold}Package 'pv' is NOT installed${reset}"
    echo -e "${yellow}${bold}Installing package 'pv' + 'pv dialog'. Please wait...${reset}"
    echo ""
    apt-get -y install pv && apt-get -y install pv dialog
fi

# Create a filename with datestamp for our current backup
OFILE="$DIR/backup_$(hostname)_$(date +%Y%m%d_%H%M%S)".img

# First sync disks
sync; sync

# Shut down some services before starting backup process
stopServices

# Begin the backup process, should take about 45 minutes hour from 8Gb SD card to HDD
echo -e "${green}${bold}Backing up SD card to img file on HDD${reset}"
SDSIZE=`blockdev --getsize64 /dev/mmcblk0`;

if [ $GZIP = 1 ];
then
    if [ $TRUNCATE = 1 ];
    then
        pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock
        truncateImage
        echo -e "${green}Gzipping backup...${reset}"
        pv -cN source $OFILE | gzip | pv -cN gzip > $OFILE.gz
        rm -rf $OFILE
        OFILE=$OFILE.gz # append gz at file
    else
        echo -e "${green}Gzipping backup,,,${reset}"
        OFILE=$OFILE.gz # append gz at file
        pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd bs=1M conv=sync,noerror iflag=fullblock | gzip > $OFILE
    fi
else
    echo -e "${green}No backup compression${reset}"
    pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock

    if [ $TRUNCATE = 1 ];
    then
        truncateImage
    fi
fi

# Wait for DD to finish and catch result
BACKUP_SUCCESS=$?

# Start services again that where shutdown before backup process
startServices

# If command has completed successfully, delete previous backups and exit
if [ $BACKUP_SUCCESS = 0 ];
then
    echo -e "${green}${bold}RaspberryPI backup process completed!${reset}"
    echo -e "${green}FILE: $OFILE${reset}"
    echo -e "${green}SIZE: $(du -sb $OFILE | awk '{print $1}') ($(du -h $OFILE | awk '{print $1}'))${reset}" 
    echo -e "${yellow}Removing backups older than $RETENTIONPERIOD days:${reset}"
    find $DIR -maxdepth 1 -name "*.img" -o -name "*.img.gz" -mtime +$RETENTIONPERIOD -print -exec rm {} \;
    echo -e "${cyan}If any backups older than $RETENTIONPERIOD days were found, they were deleted${reset}"

    if [ $POSTPROCESS = 1 ] ;
    then
        postProcessSucess
    fi

    exit 0
else
    # Else remove attempted backup file
    echo -e "${red}${bold}Backup failed!${reset}"
    rm -f $OFILE
    echo -e "${purple}Last backups on HDD:${reset}"
    find $DIR -maxdepth 1 -name "*.img" -o -name "*.img.gz" -print
    exit 1
fi
