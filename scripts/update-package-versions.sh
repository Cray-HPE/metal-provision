#!/usr/bin/env bash
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
set -eo pipefail

realpath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

function usage(){
    cat <<EOF
Usage:

    update-package-versions.sh

    Loops through the packages in the given packages-file path and compares the packages locked version to the latest found version the defined repos.
    One by one, if an update is found the script prompts if the version should be updated in the packages file.
    If you choose to update the version then the given packages-file is updated directly.
    You can then git commit to the appropriate branch and create a PR.

    -a|--architecture          Required: Set the target architecture (eg x86_64 or aarch64)
    -p|--packages-file <path>  Required: The packages file path to update versions in (eg packages/node-images-base/base.packages)

    [-f|--filter <pattern>]    Package regex pattern to filter against. Only packages matching the filter will be queried and prompted to update. (eg cray-)
    [-r|--repos <pattern>]     Repo regex pattern to filter against. Latest version will only be looked up in repos names matching the filter. (eg SUSE)
    [-c|--compute]             Whether to also include compute specific repositories (these are included with a higher priority then their NCN counterparts).
    [-o|--output-diffs-only]   The package information, including the latest found version, will be outputted instead of prompting to update the package file directly
    [-y|--yes]                 No prompts, instead auto updates the package file with any new version that matches other option filters
    [--validate]               Validate that packages exist instead looking for newer versions
    [--no-cache]               Destroy the docker image used as a cache so we do not have to re-add repos on every usage
    [--suffix <string>]        Suffix to add to the end of the docker image and container so this can be run in parallel in CI
    [--refresh]                Do a zypper refresh before querying for latest versions
    [--help]                   Prints this usage and exists

    Examples

    ./scripts/update-package-versions.sh -a x86_64 -p packages/node-images-base/base.packages
    ./scripts/update-package-versions.sh -a aarch64 -p packages/node-images-base/base.packages

    --------------
    Query all packages in base.packages and prompt the user to update the version if a newer version is found in the repos one by one.


    ./scripts/update-package-versions.sh -a x86_64 -p packages/node-images-base/base.packages -f '^cray' -o
    --------------
    Query packages in base.packages that start with 'cray'. Only print out packages that have a different version found


    ./scripts/update-package-versions.sh -a x86_64 -p packages/node-images-base/base.packages -f cray-network-config -r shasta-1.4
    --------------
    Only update the package cray-network-config in a repo that contains the shasta-1.4 name


    ./scripts/update-package-versions.sh -a aarch64 -p packages/node-images-base/base.packages -r buildonly-SUSE
    --------------
    Only update packages found in the upstream SUSE repos for aarch64

    ./scripts/update-package-versions.sh -a x86_64 -p packages/node-images-base/base.packages -r buildonly-SUSE -y
    --------------
    Same as the last example, but automatically update all SUSE packages rather than prompt one by one

EOF
}

SOURCE_DIR="$(dirname $0)/.."
SOURCE_DIR="$(pushd "$SOURCE_DIR" > /dev/null && pwd && popd > /dev/null)"

OUTPUT_DIFFS_ONLY="false"
REPOS_FILTER="all"
AUTO_YES="false"

DOCKER_CACHE_IMAGE="csm-rpms-cache"
DOCKER_BASE_IMAGE="artifactory.algol60.net/csm-docker/stable/csm-docker-sle:15.5"

while [[ "$#" -gt 0 ]]
do
  case $1 in
    -h|--help)
      usage
      exit
      ;;
    -a|--architecture)
      export ARCH="$2"
      [[ ${ARCH} == "x86_64" ]] && DOCKER_ARCH="linux/amd64"
      [[ ${ARCH} == "aarch64" ]] && DOCKER_ARCH="linux/arm64"
      DOCKER_CACHE_IMAGE="${DOCKER_CACHE_IMAGE}-${ARCH}"
      ;;
    -p|--packages-file)
      PACKAGES_FILE="$2"
      ;;
    -f|--filter)
      FILTER="$2"
      ;;
    -r|--repos)
      REPOS_FILTER="$2"
      ;;
    -c|--compute)
      DOCKER_CACHE_IMAGE="${DOCKER_CACHE_IMAGE}-compute"
      SETUP_PACKAGE_REPOS_FLAGS="--compute"
      ;;
    -o|--output-diffs-only)
      OUTPUT_DIFFS_ONLY="true"
      ;;
    -y|--yes)
      AUTO_YES="true"
      ;;
    --validate)
      VALIDATE="true"
      ;;
    --no-cache)
      NO_CACHE="true"
      ;;
    --suffix)
      DOCKER_CACHE_IMAGE="${DOCKER_CACHE_IMAGE}-$2"
      ;;
    --refresh)
      REFRESH="true"
      ;;

  esac
  shift
done

if [[ -z "$ARCH" ]]; then
    echo >&2 "error: missing -a architecture option, assuming x86_64"
    ARCH='x86_64'
    DOCKER_ARCH='linux/amd64'
    DOCKER_CACHE_IMAGE="${DOCKER_CACHE_IMAGE}-${ARCH}"
fi

if [[ "$NO_CACHE" == "true" && "$(docker images -q $DOCKER_CACHE_IMAGE 2> /dev/null)" != "" ]]; then
  echo "Removing docker image cache $DOCKER_CACHE_IMAGE"
  docker rmi $DOCKER_CACHE_IMAGE || docker rmi --force $DOCKER_CACHE_IMAGE
fi

if [[ "$(docker images -q $DOCKER_CACHE_IMAGE 2> /dev/null)" == "" ]]; then
  echo "Creating docker cache image"
  docker rm $DOCKER_CACHE_IMAGE 2> /dev/null || true

  docker run --platform $DOCKER_ARCH -e ARCH=$ARCH --name $DOCKER_CACHE_IMAGE -v "$(realpath "$SOURCE_DIR"):/app" -e ARTIFACTORY_USER=$ARTIFACTORY_USER -e ARTIFACTORY_TOKEN=$ARTIFACTORY_TOKEN $DOCKER_BASE_IMAGE bash -c "
    set -e
    source /app/scripts/rpm-functions.sh
    setup-csm-rpms
    cleanup-all-repos
    setup-package-repos $SETUP_PACKAGE_REPOS_FLAGS
    zypper refresh
    # Install yq now that it's available
    zypper --non-interactive install --no-recommends yq
    # Force a cache update
    zypper --no-refresh info man > /dev/null 2>&1
    cleanup-csm-rpms
  "

  echo "Creating cache docker image $DOCKER_CACHE_IMAGE"
  docker commit $DOCKER_CACHE_IMAGE $DOCKER_CACHE_IMAGE
  docker rm $DOCKER_CACHE_IMAGE
fi

if [[ "$REFRESH" == "true" ]]; then
  docker rm $DOCKER_CACHE_IMAGE 2> /dev/null || true
  docker run --platform $DOCKER_ARCH -e ARCH=$ARCH --name $DOCKER_CACHE_IMAGE -v "$(realpath "$SOURCE_DIR"):/app" --init $DOCKER_CACHE_IMAGE bash -c "
    set -e
    source /app/scripts/rpm-functions.sh
    zypper refresh
    # Force a cache update
    zypper --no-refresh info man > /dev/null 2>&1
  "
  echo "Updating cache docker image $DOCKER_CACHE_IMAGE"
  docker commit $DOCKER_CACHE_IMAGE $DOCKER_CACHE_IMAGE
  docker rm $DOCKER_CACHE_IMAGE

  if [[ -z "$PACKAGES_FILE" ]]; then
    exit 0
  fi
fi

if [[ -z "$PACKAGES_FILE" || ! -f "$PACKAGES_FILE" ]]; then
    echo >&2 "error: missing -p packages-file option"
    echo >&2 "or $PACKAGES_FILE is not a file"
    usage
    exit 3
fi

echo "Working with packages file $PACKAGES_FILE"

# Only use tty when we'll prompt. This will allow jenkins or other automation to work
#shellcheck disable=SC2050
if [[ "$VALIDATE" == "true" || "$AUTO_YES" == "true" || OUTPUT_DIFFS_ONLY == "true" ]]; then
  DOCKER_TTY_ARG=""
else
  DOCKER_TTY_ARG="-it"
fi

docker run --platform $DOCKER_ARCH -e ARCH=$ARCH $DOCKER_TTY_ARG --rm -v "$(realpath "$SOURCE_DIR"):/app" -v "$(realpath "$PACKAGES_FILE"):/packages" --init $DOCKER_CACHE_IMAGE bash -c "
  set -e
  source /app/scripts/rpm-functions.sh
  if [[ \"$VALIDATE\" == \"true\" ]]; then
    validate-package-versions /packages
  else
    cp /packages /tmp/packages
    update-package-versions /tmp/packages ${REPOS_FILTER} ${OUTPUT_DIFFS_ONLY} ${AUTO_YES} ${FILTER}
    cp /tmp/packages /packages
  fi
"
