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
: ${SUBDIR=raspberrypi_backups}
: ${MOUNTPOINT=/media/pi/raspi}
: ${RETENTIONPERIOD=3} # days to keep old backups, -1 to disable
: ${POSTPROCESS=0} # 1 to use a postProcessSucess function after successfull backup
: ${GZIP=1} # whether to gzip the backup or not
: ${TRUNCATE=1} # whether truncate unallocated space in image or not
: ${GUI=1}
# Dialog result constants
: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

: ${DLG_BACKTITLE="Raspberry Pi Backup"}

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

# Dialogs
if [ $GUI = 1 ];
then
# Mount point dialog
    exec 3>&1

    dlg_result=$(dialog --title "Mount point" \
        --backtitle "$DLG_BACKTITLE" \
        --clear \
        --inputbox "Enter mount point:" 8 70 "$MOUNTPOINT" \
        2>&1 1>&3)

    dlg_return_value=$?
    exec 3>&-

    case $dlg_return_value in
      $DIALOG_OK)
        MOUNTPOINT=$dlg_result
        ;;
      $DIALOG_CANCEL)
        echo "Cancel pressed. Default mount point used: $MOUNTPOINT"
        ;;
      $DIALOG_ESC)
        echo "ESC pressed. Exiting."
        exit 1
        ;;
    esac

# Backup dir dialog
    exec 3>&1

    dlg_result=$(dialog --title "Backup directory" \
        --backtitle "$DLG_BACKTITLE" \
        --clear \
        --inputbox "Enter backup directory:\n\n$MOUNTPOINT/" 10 70 "$SUBDIR" \
        2>&1 1>&3)

    dlg_return_value=$?
    exec 3>&-

    case $dlg_return_value in
      $DIALOG_OK)
        SUBDIR=$dlg_result
        ;;
      $DIALOG_CANCEL)
        echo "Cancel pressed. Default directory used: $DIR"
        ;;
      $DIALOG_ESC)
        echo "ESC pressed. Exiting."
        exit 1
        ;;
    esac

# Backup options dialog
    exec 3>&1

    dlg_selection=$(dialog --title "Options" \
        --backtitle "$DLG_BACKTITLE" \
        --clear \
        --checklist "Choose backup options:" 10 40 3 \
        1 "Compress with Gzip" on \
        2 "Truncate unallocated space" on \
        3 "Postprocess" off \
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

        if [[ $dlg_selection == *"3"* ]];
        then
            POSTPROCESS=1
        else
            POSTPROCESS=0
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

# Retention period dialog
    exec 3>&1

    dlg_result=$(dialog --title "Retention period" \
        --backtitle "$DLG_BACKTITLE" \
        --clear \
        --rangebox "Select, how many days old backups to keep.\nOlder backup files will be removed.\nSelect -1 to disable this feature." 5 70 -1 500 "$RETENTIONPERIOD" \
        2>&1 1>&3)

    dlg_return_value=$?
    exec 3>&-

    case $dlg_return_value in
      $DIALOG_OK)
        RETENTIONPERIOD=$dlg_result
        ;;
      $DIALOG_CANCEL)
        echo "Cancel pressed. Default retention period used: $RETENTIONPERIOD"
        ;;
      $DIALOG_ESC)
        echo "ESC pressed. Exiting."
        exit 1
        ;;
    esac
fi

DIR=$MOUNTPOINT/$SUBDIR

# ======================= FUNCTIONS ===================================

# Function to stop some of the running services
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

# Function to start stopped services
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

# Function to run commands after successful backup
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

# Function to get the last sector of the last partition +1
function getEndSector {
    ENDSECTOR=`fdisk -l /dev/mmcblk0 | tail -n 2 | awk '{print $3}'`;
    ENDSECTOR=$[$ENDSECTOR+1]
}

# Function to get sector size of the SD card
function getSectorSize {
    SECTORSIZE=`blockdev --getss /dev/mmcblk0`;
}

# Function to build the backup command string based on parameters
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
        tmp_ddcount=""
        SCR_TITLE="$SCR_TITLE backup"
    fi

    tmp_scr="/dev/mmcblk0 -s $SDSIZE | dd$tmp_ddof bs=$SECTORSIZE conv=sync,noerror iflag=fullblock$tmp_ddcount$tmp_gzip"

    if [ $GUI = 1 ];
    then
        SCR_FINAL="(pv -n $tmp_scr) 2>&1 | dialog --backtitle \"$DLG_BACKTITLE\" --title \"$SCR_TITLE\" --clear --gauge $OFILE 10 70 0"
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
            if [ $GUI = 1 ]
            then
                messageBox 0 0 "Unable to mount $MOUNTPOINT\nAborting!"
            else
                echo -e "${red}${bold} Unable to mount $MOUNTPOINT; Aborting!${reset}"
            fi

            exit 1
        fi

        echo -e "${green}${bold}Mounted $MOUNTPOINT; Continuing backup${reset}"
    fi
}

# Function to check if the backup directory exists, if not, create it
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
    local m=${4-Msg}	# message

    dialog --backtitle "$DLG_BACKTITLE" \
        --title "${t}" \
        --clear \
        --msgbox "${m}" ${h} ${w}
}

# =====================================================================

echo -e "${cyan}+-----------------------------------------+${reset}"
echo -e "${cyan}       BACKUP ON $(date +%Y-%m-%d\ %H:%M:%S)${reset}"
echo -e "${cyan}+-----------------------------------------+${reset}"

# Checks before backup
checkMountPoint
checkBackupDir
checkPackages

echo -e "${green}${bold}Starting Raspberry Pi backup process!${reset}"

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
        echo -e "${green}${bold}Raspberry Pi backup process completed!${reset}"
        echo -e "${green}FILE: $OFILE${reset}"
        echo -e "${green}SIZE: $(du -sb $OFILE | awk '{print $1}') ($(du -h $OFILE | awk '{print $1}'))${reset}" 
        echo -e "${yellow}Removing backups older than $RETENTIONPERIOD days:${reset}"
    fi

    if [ $RETENTIONPERIOD -ge 0 ];
    then
        echo -e "${yellow}Removing backups older than $RETENTIONPERIOD days:${reset}"
        find $DIR -maxdepth 1 -name "*.img" -o -name "*.img.gz" -mtime +$RETENTIONPERIOD -print -exec rm {} \;
        echo -e "${cyan}If any backups older than $RETENTIONPERIOD days were found, they were deleted${reset}"
    fi

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
