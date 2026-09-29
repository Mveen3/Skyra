#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${SCRIPT_DIR}/godot_version.txt"

if [ ! -f "${VERSION_FILE}" ]; then
    echo "Error: ${VERSION_FILE} not found!" >&2
    exit 1
fi

V="$(cat "${VERSION_FILE}" | tr -d '[:space:]')"
BIN_DIR="${SCRIPT_DIR}/bin"
GODOT_BIN="${BIN_DIR}/godot"

if [ -x "${GODOT_BIN}" ]; then
    INSTALLED_VER="$("${GODOT_BIN}" --version 2>/dev/null || true)"
    if [[ "${INSTALLED_VER}" == "${V}"* ]]; then
        echo "Godot ${V} already installed at ${GODOT_BIN}"
        exit 0
    fi
fi

mkdir -p "${BIN_DIR}"
TMP_ZIP="${BIN_DIR}/godot_${V}.zip"
URL="https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_linux.x86_64.zip"

echo "Downloading Godot ${V} from ${URL}..."
curl -fL -o "${TMP_ZIP}" "${URL}"

echo "Extracting Godot binary..."
if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "${TMP_ZIP}" -d "${BIN_DIR}"
else
    python3 -c "import zipfile; zipfile.ZipFile('${TMP_ZIP}').extractall('${BIN_DIR}')"
fi

rm -f "${TMP_ZIP}"

EXTRACTED_BIN="${BIN_DIR}/Godot_v${V}-stable_linux.x86_64"
if [ -f "${EXTRACTED_BIN}" ]; then
    mv -f "${EXTRACTED_BIN}" "${GODOT_BIN}"
fi

chmod +x "${GODOT_BIN}"

VER_OUTPUT="$("${GODOT_BIN}" --version)"
echo "Installed: ${VER_OUTPUT}"
if [[ "${VER_OUTPUT}" != "${V}"* ]]; then
    echo "Warning: Version mismatch: expected ${V}*, got ${VER_OUTPUT}" >&2
fi

echo "Godot ${V} setup complete at ${GODOT_BIN}"
