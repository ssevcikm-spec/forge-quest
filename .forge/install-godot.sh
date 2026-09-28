#!/usr/bin/env bash
# Nainstaluje Godot 4.7.2 + exportní šablony na běžící runner (Linux) a předá
# cesty dalším krokům přes GITHUB_ENV.
#
# Proč ručně a ne přes nějakou action: oficiální binárka je portable a šablony
# se jen rozbalí do datového adresáře Godotu. S actions/cache (path ~/.cache/forge)
# se to stahuje jen jednou za změnu verze.
set -euo pipefail

VERSION_TAG="4.7.2-stable"     # jak se jmenuje release na GitHubu
VERSION_DIR="4.7.2.stable"     # jak se jmenuje složka šablon (s tečkou!)
CACHE="${FORGE_CACHE:-$HOME/.cache/forge}"

# Architektura: stejný skript musí fungovat na runneru (x86_64), v Codespace
# i na domácím ARM uzlu (Oracle Ampere, telefon). Dřív byl x86_64 zadrátovaný,
# takže na ARM uzlu by se stahovala binárka, která se vůbec nespustí.
case "$(uname -m)" in
  x86_64)        GODOT_ARCH="x86_64" ;;
  aarch64|arm64) GODOT_ARCH="arm64" ;;
  *) echo "CHYBA: neznámá architektura $(uname -m)"; exit 1 ;;
esac

GODOT="$CACHE/godot/Godot_v${VERSION_TAG}_linux.${GODOT_ARCH}"
TPL="$CACHE/data/godot/export_templates/${VERSION_DIR}"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION_TAG}"

mkdir -p "$CACHE/godot" "$TPL"

if [ ! -x "$GODOT" ]; then
  echo "Stahuji Godot ${VERSION_TAG} pro ${GODOT_ARCH}…"
  curl -fsSL -o "$CACHE/godot.zip" "${BASE}/Godot_v${VERSION_TAG}_linux.${GODOT_ARCH}.zip"
  unzip -oq "$CACHE/godot.zip" -d "$CACHE/godot"
  rm -f "$CACHE/godot.zip"
  chmod +x "$GODOT"
else
  echo "Godot už je v cache."
fi

if [ ! -f "$TPL/version.txt" ]; then
  echo "Stahuji exportní šablony (1,2 GB)…"
  curl -fsSL -o "$CACHE/templates.tpz" "${BASE}/Godot_v${VERSION_TAG}_export_templates.tpz"
  tmp="$(mktemp -d)"
  unzip -oq "$CACHE/templates.tpz" -d "$tmp"
  cp -r "$tmp/templates/." "$TPL/"
  rm -rf "$tmp" "$CACHE/templates.tpz"
else
  echo "Exportní šablony už jsou v cache ($(cat "$TPL/version.txt"))."
fi

# Godot si data (user://, cache, šablony) bere z XDG_DATA_HOME – držíme je v cache,
# aby fungoval actions/cache a nic nezáviselo na domácím adresáři runneru.
{
  echo "FORGE_GODOT=$GODOT"
  echo "XDG_DATA_HOME=$CACHE/data"
} >> "${GITHUB_ENV:-/dev/null}"

export XDG_DATA_HOME="$CACHE/data"
"$GODOT" --headless --version
echo "Godot připraven: $GODOT"
