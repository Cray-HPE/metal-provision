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
set -euo pipefail
set -x
if [ "$RUN_OSCAP" != true ]; then
    touch /tmp/oval-results.xml
    touch /tmp/oval-patch-results.xml
    touch /tmp/oval-report.html
    touch /tmp/oval-patch-report.html
    exit 0
fi

OS_VERSION="$(awk -F= '/VERSION_ID=/{gsub(/["-]/, "") ; print tolower($NF)}' /etc/os-release)"

TEMP_DIR="$(mktemp -d)"
(
    cd "$TEMP_DIR"
    curl -fLC - \
        --proxy "${HTTPS_PROXY:-}" \
        --retry-all-errors \
        --retry 25 \
        --retry-delay 5 \
        -O "https://ftp.suse.com/pub/projects/security/oval/suse.linux.enterprise.${OS_VERSION%.*}-sp${OS_VERSION#*.}.xml.bz2"
    echo 'Running OVAL test ...'
    oscap oval eval --skip-valid --results oval-results.xml "suse.linux.enterprise.${OS_VERSION%.*}-sp${OS_VERSION#*.}.xml.bz2" > oval-standard-out.txt
    oscap oval generate report --output oval-report.html oval-results.xml
    mv oval*.xml oval*.html /tmp
)
rm -rf "${TEMP_DIR}"
TEMP_DIR="$(mktemp -d)"
(
    cd "$TEMP_DIR"
    curl -fLC - \
        --proxy "${HTTPS_PROXY:-}" \
        --retry-all-errors \
        --retry 25 \
        --retry-delay 5 \
        -O "https://ftp.suse.com/pub/projects/security/oval/suse.linux.enterprise.${OS_VERSION%.*}-sp${OS_VERSION#*.}-patch.xml.bz2"
    echo 'Running OVAL Patch test...'
    oscap oval eval --skip-valid --results oval-patch-results.xml "suse.linux.enterprise.${OS_VERSION%.*}-sp${OS_VERSION#*.}-patch.xml.bz2" > oval-patch-standard-out.txt
    oscap oval generate report --output oval-patch-report.html oval-patch-results.xml
    mv oval*.xml oval*.html /tmp
)
rm -rf "${TEMP_DIR}"
