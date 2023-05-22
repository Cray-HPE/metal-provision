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

WORKING_DIR="$(dirname $0)"

# TODO: Not done scripting this.
set -euo pipefail

# Default CSM Nexus URL
DEFAULT_NEXUS_URL='http://packages.nmn:8081'

# Defaults defined by Sonatype:
# https://help.sonatype.com/iqserver/managing/user-management#:~:text=Enter%20the%20current%20password%20(%22admin123,then%20confirm%20the%20new%20password.
DEFAULT_NEXUS_USERNAME='admin'
DEFAULT_NEXUS_PASSWORD='admin123'

function usage {

cat << EOF
usage:

Environment Variables:

ARTIFACTORY_USER    (for proxy mode only) username for artifactory.algol60.net
ARTIFACTORY_TOKEN   (for proxy mode only) token for ARTIFACTORY_USER
NEXUS_URL           (default: http://packages.nmn:8081) custom URL for reaching nexus.
NEXUS_USERNAME      (required) Nexus username (default: admin)
NEXUS_PASSWORD      (required) Nexus password (default: admin123)
CSM_PATH            (for server mode only) path to the CSM release tarball.

Options:

-p          Set up the running node as a proxy server; proxy everything defined in /srv/cray/metal-provision/scripts/repos/
            NOTE: This requires HTTPS_PROXY to be set within the running NEXUS instance http://packages.nmn:8081/#admin/system/http

            PIT access:

                - ssh -L 8081:localhost:8081 internal.system.hpc.amslabs.hpecorp.net
                - Visit http://localhost:8081/#admin/system/http
                - login with sonatype/nexus default credentials
-c          Set up the running node as a client; adds repositories /srv/cray/metal-provision/scripts/repos/ to Zypper but using the Nexus URL

-s          Set up the running node as a server; uploads a given CSM_RELEASE to the running Nexus instance at http://packages.nmn:8081
-C          Path to an EXTRACTED CSM tarball, will default to the CSM_PATH environment variable unless this is set.
EOF
}
proxy_server=0
server=0
client=0
CSM_PATH=${CSM_PATH:-''}
while getopts ":pscC" o; do
    case "${o}" in
        p)
            proxy_server=1
            ;;
        s)
            server=1
            ;;
        c)
            client=1
            ;;
        C)
            CSM_PATH="${OPTARG}"
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done
if [ $OPTIND -eq 1 ]; then usage; fi
shift $((OPTIND-1))

error=0
if [ "$proxy_server" -ne 0 ]; then
    if [ -z "${ARTIFACTORY_USER:-''}" ]; then
        echo >&2 'Missing ARTIFACTORY_USER'
        error=1
    elif [ -z "${ARTIFACTORY_TOKEN:-''}" ]; then
        echo >&2 'Missing ARTIFACTORY_TOKEN'
        error=1
    fi
fi
[ "$error" -ne 0 ] && exit 2

if [ -z "${NEXUS_USERNAME:-''}" ]; then
    echo >&2 'Missing NEXUS_USERNAME, assuming default ..'
    NEXUS_USERNAME="$DEFAULT_NEXUS_USERNAME"
elif [ -z "${NEXUS_PASSWORD:-''}" ]; then
    echo >&2 'Missing NEXUS_PASSWORD, assuming default ..'
    NEXUS_PASSWORD="$DEFAULT_NEXUS_PASSWORD"
fi

if [ -z ${NEXUS_URL:-''} ]; then
    echo >&2 'Missing NEXUS_URL, presuming default: DEFAULT_NEXUS_URL'
    NEXUS_URL="$DEFAULT_NEXUS_URL"
fi

function nexus-reset() {

    . ${WORKING_DIR}/../rpm-functions.sh
    list-google-repos-files
    list-hpe-repos-files
    list-suse-repos-files
    list-cray-repos-files
    list-compute-repos-files

    for repo_file in "${WORKING_DIR}"/../repos/*.repos; do
        if [[ $repo_file =~ template ]]; then
            continue
        fi
        mapfile -t repos < <(remove-comments-and-empty-lines ${repo_file} | awk '{print $1","$2}')
        for repo in "${repos[@]}"; do
            name="$(echo ${repo} | awk -F, '{print $NF}')"
            curl \
            -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
            --request DELETE \
            "${NEXUS_URL}/service/rest/v1/repositories/${name}"
            zypper rr ${name} || echo 'Zypper already clean'
        done
    done
}

function zypper-reset() {

    . ${WORKING_DIR}/../rpm-functions.sh
    list-google-repos-files
    list-hpe-repos-files
    list-suse-repos-files
    list-cray-repos-files
    list-compute-repos-files

    for repo_file in "${WORKING_DIR}"/../repos/*.repos; do
        if [[ $repo_file =~ template ]]; then
            continue
        fi
        mapfile -t repos < <(remove-comments-and-empty-lines ${repo_file} | awk '{print $1","$2}')
        for repo in "${repos[@]}"; do
            name="$(echo ${repo} | awk -F, '{print $NF}')"
            zypper rr "${name}"
        done
    done
}

function nexus-proxy() {

    . ${WORKING_DIR}/../rpm-functions.sh
    list-google-repos-files
    list-hpe-repos-files
    list-suse-repos-files
    list-cray-repos-files
    list-compute-repos-files

    basearch="$(uname -m)"
    sle_version="$(awk -F= '/VERSION_ID/{gsub(/["]/,""); print $NF}' /etc/os-release)"
    sle_major="${sle_version%.*}"
    sle_minor="${sle_version#*.}"

    for repo_file in "${WORKING_DIR}"/../repos/*.repos; do
        if [[ $repo_file =~ template ]]; then
            continue
        fi
	remove-comments-and-empty-lines "$repo_file" | \
	while read -r url name flags; do
            url="$(echo ${url} | sed 's/'"${ARTIFACTORY_USER}"':'"${ARTIFACTORY_TOKEN}"'@//' | awk -F, '{print $1}')"
	        url="$(echo $url | sed -e 's/${releasever_major}/'"${sle_major}"'/' -e 's/${releasever_minor}/'"${sle_minor}"'/' -e 's/${basearch}/'"${basearch}"'/' -e 's/${releasever}/'"${sle_version}"'/')"
            echo $name $url
            curl \
            -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
           "${NEXUS_URL}/service/rest/v1/repositories/yum/proxy" \
           --header "Content-Type: application/json" \
           --request POST \
           --data-binary \
           @- << EOF
{
  "name": "$name",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "$url",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {

    "blocked": false,
    "autoBlock": true,
    "connection": {
      "retries": 0,
      "timeout": 60,
      "enableCircularRedirects": false,
      "enableCookies": false,
      "useTrustStore": false
    },
    "authentication": {
      "type": "username",
      "username": "$ARTIFACTORY_USER",
      "password": "$ARTIFACTORY_TOKEN"
    }
  }
}
EOF
        zypper ar $flags "${NEXUS_URL}/repository/${name}" "${name}"

        # FIXME: The GPG check won't work because nexus does not have the GPG keys necessary. Disable GPG check for all.
        zypper mr --no-gpgcheck "${name}"
        done
    done
}

function setup-zypper-nexus() {

    . ${WORKING_DIR}/../rpm-functions.sh
    list-google-repos-files
    list-hpe-repos-files
    list-suse-repos-files
    list-cray-repos-files
    list-compute-repos-files

    for repo_file in "${WORKING_DIR}"/../repos/*.repos; do
        if [[ $repo_file =~ template ]]; then
            continue
        fi
    	remove-comments-and-empty-lines "$repo_file" | \
	    while read -r url name flags; do
            url="$(echo ${repo} | sed 's/.*@//' | awk -F, '{print $1}')"
        zypper ar $flags "${NEXUS_URL}/repository/${name}" "${name}"
        zypper mr --no-gpgcheck "${name}"
        done
    done
}

if [ "$server" -ne 0 ]; then
    echo "Uploading RPMs from $CSM_PATH/rpms ... "
    echo 'Just kidding, not yet implemented.'
elif [ "$proxy_server" -ne 0 ]; then
    echo "Setting up $NEXUS_URL as a proxy ... "
    nexus-reset 2>/dev/null
    nexus-proxy
fi
if [ "$client" -ne 0 ]; then
    echo "Adding nexus proxy repos to Zypper ... "

    echo "Purging existing definitions ... "
    zypper-reset

    echo "Adding repos ... "
    setup-zypper-nexus
fi
