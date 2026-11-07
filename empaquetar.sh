#!/bin/zsh
# Compila en release y monta build/Embery.app firmada (sin App Store ni notarizar).
set -e
cd "${0:A:h}"
swift build -c release
app=build/Embery.app
rm -rf $app
mkdir -p $app/Contents/MacOS
cp "$(swift build -c release --show-bin-path)/Embery" $app/Contents/MacOS/
cp Resources/Info.plist $app/Contents/
mkdir -p $app/Contents/Library/LaunchAgents
cp Resources/com.ivanzu.embery.guardia.plist $app/Contents/Library/LaunchAgents/
mkdir -p $app/Contents/Resources
install -m 755 Resources/embery-hook Resources/embery-status $app/Contents/Resources/
cp -RX Resources/*.lproj $app/Contents/Resources/
# El icono compilado viene en el repo; con actool (Xcode) se recompila si Icon/AppIcon.icon cambió.
car=Resources/Assets.car
if xcrun -f actool >/dev/null 2>&1 && [[ ! -f $car || -n "$(find Icon/AppIcon.icon -newer $car | head -1)" ]]; then
  tools/make_icon.sh || echo "aviso: no se pudo recompilar el icono; se usa el que viene en el repo"
fi
[[ -f $car ]] && cp -X $car Resources/AppIcon.icns $app/Contents/Resources/
# Sparkle llega ya firmado por sus autores; ditto conserva esa firma.
mkdir -p $app/Contents/Frameworks
ditto "$(swift build -c release --show-bin-path)/Sparkle.framework" $app/Contents/Frameworks/Sparkle.framework
# Con el certificado «Embery Code Signing» en el llavero la identidad no cambia entre versiones y macOS conserva
# los permisos tras actualizar; sin él (quien compila en su Mac) firma local.
firma=${EMBERY_FIRMA:-$(security find-identity -p codesigning | grep -q '"Embery Code Signing"' && echo "Embery Code Signing" || echo -)}
codesign --force --sign "$firma" $app
echo "$app"
