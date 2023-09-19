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

WORKING_DIR="$(dirname $0)"

# Default CSM Nexus URL - does not use HTTPS on purpose!
DEFAULT_NEXUS_URL='http://packages'

# Default Nexus registry - this is where csm docker images will be pushed to
# this does not have http or https purposefully. This is used with skopeo-sync function
DEFAULT_NEXUS_REGISTRY="registry:5000"

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
NEXUS_URL           (default: $DEFAULT_NEXUS_URL) custom URL for reaching nexus
NEXUS_REGISTRY      (default: $DEFAULT_NEXUS_REGISTRY) Nexus registry that images should be pushed to
NEXUS_USERNAME      (required) Nexus username (default: $DEFAULT_NEXUS_USERNAME)
NEXUS_PASSWORD      (required) Nexus password (default: $DEFAULT_NEXUS_PASSWORD)
PITDATA             (for server mode only) path to where the prep/site-init directory structure is
CSM_PATH            (for server mode only) path to the CSM release tarball
CSM_RELEASE         (for server mode only) name of the CSM release

Options:

-p          Set up the running node as a proxy server; proxy everything defined in ${WORKING_DIR}/repos/
            NOTE: This requires HTTPS_PROXY to be set within the running NEXUS instance:

            1. Visit $DEFAULT_NEXUS_URL/#admin/system/http
            2. Enable HTTP and HTTPS Proxy, set the URL, and set the ports to 80 and 443 (respectively)
            3. Save changes

            PIT access:

                - ssh -L 8081:localhost:8081 internal.system.hpc.amslabs.hpecorp.net
                - Visit http://localhost:8081/#admin/system/http
                - login with sonatype/nexus default credentials
-c          Set up the running node as a client; adds repositories ${WORKING_DIR}/repos/ to Zypper but using the Nexus URL
-d          Delete a repository by name
-s          Uploads a CSM_RELEASE tarball's RPMs to nexus, creating a CSM package server.

-u          Generic function to upload a given path to nexus.
-r          Name of repository to create or update in nexus (pairs with -u)
-t          Type of repository (e.g. raw, yum)
EOF
}
proxy_server=0
server=0
client=0
upload=0
delete=0
repo_path=''
repo_type='raw'
CSM_PATH=${CSM_PATH:-''}
while getopts ":pscr:d:u:t:" o; do
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
        r)
            repo_name="${OPTARG}"
            ;;
        d)
            delete=1
            repo_name="${OPTARG}"
            ;;
        u)
            upload=1
            repo_path="${OPTARG}"
            ;;
        t)
            repo_type="${OPTARG}"
            if [ "$repo_type" = 'rpm' ]; then
                repo_type='yum'
            fi
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

if [ -z "${NEXUS_URL:-}" ]; then
    echo >&2 'Missing NEXUS_URL, presuming default: DEFAULT_NEXUS_URL'
    NEXUS_URL="$DEFAULT_NEXUS_URL"
fi

if [ -z "${NEXUS_REGISTRY:-}" ]; then
    echo >&2 'Missing NEXUS_REGISTRY, presuming default: DEFAULT_NEXUS_REGISTRY'
    NEXUS_REGISTRY="$DEFAULT_NEXUS_REGISTRY"
fi

function nexus-reset() {

    . "${WORKING_DIR}/../rpm-functions.sh"
    list-google-repos-files
    list-hpe-repos-files
    list-suse-repos-files
    list-cray-repos-files
    list-compute-repos-files

    for repo_file in "${WORKING_DIR}"/../repos/*.repos; do
        if [[ $repo_file =~ template ]]; then
            continue
        fi
        mapfile -t repos < <(remove-comments-and-empty-lines "${repo_file}" | awk '{print $1","$2}')
        for repo in "${repos[@]}"; do
            name="$(echo "${repo}" | awk -F, '{print $NF}')"
            curl \
            -L \
            -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
            --request DELETE \
            "${NEXUS_URL}/service/rest/v1/repositories/${name}"
            zypper rr ${name} || echo 'Zypper already clean'
        done
    done
}

function zypper-reset() {

    . "${WORKING_DIR}/../rpm-functions.sh"
    list-google-repos-files
    list-hpe-repos-files
    list-suse-repos-files
    list-cray-repos-files
    list-compute-repos-files

    for repo_file in "${WORKING_DIR}"/../repos/*.repos; do
        if [[ $repo_file =~ template ]]; then
            continue
        fi
        mapfile -t repos < <(remove-comments-and-empty-lines "${repo_file}" | awk '{print $1","$2}')
        for repo in "${repos[@]}"; do
            name="$(echo ${repo} | awk -F, '{print $NF}')"
            zypper rr "${name}"
        done
    done
}

function nexus-proxy() {

    . "${WORKING_DIR}/../rpm-functions.sh"
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
	        name="$(echo $name | sed -e 's/${releasever_major}/'"${sle_major}"'/' -e 's/${releasever_minor}/'"${sle_minor}"'/' -e 's/${basearch}/'"${basearch}"'/' -e 's/${releasever}/'"${sle_version}"'/')"
	        url="$(echo $url | sed -e 's/${releasever_major}/'"${sle_major}"'/' -e 's/${releasever_minor}/'"${sle_minor}"'/' -e 's/${basearch}/'"${basearch}"'/' -e 's/${releasever}/'"${sle_version}"'/')"
            echo $name $url
            curl \
            -L \
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

function nexus-get-credential() {

    if ! command -v kubectl 1>&2 >/dev/null; then
      echo "Requires kubectl for auto-fetching credentials from Kubernetes secrets."
      return 1
    fi
    if ! command -v base64 1>&2 >/dev/null ; then
      echo "Requires base64 for decoding credentials from Kubernetes secrets."
      return 1
    fi

    [[ $# -gt 0 ]] || set -- -n nexus nexus-admin-credential

    kubectl get secret "${@}" >/dev/null || return $?

    NEXUS_USERNAME="$(kubectl get secret "${@}" --template '{{.data.username}}' | base64 -d)"
    NEXUS_PASSWORD="$(kubectl get secret "${@}" --template '{{.data.password}}' | base64 -d)"
}

function setup-nexus-server() {

    local name
    local repo_name

    if [ -n "$repo_path" ]; then
        name="$(basename "$repo_path")"
        for directory in "$repo_path/repos/"*; do
            repo_name="${name}-$(basename "$directory")"
            if ! nexus-create-repo "$repo_name" yum; then
                echo >&2 "Failed to create repo: $directory"
            fi
            if ! nexus-upload-yum "${directory}" "$repo_name"; then
                echo >&2 "Failed to upload $directory to $repo_name! Aborting."
                return 1
            fi
        done
    elif [ -n "${CSM_PATH}" ]; then
        if [ -z "${CSM_RELEASE:-}" ]; then
            echo >&2 'CSM_RELEASE value was unset!'
            return 1
        fi
        for directory in "${CSM_PATH}/rpm/cray/csm/"*; do
            name="$(basename "$directory")"
            # Name distro specific repos with their distro name in lower case.
            repo_name="csm-$CSM_RELEASE-${name,,}"
            if ! nexus-create-repo "$repo_name" yum; then
                echo >&2 "Failed to create repo: $repo_name. Aborting."
                return 1
            fi
            if ! nexus-create-repo-group-yum "csm-${name,,}" "$repo_name"; then
                echo >&2 "Failed to create repo group: csm-${name,,}"
                return 1
            fi
            if ! nexus-upload-yum "${directory}" "${repo_name}"; then
                echo >&2 "Failed to upload $directory to $repo_name! Aborting."
                return 1
            fi
            echo "Successfully created repository: $NEXUS_URL/repository/$repo_name"
        done
        if ! nexus-upload-docker-images; then
            echo >&2 "Failed to upload docker images in ${CSM_PATH}/docker. Aborting"
            return 1
        else
            echo "Successfully uploaded docker images in ${CSM_PATH}/docker."
        fi
    else
        echo >&2 'Nothing to upload. CSM_PATH is unset, and nothing was given with -r. Aborting.'
        return 1
    fi

}

function setup-apache2-https-proxy() {
    if [ ! -f /etc/pit-release ]; then
        echo 'No apache2 proxy necessary, this is not a pit node.'
        return 0
    fi
    if [ -z "${PITDATA}" ]; then
        echo >&2 'PITDATA was blank, please set PITDATA to where the prep directory is'
        return 1
    elif [ ! -d "${PITDATA}/prep/site-init/" ]; then
        echo >&2 "site-init was not found at ${PITDATA}/prep/site-init ! Can't setup HTTPS proxy for https://packages.nmn"
        return 1
    fi
    "${PITDATA}/prep/site-init/utils/secrets-decrypt.sh" gen_platform_ca_1 \
        "${PITDATA}/prep/site-init/certs/sealed_secrets.key" \
        "${PITDATA}/prep/site-init/customizations.yaml" \
        | jq -r '.data."ca_bundle.crt" | @base64d' > /etc/apache2/ssl.crt/ca.crt
    "${PITDATA}/prep/site-init/utils/secrets-decrypt.sh" gen_platform_ca_1 \
        "${PITDATA}/prep/site-init/certs/sealed_secrets.key" \
        "${PITDATA}/prep/site-init/customizations.yaml" \
        | jq -r '.data."root_ca.key" | @base64d' > /etc/apache2/ssl.key/ca.key
    if [ ! -f /etc/apache2/vhosts.d/nexus-ssl.conf ]; then
        cp -p "$(dirname $0)/nexus-ssl.htaccess" /etc/apache2/vhosts.d/nexus-ssl.conf
        systemctl restart apache2
    fi
}

function nexus-delete-repo() {
    local name="${1:-}"
    echo >&2 "Deleting $name ..."
    curl \
    -L \
    -v \
    -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
    -X DELETE \
    "${NEXUS_URL}/service/rest/v1/repositories/${name}"
    echo 'Done.'
}

function nexus-create-repo() {
    local exists
    local method
    local repo_name="${1:-}"
    local repo_type="${2:-}"


    exists="$(curl \
    -L \
    -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
    "${NEXUS_URL}/service/rest/v1/repositories" \
    -s \
    --header "Content-type: application/json" \
    | jq -r '.[] | select(.name=="'"${repo_name}"'")')"
    if [ -z "$exists" ]; then
        echo -n "Creating repo '$repo_name' ... "
        method=POST
    else
        echo -n "Updating existing repo '$repo_name' ... "
        method=PUT
    fi

    "nexus-create-repo-${repo_type}" "${repo_name}" "${method}"

    exists="$(curl \
    -L \
    -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
    "${NEXUS_URL}/service/rest/v1/repositories" \
    -s \
    --header "Content-type: application/json" \
    | jq -r '.[] | select(.name=="'"${repo_name}"'")')"
    if [ -z "$exists" ]; then
        echo >&2 "Error! The repository ${repo_name} failed to create! Please double-check the running nexus instance's health."
        return 1
    fi
    echo 'Done'
}

nexus-create-repo-raw() {
    local repo_name="${1:-}"
    local method="${2:-POST}"
    local uri="service/rest/v1/repositories/raw/hosted/"

    if [ -z "$repo_name" ];then
        return 1
    fi

    if [ "$method" = PUT ]; then
        uri="$uri/$repo_name"
    fi

    curl \
    -L \
    -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
    "${NEXUS_URL}/$uri" \
    --header "Content-Type: application/json" \
    --request "$method" \
    --data-binary \
   @- << EOF
{
  "name": "$repo_name",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": false,
    "writePolicy": "ALLOW"
  },
  "cleanup": null,
  "component": {
    "proprietaryComponents": false
  },
  "raw": {
    "contentDisposition": "ATTACHMENT"
  }
}
EOF
}

nexus-create-repo-yum() {
    local repo_name="${1:-}"
    local method="${2-POST}"
    local uri="service/rest/v1/repositories/yum/hosted/"

    if [ -z "$repo_name" ];then
        return 1
    fi

    if [ "$method" = PUT ]; then
        uri="$uri/$repo_name"
    fi

    curl \
    -L \
    -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
    "${NEXUS_URL}/$uri" \
    --header "Content-Type: application/json" \
    --request "$method" \
    --data-binary \
   @- << EOF
{
  "name": "$repo_name",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW"
  },
  "cleanup": null,
  "component": {
    "proprietaryComponents": false
  },
  "yum": {
    "repodataDepth": 0,
    "deployPolicy": "STRICT"
  }
}
EOF
}

function nexus-create-repo-group-yum() {
    local exists
    local method
    local uri='service/rest/v1/repositories/yum/group'
    local repo_group_name="${1:-}"
    shift
    local repo_names="$*"
    exists="$(curl \
    -L \
    -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
    "${NEXUS_URL}/service/rest/v1/repositories" \
    -s \
    --header "Content-type: application/json" \
    | jq '.[] | select(.name=="'"${repo_group_name}"'")')"
    if [ -z "$exists" ]; then
        echo -n "Creating repo group '$repo_group_name' with: $repo_names ... "
        method=POST
    else
        echo -n "Updating existing repo group '$repo_group_name' with: $repo_names ... "
        uri="$uri/$repo_group_name"
        method=PUT
    fi
    curl \
    -L \
    -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
    "${NEXUS_URL}/$uri" \
    --header "Content-Type: application/json" \
    --request $method \
    --data-binary \
   @- << EOF
   {
     "name": "$repo_group_name",
     "online": true,
     "storage": {
       "blobStoreName": "default",
       "strictContentTypeValidation": true
     },
     "group": {
       "memberNames": [
         "$(echo $repo_names | sed 's/ /,/')"
       ]
     }
   }
EOF
    exists="$(curl \
    -L \
    -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
    "${NEXUS_URL}/service/rest/v1/repositories" \
    -s \
    --header "Content-type: application/json" \
    | jq '.[] | select(.name=="'"${repo_name}"'")')"
    if [ -z "$exists" ]; then
        echo >&2 "Error! The repository ${repo_group_name} failed to create! Please double-check the running nexus instance's health."
        return 1
    fi
    echo 'Done'
}

function nexus-upload-raw() {
    local dir="${1:-}"
    local repo_name="${2:-}"
    echo -n "Uploading $dir to $repo_name ... "
    mapfile -t files < <(find "$dir/" -type f)
    for i in "${files[@]}"; do
       curl \
       -L \
       -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
       --upload-file \
       "$i" \
       --max-time 600 \
       "${NEXUS_URL}/repository/$repo_name/";
    done
    echo 'Done'
}

function nexus-upload-yum() {
    local dir="${1:-}"
    local repo_name="${2:-}"
    echo -n "Uploading $dir to $repo_name ... "
    mapfile -t rpms < <(find "$dir/" -type f -name \*.rpm)
    for i in "${rpms[@]}"; do
       curl \
       -L \
       -u "${NEXUS_USERNAME}":"${NEXUS_PASSWORD}" \
       --upload-file \
       "$i" \
       --max-time 600 \
       "${NEXUS_URL}/repository/$repo_name/";
    done
    echo 'Done'
}

function nexus-upload-docker-images() {
    # source install.sh to use skopeo-sync function
    source "$CSM_PATH/lib/install.sh"

    # overwrite default NEXUS_REGISTRY value in install.sh
    export NEXUS_REGISTRY
    echo -n "Uploading CSM docker images to nexus ... "
    echo "This can take up to 20 minutes."
    {
    load-install-deps
    # Upload images
    skopeo-sync-with-retry "${CSM_PATH}/docker"
    to_return=$?
    clean-install-deps
    } >/var/log/setup-nexus-docker.log 2>&1
    echo 'Done - Logs available at /var/log/setup-nexus-docker.log'
    return $to_return
}

function skopeo-sync-with-retry() {
    local src="$1"

    [[ -d "$src" ]] || return 0
    declare -a podman_run_flags=(--network host)
    nexus-setdefault-credential
    # Note: Have to default NEXUS_USERNAME below since
    # nexus-setdefault-credential returns immediately if NEXUS_PASSWORD is set.
    # retries 10 times, takes approx. 15 minutes for all retries
    podman run --rm "${podman_run_flags[@]}" \
        -v "$(realpath "$src"):/image:ro" \
        "$SKOPEO_IMAGE" \
        sync --scoped --retry-times 10 --src dir --dest docker \
        --dest-creds "${NEXUS_USERNAME:-admin}:${NEXUS_PASSWORD}" \
        --dest-tls-verify=false \
        /image "$NEXUS_REGISTRY"
}

# If no overrides are set, fetch the credentials.
if [ -z "${NEXUS_USERNAME:-}" ] && [ -z "${NEXUS_PASSWORD:-}" ]; then
    if ! nexus-get-credential; then
        echo >&2 'Unable to resolve NEXUS_USERNAME and NEXUS_PASSWORD from Kubernetes secret, assuming default ..'
        NEXUS_USERNAME="$DEFAULT_NEXUS_USERNAME"
        NEXUS_PASSWORD="$DEFAULT_NEXUS_PASSWORD"
    fi
fi

if [ "$delete" -ne 0 ]; then
    nexus-delete-repo "${repo_name}"
    exit
elif [ "$server" -ne 0 ]; then
    echo "Uploading RPMs from $CSM_PATH/rpms ... "
    setup-apache2-https-proxy
    if ! setup-nexus-server; then
        echo >&2 'Failed to setup nexus server! Aborting.'
        exit 1
    fi
elif [ "$upload" -ne 0 ]; then
    echo "Uploading files from $repo_path to $repo_name ... "
    nexus-create-repo "${repo_name}" "${repo_type:-raw}"
    "nexus-upload-${repo_type}" "${repo_path}" "${repo_name}"
elif [ "$proxy_server" -ne 0 ]; then
    echo "Setting up $NEXUS_URL as a proxy ... "
    nexus-reset
    nexus-proxy
elif [ "$client" -ne 0 ]; then
    echo "Adding nexus proxy repos to Zypper ... "

    echo "Purging existing definitions ... "
    zypper-reset

    echo "Adding repos ... "
    setup-zypper-nexus
fi
