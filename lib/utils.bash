#!/usr/bin/env bash

set -eu -o pipefail

GH_REPO="https://github.com/qasim/Xcode"

fail() {
	echo -e "mise-xcode: $*"
	exit 1
}

list_github_tags() {
    git ls-remote --tags --refs --sort="v:refname" "$GH_REPO" | grep -o 'refs/tags/.*' | cut -d/ -f3-
}

list_github_versions() {
    list_github_tags | cut -f1 -d"+"
}

sort_versions() {
    sed -e '/[a-zA-Z]/! s/$/|/' | sort -V | sed -e 's/|$//'
}

list_all_versions() {
    list_github_versions | sort_versions | xargs echo
}

print_latest_stable_version() {
    list_github_versions | sort_versions | tail -r | grep -m 1 -v "-"
}

list_legacy_filenames() {
    echo ".xcode-version .xcversion"
}

parse_legacy_file() {
    file_path="$0"
}

xcode_developer_dir() {
    search_path="${MISE_TOOL_OPTS__SEARCH_PATH:-/}"

    install_tag=$(list_github_tags | grep "$ASDF_INSTALL_VERSION+" -s || true)
    if [ -z "$install_tag" ]; then
        fail "No Xcode version exists that corresponds to $ASDF_INSTALL_VERSION."
    fi

    install_build=$(echo "$install_tag" | cut -d"+" -f2)

    install_developer_dir=""
    for bundle_path in $(mdfind -onlyin "$search_path" "kMDItemCFBundleIdentifier='com.apple.dt.Xcode'"); do
        version_plist_path="$bundle_path/Contents/version.plist"
        build=$(/usr/libexec/PlistBuddy -c "print 'ProductBuildVersion'" "$version_plist_path")
        if [ "$install_build" == "$build" ]; then
            install_developer_dir="$bundle_path/Contents/Developer"
        fi
    done

    if [ -z "$install_developer_dir" ]; then
        fail "Xcode version $ASDF_INSTALL_VERSION not found on disk."
    fi

    echo "$install_developer_dir"
}

download() {
    if [ "$ASDF_INSTALL_TYPE" != "version" ]; then
        fail "Git ref install types are not supported."
    fi

    xcode_developer_dir 1> /dev/null
}

install() {
    xcode_developer_dir 1> /dev/null
}

prepare_environment() {
    DEVELOPER_DIR=$(xcode_developer_dir)
    export DEVELOPER_DIR
}
