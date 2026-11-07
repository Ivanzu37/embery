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

# Añade la versión a appcast.xml, firmada con la clave EdDSA del llavero (generate_keys). Sin la clave, no hay entrada.
# Las versiones anteriores se conservan: solo el DMG nuevo pasa por generate_appcast.
sparkle=$repo/.build/artifacts/sparkle/Sparkle/bin
cola=$(mktemp -d)
trap 'rm -rf "$staging" "$cola"' EXIT
cp "$dmg" "$cola/"
[[ -f appcast.xml ]] && cp appcast.xml "$cola/"
"$sparkle/generate_appcast" --download-url-prefix "https://github.com/Ivanzu37/embery/releases/download/v$version/" \
  --link https://github.com/Ivanzu37/embery "$cola"
cp "$cola/appcast.xml" appcast.xml
echo "appcast.xml listo: sube $dmg a la release v$version y después haz push de appcast.xml"
