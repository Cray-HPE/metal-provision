#!/usr/bin/env bash
#
# MIT License
#
# (C) Copyright 2023 Hewlett Packard Enterprise Development LP
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

ANSIBLE_VERSION=7.5.0
ANSIBLE_CORE_VERSION=2.14.5

# Some distros (e.g. centos) use space delimited values in /etc/os-release for ID_LIKE, ensure we just grab
# the first entry.
OS="$(awk -F= '/ID_LIKE/{gsub("\"", ""); print $NF}' /etc/os-release | awk '{print $1}')"
if [ -z "${OS}" ]; then
    echo >&2 'Failed to detect OS from /etc/os-release'
    exit 1
else
    echo "Detected OS family: ${OS}"
fi

# Installs Ansible
function install_ansible {

    local requirements=( boto3 netaddr )

    echo "Installing Ansible ${ANSIBLE_VERSION} (ansible-core: ${ANSIBLE_CORE_VERSION})"
    mkdir -pv /etc/ansible /opt/cray/ansible
    case "${OS}" in
        debian)
            python3.10 -m venv --upgrade-deps /opt/cray/ansible
            ;;
        rhel)
            python3.11 -m venv --upgrade-deps /opt/cray/ansible
            ;;
        suse)
            python3.10 -m venv --upgrade-deps /opt/cray/ansible
            ;;
    esac

    . /opt/cray/ansible/bin/activate
    python3 -m pip install ansible-core==$ANSIBLE_CORE_VERSION ansible==${ANSIBLE_VERSION}

    echo "Installing requirements: ${requirements[*]}"
    for requirement in "${requirements[@]}"; do
        python3 -m pip install -U "${requirement}"
    done
    deactivate
}

# Wrapper function for setting up repositories in a Packer environment.
# Expects the metal-provision repository to be at /srv/cray/metal-provision.
function setup_repositories {
    case "${OS}" in
        debian)
            apt-get update
            apt list --installed > /tmp/initial.packages
            ;;
        rhel)
            # TODO: Use our own mirrors.
            rpm --import https://www.centos.org/keys/RPM-GPG-KEY-CentOS-Official && \
            rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-8 && \
            dnf -y --disablerepo '*' --enablerepo=extras \
                swap centos-linux-repos centos-stream-repos && \
            dnf -y distro-sync
            yum makecache -y -q
            yum update -y
            rpm -qa | sort -h > /tmp/initial.packages
            ;;
        suse)
            set +eu
            . /srv/cray/metal-provision/scripts/rpm-functions.sh
            setup-package-repos "$@"
            get-current-package-list /tmp/initial.packages explicit
            get-current-package-list /tmp/initial.deps.packages deps
            set -eu
            ;;
    esac
}

# Resize the rootFS, useful for expanding a VM's rootFS when using a new disk.
function resize_root {
    local dev_disk
    local dev_partition_nr

    # Find device and partition of /
    cd /
    df . | tail -n 1 | tr -s " " | cut -d " " -f 1 | sed -E -e 's/^([^0-9]+)([0-9]+)$/\1 \2/' |
    if read -r dev_disk dev_partition_nr && [ -n "$dev_partition_nr" ]; then
        echo "Expanding $dev_disk partition $dev_partition_nr";
        sgdisk --move-second-header
        sgdisk --delete=${dev_partition_nr} "$dev_disk"
        sgdisk --new=${dev_partition_nr}:0:0 --typecode=0:8e00 ${dev_disk}
        partprobe "$dev_disk"

        if ! resize2fs "${dev_disk}${dev_partition_nr}"; then
            if ! xfs_growfs ${dev_disk}${dev_partition_nr}; then
                echo >&2 "Neither resize2fs nor xfs_growfs could resize the device. Potential filesystem mismatch on [$dev_disk]."
                lsblk "$dev_disk"
            fi
        fi
    fi
    cd -
}

# LEGACY FUNCTION
# Overrides any newer Python version than what the python3 package installed.
# Newer images defer to newer versions of Python not provided by python3-base.
# This script will only be used in the following image layers (and it will not live in metal-pro):
# node-images-ncn-common
# node-images-kubernetes
# node-images-storage-ceph
# node-images-application <--- potentially changing after blue/green
# node-images-compute     <--- potentially changing after blue/green
function setup_legacy_python {
    local python_default
    python_default="$(rpm -q --queryformat '%{VERSION}' python3 | awk -F'.' '{ printf("%d.%d", $1, $2) }')"

    echo 'Removing /usr/local/bin/pip3 to ensure /usr/bin/pip3 is preferred in the $PATH'
    rm -f /usr/local/bin/pip3

    # ensure $PYTHON_DEFAULT is in fact the default
    rm -f /usr/bin/pip /usr/bin/pip3 /usr/bin/python3
    ln -s "/usr/bin/pip$python_default" /usr/bin/pip
    ln -s "/usr/bin/pip$python_default" /usr/bin/pip3
    ln -s "/usr/bin/python$python_default" /usr/bin/python3 # /usr/bin/python is set by Ansible later.
}


# HPC metal clusters reflect their nature through the SLES HPC Release RPM.
# The conflicting RPM needs to be removed
# Forcing the the HPC rpm because removing sles-release auto removes dependencies
# even with -U when installing with inventory file
function hpc-release {

    echo "Etching release file"
    local restore_lock=0
    if zypper removelock kernel-default; then
        echo '- removing zypper lock for kernel-default'
        restore_lock=1
    fi
    echo '- installing SLE_HPC-release'
    zypper -n install --auto-agree-with-licenses --force-resolution SLE_HPC-release
    if [ "$restore_lock" -ne 0 ]; then
        echo '- restoring lock for kernel-default'
        zypper addlock kernel-default
    fi
}
