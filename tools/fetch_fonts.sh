#!/usr/bin/env bash
# Optional (§7.8): downloads the OFL fonts "Russo One" (headings) and "Rajdhani" (body)
# into assets/fonts/. Without them the game uses the engine font with a bold variation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$(cd "${SCRIPT_DIR}/.." && pwd)/assets/fonts"
mkdir -p "${DEST}"
BASE="https://github.com/google/fonts/raw/main/ofl"
curl -fL -o "${DEST}/RussoOne-Regular.ttf" "${BASE}/russoone/RussoOne-Regular.ttf"
curl -fL -o "${DEST}/Rajdhani-Bold.ttf" "${BASE}/rajdhani/Rajdhani-Bold.ttf"
curl -fL -o "${DEST}/OFL.txt" "${BASE}/russoone/OFL.txt"
echo "Fonts installed to ${DEST} - open the project once (or run --import) so Godot imports them."
