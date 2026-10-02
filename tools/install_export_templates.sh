#!/usr/bin/env bash
# Downloads the Godot export templates (~1 GB, owner-initiated, §2.5) into
# ~/.local/share/godot/export_templates/<version>.stable/
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V="$(tr -d '[:space:]' < "${SCRIPT_DIR}/godot_version.txt")"
DEST="${HOME}/.local/share/godot/export_templates/${V}.stable"
if [ -f "${DEST}/linux_release.x86_64" ]; then
    echo "Export templates ${V} already installed at ${DEST}"
    exit 0
fi

mkdir -p "${DEST}"

# Try fast range-based downloader for Linux templates first (~25 MB instead of ~1.1 GB)
if python3 "${SCRIPT_DIR}/fetch_linux_template.py" "${V}" "${DEST}"; then
    echo "Successfully installed Linux export templates (${V}) to ${DEST}"
    exit 0
fi

echo "Fast download failed or not supported. Falling back to full templates download (~1.1 GB)..."
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
URL="https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_export_templates.tpz"
echo "Downloading ${URL} ..."
curl -fL -o "${TMP}/templates.tpz" "${URL}"
if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "${TMP}/templates.tpz" -d "${TMP}/x"
else
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "${TMP}/templates.tpz" "${TMP}/x"
fi
cp -r "${TMP}/x/templates/." "${DEST}/"
echo "Installed export templates to ${DEST}"
