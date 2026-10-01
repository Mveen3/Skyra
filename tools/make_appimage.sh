#!/usr/bin/env bash
# Optional: packages build/linux/Skyra.x86_64 as an AppImage when appimagetool is installed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
command -v appimagetool >/dev/null 2>&1 || { echo "appimagetool not found - skipping (optional step)"; exit 0; }
APPDIR="${ROOT_DIR}/build/Skyra.AppDir"
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin"
install -m 755 "${ROOT_DIR}/build/linux/Skyra.x86_64" "${APPDIR}/usr/bin/Skyra.x86_64"
install -m 644 "${ROOT_DIR}/icon.svg" "${APPDIR}/skyra.svg"
sed "s|@EXEC@|Skyra.x86_64|" "${SCRIPT_DIR}/skyra.desktop" > "${APPDIR}/skyra.desktop"
printf '#!/bin/sh\nexec "$(dirname "$0")/usr/bin/Skyra.x86_64" "$@"\n' > "${APPDIR}/AppRun"
chmod +x "${APPDIR}/AppRun"
appimagetool "${APPDIR}" "${ROOT_DIR}/build/Skyra-x86_64.AppImage"
