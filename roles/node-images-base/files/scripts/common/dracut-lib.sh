#!/bin/bash
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

# These modules can't exist in the dracut.conf files because they fail on --hostonly builds of dracut,
# for example when kdump.service runs it uses --hostonly. These modules are necessary when building a
# PXE bootable initrd, but not for things such as kdump.
export ADD=( "dmsquash-live" "livenet" )

# Kernel Version
# This won't work well if multiple kernels are installed, this rpm command returns the highest
# installed version (which might not what's actually running). This script is used for dracut commands
# and other kernel dependent commands that need to run against the intended kernel. For example, during builds
# the kernel version might have changed (new RPM installed, old RPM removed) but because the build is ongoing
# the old kernel is still active. Therefore any scripts ran to prepare artifacts under the new kernel must key off
# of the actual installed package instead of `uname -r`.
version_full=$(rpm -q --queryformat "%{VERSION}-%{RELEASE}\n" kernel-default)
version_base=${version_full%%-*}
version_suse=${version_full##*-}

# If a TEST or PTF kernel is installed, the RELEASE string matches what's in /lib/modules. For released
# kernels the value of RELEASE does NOT match what's in /lib/modules and the revision digit on the end needs
# to be stripped.
if ! [[ ${version_suse} =~ \.(TEST|PTF)\. ]]; then
    version_suse=${version_suse%.*}
fi
export KVER="${version_base}-${version_suse}-default"
