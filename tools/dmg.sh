#!/bin/zsh
# Empaqueta la app y la mete en build/Embery-<versión>.dmg, con el acceso a Applications para arrastrarla.
# La app va con firma local, sin notarizar: macOS pide permiso la primera vez que se abre (ver README).
set -euo pipefail
repo=${0:A:h:h}
cd $repo
./empaquetar.sh >/dev/null
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
dmg=build/Embery-$version.dmg
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto build/Embery.app "$staging/Embery.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
diskutil image create from --format UDZO --volumeName Embery "$staging" "$dmg" >/dev/null
echo "$dmg"
shasum -a 256 "$dmg"
