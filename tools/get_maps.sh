#!/usr/bin/env bash
# ============================================================
#  SECTIA 16 - Harti Jailbreak oficiale
#  Descarca pachetul oficial de harti JB (loadcs.com) si il
#  instaleaza ca overlay peste directorul cstrike al serverului.
#
#  Usage:
#    ./get_maps.sh                    -> instaleaza in /home/csserver/server
#    ./get_maps.sh /cale/spre/server  -> instaleaza in <dir>
#    S16_DIR=~/Documents/sv ./get_maps.sh
#
#  Pachet: https://loadcs.com/download/maps/3/  (~100 MB)
#  Contine 30+ harti jailbreak + wad-uri + skybox-uri.
# ============================================================
set -euo pipefail

SERVER_DIR="${1:-${S16_DIR:-/home/csserver/server}}"
MAPS_URL="https://loadcs.com/download/maps/3/"
TMP_ZIP="$(mktemp /tmp/sectia16-maps.XXXXXX.zip)"

echo "[s16] Harti Jailbreak oficiale -> ${SERVER_DIR}"

if [ ! -d "${SERVER_DIR}/cstrike" ]; then
    echo "[s16] EROARE: ${SERVER_DIR}/cstrike nu exista."
    echo "[s16] Ruleaza intai bootstrap.sh sau da calea serverului ca argument."
    exit 1
fi

if [ -f "${SERVER_DIR}/cstrike/maps/jail_xmf.bsp" ]; then
    echo "[s16] Hartile jailbreak sunt deja instalate (jail_xmf.bsp exista)."
    echo "[s16] Sterge ${SERVER_DIR}/cstrike/maps/jail_xmf.bsp pentru reinstall."
    exit 0
fi

echo "[s16] Descarc pachetul de harti (~100 MB) de la loadcs.com..."
if ! curl -fSL --retry 3 --retry-delay 2 -o "${TMP_ZIP}" "${MAPS_URL}"; then
    echo "[s16] EROARE: download-ul a esuat. Incearca manual:"
    echo "[s16]   browser: ${MAPS_URL}"
    echo "[s16]   apoi: unzip -o pachet.zip -d ${SERVER_DIR}"
    exit 1
fi

echo "[s16] Dezarhivez peste cstrike/..."
unzip -oq "${TMP_ZIP}" -d "${SERVER_DIR}"
rm -f "${TMP_ZIP}"

echo "[s16] Harti jailbreak instalate:"
ls "${SERVER_DIR}/cstrike/maps/" | grep -iE '^(jail|jb)_' | sort | head -40

echo "[s16] GATA. mapcycle.txt (din repo) contine deja selectia de harti."
