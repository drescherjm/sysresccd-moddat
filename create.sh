#!/bin/bash

# Copyright 2014-2015 Jonathan Vasquez <jvasquez1011@gmail.com>
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Instructions:
# ./create.sh <rescue64> <altker64> <path_to_iso>

# Your files will be located in the out/ directory.

H="$(pwd)"
SRM="${H}/zfs-srm"
BIC="/opt/bliss-initramfs"
BIC_EXE="mkinitrd.py"
R="${H}/extract"
IR="${H}/initram"
OUT="${H}/out"
T=`mktemp -d`

# Utility Functions

# Used for displaying information
einfo()
{
        eline && echo -e "\e[1;32m>>>\e[0;m ${@}"
}

# Used for input (questions)
eqst()
{
        eline && echo -en "\e[1;37m>>>\e[0;m ${@}"
}

# Used for warnings
ewarn()
{
        eline && echo -e "\e[1;33m>>>\e[0;m ${@}"
}

# Used for flags
eflag()
{
        eline && echo -e "\e[1;34m>>>\e[0;m ${@}"
}

# Used for options
eopt()
{
        echo -e "\e[1;36m>>\e[0;m ${@}"
}


# Prints empty line
eline()
{
    echo ""
}


# Used for errors
die()
{
        eline && echo -e "\e[1;31m>>>\e[0;m ${@}" && eline && exit
}

# Clean up
clean()
{
    rm -rf ${R} ${SRM} ${IR} ${H}/*-ori*
}

# ============================================================

if [[ $# != 3 ]] ; then
    die "./create.sh <rescue64> <altker64> <path_to_iso>. Example: ./create.sh 3.14.35-std452-amd64 3.18.10-alt452-amd64 /root/sysresccd.iso"
fi

# We will make sure we are home (We are already home though since H = pwd)
cd ${H}

# First we will extract the required files from the sysresccd iso
einfo "Mounting..."

mount -o ro,loop ${3} ${T} || "Failed to loop mount the iso. Make sure you have loop support in your kernel."

einfo "Copying required files..."

cp -f ${T}/sysrcd.dat sysrcd-ori.dat
cp -f ${T}/isolinux/initram.igz initram-ori.igz
cp -f ${T}/isolinux/isolinux.cfg isolinux-ori.cfg

einfo "Unmounting..." && umount ${T}

# Remove temporary directory
rm -rf "${T}"

# Check to see if required files exist
if [ ! -f "sysrcd-ori.dat" ]; then
    die "The 'sysrcd-ori.dat' file doesn't exist."
elif [ ! -f "initram-ori.igz" ]; then
    die "The 'initram-ori.igz' file doesn't exist."
elif [ ! -f "isolinux-ori.cfg" ]; then
    die "The 'isolinux-ori.cfg' file doesn't exist."
fi

# Check to see if the kernel directory exists
if [ ! -d "/usr/src/linux-${1}" ]; then
    die "The kernel directory: /usr/src/linux-${1} doesn't exist."
fi

if [ ! -d "/usr/src/linux-${2}" ]; then
    die "The kernel directory: /usr/src/linux-${2} doesn't exist."
fi

# Check to see if the kernel modules directory exists
if [ ! -d "/lib64/modules/${1}" ]; then
    die "The kernel modules directory: /lib64/modules/${1} doesn't exist."
else
    if [ ! -d "/lib64/modules/${1}/extra" ]; then
        die "The kernel modules directory for spl/zfs: /lib64/modules/${1}/extra doesn't exist. Please compile your spl and zfs modules before running the application."
    fi
fi

if [ ! -d "/lib64/modules/${2}" ]; then
    die "The kernel modules directory: /lib64/modules/${2} doesn't exist."
else
    if [ ! -d "/lib64/modules/${2}/extra" ]; then
        die "The kernel modules directory for spl/zfs: /lib64/modules/${2}/extra doesn't exist. Please compile your spl and zfs modules before running the application."
    fi
fi

einfo "Creating clean baselayout..."

if [ ! -d "${R}" ]; then
    mkdir ${R}
else
    rm -rf ${R} && mkdir ${R}
fi

if [ ! -d "${IR}" ]; then
    mkdir ${IR}
else
    rm -rf ${IR} && mkdir ${IR}
fi

if [ ! -d "${SRM}" ]; then
    mkdir ${SRM}
else
    rm -rf ${SRM} && mkdir ${SRM}
fi

if [ ! -d ${OUT} ]; then
    mkdir ${OUT}
else
    rm -rf ${OUT} && mkdir ${OUT}
fi

# =========
# Generate the zfs srm (bliss-initramfs basically, and then we strip it to only keep userspace applications and a few other files)
# =========

# Generate a bliss-initramfs and extract it in the zfs-srm directory

cd ${BIC} && ./${BIC_EXE} 1 ${1} && mv initrd-${1} ${SRM} && cd ${SRM}
mv initrd-${1} initrd.gz && cat initrd.gz | gzip -d | cpio -id && rm initrd.gz

# ===========
# Clean out the junk not necessary for sysresccd
# ===========

einfo "Removing unnecessary files from bliss-initramfs and configuring it for sysresccd use..."

# Remove unncessary directories
rm -rf bin/ dev/ proc/ sys/ root/ run/ mnt/ usr/bin/ etc/ \
    init libraries/ lib/modules/ lib/udev/
rm sbin/{depmod,insmod,kmod,lsmod,modinfo,modprobe,rmmod,*udevd} 2> /dev/null

# Make /etc/zfs directory so that the zpool.cache file can be created
# when the user creates/imports their pool in the iso
mkdir -p etc/zfs

# Copy udev files from live system
mkdir -p lib/udev/rules.d
cp /lib64/udev/rules.d/{60-zvol,69-vdev,90-zfs}.rules lib/udev/rules.d
cp /lib64/udev/{vdev,zvol}_id lib/udev

# Perform some substitions so that udev uses the correct udev_id file
# (Needed for making swap zvol - /dev/zvol/<pool name>/<swap dataset name>)
sed -i -e 's:/lib64/:/lib/:' lib/udev/rules.d/69-vdev.rules
sed -i -e 's:/lib64/:/lib/:' lib/udev/rules.d/60-zvol.rules

# ============
# Prepare the sysrcd.dat
# ============

einfo "Extracting sysresccd rootfs and installing our modules/userspace applications into it..."

cd ${R} && unsquashfs ${H}/sysrcd-ori.dat

if [ ! -d "squashfs-root" ]; then
    die "The 'squashfs-root' directory doesn't exist."
fi

einfo "Removing old kernel modules and copying new ones..."

# Remove the old sysresccd 64 bit kernel modules since we will be replacing them
rm -rf squashfs-root/lib64/modules/${1}
rm -rf squashfs-root/lib64/modules/${2}

# Copy the spl/zfs modules into the squashfs image (sysresccd rootfs)
cp -r /lib64/modules/${1} squashfs-root/lib64/modules/
cp -r /lib64/modules/${2} squashfs-root/lib64/modules/

einfo "Regenerating module dependencies from within the sysresccd rootfs..."

# Regenerate module dependencies for the kernel from within the sysresccd rootfs
chroot squashfs-root /bin/bash -l -c "depmod ${1}" 2> /dev/null
chroot squashfs-root /bin/bash -l -c "depmod ${2}" 2> /dev/null

# Merge zfs-srm folder with this folder
einfo "Installing zfs userspace applications and files into the sysresccd rootfs..."
rsync -av ${SRM}/ squashfs-root/

einfo "Remaking the squashfs..."
mksquashfs squashfs-root/ ${H}/sysrcd-new.dat

# ============
# Now it's time to work on the initram
# ============

einfo "Extracting the sysresccd initramfs and installing our modules into it..."
cd ${IR} && cat ${H}/initram-ori.igz | xz -d | cpio -id

# Copy the kernel modules to the /lib/modules directory.
mkdir lib/modules
cp -r ${R}/squashfs-root/lib64/modules/${1} lib/modules
cp -r ${R}/squashfs-root/lib64/modules/${2} lib/modules

# Delete old firmware files for wireless cards (This folder only contains the kernel provided firmware)
rm -rf lib/firmware

# Copy the firmware files for wireless cards (This includes support for all wireless cards - linux-firmware)
cp -r ${R}/squashfs-root/lib/firmware/ lib/firmware

# Remake the initramfs
ewarn "Creating the new initram.igz. Please wait a moment since this is a single-threaded operation!"
find . | cpio -H newc -o | xz --check=crc32 --x86 --lzma2 > ${H}/initram-new.igz

# =========
# Edit the isolinux.cfg to it has + ZFS in its name
# =========

einfo "Editing the isolinux.cfg and adding '+ ZFS' to the title"

# Add "+ ZFS" after the version in the title to distinguish
# it from original disks
SRV="$(cat ${H}/isolinux-ori.cfg | grep SYSTEM-RESCUE-CD | cut -d " " -f 4)"
sed "s/${SRV}/${SRV} + ZFS/" ${H}/isolinux-ori.cfg > ${H}/isolinux-new.cfg

einfo "Renaming other files and making sure all necessary files are in the out/ directory ..."

# Move the new files to the out/ directory
mv ${H}/*-new* ${OUT}

cd ${OUT}
mv sysrcd-new.dat sysrcd.dat && md5sum sysrcd.dat > sysrcd.md5
mv initram-new.igz initram.igz
mv isolinux-new.cfg isolinux.cfg

cp /usr/src/linux-${1}/arch/x86_64/boot/bzImage rescue64
cp /usr/src/linux-${2}/arch/x86_64/boot/bzImage altker64

clean

einfo "Complete"
