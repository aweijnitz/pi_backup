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
	echo -e "${purple}${bold}Stopping services before backup${NC}${normal}" | tee -a $DIR/backup.log
    sudo service sendmail stop
    sudo service cron stop
    sudo service ssh stop
    sudo pkill deluged
    sudo pkill deluge-web
    sudo service deluge-daemon stop
    sudo service btsync stop
    sudo service apache2 stop
    sudo service samba stop
    
    #sudo service noip stop
    #sudo service proftpd stop
    #sudo service webmin stop
    #sudo service xrdp stop
    #sudo service ddclient stop
    #sudo service apache2 stop
    #sudo service samba stop
    #sudo service avahi-daemon stop
    #sudo service netatalk stop
}

function startServices {
	echo -e "${purple}${bold}Starting the stopped services${NC}${normal}" | tee -a $DIR/backup.log
    sudo service samba start
    sudo service apache2 start
    sudo service btsync start
    sudo service deluge-daemon start
    sudo service ssh start
    sudo service cron start
    sudo service sendmail start
}


# Setting up directories
SUBDIR=raspberrypi_backups
MOUNTPOINT=/media/usbstick64gb
DIR=$MOUNTPOINT/$SUBDIR
RETENTIONPERIOD=1 # days to keep old backups
POSTPROCESS=0 # 1 to use a postProcessSucess function after successfull backup
GZIP=0 # whether to gzip the backup or not

# Function which tries to mount MOUNTPOINT
function mountMountPoint {
    # mount all drives in fstab (that means MOUNTPOINT needs an entry there)
    mount -a
}


function postProcessSucess {
	# Update Packages and Kernel
	echo -e "${yellow}Update Packages and Kernel${NC}${normal}" | tee -a $DIR/backup.log
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get autoclean

    echo -e "${yellow}Update Raspberry Pi Firmware${NC}${normal}" | tee -a $DIR/backup.log
    sudo rpi-update
    sudo ldconfig

    # Reboot now
    echo -e "${yellow}Reboot now ...${NC}${normal}" | tee -a $DIR/backup.log
    sudo reboot
}

# =====================================================================


# Setting up echo fonts
red='\e[0;31m'
green='\e[0;32m'
cyan='\e[0;36m'
yellow='\e[1;33m'
purple='\e[0;35m'
NC='\e[0m' #No Color
bold=`tput bold`
normal=`tput sgr0`

# Check if mount point is mounted, if not quit!
if ! mountpoint -q "$MOUNTPOINT" ; then
    echo -e "${yellow}${bold}Destination is not mounted; attempting to mount ... ${NC}${normal}"
    mountMountPoint
    if ! mountpoint -q "$MOUNTPOINT" ; then
        echo -e "${red}${bold} Unable to mount $MOUNTPOINT; Aborting! ${NC}${normal}"
        exit 1
    fi
    echo -e "${green}${bold}Mounted $MOUNTPOINT; Continuing backup${NC}${normal}"
fi


#LOGFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S).log"

# Check if backup directory exists
if [ ! -d "$DIR" ];
   then
      mkdir $DIR
	  echo -e "${yellow}${bold}Backup directory $DIR didn't exist, I created it${NC}${normal}"  | tee -a $DIR/backup.log
fi

echo -e "${green}${bold}Starting RaspberryPI backup process!${NC}${normal}" | tee -a $DIR/backup.log
echo "____ BACKUP ON $(date +%Y/%m/%d_%H:%M:%S)" | tee -a $DIR/backup.log
echo ""
# First check if pv package is installed, if not, install it first
PACKAGESTATUS=`dpkg -s pv | grep Status`;

if [[ $PACKAGESTATUS == S* ]]
   then
      echo -e "${cyan}${bold}Package 'pv' is installed${NC}${normal}" | tee -a $DIR/backup.log
      echo ""
   else
      echo -e "${yellow}${bold}Package 'pv' is NOT installed${NC}${normal}" | tee -a $DIR/backup.log
      echo -e "${yellow}${bold}Installing package 'pv' + 'pv dialog'. Please wait...${NC}${normal}" | tee -a $DIR/backup.log
      echo ""
      sudo apt-get -y install pv && sudo apt-get -y install pv dialog
fi




# Create a filename with datestamp for our current backup
OFILE="$DIR/backup_$(hostname)_$(date +%Y%m%d_%H%M%S)".img


# First sync disks
sync; sync

# Shut down some services before starting backup process
stopServices

# Begin the backup process, should take about 45 minutes hour from 8Gb SD card to HDD
echo -e "${green}${bold}Backing up SD card to img file on HDD${NC}${normal}" | tee -a $DIR/backup.log
SDSIZE=`sudo blockdev --getsize64 /dev/mmcblk0`;
if [ $GZIP = 1 ];
	then
		echo -e "${green}Gzipping backup${NC}${normal}"
		OFILE=$OFILE.gz # append gz at file
        sudo pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd  bs=1M conv=sync,noerror iflag=fullblock | gzip > $OFILE
	else
		echo -e "${green}No backup compression${NC}${normal}"
		sudo pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock
fi

# Wait for DD to finish and catch result
BACKUP_SUCCESS=$?

# Start services again that where shutdown before backup process
startServices

# If command has completed successfully, delete previous backups and exit
if [ $BACKUP_SUCCESS =  0 ];
then
      echo -e "${green}${bold}RaspberryPI backup process completed! FILE: $OFILE${NC}${normal}" | tee -a $DIR/backup.log
      echo -e "${yellow}Removing backups older than $RETENTIONPERIOD days${NC}" | tee -a $DIR/backup.log
      sudo find $DIR -maxdepth 1 -name "*.img" -o -name "*.gz" -mtime +$RETENTIONPERIOD -exec rm {} \;
      echo -e "${cyan}If any backups older than $RETENTIONPERIOD days were found, they were deleted${NC}" | tee -a $DIR/backup.log

 
 	  if [ $POSTPROCESS = 1 ] ;
	  then
			postProcessSucess
	  fi
	  exit 0
else 
    # Else remove attempted backup file
     echo -e "${red}${bold}Backup failed!${NC}${normal}" | tee -a $DIR/backup.log
     sudo rm -f $OFILE
     echo -e "${purple}Last backups on HDD:${NC}" | tee -a $DIR/backup.log
     sudo find $DIR -maxdepth 1 -name "*.img" -exec ls {} \;
     exit 1
fi
