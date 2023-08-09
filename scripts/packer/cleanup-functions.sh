#!/bin/bash
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

# Some distros (e.g. centos) use space delimited values in /etc/os-release for ID_LIKE, ensure we just grab
# the first entry.
OS="$(awk -F= '/ID_LIKE/{gsub("\"", ""); print $NF}' /etc/os-release | awk '{print $1}')"
if [ -z "${OS}" ]; then
    echo >&2 'Failed to detect OS from /etc/os-release'
    exit 1
else
    echo "Detected OS family: ${OS}"
fi

# Function for priming SSH and authentication.
function cleanup_root_user {
    echo 'Cleanup authentication and SSH ... '
    echo "- Remove /etc/shadow entry for root"
    seconds_per_day=$(( 60*60*24 ))
    days_since_1970=$(( $(date +%s) / seconds_per_day ))
    sed -i "/^root:/c\root:\*:$days_since_1970::::::" /etc/shadow

    echo "- Remove root's .ssh directory"
    rm -rvf /root/.ssh

    echo "- Remove ssh host keys"
    rm -fv /etc/ssh/ssh_host*
}

# Function for printing rpm/zypper repo association
function zypper_repo_rpm {
    echo '- Zypper repository / RPM association'

    mapfile -t PACKAGES < <(rpm -qa --queryformat '%{NAME}\n' || true)
    mapfile -t REPOS_ALIAS < <(zypper --no-refresh info "${PACKAGES[@]}" | awk -F: '/^Repository/{gsub(/^[ \t]+/, "", $2); print $2}' | sort | uniq | grep -vi 'expired\|\@System' || true)

    # List zypper repository and the RPM's installed from it
    if [ ${#REPOS_ALIAS[@]} -gt 0 ]; then
        for repo in "${REPOS_ALIAS[@]}"; do
            printf '\n%s\n' "$(zypper --no-refresh lr -u "${repo}" | awk '/^URI/{print $3}' || true)"
            zypper se -s -i -r "${repo}" | awk -F'|' 'NF>0{print $2,$4,$5}' || true
            printf '=%.0s' {1..100}
        done
    fi

    # List RPM's that are not associated with a zypper repository (orphaned)
    printf '\n%s\n' "Orphaned packages. '@System'"
    zypper -q pa -i --orphaned | grep -v 'expired' | awk -F'|' 'NF>0{print $3,$4,$5}' || true
    printf '=%.0s' {1..100}
    printf '\n'
}

# Function for handling the cleanup/purge of any package manager
function cleanup_package_manager {
    echo 'Cleaning up OS package manager ...'
    case "${OS}" in
        debian)
            rm -rf /var/cache/apk/*
            ;;
        rhel)
            yum repolist > /tmp/installed.repos
            rpm -qa | sort -h > /tmp/installed.packages
            dnf clean all
            yum clean all
            ;;
        suse)
            . /srv/cray/metal-provision/scripts/rpm-functions.sh

            echo '- Generating BOM'
            get-current-package-list /tmp/installed.packages explicit
            get-current-package-list /tmp/installed.deps.packages deps
            zypper lr -e /tmp/installed.repos
            zypper_repo_rpm | tee /tmp/zypper_repo_rpm.log

            echo '- Removing Zypper Repos'
            cleanup-package-repos
            cleanup-all-repos

            echo '- Remove service repositories'
            mapfile -t repos < <(zypper ls | awk -F'|' '{print $3}' | tail -n +3 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
            for repo in "${repos[@]}"; do
                zypper rs "$repo"
            done

            echo "- Remove credential files ... "
            rm -vf /root/.zypp/credentials.cat
            rm -vf /etc/zypp/credentials.cat
            rm -vf /etc/zypp/credentials.d/*

            echo '- Any/all autoinstall cache '
            rm -rf /var/adm/autoinstall/cache

            echo '- zypper clean'
            zypper clean --all
            ;;
        *)
            echo >&2 'Unhandled OS; nothing to do'
            ;;
    esac
}

# Function for removing udev and networkmanager files from the build environment.
function cleanup_network {
    echo 'Removing build environment network files ... '
    echo '- Purge persistent-net udev rules'
    rm -f /etc/udev/rules.d/*-net.rules
    case "${OS}" in
        debian)
            :
            ;;
        rhel)
            :
            ;;
        suse)
            echo '- Purge wicked interface cache (necessary for virsh, or `vagrant up` on multiple instances will fail)'
            rm -f /var/lib/wicked/*.xml
            ;;
        *)
            echo >&2 'Unhandled OS; nothing to do'
            ;;
    esac
    echo 'Done'
}

function cleanup_id {
    echo 'Resetting ID files ... '
    echo '- Force a new, unique machine ID to be generated on next boot'
    truncate -s 0 /etc/machine-id

    echo '- Force a new random seed to be generated on next boot'
    rm -f /var/lib/systemd/random-seed
    echo 'Done'
}

function cleanup_history {
    echo 'Cleaning history ... '
    echo '- Truncate any logs from the install'
    find /var/log/ -type f -name "*.log.*" -exec rm -rf {} \;
    find /var/log -type f -exec truncate --size=0 {} \;

    echo '- Clear the history from the install'
    rm -f /root/.wget-hsts
    export HISTSIZE=0

    echo '- Print currently failed services'
    systemctl list-units --failed
    echo '- Clear all failed services for a fresh start'
    systemctl reset-failed
    echo '- Reprint currently failed services.'
    systemctl list-units --failed
    echo 'Done'
}

function cleanup_tmp {
    echo 'Purge /tmp and /var/tmp'
    rm -rf /tmp/* /var/tmp/*
}

function defrag {
    echo 'Defragment disk image file (write zeros to remaining space) ... '
    filler="$(($(df -BM --output=avail /|grep -v Avail|cut -d "M" -f1)-1024))"
    dd if=/dev/zero of=/root/zero-file bs=1M count=$filler
    rm -f /root/zero-file
}
