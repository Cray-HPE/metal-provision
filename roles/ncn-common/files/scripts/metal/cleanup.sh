#!/bin/bash
#
# MIT License
#
# (C) Copyright 2022 Hewlett Packard Enterprise Development LP
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
set -euo pipefail

ALL=0
AUTO=0
BASE="$(lsblk -o MOUNTPOINT -nr /dev/disk/by-label/SQFSRAID)"
DISK="$(blkid -L SQFSRAID)"
LIVE_DIR=$(grep -oP 'rd.live.dir=[\w\d-_.]+' /proc/cmdline)
[ -z "$LIVE_DIR" ] && LIVE_DIR='rd.live.dir=LiveOS'
LIVE_DIR="${LIVE_DIR#*=}"

function usage {
    cat << EOF
$0 can be ran with the following:

- Passing any argument other than -y or -a will print this usage.
- Passing '-y' will automatically clean unused images, bypassing the prompt.
- Passing '-a' will include all images (unused and used), this will break disk booting unless the node is re-imaged on the next reboot.
EOF
}

while getopts "ya" opt; do
    case ${opt} in
        y)
            AUTO=1
            ;;
        a)
            ALL=1
            ;;
        *)
            usage
    esac
done

if [ ${ALL} = 0 ]; then
    readarray -t LIVE_DIRS < <(find /run/initramfs/live/* -type d -exec basename {} \; 2>/dev/null| grep -v ${LIVE_DIR})
else
    readarray -t LIVE_DIRS < <(find /run/initramfs/live/* -type d -exec basename {} \; 2>/dev/null)
fi
function print_capacity {
    local capacity
    local used

    capacity="$(df -h /run/initramfs/live | awk '{print $2}' | sed -z 's/\n/: /g;s/: $/\n/')"
    used="$(df -h /run/initramfs/live | awk '{print $3}' | sed -z 's/\n/: /g;s/: $/\n/')"

    echo -e "Image storage status:\n\n\t$capacity\n\t$used\n" 
}
print_capacity
echo "Current used image directory is: [${BASE}/${LIVE_DIR}]"
if [ "${#LIVE_DIRS[@]}" = 0 ]; then
    echo 'Nothing to remove.'
    exit 1
fi
echo 'Found the following unused image directories: '
for live_dir in "${LIVE_DIRS[@]}"; do
    size=$(du -hs ${BASE}/$live_dir | awk '{print $1}')
    printf '\t%s\t%s\n' ${live_dir} ${size}
done
if [ ${AUTO} = 0 ]; then
    read -r -p "Proceed to cleanup listed image directories? [y/n]:" response
    case "$response" in
        [yY][eE][sS]|[yY])
            echo 'Removing image directories ...'
            ;;
        *)
            echo 'Exiting without removing anything.'
            exit 0
            ;;
    esac
else
    echo '-y was present; automatically removing images ...'
fi

to_remove="$(printf ${BASE}'/%s ' "${LIVE_DIRS[@]}")"
mount -o rw,remount ${DISK} ${BASE}
if [ ${ALL} = 1 ]; then
    echo "-a was present; removing ALL images including the currently booted image [${BASE}/${LIVE_DIR}]"
    echo >&2 "This node will be unable to diskboot until it is reimaged with a netboot."
    rm -rf ${to_remove} "${BASE:?}/${LIVE_DIR}"
else
    rm -rf ${to_remove}
fi
echo 'Done'

# Attempt to remount as ro, but don't fail
if ! mount -o ro,remount ${DISK} ${BASE} 2>/dev/null; then
    echo >&2 "Attempted to remount ${BASE} as read-only but the device was busy"
fi 

# Do not reprint the size, for some reason it doesn't report properly for a given amount of time.
#print_capacity
