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
set -eu

if [ "$RUN_OSCAP" != true ] ; then
  touch /tmp/oval-results.xml
  touch /tmp/oval-patch-results.xml
  touch /tmp/oval-report.html
  touch /tmp/oval-patch-report.html
  exit 0
fi

SLES_MAJOR=$(awk -F= '/VERSION_ID/{gsub(/["]/,"");printf("%d", $NF)}' /etc/os-release)
TEMP_DIR=$(mktemp -d)

# Obtain the relevant OVAL files, download to a temporary directory.
cd $TEMP_DIR
wget -e use_proxy=yes \
     -e https_proxy=${HTTPS_PROXY:-} \
     --continue \
     --retry-connrefused \
     --tries=35 \
     --waitretry=5 \
     https://${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}@artifactory.algol60.net/artifactory/suse-pub-mirror/projects/security/oval/suse.linux.enterprise.server.${SLES_MAJOR}.xml

wget -e use_proxy=yes \
     -e https_proxy=${HTTPS_PROXY:-} \
     --continue \
     --retry-connrefused \
     --tries=35 \
     --waitretry=5 \
     https://${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}@artifactory.algol60.net/artifactory/suse-pub-mirror/projects/security/oval/suse.linux.enterprise.server.${SLES_MAJOR}-patch.xml

# Create oval test results in /tmp so the Pipeline can find them in an expected location.
echo 'Running OVAL test ...'
oscap oval eval --skip-valid --results oval-results.xml suse.linux.enterprise.server.${SLES_MAJOR}.xml > oval-standard-out.txt
oscap oval generate report --output oval-report.html oval-results.xml

echo 'Running OVAL Patch test...'
oscap oval eval --skip-valid --results oval-patch-results.xml suse.linux.enterprise.server.${SLES_MAJOR}-patch.xml > oval-patch-standard-out.txt
oscap oval generate report --output oval-patch-report.html oval-patch-results.xml

# Make available for Packer to download.
mv oval*.xml oval*.html /tmp

cd && rm -rf ${TEMP_DIR}
