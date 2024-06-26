#!/usr/bin/env bash
#
# MIT License
#
# (C) Copyright [2021-2023] Hewlett Packard Enterprise Development LP
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
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}")/.." &> /dev/null && pwd )"
function list-compute-repos-files() {
    /usr/bin/envsubst '$ARTIFACTORY_USER $ARTIFACTORY_TOKEN' < ${BASE_DIR}/scripts/repos/compute.template.repos > ${BASE_DIR}/scripts/repos/compute.repos
    cat <<-EOF
${BASE_DIR}/scripts/repos/compute.repos
EOF
}

function list-cray-repos-files() {
    /usr/bin/envsubst '$ARTIFACTORY_USER $ARTIFACTORY_TOKEN' < ${BASE_DIR}/scripts/repos/cray.template.repos > ${BASE_DIR}/scripts/repos/cray.repos
    cat <<-EOF
${BASE_DIR}/scripts/repos/cray.repos
EOF
}

function list-google-repos-files() {
    /usr/bin/envsubst '$ARTIFACTORY_USER $ARTIFACTORY_TOKEN' < ${BASE_DIR}/scripts/repos/google.template.repos > ${BASE_DIR}/scripts/repos/google.repos
    cat <<-EOF
${BASE_DIR}/scripts/repos/google.repos
EOF
}

function list-hpe-repos-files() {

    # NOTE: HPE SDR Repositories capitalize their AARCH64 repo names.
#    local hpe_arch
#    if [ "$ARCH" = 'aarch64' ]; then
#        hpe_arch="${ARCH^^}"
#    else
#        hpe_arch="$ARCH"
#    fi
#    export hpe_arch
#    /usr/bin/envsubst '$ARTIFACTORY_USER $ARTIFACTORY_TOKEN $hpe_arch' < ${BASE_DIR}/scripts/repos/hpe.template.repos > ${BASE_DIR}/scripts/repos/hpe.repos
    /usr/bin/envsubst '$ARTIFACTORY_USER $ARTIFACTORY_TOKEN' < ${BASE_DIR}/scripts/repos/hpe.template.repos > ${BASE_DIR}/scripts/repos/hpe.repos
    cat <<-EOF
${BASE_DIR}/scripts/repos/hpe.repos
EOF
#    unset hpe_arch
}

function list-suse-repos-files() {
    /usr/bin/envsubst '$ARTIFACTORY_USER $ARTIFACTORY_TOKEN' < ${BASE_DIR}/scripts/repos/suse.template.repos > ${BASE_DIR}/scripts/repos/suse.repos
	cat <<-EOF
${BASE_DIR}/scripts/repos/suse.repos
EOF
}

function create-fake-conntrack {
    zypper --non-interactive install rpm-build createrepo_c
    echo "Building a custom local repository for conntrack dependency, pulls in conntrack-tools while mocking conntrack."
    rm -rf "${BASE_DIR}/scripts/repos/conntrack" || true
    mkdir -p /tmp/conntrack
    cp -v "${BASE_DIR}/scripts/repos/conntrack.spec" /tmp/conntrack
    rpmbuild -ba --define "_rpmdir /tmp/conntrack" /tmp/conntrack/conntrack.spec
    mkdir -p "${BASE_DIR}/scripts/repos/conntrack/noarch"
    rm /tmp/conntrack/conntrack.spec
    mv /tmp/conntrack/* /var/local-repos/conntrack/
    createrepo /var/local-repos/conntrack
    zypper -n addrepo --no-refresh --no-gpgcheck "${BASE_DIR}/scripts/repos/conntrack" buildonly-local-conntrack
    zypper --non-interactive remove --clean-deps rpm-build createrepo_c
}

function remove-comments-and-empty-lines() {
    # Removes:
    # - comments
    # - white-space
    # - YAML list identifiers
    # - YAML header lines '---'
    # - YAML keys
    # - PACKAGES arrays (and their trailing paren).
    sed \
        -e 's/#.*$//' \
        -e '/^[[:space:]]*$/d' \
        -e 's/^[[:space:]]*- //' \
        -e '/^[[:alpha:][:punct:]]*$/d' \
        -e 's/"*//g' \
        -e "s/'*//g" \
        -e '/{{.*}}/d' \
        -e '/^PACKAGES=(/d' \
        -e '/^packages:/d' \
        -e '/^packages_aarch64:/d' \
        -e '/^packages_x86_64:/d' \
        -e '/^)$/d' \
        "$@"
}

function setup-csm-rpms {
    zypper --non-interactive install --no-recommends ca-certificates-mozilla ca-certificates gettext-tools gawk jq
}

function cleanup-csm-rpms {
    # Do not invoke this within a packer build, otherwise if any of the following packages were intentionally installed they will end up getting removed.
    # Do not use --clean-deps here, doing so may remove extra packages that already existed prior to setup-csm-rpms.
    # Do not remove ca-certificates-mozilla ca-certificates or SSL errors will occur in the metal-provision pipeline.
    zypper --non-interactive remove gettext-tools gawk jq || echo 'Ignoring errors'
    rm -f \
    "${BASE_DIR}/scripts/repos/compute.repos" \
    "${BASE_DIR}/scripts/repos/cray.repos" \
    "${BASE_DIR}/scripts/repos/google.repos" \
    "${BASE_DIR}/scripts/repos/hpe.repos" \
    "${BASE_DIR}/scripts/repos/suse.repos"
}

function zypper-add-repos() {
    remove-comments-and-empty-lines \
        | while read -r url name flags; do
            local alias="buildonly-${name}"
            echo "Adding repo ${alias} at ${url}"
            zypper -n addrepo $flags "${url}" "${alias}"
            zypper -n --gpg-auto-import-keys refresh "${alias}"
        done
}

function add-compute-repos() {
    list-compute-repos-files | xargs -r cat | zypper-add-repos
}

function add-cray-repos() {
    list-cray-repos-files | xargs -r cat | zypper-add-repos
}

function add-google-repos() {
    list-google-repos-files | xargs -r cat | zypper-add-repos
}

function add-hpe-repos() {
    list-hpe-repos-files | xargs -r cat | zypper-add-repos
}

function add-suse-repos() {
    list-suse-repos-files | xargs -r cat | zypper-add-repos
}

function setup-package-repos-with-compute() {
    setup-package-repos -c
}

function setup-package-repos() {
    for arg in "$@"; do
        case "$arg" in
            -c | --compute)
                add-compute-repos
                ;;
            *)
                # No args.
                :
                ;;
        esac
    done
    add-cray-repos
    add-google-repos
    add-hpe-repos
    add-suse-repos

    # fake-conntrack necessary for kubernetes on SUSE distros; must run after all repos are setup.
    if [ ! -d ${BASE_DIR}/scripts/repos/conntrack ]; then
        create-fake-conntrack
    else
        zypper -n addrepo --refresh --no-gpgcheck "${BASE_DIR}/scripts/repos/conntrack" buildonly-local-conntrack
    fi
    zypper lr -e /tmp/repos.repos
    cat /tmp/repos.repos
}

function install-packages() {
    # rpm scripts often exit with errors, which should not break any scripts calling us
    remove-comments-and-empty-lines "$1" | xargs -t -r zypper -n install --oldpackage --auto-agree-with-licenses --no-recommends
}

function update-package-versions() {
    local packages_path="$1"
    local repos_filter="$2"
    local output_diffs_only="$3"
    local auto_yes="$4"
    local filter="$5"

    if [[ -n "$filter" ]]; then
        echo "Filtering packages with regex $filter"
    fi

    local package_names=""

    # Filter out just the package names we want
    while read -r package; do
        #shellcheck disable=SC2206
        local parts=(${package//[=<>]/ })
        local package="${parts[0]/[<>]/}"
        #shellcheck disable=SC2034
        local version="${parts[1]/[<>]/}"

        if [[ -n "$filter" && ! $package =~ $filter ]]; then
            continue
        fi

        package_names="${package_names} $package"
    done < <(
        if [[ "$packages_path" =~ .*ya?ml ]]; then
            if [[ "$packages_path" =~ .*x86_64.* ]]; then
                yq '.packages_x86_64' "$packages_path" | remove-comments-and-empty-lines
            elif [[ "$packages_path" =~ .*aarch64.* ]]; then
                yq '.packages_aarch64' "$packages_path" | remove-comments-and-empty-lines
            else
                yq '.packages' "$packages_path" | remove-comments-and-empty-lines
            fi
        else
            remove-comments-and-empty-lines "$packages_path"
        fi
    )

    echo "Looking up latest versions"

    if [[ "$repos_filter" != "all" ]]; then
        #shellcheck disable=SC2155
        local repos=$(zypper lr | grep "${repos_filter}" | awk '{printf " -r %s", $1}')
        echo "Filtering repos matching grep pattern ${repos_filter}"
        if [[ -z "$repos" ]]; then
            echo "Error: No repos matched filter"
            exit 1
        fi
    else
        local repos=""
    fi

    #shellcheck disable=SC2155
    local package_info=$(zypper --no-refresh info $repos $package_names)

    for package in $package_names; do
        #shellcheck disable=SC2155
        local current_version
        if [[ $packages_path =~ .*ya?ml ]]; then
            if [[ "$packages_path" =~ .*x86_64.* ]]; then
                current_version=$(yq '.packages_x86_64' "$packages_path" | remove-comments-and-empty-lines | grep -oP "^${package//+/\\+}[=<>]\K.*$")
            elif [[ "$packages_path" =~ .*aarch64.* ]]; then
                current_version=$(yq '.packages_aarch64' "$packages_path" | remove-comments-and-empty-lines | grep -oP "^${package//+/\\+}[=<>]\K.*$")
            else
                current_version=$(yq '.packages' "$packages_path" | remove-comments-and-empty-lines | grep -oP "^${package//+/\\+}[=<>]\K.*$")
            fi
        else
            current_version=$(remove-comments-and-empty-lines "$packages_path" | grep -oP "^${package//+/\\+}[=<>]\K.*$")
        fi
        #shellcheck disable=SC2155
        local latest_version=$(echo "${package_info}" | grep -oPz "Name + : ${package}\nVersion + : \K.*" | tr '\0' '\n')
        #shellcheck disable=SC2155
        local repo=$(echo "${package_info}" | grep -oPz "Repository + : .*\nName + : ${package}\n" | grep -oPz "Repository + : \K.*" | tr '\0' '\n')

        if [[ "$current_version" != "$latest_version" || $output_diffs_only != "true" ]]; then
            echo
            echo "Package:         $package"
            if [[ "$latest_version" == "" ]]; then
                echo "                 Couldn't find '$package' in current repo list. Skipping"
                continue
            fi
            echo "Repository:      $repo"
            echo "Current version: $current_version"
            echo "Latest version:  $latest_version"
        fi

        if [[ "$current_version" != "$latest_version" && $output_diffs_only != "true" ]]; then
            if grep -q "$package=$current_version" "$packages_path"; then
                if [[ "$auto_yes" != "true" ]]; then
                    read -rp "Update package lock version (y/N)?" answer
                fi
                if [[ "$auto_yes" == "true" || "$answer" == "y" ]]; then
                    update-package-version $packages_path $package $current_version $latest_version
                    echo "Packages file updated"
                fi
            else
                echo >&2 "WARNING: ${package} isn't pinned to a specific version with '=', skipping update"
            fi
        elif [[ $output_diffs_only != "true" ]]; then
            echo "Version already up to date"
        fi

    done
}

function update-package-version() {
    local packages_path="$1"
    local package="$2"
    local current_version="$3"
    local new_version="$4"
    sed -e "s/$package=$current_version/$package=$new_version/" -i "$packages_path"
}

function validate-package-versions() {
    local packages_path="$1"
    echo "Running zypper install --dry-run to validate packages"

    if [[ $packages_path =~ .*ya?ml ]]; then
            if [[ "$packages_path" =~ .*x86_64.* ]]; then
                yq '.packages_x86_64' "$packages_path" | remove-comments-and-empty-lines | xargs -t -r zypper --no-refresh --non-interactive install --dry-run --auto-agree-with-licenses --no-recommends --force-resolution
            elif [[ "$packages_path" =~ .*aarch64.* ]]; then
                yq '.packages_aarch64' "$packages_path" | remove-comments-and-empty-lines | xargs -t -r zypper --no-refresh --non-interactive install --dry-run --auto-agree-with-licenses --no-recommends --force-resolution
            else
                yq '.packages' "$packages_path" | remove-comments-and-empty-lines | xargs -t -r zypper --no-refresh --non-interactive install --dry-run --auto-agree-with-licenses --no-recommends --force-resolution
            fi
    else
        #shellcheck disable=SC2046
        remove-comments-and-empty-lines "$packages_path" | xargs -t -r zypper --no-refresh --non-interactive install --dry-run --auto-agree-with-licenses --no-recommends --force-resolution
    fi
}

function get-current-package-list() {
    #shellcheck disable=SC2155
    local inventory_file=$(mktemp)
    local output_file="$1"
    local packages="$2"
    local base_inventory="${3:-""}"

    if [[ -n "$base_inventory" ]]; then
        local base_arg="-b $base_inventory"
    else
        local base_arg=""
    fi
    #shellcheck disable=SC2046
    python3 "${BASE_DIR}/scripts/get-packages.py" -p /tmp -f $(basename $inventory_file) $base_arg
    if [[ "$packages" == "explicit" ]]; then
        python3 "${BASE_DIR}/scripts/get-package-list-from-inventory.py" -p "$inventory_file" -o "$output_file" -e
    elif [[ "$packages" == "deps" ]]; then
        python3 "${BASE_DIR}/scripts/get-package-list-from-inventory.py" -p "$inventory_file" -o "$output_file" -d
    else
        python3 "${BASE_DIR}/scripts/get-package-list-from-inventory.py" -p "$inventory_file" -o "$output_file"
    fi
}

function cleanup-package-repos() {
    echo "Cleaning up buildonly-* package repos"
    for repo in $(zypper lr | grep -E '^[[:space:]]*[0-9]' | awk -F'|' '{gsub(/ /,""); print $3}'); do
        echo "Removing package repo ${repo}"
        zypper -n removerepo ${repo} || true
    done
    echo "Running a zypper clean"
    zypper -n clean --all
    echo "Unmounting and removing any mounted artifacts, if present"
    umount /mnt/shasta-cd-repo &> /dev/null || true
    rm -rf /mnt/shasta-cd-repo &> /dev/null || true
}

function cleanup-all-repos() {
    echo "Cleaning up all repos"
    # Remove all repos since everything is configured at this point
    zypper -n removerepo -a
    echo "Running a zypper clean"
    zypper -n clean --all
    echo "Disabling remote zypper service repos"
    zypper ms --remote --disable
}
