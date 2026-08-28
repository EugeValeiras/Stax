#!/usr/bin/env bash
# Copia el plugin StaxBridge dentro de un checkout de Vencord y lo recompila.
#
#   scripts/install-vencord-plugin.sh [ruta-a-Vencord]     (por defecto ~/workspace/Vencord)
#
# Se copia en vez de enlazar con symlink a propósito: esbuild resuelve los archivos por su ruta real,
# y desde afuera del árbol de Vencord no encuentra los alias @webpack, @utils, etc.
# Después de correrlo, reiniciá Discord para que tome el build nuevo.
set -euo pipefail
cd "$(dirname "$0")/.."

VENCORD="${1:-$HOME/workspace/Vencord}"
SOURCE="$PWD/VencordPlugin/staxBridge"

if [ ! -f "$VENCORD/package.json" ]; then
    echo "No encontré un checkout de Vencord en $VENCORD" >&2
    echo "Cloná uno con: git clone https://github.com/Vendicated/Vencord $VENCORD && cd $VENCORD && pnpm install" >&2
    exit 1
fi

DESTINATION="$VENCORD/src/userplugins/staxBridge"
mkdir -p "$DESTINATION"
cp "$SOURCE"/index.tsx "$SOURCE"/native.ts "$DESTINATION/"
echo "Plugin copiado a $DESTINATION"

cd "$VENCORD"
pnpm build
echo
echo "Listo. Reiniciá Discord para que cargue el build nuevo."
echo "Si es la primera vez, corré también:  cd $VENCORD && pnpm inject"
