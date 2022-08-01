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

set -e

echo "Setting up root SSH keys from 'cloud-init' (aka platform metadata)"
craysys metadata get root-private-key > /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa
craysys metadata get root-public-key > /root/.ssh/id_rsa.pub
chmod 644 /root/.ssh/id_rsa.pub
cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
chmod 644 /root/.ssh/authorized_keys

echo "Scheduling local DNS server(s) awareness updates for every 5 minutes"
echo "*/5 * * * * root . /etc/profile.d/cray.sh; /etc/ansible/gcp/bin/python3 /srv/cray/scripts/google/update-dns.py >> /var/log/cray/cron.log 2>&1" > /etc/cron.d/cray-update-dns

echo "Running initial local DNS server(s) awareness update"
while ! /etc/ansible/gcp/bin/python3 /srv/cray/scripts/google/update-dns.py; do
  sleep 5
done
systemctl restart cron
# TODO: something is wiping out the authorized_keys file, at least on Virtual Shasta, figure it out
#       traced it to something in either the update-dns.py above: restarting network services?
#       or the cron restart above?
cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
