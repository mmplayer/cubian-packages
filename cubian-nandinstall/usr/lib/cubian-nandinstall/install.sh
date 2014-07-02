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

PARTNUM=;
CWD="/usr/lib/cubian-nandinstall"

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
MNT_INITRD=
MNT_ROOT=

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
NAND_INITRD_DEVICE=

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

promptpart () {
while true; do
  read -p "$1 " pn
  case $pn in
    2 )  PARTNUM=2
		 break;;
    3 )  PARTNUM=3
		 break;;
    * ) echo "2 or 3 partitions only";;
  esac
done
}

partChoice () {
if [[ "$PARTNUM" = "2" ]];then
	MNT_INITRD=
	MNT_ROOT="/mnt/nandb"
fi

if [[ "$PARTNUM" = "3" ]];then
	MNT_INITRD="/mnt/nandb"
	MNT_ROOT="/mnt/nandc"
fi
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
echo "NUMBER OF PARTTIONS: $PARTNUM"
if [[ "$PARTNUM" = "2" ]];then
	if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
		(echo y;) | nand-part -f a20 $NAND_DEVICE 32768 'bootloader 20480' 'linux 0' >> /dev/null
	else
		(echo y;) | nand-part -f a10 $NAND_DEVICE 16 'bootloader 20480' 'linux 0' >> /dev/null
	fi
fi
if [[ "$PARTNUM" = "3" ]];then
	if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
		(echo y;) | nand-part -f a20 $NAND_DEVICE 32768 'bootloader 20480' 'initrd 104200' 'linux 0' >> /dev/null
	else
		(echo y;) | nand-part -f a10 $NAND_DEVICE 16 'bootloader 20480' 'initrd 104200' 'linux 0' >> /dev/null
	fi
fi
}

nandPartitionOK(){
local partinfo=
local partbad=
if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
    partinfo=$(nand-part -f a20 $NAND_DEVICE)
else
    partinfo=$(nand-part -f a10 $NAND_DEVICE)
fi
printf "$partinfo" | grep "all partition tables are bad" >> /dev/null
if [ $? -eq 0 ];then
  return 1
fi
return 0
}

mkFS(){
if [[ "$PARTNUM" = "2" ]];then
	echo "start nanda FS"
	mkfs.vfat $NAND_BOOT_DEVICE >> /dev/null
	echo "start nandb FS"
	mkfs.ext4 $NAND_ROOT_DEVICE >> /dev/null
fi
if [[ "$PARTNUM" = "3" ]];then
	echo "start nanda FS ($NAND_BOOT_DEVICE)" 
	mkfs.vfat $NAND_BOOT_DEVICE >> /dev/null
	echo "start nandb FS ($NAND_INITRD_DEVICE)"
	mkfs.ext4 $NAND_INITRD_DEVICE >> /dev/null
	echo "start nandc FS ($NAND_ROOT_DEVICE)"
	mkfs.ext4 $NAND_ROOT_DEVICE >> /dev/null
fi
}

disableJournal(){
echo "start ${NAND_ROOT_DEVICE}"
tune2fs -o journal_data_writeback $NAND_ROOT_DEVICE >> /dev/null
tune2fs -O ^has_journal $NAND_ROOT_DEVICE >> /dev/null
e2fsck -f $NAND_ROOT_DEVICE
if [[ "$PARTNUM" = "3" ]];then
	echo ""
	echo "start ${NAND_INITRD_DEVICE}"
	tune2fs -o journal_data_writeback $NAND_INITRD_DEVICE >> /dev/null
	tune2fs -O ^has_journal $NAND_INITRD_DEVICE >> /dev/null
	e2fsck -f $NAND_INITRD_DEVICE
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
if [[ "$PARTNUM" = "3" ]];then
	if [ ! -d $MNT_INITRD ];then
	mkdir $MNT_INITRD
	fi
fi
mount $NAND_INITRD_DEVICE $MNT_INITRD
}

installBootloader(){
rm -rf $MNT_BOOT/*
rsync -avc $BOOTLOADER/* $MNT_BOOT
echo ""
if [[ "$PARTNUM" = "2" ]];then
	rsync -avc /boot/script.bin /boot/uEnv.txt /boot/uImage* $MNT_ROOT/boot/
	echo ""
	sed -e 's|root=/dev/mmcblk0p1|root='$NAND_ROOT_DEVICE'|g' -i $MNT_ROOT/boot/uEnv.txt
	if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
        echo "machid=${MACH_ID}" >> $MNT_ROOT/boot/uEnv.txt
	fi
fi
if [[ "$PARTNUM" = "3" ]];then
	rsync -avc /boot/script.bin /boot/uEnv.txt /boot/uImage* $MNT_INITRD/boot/
	echo ""
	sed -e 's|root=/dev/mmcblk0p1|root='$NAND_ROOT_DEVICE'|g' -i $MNT_INITRD/boot/uEnv.txt
	if [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
        echo "machid=${MACH_ID}" >> $MNT_INITRD/boot/uEnv.txt
	fi
fi
}

installRootfs(){
set +e
rsync -avc --exclude-from=$EXCLUDE_FILE_LIST / $MNT_ROOT
if [[ "$PARTNUM" = "3" ]];then
	rm -R /mnt/nandc/boot
	echo ""
	mkdir -v /mnt/nandc/mnt/nandb
	echo "create symlink"
	ln -sv /mnt/nandb/boot  /mnt/nandc/boot
fi
set -e
echoBlue "sync disk... please wait"
sync
}

patchRootfs(){
if [[ "$PARTNUM" = "2" ]];then
cat > ${MNT_ROOT}/etc/fstab <<END
#<file system>  <mount point>   <type>  <options>       <dump>  <pass>
$NAND_ROOT_DEVICE       /               ext4    defaults,noatime        0       1
END
fi

if [[ "$PARTNUM" = "3" ]];then
cat > ${MNT_ROOT}/etc/fstab <<END
#<file system>  <mount point>   <type>  <options>       <dump>  <pass>
$NAND_ROOT_DEVICE       /               ext4    defaults,noatime        0       1
$NAND_INITRD_DEVICE       /mnt/nandb      ext4    defaults        0       1
END
fi
}

rootSelect () {
if [[ "$PARTNUM" = "2" ]];then
	if [[ "$DEVICE_TYPE" = "$DEVICE_A10" ]];then
        NAND_ROOT_DEVICE="$NANDB_DEVICE"
	elif [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
        if [[ -b "$NANDB_DEVICE" ]];then
                 NAND_ROOT_DEVICE="$NANDB_DEVICE"
       elif [[ -b "$NAND3_DEVICE" ]];then
                NAND_ROOT_DEVICE="$NAND3_DEVICE"
        fi
	fi
fi

if [[ "$PARTNUM" = "3" ]];then
	if [[ -b $NANDB_DEVICE ]];then
			NAND_INITRD_DEVICE="$NANDB_DEVICE"
	elif [[ -b $NAND2_DEVICE ]];then
        NAND_INITRD_DEVICE="$NAND2_DEVICE"
	fi
	if [[ "$DEVICE_TYPE" = "$DEVICE_A10" ]];then
        NAND_ROOT_DEVICE="$NANDC_DEVICE"
	elif [[ "$DEVICE_TYPE" = "${DEVICE_A20}" ]];then
        if [[ -b "$NANDB_DEVICE" ]];then
                 NAND_ROOT_DEVICE="$NANDC_DEVICE"
       elif [[ -b "$NAND2_DEVICE" ]];then
                NAND_ROOT_DEVICE="$NAND3_DEVICE"
        fi
	fi
fi
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
clear
echo "


                                             
	##      ##    ###    ########  ##    ## #### ##    ##  ######   
	##  ##  ##   ## ##   ##     ## ###   ##  ##  ###   ## ##    ##  
	##  ##  ##  ##   ##  ##     ## ####  ##  ##  ####  ## ##        
	##  ##  ## ##     ## ########  ## ## ##  ##  ## ## ## ##   #### 
	##  ##  ## ######### ##   ##   ##  ####  ##  ##  #### ##    ##  
	##  ##  ## ##     ## ##    ##  ##   ###  ##  ##   ### ##    ##  
	 ###  ###  ##     ## ##     ## ##    ## #### ##    ##  ######   
 




                                                                              


"
if promptpart "How many partitions do you want to create?[2|3]"; then
echo ""
partChoice
rootSelect
if promptyn "Your data on $NAND_DEVICE will be PERMINANTLY lost, Are you sure to continue?[y|n]"; then
	echo ""
	echoBlue "Preparing NAND device"
    umountNand
    echoBlue "Re-partitioning NAND device"   
    formatNand 
    echoBlue "Check partition table"   
    if nandPartitionOK;then
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
        echoBlue "Optimize NAND performance"
            disableJournal
        echo ""
        echoGreen "*** Success! remember to REMOVE your SD card from board ***"
        echo ""
        if promptyn "shutdown now?";then
        shutdown -h now
        fi
        else
			echo ""
            echoRed "*** Re-partition NAND device ${NAND_DEVICE} failed, Partition table has damaged ***"
			echo ""
            echoYellow "To fix the partition table, You need to use livesuit restore a factory image"
        fi
	fi
fi
