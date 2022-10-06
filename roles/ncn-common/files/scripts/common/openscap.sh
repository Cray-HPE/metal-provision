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

# Remove any existing files
rm -f suse.linux.enterprise.server.15.xml
rm -f suse.linux.enterprise.server.15-patch.xml
# Obtain the relevant OVAL files
curl -f -O -J https://ftp.suse.com/pub/projects/security/oval/suse.linux.enterprise.server.15.xml
curl -f -O -J https://ftp.suse.com/pub/projects/security/oval/suse.linux.enterprise.server.15-patch.xml

# Run a test, output the results
echo 'Running OVAL test...'
oscap oval eval --results /tmp/oval-results.xml suse.linux.enterprise.server.15.xml > /tmp/oval-standard-out.txt
# Convert to html
oscap oval generate report --output /tmp/oval-report.html /tmp/oval-results.xml
echo 'Running OVAL Patch test...'
oscap oval eval --results /tmp/oval-patch-results.xml suse.linux.enterprise.server.15-patch.xml > /tmp/oval-patch-standard-out.txt
# Convert to html
oscap oval generate report --output /tmp/oval-patch-report.html /tmp/oval-patch-results.xml
