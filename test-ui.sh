#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${QINGFILES_BUILD_DIR:-$source_dir/.build}"
mkdir -p "$build_dir/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" -framework AppKit "$source_dir/Theme.swift" "$source_dir/FileService.swift" "$source_dir/FilePane.swift" "$source_dir/Tests/PaneHeaderTests.swift" -o "$build_dir/pane-header-tests"
"$build_dir/pane-header-tests"
