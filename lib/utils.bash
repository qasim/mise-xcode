#!/usr/bin/env bash

set -eu -o pipefail

list_all_versions() {
    search_path="${MISE_TOOL_OPTS__SEARCH_PATH:-/}"

    xcode_bundle_paths=()
    xcode_version_aliases=()

    for bundle_path in $(mdfind -onlyin "$search_path" "kMDItemCFBundleIdentifier='com.apple.dt.Xcode'"); do
        echo "$bundle_path"
    done
}

print_latest_stable_version() {
}

list_legacy_filenames() {
    echo ".xcode-version .xcversion"
}

parse_legacy_file() {
    file_path="$0"
}

install() {
}

prepare_environment() {

}
