#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${QINGFILES_BUILD_DIR:-$source_dir/.build}"
app_dir="${1:-$source_dir/dist/QingFiles.app}"
mkdir -p "$build_dir/ModuleCache"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" -framework AppKit -framework CoreServices -framework UniformTypeIdentifiers "$source_dir/Tests/DocumentRegistrationTests.swift" -o "$build_dir/document-registration-tests"
"$build_dir/document-registration-tests" "$app_dir"
