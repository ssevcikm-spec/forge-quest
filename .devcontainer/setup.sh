#!/usr/bin/env bash
# Nastavení Codespace tak, aby v něm šlo dělat totéž co na stanici:
# Godot headless + exportní šablony, knihovny pro brány kvality, virtuální displej
# pro renderovací kontrolu. Používá stejný skript jako CI (.forge/install-godot.sh),
# takže se nastavení nerozejde se skutečným během v Actions.
set -euo pipefail

echo "=== Systémové balíčky (virtuální displej pro --write-movie) ==="
sudo apt-get update -qq
sudo apt-get install -y -qq xvfb libgl1-mesa-dri libglx-mesa0 mesa-utils ffmpeg

echo "=== Godot + exportní šablony ==="
bash .forge/install-godot.sh

echo "=== Knihovny pipeline (brány kvality) ==="
python3 -m pip install --quiet --upgrade pip
python3 -m pip install --quiet pillow numpy

echo "=== Kontrola: Godot a hra ==="
"$FORGE_GODOT" --version
"$FORGE_GODOT" --headless --path . --import >/dev/null 2>&1 || true
timeout 150 "$FORGE_GODOT" --headless --path . --script res://tests/run_tests.gd | tail -3

echo
echo "Hotovo. Co teď jde spustit:"
echo "  python3 .forge/check-assets.py .     # vzhled a hudba proti specu"
echo "  python3 .forge/check-wiring.py .     # žádný mrtvý kód"
echo "  python3 .forge/node/provider-choice.test.mjs   # test volby poskytovatele"
echo "  xvfb-run -a \"\$FORGE_GODOT\" --path . --rendering-driver opengl3 \\"
echo "    --resolution 480x270 --fixed-fps 20 --write-movie /tmp/frames/frame.png --quit-after 20"
