#!/bin/zsh
# Compila Embery en este Mac y la instala en /Applications. Al compilarse aquí, macOS no la bloquea.
# Uso, desde el repo:        ./install.sh
#      o sin clonar a mano:  curl -fsSL https://raw.githubusercontent.com/Ivanzu37/embery/main/install.sh | zsh
# EMBERY_DEST cambia la carpeta de destino.
set -euo pipefail
dest=${EMBERY_DEST:-/Applications}

[[ $(uname) == Darwin ]] || { echo "Embery is a Mac app."; exit 1; }
macos=$(sw_vers -productVersion)
(( ${macos%%.*} >= 27 )) || { echo "Embery needs macOS 27 or later (you have $macos)."; exit 1; }
xcrun --sdk macosx --show-sdk-version 2>/dev/null | grep -q '^2[7-9]\|^[3-9][0-9]' \
  || { echo "Embery needs Xcode 27 or later: install it from the App Store and open it once."; exit 1; }

src=${0:A:h}
if [[ ! -f $src/Package.swift || ! -f $src/empaquetar.sh ]]; then
  src=$(mktemp -d)/embery
  trap 'rm -rf "${src:h}"' EXIT
  echo "Downloading Embery…"
  git clone --depth 1 --quiet https://github.com/Ivanzu37/embery.git "$src"
fi

echo "Building (the first time takes a couple of minutes)…"
"$src/empaquetar.sh" >/dev/null

# Si está abierta, se cierra antes de sustituirla.
osascript -e 'tell application id "com.ivanzu.embery" to quit' >/dev/null 2>&1 || true
pkill -x Embery 2>/dev/null || true
sleep 1

mkdir -p "$dest"
rm -rf "$dest/Embery.app"
ditto "$src/build/Embery.app" "$dest/Embery.app"
echo "Installed in $dest/Embery.app"
open "$dest/Embery.app"
