#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
cd "$project_dir"

swift build -c release --product MissionControlCapacity
binary_dir=$(swift build -c release --show-bin-path)
app_dir="$project_dir/.build/Mission Control Capacity.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MissionControlCapacity" "$app_dir/Contents/MacOS/MissionControlCapacity"
cp "$project_dir/Support/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir" >/dev/null

print "$app_dir"
