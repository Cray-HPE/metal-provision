#!/bin/bash
#
# MIT License
#
# (C) Copyright 2021-2022 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#

# This script does not use bind mounts and thus executes correctly in a container.
set -ex

. "$(dirname $0)/dracut-lib.sh"

echo "Generating initrd..."
dracut \
--force \
--force-add "dmsquash-live livenet" \
--kver ${KVER} \
--no-hostonly \
--no-hostonly-cmdline \
--printsize

echo "Copying vmlinuz and initrd into /squashfs for disk-bootloader setup."
rm -f /squashfs/*
cp -pv /boot/vmlinuz-${KVER} /squashfs/${KVER}.kernel
cp -pv /boot/initrd-${KVER} /squashfs/initrd.img.xz

exit 0
