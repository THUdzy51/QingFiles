#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${QINGFILES_BUILD_DIR:-$source_dir/.build}"
mkdir -p "$build_dir/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" "$source_dir/FileService.swift" "$source_dir/Tests/FileServiceTests.swift" -o "$build_dir/file-service-tests"
"$build_dir/file-service-tests"

swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" -framework Security "$source_dir/RemoteService.swift" "$source_dir/Tests/RemoteServiceTests.swift" -o "$build_dir/remote-service-tests"
"$build_dir/remote-service-tests"
