#!/usr/bin/env bash
# ============================================================
#  SECTIA 16 - pregatirea toolchain-ului AMX Mod X 1.10
#  Folosit atat local cat si in GitHub Actions.
#  Usage: setup_amxx.sh <director_destinatie>
# ============================================================
set -euo pipefail

DEST="${1:?utilizare: setup_amxx.sh <dest>}"

AMXX_TAG="1.10.0.5487"
AMXX_VER="1.10.0"
AMXX_GIT="5487"
BASE_URL="https://github.com/alliedmodders/amxmodx/releases/download/${AMXX_TAG}/amxmodx-${AMXX_VER}-git${AMXX_GIT}-base-linux.tar.gz"
CSTRIKE_URL="https://github.com/alliedmodders/amxmodx/releases/download/${AMXX_TAG}/amxmodx-${AMXX_VER}-git${AMXX_GIT}-cstrike-linux.tar.gz"

if [ -x "${DEST}/addons/amxmodx/scripting/amxxpc" ]; then
    echo "[s16] Toolchain AMXX ${AMXX_TAG} deja prezent in ${DEST}."
    exit 0
fi

echo "[s16] Descarc AMX Mod X ${AMXX_TAG} (base + cstrike, linux)..."
mkdir -p "${DEST}"

curl -fsSL "${BASE_URL}" | tar -xz -C "${DEST}"
curl -fsSL "${CSTRIKE_URL}" | tar -xz -C "${DEST}"

echo "[s16] Verific binar compilator..."
USAGE_OUT="$("${DEST}/addons/amxmodx/scripting/amxxpc" 2>&1 || true)"
if ! echo "${USAGE_OUT}" | grep -q "Usage"; then
    echo "[s16] ATENTIE: amxxpc nu ruleaza (iesire: ${USAGE_OUT})."
    echo "[s16] Pe Ubuntu/Debian 64-bit instaleaza:"
    echo "[s16]   sudo apt-get install -y libc6-i386 lib32stdc++6 lib32gcc-s1"
    exit 1
fi

echo "[s16] Toolchain AMXX ${AMXX_TAG} gata in ${DEST}."
