#!/usr/bin/env bash

set -eu -o pipefail

GH_REPO="https://github.com/qasim/Xcode"

list_github_tags() {
    git ls-remote --tags --refs --sort="v:refname" "$GH_REPO" | grep -o 'refs/tags/.*' | cut -d/ -f3-
}

sort_versions() {
    sed -e '/[a-zA-Z]/! s/$/|/' | sort -V | sed -e 's/|$//'
}

list_all_versions() {
    list_github_tags | sort_versions | xargs echo
}

print_latest_stable_version() {
    list_github_tags | sort_versions | tail -r | grep -m 1 -v "-"
}

list_legacy_filenames() {
    echo ".xcode-version .xcversion"
}

parse_legacy_file() {
    file_path="$0"
}

install() {
    # search_path="${MISE_TOOL_OPTS__SEARCH_PATH:-/}"

    # xcode_bundle_paths=()
    # xcode_version_aliases=()

    # for bundle_path in $(mdfind -onlyin "$search_path" "kMDItemCFBundleIdentifier='com.apple.dt.Xcode'"); do
    #     echo "$bundle_path"
    # done
    echo "ok"
}

prepare_environment() {
    echo "ok"
}
