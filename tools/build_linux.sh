#!/usr/bin/env bash
# Builds the release Linux binary (single file, embedded PCK) into build/linux/ (§2.5).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
V="$(tr -d '[:space:]' < "${SCRIPT_DIR}/godot_version.txt")"
GODOT="${SCRIPT_DIR}/bin/godot"
TEMPLATES="${HOME}/.local/share/godot/export_templates/${V}.stable"
[ -x "${GODOT}" ] || { echo "Godot not found - run tools/setup_godot.sh first" >&2; exit 1; }
[ -d "${TEMPLATES}" ] || { echo "Export templates missing - run tools/install_export_templates.sh first" >&2; exit 1; }
mkdir -p "${ROOT_DIR}/build/linux"
"${GODOT}" --headless --path "${ROOT_DIR}" --export-release "Linux" "${ROOT_DIR}/build/linux/Skyra.x86_64"
ls -lh "${ROOT_DIR}/build/linux/Skyra.x86_64"
