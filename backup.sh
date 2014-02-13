#!/bin/bash

# ___ CREDITS
# This script started from 
#   http://raspberrypi.stackexchange.com/questions/5427/can-a-raspberry-pi-be-used-to-create-a-backup-of-itself
# which in turn started from 
#   http://www.raspberrypi.org/phpBB3/viewtopic.php?p=136912 
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

#Setting variables
DIR=/mnt/fileserver/archive/backups/$(hostname)
RETENTIONPERIOD=30 # days to keep old backups
UPDATE=0 # 1 to update packages and firmware
GZIP=1 # whether to gzip the backup or not

# Setting up echo fonts
red='\e[0;31m'
green='\e[0;32m'
cyan='\e[0;36m'
yellow='\e[1;33m'
purple='\e[0;35m'
NC='\e[0m' #No Color
bold=`tput bold`
normal=`tput sgr0`

LOGFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S).log"
# Check if backup directory exists
if [ ! -d "$DIR" ];
   then
      sudo mkdir $DIR
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




# Create a filename with datestamp for our current backup (without .img suffix)
OFILE="$DIR/backup_$(hostname)_$(date +%Y%m%d_%H%M%S)".img


# First sync disks
sync; sync

# Shut down some services before starting backup process
echo ""
echo -e "${purple}${bold}Stopping services before backup${NC}${normal}" | tee -a $DIR/backup.log
#sudo pkill deluged
#sudo pkill deluge-web
#sudo service deluge-daemon stop
#sudo service noip stop
#sudo service proftpd stop
#sudo service webmin stop
#sudo service xrdp stop
#sudo service ddclient stop
#sudo service apache2 stop
#sudo service samba stop
#sudo service avahi-daemon stop
#sudo service netatalk stop
#sudo service sendmail stop
#sudo /var/ossec/bin/ossec-control stop
#sudo service ssh stop
sudo service cron stop


# Begin the backup process, should take about 45 minutes hour from 8Gb SD card to HDD
echo ""
echo -e "${green}${bold}Backing up SD card to img file on HDD${NC}${normal}" | tee -a $DIR/backup.log
SDSIZE=`sudo blockdev --getsize64 /dev/mmcblk0`;
if [ $GZIP = 1 ];
	then
		echo -e "${green}Gzipping backup${NC}${normal}"
		sudo pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd  bs=1M conv=sync,noerror iflag=fullblock | gzip > $OFILE.tgz
	else
		echo -e "${green}No backup compression${NC}${normal}"
		sudo pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock
fi


# Wait for DD to finish and catch result
RESULT=$?

# Start services again that where shutdown before backup process
echo ""
echo -e "${purple}${bold}Starting the stopped services${NC}${normal}" | tee -a $DIR/backup.log
#sudo service deluge-daemon start
#sudo deluged
#sudo deluge-web
#sudo service noip start
#sudo service proftpd start
#sudo service webmin start
#sudo service xrdp start
sudo service cron start


# If command has completed successfully, if not, delete created files
if [ $RESULT = 0 ];
   then
      echo ""
      echo -e "${green}${bold}RaspberryPI backup process completed! FILE: $OFILE${NC}${normal}" | tee -a $DIR/backup.log
      echo -e "${yellow}Removing backups older than $RETENTIONPERIOD days${NC}" | tee -a $DIR/backup.log
      sudo find $DIR -maxdepth 1 -name "*.img" -mtime +$RETENTIONPERIOD -exec rm {} \;
      echo -e "${cyan}If any backups older than $RETENTIONPERIOD days were found, they were deleted${NC}" | tee -a $DIR/backup.log

 
 	  if [ $UPDATE = 1 ] ;# Update Raspberry Pi Firmware
		  then
				  
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
		  else
			exit 0
	  fi		
      
# Else remove attempted backup file
   else
      echo ""
      echo -e "${red}${bold}Backup failed!${NC}${normal}" | tee -a $DIR/backup.log
     sudo rm -f $OFILE
      echo ""
      echo -e "${purple}Last backups on HDD:${NC}" | tee -a $DIR/backup.log
     sudo find $DIR -maxdepth 1 -name "*.img" -exec ls {} \;
      echo ""
      echo -e "${red}${bold}RaspberryPI backup process failed!${NC}${normal}" | tee -a $DIR/backup.log
      exit 1
fi
