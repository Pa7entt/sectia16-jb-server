#!/usr/bin/env bash
# ============================================================
#  SECTIA 16 - compilarea pluginurilor .sma -> .amxx
#  Usage: compile.sh <directorul scripting al toolchain-ului AMXX>
#  Iesire: cstrike/addons/amxmodx/plugins/*.amxx
#  Compilarea trebuie sa treaca cu ZERO erori si ZERO warning-uri.
# ============================================================
set -euo pipefail

SCRIPTING_DIR="${1:?utilizare: compile.sh <amxx_toolchain>/addons/amxmodx/scripting}"
AMXXPC="${SCRIPTING_DIR}/amxxpc"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGINS_SRC="${REPO_ROOT}/cstrike/addons/amxmodx/scripting"
INCLUDE_DIR="${PLUGINS_SRC}/include"
PLUGINS_OUT="${REPO_ROOT}/cstrike/addons/amxmodx/plugins"

[ -x "${AMXXPC}" ] || { echo "[s16] amxxpc lipsa: ${AMXXPC}"; exit 1; }

mkdir -p "${PLUGINS_OUT}"

echo "[s16] Compilare pluginuri SECTIA 16 (AMX Mod X 1.10)..."
echo "[s16] Sursa:    ${PLUGINS_SRC}"
echo "[s16] Include:  ${INCLUDE_DIR}"
echo "[s16] Iesire:   ${PLUGINS_OUT}"
echo ""

cd "${PLUGINS_SRC}"

FAIL=0
for sma in sectia16_*.sma; do
    out="${PLUGINS_OUT}/${sma%.sma}.amxx"
    echo "------------------------------------------------------------"
    echo ">> ${sma}"
    if ! "${AMXXPC}" "${sma}" "-o${out}" "-i${INCLUDE_DIR}"; then
        echo "<< EZUARA: ${sma}"
        FAIL=1
    else
        echo "<< OK: ${out}"
    fi
done

echo ""
echo "------------------------------------------------------------"
if [ "${FAIL}" -ne 0 ]; then
    echo "[s16] COMPILARE ESUATA - verifica erorile de mai sus."
    exit 1
fi

echo "[s16] Toate pluginurile s-au compilat cu succes:"
ls -la "${PLUGINS_OUT}"
