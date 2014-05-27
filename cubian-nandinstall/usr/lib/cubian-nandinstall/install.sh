#!/bin/bash
#
# Author: cubieplayer(cubieplayer@github.com)
# Filename: cubian-install.sh
# Depends: md5
# Description: This script can help transfer you system on 
#  SD-card to NAND_DEVICE automatically. Supports the following
#  Distributions.
#
#  Cubian for cubieboad1 A10 kernel 3.4.43
#  Cubian for cubieboad2 A20 kernel 3.3.0
#  Cubian for cubieboad2 A20 kernel 3.4.43
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

FLAG=".reboot-nand-install.pid"
NANDPART="${CWD}/nand-part"

MMC_DEVICE="/dev/mmcblk0"
NAND_DEVICE="/dev/nand"
NANDA_DEVICE="/dev/nanda"
NANDB_DEVICE="/dev/nandb"
NANDC_DEVICE="/dev/nandc"
NAND1_DEVICE="/dev/nand1"
NAND2_DEVICE="/dev/nand2"
NAND3_DEVICE="/dev/nand3"

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
NAND_MAGIC_DEVICE=

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
            echoBlue "umounting ${n}"
            umount -l $n
        fi
    fi
done
}

formatNand(){
if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
(echo y;) | nand-part -f a20 /dev/nand 32768 'bootloader 2048' 'magic 512' 'linux 0'
else
(echo y;) | nand-part -f a10 /dev/nand 16 'bootloader 2048' 'linux 0'
fi
}

nandPartitionOK(){
if [[ -f $FLAG ]];then
	return 0
else
	return 1
fi
}

mkFS(){
mkfs.vfat $NAND_BOOT_DEVICE
mkfs.ext4 $NAND_ROOT_DEVICE
tune2fs -o journal_data_writeback $NAND_ROOT_DEVICE
tune2fs -O ^has_journal $NAND_ROOT_DEVICE
e2fsck -f $NAND_ROOT_DEVICE
if [[ -n "$NAND_MAGIC_DEVICE" ]];then
	echo -e 'ANDROID!\0\0\0\0\0\0\0\0\c' > $NAND_MAGIC_DEVICE
fi
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
rsync -avc $BOOTLOADER/* $MNT_BOOT
rsync -avc /boot/script.bin /boot/uEnv.txt /boot/uImage* $MNT_ROOT/boot/
sed -e 's|root=/dev/mmcblk0p1|root='$NAND_ROOT_DEVICE'|g' -i $MNT_ROOT/boot/uEnv.txt
}

installRootfs(){
set +e
rsync -avc --exclude-from=$EXCLUDE_FILE_LIST / $MNT_ROOT
set -e
echoBlue "sync disk... please wait"
sync
}

patchRootfs(){
cat > ${MNT_ROOT}/etc/fstab <<END
#<file system>	<mount point>	<type>	<options>	<dump>	<pass>
$NAND_ROOT_DEVICE	/		ext4	defaults	0	1
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

### determine u-boot.bin on a20
# use 0f35 for kernel 3.3.0
# use 10bb for kernel 3.4.43
# copy correct u-boot.bin
if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
	rm -f ${CWD}/${DEVICE_TYPE}/bootloader/linux/u-boot*.bin
	cp -f "${CWD}/${DEVICE_TYPE}/u-boot-${MACH_ID}.bin" \
		"${CWD}/${DEVICE_TYPE}/bootloader/linux/u-boot.bin"
fi

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
	if [[ -b "$NANDC_DEVICE" ]];then
		NAND_ROOT_DEVICE="$NANDC_DEVICE"
		NAND_MAGIC_DEVICE="$NANDB_DEVICE"
	elif [[ -b "$NAND3_DEVICE" ]];then
		NAND_ROOT_DEVICE="$NAND3_DEVICE"
		NAND_MAGIC_DEVICE="$NAND2_DEVICE"
	fi
fi

if nandPartitionOK;then
    umountNand
    echoBlue "Now continue to install on NAND"   
    echoBlue "Formating NAND devices"   
    mkFS
    echoBlue "Mount NAND partitions"   
    mountDevice
    echoBlue "Install and configure bootloader"
    installBootloader
    echoBlue "Transferring rootfs, please be patient"
	if ! $TESTING;then
    installRootfs
    patchRootfs
	fi
    umountNand
	rm -f $FLAG
    echoGreen "*** Success! remember to REMOVE your SD card from board ***"
    if promptyn "shutdown now?";then
        shutdown -h now
    fi
else
    echo "
                                                 
     #    #   ##   #####  #    # # #    #  ####  
     #    #  #  #  #    # ##   # # ##   # #    # 
     #    # #    # #    # # #  # # # #  # #      
     # ## # ###### #####  #  # # # #  # # #  ### 
     ##  ## #    # #   #  #   ## # #   ## #    # 
     #    # #    # #    # #    # # #    #  ####  

    "
    if promptyn "This operation will completely destory your data on $NAND_DEVICE, Are you sure to continue?[y/n]"; then
        umountNand
        formatNand   
		touch $FLAG
        echo ""
		echoRed "*** Reboot is needed! Please re-run cubian-nandinstall after system is up ***"
        echo ""
        if promptyn "reboot now?";then
            shutdown -r now
        fi
    fi
fi
