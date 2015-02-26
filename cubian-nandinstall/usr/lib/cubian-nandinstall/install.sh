#!/bin/bash
#
# Author: cubieplayer(cubieplayer@github.com)
# Filename: cubian-install.sh
# Depends: md5
# Description: This script can help transfer you system on 
#  SD-card to NAND_DEVICE automatically. Supports the following
#  Distributions.
#
#  Cubian for cubieboad1 A10 kernel greater than 3.4.43
#  Cubian for cubieboad2 A20 kernel 3.3.0
#  Cubian for cubieboad2 A20(Rev A,B) kernel greater than 3.4.43
#  Cubian for cubietruck A20(Rev A,B) kernel greater than 3.4.43
# 
#  U-Boot source:
#
#  https://github.com/mmplayer/u-boot-sunxi
#
# Copyright (c) 2013, cubieplayer. All rights reserved.
#

set -e

TESTING=false;

if [[ "$1" = "test" ]];then
	TESTING=true;
fi

CWD="/usr/lib/cubian-nandinstall"

NANDPART="${CWD}/nand-part"

MMC_DEVICE="/dev/mmcblk0"
NAND_DEVICE="/dev/nand"
NANDA_DEVICE="/dev/nanda"
NANDB_DEVICE="/dev/nandb"
NAND1_DEVICE="/dev/nand1"
NAND2_DEVICE="/dev/nand2"

DEVICE_A10="a10"
DEVICE_A20="a20"

CPU_INFO="/proc/cpuinfo"

MNT_BOOT="/mnt/nanda"
MNT_ROOT="/mnt/nandb"

CURRENT_PART_DUMP="${CWD}/nand.tmp"
EXCLUDE_FILE_LIST="${CWD}/exclude.txt"

COLOR_NORMAL=$(echo -e "\033[m")
COLOR_BLUE=$(echo -e "\033[36m")
COLOR_GREEN=$(echo -e "\033[32m")
COLOR_YELLOW=$(echo -e "\033[33m")
COLOR_GRAY=$(echo -e "\033[37m")
COLOR_RED=$(echo -e "\033[31m")

ERR_DETECT_DEVICE="error: failed to detect your device"

NAND_BOOT_DEVICE=
NAND_ROOT_DEVICE=

DEVICE_TYPE=
MACH_ID=

echoBlue(){
	echo "${COLOR_BLUE}${1}${COLOR_NORMAL}"
}

echoRed(){
	echo "${COLOR_RED}${1}${COLOR_NORMAL}"
}

echoYellow(){
	echo "${COLOR_YELLOW}${1}${COLOR_NORMAL}"
}

echoGreen(){
	echo "${COLOR_GREEN}${1}${COLOR_NORMAL}"
}

promptyn () {
while true; do
  read -p "$1 " yn
  case $yn in
    [Yy]* ) return 0;;
    [Nn]* ) return 1;;
    * ) echo "Please answer yes or no.";;
  esac
done
}

umountNand() {
sync
for n in ${NAND_DEVICE}*;do
    if [ "${NAND_DEVICE}" != "$n" ];then
        if mount|grep ${n};then
            umount -l $n
        fi
    fi
done
}

formatNand(){
if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
(echo y;) | $NANDPART -f a20 $NAND_DEVICE 128 'bootloader 2048' 'linux 0'
else
(echo y;) | $NANDPART -f a10 $NAND_DEVICE 16 'bootloader 2048' 'linux 0' >> /dev/null
fi
}

nandPartitionOK(){
local partinfo=
local partcount=
local partbad=
local partcount=
if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
        partinfo=$($NANDPART -f a20 $NAND_DEVICE)
else
        partinfo=$($NANDPART -f a10 $NAND_DEVICE)
fi
printf "$partinfo" | grep "all partition tables are bad" >> /dev/null
if [ $? -eq 0 ];then
  return 1
fi

partcount=$(printf "$partinfo" | grep "partitions" | sed 's/[^0-9]//g')

if [ "$partcount" != "2" ];then
  return 1
fi

if ! test -b $NAND_BOOT_DEVICE;then
  return 1
fi 

if ! test -b $NAND_ROOT_DEVICE;then
  return 1
fi 

return 0
}

mkFS(){
mkfs.vfat $NAND_BOOT_DEVICE >> /dev/null
mkfs.ext4 $NAND_ROOT_DEVICE >> /dev/null
}

disableJournal(){
tune2fs -o journal_data_writeback $NAND_ROOT_DEVICE >> /dev/null
tune2fs -O ^has_journal $NAND_ROOT_DEVICE >> /dev/null
e2fsck -f $NAND_ROOT_DEVICE
}

mountDevice(){
if [ ! -d $MNT_BOOT ];then
    mkdir $MNT_BOOT
fi
mount $NAND_BOOT_DEVICE $MNT_BOOT

if [ ! -d $MNT_ROOT ];then
    mkdir $MNT_ROOT
fi
mount $NAND_ROOT_DEVICE $MNT_ROOT
}

installBootloader(){
rm -rf $MNT_BOOT/*
rsync -avcL $BOOTLOADER/* $MNT_BOOT
rsync -avcL /boot/script.bin /boot/uEnv.txt /boot/uImage* $MNT_ROOT/boot/
sed -e 's|root=/dev/mmcblk0p1|root='$NAND_ROOT_DEVICE'|g' -i $MNT_ROOT/boot/uEnv.txt
if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
	echo "machid=${MACH_ID}" >> $MNT_ROOT/boot/uEnv.txt
fi
}

installRootfs(){
set +e
rsync -avcL --exclude-from=$EXCLUDE_FILE_LIST / $MNT_ROOT
set -e
echoBlue "sync disk... please wait"
sync
}

patchRootfs(){
cat > ${MNT_ROOT}/etc/fstab <<END
#<file system>	<mount point>	<type>	<options>	<dump>	<pass>
$NAND_ROOT_DEVICE	/		ext4	defaults,noatime	0	1
END
}

########## main ##########

### check if root
if [[ ${EUID} -ne 0 ]]; then
	echoRed "!!! This tool must be run as root"
	exit 1
fi

### check if running on SD-card fstab should contains "/dev/mmcblk0p1 /"
set +e

cat /etc/fstab | awk '{if($2=="/") {print $1}}' | grep $MMC_DEVICE > /dev/null 2>&1
if [[ $? -ne 0 ]];then
	echoRed "!!! This tool must be run on SD-card system"
	exit 2
fi

### determine device
if [[ -f $CPU_INFO ]];then
	if cat $CPU_INFO | grep -q 'sun4i';then
		DEVICE_TYPE="$DEVICE_A10"
	elif cat $CPU_INFO | grep -q 'sun7i';then
		DEVICE_TYPE="${DEVICE_A20}"
		### determine machid
		uname -r | grep '3.3.0' > /dev/null 2>&1
		if [[ $? -eq 0 ]];then
			MACH_ID='0f35'
		else
			MACH_ID='10bb'
		fi
	else
        echoRed "$ERR_DETECT_DEVICE, must be sun4i or sun7i device"
		exit 1
	fi
else
    echoRed "$ERR_DETECT_DEVICE, ${CPU_INFO} is not exist"
	exit 1
fi

set -e

### The bootloader is ready now
BOOTLOADER="${CWD}/${DEVICE_TYPE}/bootloader"

### set nand device
if [[ -b $NANDA_DEVICE ]];then
	NAND_BOOT_DEVICE="$NANDA_DEVICE"
elif [[ -b $NAND1_DEVICE ]];then
	NAND_BOOT_DEVICE="$NAND1_DEVICE"
fi

if [[ "$DEVICE_TYPE" = "$DEVICE_A10" ]];then
	NAND_ROOT_DEVICE="$NANDB_DEVICE"
elif [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
	if [[ -b "$NANDB_DEVICE" ]];then
		NAND_ROOT_DEVICE="$NANDB_DEVICE"
	elif [[ -b "$NAND2_DEVICE" ]];then
		NAND_ROOT_DEVICE="$NAND2_DEVICE"
	fi
fi

echo "
                                             
 #    #   ##   #####  #    # # #    #  ####  
 #    #  #  #  #    # ##   # # ##   # #    # 
 #    # #    # #    # # #  # # # #  # #      
 # ## # ###### #####  #  # # # #  # # #  ### 
 ##  ## #    # #   #  #   ## # #   ## #    # 
 #    # #    # #    # #    # # #    #  ####  

"
if promptyn "Your data on $NAND_DEVICE will lost, Are you sure to continue?[y/n]"; then
    umountNand
	echoBlue "Re-partitioning NAND device"   
    formatNand 
	echoBlue "Check partition table"   
	if nandPartitionOK;then
	    echoBlue "Formating NAND devices"   
	    mkFS
	    echoBlue "Mount NAND partitions"   
	    mountDevice
    	    umountNand
	    mountDevice
	    echoBlue "Install and configure bootloader"
	    installBootloader
	    echoBlue "Transferring rootfs, please be patient"
	    if ! $TESTING;then
	    	installRootfs
	    	patchRootfs
	    fi
	    umountNand
	    echoBlue "Optimize NAND performance"
            disableJournal
    	echo ""
	    	echoGreen "*** Success! remember to REMOVE your SD card from board ***"
	    	echoGreen "*** Read http://tinyurl.com/qyee5k2, if the board won't boot from NAND ***"
    	echo ""
	    if promptyn "shutdown now?";then
	        shutdown -h now
	    fi
	else
    	echo ""
		echoRed "*** Re-partition NAND device ${NAND_DEVICE} failed, Partition table has damaged ***"
    	echo ""
		echoYellow "To fix the partition table, You can try to run cubian-nandinstall again. If the error still there, then you need to use livesuit restore a factory image first, then run cubian-nandinstall."
	fi
fi
