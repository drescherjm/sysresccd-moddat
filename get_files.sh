#!/bin/bash

# Copyright (C) 2013 Jonathan Vasquez <jvasquez1011@gmail.com>
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

if [ -z ${1} ]; then
	echo "Please pass the iso to this script. Example: ./get_files.sh /root/sysrcd.iso" && exit
fi

echo "Mounting"
mount -o loop,ro ${1} /tmp/iso

echo "Copying data"
cp -f /tmp/iso/sysrcd.dat sysrcd-ori.dat
cp -f /tmp/iso/isolinux/initram.igz initram-ori.igz
cp -f /tmp/iso/isolinux/isolinux.cfg isolinux-ori.cfg

echo "Unmounting"
umount /tmp/iso
