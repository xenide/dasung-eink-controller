#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-0.0.0-dev}"
build_number="$(git -C "$root" rev-list --count HEAD)"
app="$root/build/Dasung Control.app"
archive="$root/build/DasungControl-$version.zip"
arch_flags=(--arch arm64 --arch x86_64)

swift build --package-path "$root" -c release "${arch_flags[@]}"
bin="$(swift build --package-path "$root" -c release "${arch_flags[@]}" --show-bin-path)"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/DasungControl" "$app/Contents/MacOS/DasungControl"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"
codesign --force --sign - "$app"

ditto -c -k --keepParent "$app" "$archive"
echo "$archive"
