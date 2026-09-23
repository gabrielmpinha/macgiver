#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /path/to/MacGiver.app /path/to/MacGiver.dmg" >&2
  exit 2
fi

app_path="$1"
output_path="$2"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/macgiver-dmg.XXXXXX")"
trap 'rm -R "$staging_dir"' EXIT

ditto --norsrc "$app_path" "$staging_dir/MacGiver.app"
# Unsigned Xcode builds may only have a linker signature on the executable.
# Seal the complete staged bundle so its identifier and resources are bound.
# Keep an existing valid developer signature intact.
if ! codesign --verify --deep --strict "$staging_dir/MacGiver.app" 2>/dev/null; then
  xattr -cr "$staging_dir/MacGiver.app"
  codesign --force --sign - --identifier com.macgiver.app "$staging_dir/MacGiver.app"
fi
codesign --verify --deep --strict "$staging_dir/MacGiver.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "MacGiver" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$output_path"

echo "Created $output_path"
