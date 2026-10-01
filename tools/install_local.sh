#!/usr/bin/env bash
# Installs the built game for the current user: binary to ~/.local/share/skyra/,
# a desktop entry and the icon (run tools/build_linux.sh first).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN="${ROOT_DIR}/build/linux/Skyra.x86_64"
[ -f "${BIN}" ] || { echo "Build not found - run tools/build_linux.sh first" >&2; exit 1; }
DEST="${HOME}/.local/share/skyra"
mkdir -p "${DEST}" "${HOME}/.local/share/applications" "${HOME}/.local/share/icons/hicolor/scalable/apps"
install -m 755 "${BIN}" "${DEST}/Skyra.x86_64"
install -m 644 "${ROOT_DIR}/icon.svg" "${HOME}/.local/share/icons/hicolor/scalable/apps/skyra.svg"
sed "s|@EXEC@|${DEST}/Skyra.x86_64|" "${SCRIPT_DIR}/skyra.desktop" > "${HOME}/.local/share/applications/skyra.desktop"
echo "Installed Skyra to ${DEST} (menu entry: Skyra)"
