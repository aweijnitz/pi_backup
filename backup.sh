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

#Get command line arguments
while [[ $# -gt 1 ]]
do
    key="$1"

    case $key in
        -s|--subdir)
        SUBDIR:="$2"
        shift # past argument
        ;;
        -c|--compress)
        GZIP="$2"
        shift # past argument
        ;;
        -t|--truncate)
        TRUNCATE="$2"
        shift # past argument
        ;;
        -m|--mountpoint)
        MOUNTPOINT="$2"
        shift
        ;;
        -p|--postprocess)
        POSTPROCESS="$2"
        shift
        ;;
        -r|--retperiod)
        RETENTIONPERIOD="$2"
        shift
        ;;
        -g|--gui)
        GUI="$2"
        shift
        ;;
        *)
    ;;
esac
shift
done

# Setting up variables
: ${SUBDIR:=raspberrypi_backups}
: ${MOUNTPOINT=/media/pi/raspi}
DIR=$MOUNTPOINT/$SUBDIR
: ${RETENTIONPERIOD=3} # days to keep old backups
: ${POSTPROCESS=0} # 1 to use a postProcessSucess function after successfull backup
: ${GZIP=1} # whether to gzip the backup or not
: ${TRUNCATE=1} # whether truncate unallocated space in image or not
: ${GUI=1}

: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

# Setting up echo fonts
red='\e[31m'
green='\e[32m'
cyan='\e[36m'
yellow='\e[33m'
purple='\e[35m'
default='\e[39m'
bold='\e[1m'
reset='\e[0m'
#bold=`tput bold`
#normal=`tput sgr0`

# Backup options dialog
if [ $GUI = 1 ];
then
    exec 3>&1

    dlg_selection=$(dialog --title "Options" \
        --backtitle "Raspberry Pi Backup" \
        --clear \
        --checklist "Choose backup options:" 10 40 2 \
        1 "Compress with Gzip" on \
        2 "Truncate unallocated space" on \
        2>&1 1>&3)

    dlg_return_value=$?
    exec 3>&-

    case $dlg_return_value in
        $DIALOG_OK)

        if [[ $dlg_selection == *"1"* ]];
        then
            GZIP=1
        else
            GZIP=0
        fi

        if [[ $dlg_selection == *"2"* ]];
        then
            TRUNCATE=1
        else
            TRUNCATE=0
        fi
        ;;
        $DIALOG_CANCEL)
        echo "Cancel pressed. Defaults used."
        ;;
        $DIALOG_ESC)
        echo "ESC pressed. Exiting."
        exit 1
        ;;
    esac
fi

# ======================= FUNCTIONS ===================================
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

function getEndSector {
    ENDSECTOR=`fdisk -l /dev/mmcblk0 | tail -n 2 | awk '{print $3}'`;
    ENDSECTOR=$[$ENDSECTOR+1]
}

function getSectorSize {
    SECTORSIZE=`blockdev --getss /dev/mmcblk0`;
}

function buildBackupCommand {
    if [ $GZIP = 1 ];
    then
        OFILE=$OFILE.gz
        tmp_ddof=""
        tmp_gzip=" | gzip > $OFILE"
        SCR_TITLE="Gzipping"
    else
        tmp_ddof=" of=$OFILE"
        tmp_gzip=""
        SCR_TITLE="Creating uncompressed"
    fi

    if [ $TRUNCATE = 1 ];
    then
        getEndSector
        SDSIZE=$[$SECTORSIZE*$ENDSECTOR]
        tmp_ddcount=" count=$ENDSECTOR"
        SCR_TITLE="$SCR_TITLE truncated backup"
    else
        SDSIZE=`blockdev --getsize64 /dev/mmcblk0`;
        ddcount=""
        SCR_TITLE="$SCR_TITLE backup"
    fi

    tmp_scr="/dev/mmcblk0 -s $SDSIZE | dd$tmp_ddof bs=$SECTORSIZE conv=sync,noerror iflag=fullblock$tmp_ddcount$tmp_gzip"

    if [ $GUI = 1 ];
    then
        SCR_FINAL="(pv -n $tmp_scr) 2>&1 | dialog --backtitle \"Raspberry Pi Backup\" --title \"$SCR_TITLE\" --gauge $OFILE 10 70 0"
    else
        SCR_FINAL="echo -e '${green}$SCR_TITLE...${reset}' && pv $tmp_scr"
    fi
}

# Function to check if required packages are installed
function checkPackages {
    # pv
    PACKAGESTATUS=`dpkg-query --show --showformat='${db:Status-Status}\n' 'pv'`

    if [[ $PACKAGESTATUS == installed ]]
    then
        echo -e "${cyan}${bold}Package 'pv' is installed${reset}"
    else
        echo -e "${yellow}${bold}Installing missing package 'pv'. Please wait...${reset}"
        apt-get -y install pv
    fi

    # dialog
    PACKAGESTATUS=`dpkg-query --show --showformat='${db:Status-Status}\n' 'dialog'`

    if [[ $PACKAGESTATUS == installed ]]
    then
        echo -e "${cyan}${bold}Package 'dialog' is installed${reset}"
    else
        echo -e "${yellow}${bold}Installing missing package 'pv'. Please wait...${reset}"
        apt-get -y install dialog
    fi
}

# Function to check if mount point is mounted, if not quit
function checkMountPoint {
    #if ! grep -qs "$MOUNTPOINT" /proc/mounts; then
    if ! mountpoint -q "$MOUNTPOINT"; then
        echo -e "${yellow}${bold}Destination is not mounted; attempting to mount ...${reset}"
        mountMountPoint

        #if ! grep -qs "$MOUNTPOINT" /proc/mounts; then
        if ! mountpoint -q "$MOUNTPOINT"; then
            echo -e "${red}${bold} Unable to mount $MOUNTPOINT; Aborting!${reset}"
            exit 1
        fi

        echo -e "${green}${bold}Mounted $MOUNTPOINT; Continuing backup${reset}"
    fi
}

# functino to check if backup directory exists, if not, create it
function checkBackupDir {
    if [ ! -d "$DIR" ];
    then
        mkdir $DIR
        echo -e "${yellow}${bold}Backup directory $DIR didn't exist, I created it${reset}"
    fi
}

# Function to display message box
function messageBox() {
    local h=${1-10}	# box height default 10
    local w=${2-40} 	# box width default 41
    local t=${3-Output} # box title 
    local m=${4-Msg}

    dialog --backtitle "Raspberry Pi Backup" \
        --title "${t}" \
        --clear \
        --msgbox "${m}" ${h} ${w}
}

# =====================================================================

checkMountPoint
checkBackupDir
checkPackages

echo -e "${green}${bold}Starting RaspberryPI backup process!${reset}"
echo "____ BACKUP ON $(date +%Y/%m/%d_%H:%M:%S)"
echo ""

# Create a filename with datestamp for our current backup
OFILE="$DIR/backup_$(hostname)_$(date +%Y%m%d_%H%M%S)".img

# First sync disks
sync; sync

# Shut down some services before starting backup process
stopServices

# Begin the backup process, should take about 45 minutes hour from 8Gb SD card to HDD
echo -e "${green}${bold}Backing up SD card to img file on HDD${reset}"
getSectorSize
buildBackupCommand

eval $SCR_FINAL

# Wait for DD to finish and catch result
BACKUP_SUCCESS=$?

# Start services again that where shutdown before backup process
startServices

# If command has completed successfully, delete previous backups and exit
if [ $BACKUP_SUCCESS = 0 ];
then
    if [ $GUI = 1 ];
    then
        messageBox 13 70 "Success" "Raspberry Pi backup process completed!\nFILE: $OFILE\nSIZE: $(du -sb $OFILE | awk '{print $1}') ($(du -h $OFILE | awk '{print $1}'))"
    else
        echo -e "${green}${bold}Raspberry Pu backup process completed!${reset}"
        echo -e "${green}FILE: $OFILE${reset}"
        echo -e "${green}SIZE: $(du -sb $OFILE | awk '{print $1}') ($(du -h $OFILE | awk '{print $1}'))${reset}" 
        echo -e "${yellow}Removing backups older than $RETENTIONPERIOD days:${reset}"
    fi

    find $DIR -maxdepth 1 -name "*.img" -o -name "*.img.gz" -mtime +$RETENTIONPERIOD -print -exec rm {} \;
    echo -e "${cyan}If any backups older than $RETENTIONPERIOD days were found, they were deleted${reset}"

    if [ $POSTPROCESS = 1 ] ;
    then
        postProcessSucess
    fi

    exit 0
else
    # Else remove attempted backup file
    if [ $GUI = 1 ];
    then
        messageBox 10 40  "Fail" "Backup failed!"
    else
        echo -e "${red}${bold}Backup failed!${reset}"
    fi

    rm -f $OFILE
    echo -e "${purple}Last backups on HDD:${reset}"
    find $DIR -maxdepth 1 -name "*.img" -o -name "*.img.gz" -print
    exit 1
fi
