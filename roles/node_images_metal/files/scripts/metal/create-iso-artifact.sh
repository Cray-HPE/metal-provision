#!/bin/bash
# MIT License
#
# (C) Copyright 2022-2023 Hewlett Packard Enterprise Development LP
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
set -ex
trap cleanup EXIT

function cleanup {
    rm -rf /iso_src
    rm -fv /tmp/grub.cfg
}

# Fetch ARCH from the buildenv, if it is defined.
ARCH="${ARCH:-}"

if [ -z "${ARCH}" ]; then
    ARCH="$(uname -m)"
fi

if [ "${ARCH}" = "aarch64" ]; then
    ARCH="arm64"
fi

EFI_DIR='EFI/BOOT'
BOOT_DIR="boot/${ARCH}"
BOOT_LOADER_DIR="${BOOT_DIR}/loader"
BOOT_CATALOG="boot.catalog"
BOOT_IMAGE='efiboot.img'
EFI_A64_BINARY='bootaa64.efi'
EFI_X64_BINARY='bootx64.efi'

if [ ${ARCH,,} = 'arm64' ]; then
    EFI_BINARY=${EFI_A64_BINARY}
elif [ ${ARCH,,} = 'x86_64' ]; then
    EFI_BINARY=${EFI_X64_BINARY}
fi

echo "Building for [${ARCH}] [${EFI_BINARY}]"

ISO_FSLABEL="${ISO_FSLABEL:-CRAYLIVE}"
export ISO_FSLABEL
ISO_NAME="${ISO_NAME:-'ISO'}"
ISO_OUTPUT='/tmp/iso'
ISO_SOURCE="${ISO_OUTPUT}_src"

# Cleanup the /boot/efi entry in /etc/fstab to avoid trying to mount the EFI partition on ISO boot.
function cleanup-fstab {
    # temporarily mount a new /etc/fstab
    cp /etc/fstab /tmp/fstab.new
    sed -i '/UUID=.*\/boot\/efi.*/d' /tmp/fstab.new
    mount --bind /tmp/fstab.new /etc/fstab
}

# The default image name for dracut is squashfs.img, and the default directory for dracut is LiveOS.
function install-squashimg {
    mkdir -pv ${ISO_SOURCE}/LiveOS || return 1
    mv -v /squashfs/filesystem.squashfs ${ISO_SOURCE}/LiveOS/squashfs.img
}


function install-grub2 {
    local random_hex

    random_hex="$(openssl rand -hex 4)"
    export app_id="0x${random_hex}"
    export BOOT_LOADER_DIR
    name=$(grep PRETTY_NAME /etc/*release* | cut -d '=' -f2 | tr -d '"')
    export name

    mkdir -pv "${ISO_SOURCE}/${EFI_DIR}" "${ISO_SOURCE}/${BOOT_LOADER_DIR}" || return 1

    echo "$app_id" > ${ISO_SOURCE}/${BOOT_DIR}/../${app_id}
    envsubst '$app_id $BOOT_LOADER_DIR $name $ISO_FSLABEL' < $(dirname $0)/grub.template.cfg > /tmp/grub.cfg

    grub2-mkstandalone \
        --format=${ARCH}-efi \
        --output=${ISO_SOURCE}/${EFI_DIR}/${EFI_BINARY} \
        --locales="" \
        --fonts="" \
        --themes=SLE \
        "boot/grub/grub.cfg=/tmp/grub.cfg"

    mv -v "/squashfs/${KVER}.kernel" "${ISO_SOURCE}/${BOOT_LOADER_DIR}/kernel"
    mv -v /squashfs/initrd.img.xz "${ISO_SOURCE}/${BOOT_LOADER_DIR}"

    (dd if=/dev/zero of="${ISO_SOURCE}/${BOOT_LOADER_DIR}/${BOOT_IMAGE}" bs=1M count=10 && \
        mkfs.vfat -n BOOT "${ISO_SOURCE}/${BOOT_LOADER_DIR}/${BOOT_IMAGE}" && \
        mmd -i "${ISO_SOURCE}/${BOOT_LOADER_DIR}/${BOOT_IMAGE}" efi ${EFI_DIR,,} && \
        mcopy -i "${ISO_SOURCE}/${BOOT_LOADER_DIR}/${BOOT_IMAGE}" "${ISO_SOURCE}/${EFI_DIR}/${EFI_BINARY}" ::${EFI_DIR,,}
    )

}

function create-iso {
    local iso="${ISO_OUTPUT}/${ISO_NAME}.iso"
    mkdir -pv "${ISO_OUTPUT}" || return 1
    xorriso \
        -publisher 'Cray-HPE' \
        -application_id ${app_id} \
        -preparer_id 'METAL - https://github.com/Cray-HPE/node-images' \
        -copyright_file /tmp/LICENSE \
        -joliet on \
        -padding 0 \
        -volid "${ISO_FSLABEL}" \
        -outdev ${iso} \
        --map "${ISO_SOURCE}" / \
        -- \
        -boot_image grub bin_path="${BOOT_LOADER_DIR}/${BOOT_IMAGE}" \
        -boot_image grub grub2_boot_info=on \
        -boot_image any partition_offset=16 \
        -boot_image any cat_path="${BOOT_DIR}/${BOOT_CATALOG}" \
        -boot_image any cat_hidden=on \
        -boot_image any boot_info_table=on \
        -boot_image any platform_id=0x00 \
        -boot_image any emul_type=no_emulation \
        -boot_image any load_size=2048 \
        -append_partition 2 0xef "${ISO_SOURCE}/${BOOT_LOADER_DIR}/${BOOT_IMAGE}" \
        -boot_image any appended_part_as=gpt \
        -boot_image any next \
        -boot_image any efi_path=--interval:appended_partition_2:all:: \
        -boot_image any platform_id=0xef \
        -boot_image any emul_type=no_emulation
    # NOTE: Can't sign the ISO with the HPE key because it is too large. --create-signature could be used but this makes a unique key.
    tagmedia --md5 --check --pad 150 "${iso}"
}

cleanup-fstab
cleanup
mkdir -pv "${ISO_SOURCE}" || exit 1

# Source common dracut parameters.
. "$(dirname $0)/../common/dracut-lib.sh"

install-grub2
install-squashimg
create-iso
