#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${QINGFILES_BUILD_DIR:-$source_dir/.build}"
mkdir -p "$build_dir/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" -framework AppKit "$source_dir/Theme.swift" "$source_dir/FileService.swift" "$source_dir/FilePane.swift" "$source_dir/Tests/PaneHeaderTests.swift" -o "$build_dir/pane-header-tests"
"$build_dir/pane-header-tests"

swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" -framework AppKit "$source_dir/Theme.swift" "$source_dir/FileService.swift" "$source_dir/FilePane.swift" "$source_dir/Tests/PanePathTests.swift" -o "$build_dir/pane-path-tests"
"$build_dir/pane-path-tests"

swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" -framework AppKit "$source_dir/Theme.swift" "$source_dir/FileService.swift" "$source_dir/FilePane.swift" "$source_dir/Tests/PaneRevealTests.swift" -o "$build_dir/pane-reveal-tests"
"$build_dir/pane-reveal-tests"

swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" -framework AppKit "$source_dir/FileService.swift" "$source_dir/FileRevealService.swift" "$source_dir/Tests/FileRevealServiceTests.swift" -o "$build_dir/file-reveal-service-tests"
"$build_dir/file-reveal-service-tests"

swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" -framework AppKit "$source_dir/Theme.swift" "$source_dir/FileService.swift" "$source_dir/FilePane.swift" "$source_dir/Tests/PaneRenameTests.swift" -o "$build_dir/pane-rename-tests"
"$build_dir/pane-rename-tests"
