#!/usr/bin/env bash
# Compila en release y arma build/Stax.app firmada ad hoc.
# Si tenés un certificado "Apple Development", pasalo en SIGN_IDENTITY para que el permiso
# de Accesibilidad sobreviva a los rebuilds: SIGN_IDENTITY="Apple Development: ..." scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Stax.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Stax "$APP/Contents/MacOS/Stax"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Los mismos GIFs del README: el asistente los muestra para explicar cada atajo.
cp docs/demo-cycle.gif docs/demo-share.gif docs/demo-columns-2.gif docs/demo-columns-3.gif docs/demo-columns-4.gif "$APP/Contents/Resources/"

codesign --force --sign "${SIGN_IDENTITY:--}" --identifier com.eugeniovaleiras.Stax "$APP"
echo "Listo: $APP"
echo "Instalar: cp -R $APP /Applications/"
