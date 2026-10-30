#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="${QINGFILES_OUTPUT_DIR:-$source_dir/dist}"
architecture="${QINGFILES_ARCH:-$(uname -m)}"
case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;; esac
version="${QINGFILES_VERSION:-1.2.0}"
app_dir="$output_dir/QingFiles.app"
build_dir="${QINGFILES_BUILD_DIR:-$source_dir/.build}"
mkdir -p "$build_dir/ModuleCache" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
swiftc -swift-version 5 -parse-as-library -O -target "${architecture}-apple-macosx13.0" -module-cache-path "$build_dir/ModuleCache" -framework AppKit -framework Quartz -framework Security "$source_dir/RemoteService.swift" "$source_dir/RemoteWorkspace.swift" "$source_dir/Theme.swift" "$source_dir/FileService.swift" "$source_dir/FilePane.swift" "$source_dir/App.swift" -o "$app_dir/Contents/MacOS/QingFiles"
swiftc -swift-version 5 -module-cache-path "$build_dir/ModuleCache" -framework AppKit "$source_dir/Tools/MakeIcon.swift" -o "$build_dir/make-icon"
"$build_dir/make-icon" "$build_dir/icon-1024.png"
mkdir -p "$build_dir/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$build_dir/icon-1024.png" --out "$build_dir/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$build_dir/icon-1024.png" --out "$build_dir/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
swiftc -swift-version 5 -module-cache-path "$build_dir/ModuleCache" "$source_dir/Tools/PackIcon.swift" -o "$build_dir/pack-icon"
"$build_dir/pack-icon" "$build_dir/AppIcon.iconset" "$app_dir/Contents/Resources/AppIcon.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>QingFiles</string>
<key>CFBundleDisplayName</key><string>QingFiles</string>
<key>CFBundleIdentifier</key><string>local.qingfiles.app</string>
<key>CFBundleExecutable</key><string>QingFiles</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>QingFiles contributors · MIT License</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_dir/Contents/Info.plist"
swiftc -swift-version 5 -O -target "${architecture}-apple-macosx13.0" -module-cache-path "$build_dir/ModuleCache" "$source_dir/Tools/Askpass.swift" -o "$app_dir/Contents/MacOS/QingFilesAskpass"
codesign --force --sign - "$app_dir/Contents/MacOS/QingFilesAskpass"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'Built: %s\n' "$app_dir"
