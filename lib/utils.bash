#!/usr/bin/env bash

set -eu -o pipefail

list_all_versions() {
    search_path="${MISE_TOOL_OPTS__SEARCH_PATH:-/}"

    xcode_bundle_paths=()
    xcode_version_aliases=()

    for bundle_path in $(mdfind -onlyin "$search_path" "kMDItemCFBundleIdentifier='com.apple.dt.Xcode'"); do
        echo "$i"
    done
}

# sort_versions() {
# }
