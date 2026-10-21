#!/usr/bin/env bash
# ============================================================
#  SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
#  Bootstrap complet pentru Debian 13 "Trixie" (amd64 + i386 multilib)
#
#  Instaleaza: steamcmd + HLDS (CS 1.6) + ReHLDS + metamod-r
#              + ReGameDLL_CS + ReAPI + AMX Mod X 1.10 + repo-ul SECTIA 16
#  Porneste:   serviciu systemd "sectia16" (port 27015)
#
#  Usage:  curl -fsSL https://raw.githubusercontent.com/Pa7entt/sectia16-jb-server/main/tools/bootstrap.sh | sudo bash
#  Var.:   S16_MAP=jb_snow  (implicit; fallback automat pe de_dust2)
# ============================================================
set -euo pipefail

S16_USER="csserver"
S16_GROUP="csserver"
S16_DIR="/home/${S16_USER}/server"
S16_SERVICE="sectia16"
S16_PORT="27015"
S16_MAP="${S16_MAP:-jb_snow}"
S16_REPO="Pa7entt/sectia16-jb-server"
STEAMCMD_DIR="/opt/steamcmd"
WORKDIR="$(mktemp -d /tmp/sectia16.XXXXXX)"

# ------------------------------------------------------------

say()  { echo -e "\e[1;33m[s16]\e[0m $*"; }
die()  { echo -e "\e[1;31m[s16] EROARE:\e[0m $*" >&2; exit 1; }

on_exit() { rm -rf "${WORKDIR}"; }
trap on_exit EXIT

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    fi
    die "ruleaza ca root (sudo)."
fi

# ---------- 1. Dependențe + i386 multilib ----------
say "1/10 - Dependențe sistem + arhitectura i386..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates tar xz unzip git python3 perl bash

if ! dpkg --print-foreign-architectures | grep -q i386; then
    dpkg --add-architecture i386
    apt-get update -y
fi
apt-get install -y libc6:i386 lib32gcc-s1 lib32stdc++6 lib32z1 || \
    apt-get install -y libc6-i386 lib32gcc-s1 lib32stdc++6

# HLDS (binar vechi) poate cere libtinfo.so.5 - pe trixie exista doar .6
if [ ! -e /usr/lib/i386-linux-gnu/libtinfo.so.5 ] && [ -e /usr/lib/i386-linux-gnu/libtinfo.so.6 ]; then
    ln -sf /usr/lib/i386-linux-gnu/libtinfo.so.6 /usr/lib/i386-linux-gnu/libtinfo.so.5
fi

# ---------- 2. Utilizator dedicat ----------
say "2/10 - Utilizatorul ${S16_USER}..."
if ! id -u "${S16_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${S16_USER}"
fi
mkdir -p "${S16_DIR}"

# ---------- 3. steamcmd ----------
say "3/10 - SteamCMD..."
if [ ! -x "${STEAMCMD_DIR}/steamcmd.sh" ]; then
    mkdir -p "${STEAMCMD_DIR}"
    curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar -xz -C "${STEAMCMD_DIR}"
fi

# ---------- 4. HLDS + Counter-Strike 1.6 (app 90) ----------
say "4/10 - HLDS + Counter-Strike 1.6 prin SteamCMD (rabdare, ~1 GB)..."
chown -R "${S16_USER}:${S16_GROUP}" "${S16_DIR}"
install_cs() {
    sudo -u "${S16_USER}" "${STEAMCMD_DIR}/steamcmd.sh" \
        +force_install_dir "${S16_DIR}" \
        +login anonymous \
        +app_set_config 90 mod cstrike \
        +app_update 90 validate \
        +quit
}
OK=0
for i in 1 2 3; do
    if install_cs; then OK=1; break; fi
    say "incercarea ${i} a esuat, mai incerc o data..."
    sleep 5
done
[ "${OK}" -eq 1 ] || die "SteamCMD nu a putut instala HLDS. Verifica log-ul de mai sus."
[ -x "${S16_DIR}/hlds_linux" ] || die "hlds_linux lipseste dupa instalare."

# ---------- helper: asset latest de pe GitHub ----------
gh_asset() {
    local repo="$1" pattern="$2" url
    url="$(python3 - "${repo}" "${pattern}" <<'PYEOF'
import json, re, sys, urllib.request
repo, pattern = sys.argv[1], sys.argv[2]
req = urllib.request.Request(
    "https://api.github.com/repos/%s/releases/latest" % repo,
    headers={"User-Agent": "sectia16-bootstrap", "Accept": "application/vnd.github+json"})
data = json.load(urllib.request.urlopen(req, timeout=60))
for asset in data.get("assets", []):
    if re.search(pattern, asset["name"]):
        print(asset["browser_download_url"])
        sys.exit(0)
sys.exit(1)
PYEOF
    )" || die "nu am gasit asset '${pattern}' in ${repo}."
    echo "${url}"
}

# ---------- 5. ReHLDS (engine) ----------
say "5/10 - ReHLDS (ultimul release)..."
REHLDS_URL="$(gh_asset dreamstalker/rehlds '^rehlds-bin-.*\.zip$')"
curl -fsSL "${REHLDS_URL}" -o "${WORKDIR}/rehlds.zip"
unzip -q -o "${WORKDIR}/rehlds.zip" -d "${WORKDIR}/rehlds"
cp -f "${WORKDIR}/rehlds/bin/linux32/core.so"                "${S16_DIR}/"
cp -f "${WORKDIR}/rehlds/bin/linux32/engine_i486.so"         "${S16_DIR}/"
cp -f "${WORKDIR}/rehlds/bin/linux32/filesystem_stdio.so"    "${S16_DIR}/"
cp -f "${WORKDIR}/rehlds/bin/linux32/hlds_linux"             "${S16_DIR}/"
cp -f "${WORKDIR}/rehlds/bin/linux32/hltv"                   "${S16_DIR}/" 2>/dev/null || true
mkdir -p "${S16_DIR}/valve/dlls"
cp -f "${WORKDIR}/rehlds/bin/linux32/valve/dlls/director.so" "${S16_DIR}/valve/dlls/" 2>/dev/null || true

# ---------- 6. metamod-r ----------
say "6/10 - metamod-r..."
METAMOD_URL="$(gh_asset theAsmodai/metamod-r '^metamod-bin-.*\.zip$')"
curl -fsSL "${METAMOD_URL}" -o "${WORKDIR}/metamod.zip"
unzip -q -o "${WORKDIR}/metamod.zip" -d "${WORKDIR}/metamod"
mkdir -p "${S16_DIR}/cstrike/addons/metamod"
cp -f "${WORKDIR}/metamod/addons/metamod/metamod_i386.so" "${S16_DIR}/cstrike/addons/metamod/"
cp -f "${WORKDIR}/metamod/addons/metamod/config.ini"      "${S16_DIR}/cstrike/addons/metamod/" 2>/dev/null || true

# liblist.gam -> metamod
if grep -q '^gamedll_linux' "${S16_DIR}/cstrike/liblist.gam" 2>/dev/null; then
    sed -i 's|^gamedll_linux .*|gamedll_linux "addons/metamod/metamod_i386.so"|' "${S16_DIR}/cstrike/liblist.gam"
else
    echo 'gamedll_linux "addons/metamod/metamod_i386.so"' >> "${S16_DIR}/cstrike/liblist.gam"
fi

# ---------- 7. ReGameDLL_CS ----------
say "7/10 - ReGameDLL_CS..."
REGAMEDLL_URL="$(gh_asset s1lentq/ReGameDLL_CS '^regamedll-bin-.*\.zip$')"
curl -fsSL "${REGAMEDLL_URL}" -o "${WORKDIR}/regamedll.zip"
unzip -q -o "${WORKDIR}/regamedll.zip" -d "${WORKDIR}/regamedll"
cp -f "${WORKDIR}/regamedll/bin/linux32/cstrike/dlls/cs.so" "${S16_DIR}/cstrike/dlls/cs.so"
cp -f "${WORKDIR}/regamedll/bin/linux32/cstrike/delta.lst"  "${S16_DIR}/cstrike/delta.lst"

# metamod-r incarca ReGameDLL in locul mp.dll
if ! grep -q '^gamedll ' "${S16_DIR}/cstrike/addons/metamod/config.ini" 2>/dev/null; then
    echo "" >> "${S16_DIR}/cstrike/addons/metamod/config.ini"
    echo "gamedll dlls/cs.so" >> "${S16_DIR}/cstrike/addons/metamod/config.ini"
fi

# ---------- 8. AMX Mod X 1.10 ----------
say "8/10 - AMX Mod X 1.10.0.5487..."
AMXX_TAG="1.10.0.5487"
curl -fsSL "https://github.com/alliedmodders/amxmodx/releases/download/${AMXX_TAG}/amxmodx-1.10.0-git5487-base-linux.tar.gz"    | tar -xz -C "${S16_DIR}/cstrike/"
curl -fsSL "https://github.com/alliedmodders/amxmodx/releases/download/${AMXX_TAG}/amxmodx-1.10.0-git5487-cstrike-linux.tar.gz" | tar -xz -C "${S16_DIR}/cstrike/"

# metamod incarca amxx
echo "linux addons/amxmodx/dlls/amxmodx_mm.so" > "${S16_DIR}/cstrike/addons/metamod/plugins.ini"

# ReAPI (modul AMXX)
say "       + ReAPI (modul)..."
REAPI_URL="$(gh_asset rehlds/ReAPI '^reapi-bin-.*\.zip$')"
curl -fsSL "${REAPI_URL}" -o "${WORKDIR}/reapi.zip"
unzip -q -o "${WORKDIR}/reapi.zip" -d "${WORKDIR}/reapi"
mkdir -p "${S16_DIR}/cstrike/addons/amxmodx/modules"
cp -f "${WORKDIR}/reapi/addons/amxmodx/modules/reapi_amxx_i386.so" "${S16_DIR}/cstrike/addons/amxmodx/modules/"

# ---------- 9. Repo-ul SECTIA 16 (configuri + pluginuri + sunete) ----------
say "9/10 - Repository SECTIA 16..."
if git clone --depth 1 "https://github.com/${S16_REPO}.git" "${WORKDIR}/repo" 2>/dev/null; then
    :
else
    curl -fsSL "https://github.com/${S16_REPO}/archive/refs/heads/main.tar.gz" | tar -xz -C "${WORKDIR}"
    mv "${WORKDIR}/sectia16-jb-server-main" "${WORKDIR}/repo"
fi

# overlay peste cstrike (configurile si plugins.ini ale noastre raman)
cp -r "${WORKDIR}/repo/cstrike/." "${S16_DIR}/cstrike/"

# parole RCON generate aleator
RCON_PW="$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 20)"
sed -i "s|^rcon_password .*|rcon_password \"${RCON_PW}\"|" "${S16_DIR}/cstrike/server.cfg"

# harta: fallback daca nu exista pe server
if [ ! -f "${S16_DIR}/cstrike/maps/${S16_MAP}.bsp" ]; then
    say "harta ${S16_MAP}.bsp nu exista - folosesc de_dust2 (pune hartile JB in cstrike/maps/)."
    S16_MAP="de_dust2"
fi

chown -R "${S16_USER}:${S16_GROUP}" "${S16_DIR}"

# ---------- 10. systemd + pornire ----------
say "10/10 - Serviciu systemd ${S16_SERVICE}..."
cat > "/etc/systemd/system/${S16_SERVICE}.service" <<UNIT
[Unit]
Description=SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${S16_USER}
Group=${S16_GROUP}
WorkingDirectory=${S16_DIR}
ExecStart=${S16_DIR}/hlds_run -game cstrike -port ${S16_PORT} +map ${S16_MAP} +maxplayers 32 -secure
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
KillSignal=SIGINT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable "${S16_SERVICE}" >/dev/null
systemctl restart "${S16_SERVICE}"

# firewall (best effort)
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "${S16_PORT}/udp" >/dev/null
    ufw allow "${S16_PORT}/tcp" >/dev/null
fi

sleep 3
say "============================================================"
say " SECTIA 16 e LIVE."
say "============================================================"
echo ""
echo "  Serviciu :  systemctl status ${S16_SERVICE}"
echo "  Live log :  journalctl -u ${S16_SERVICE} -f"
echo "  Consola  :  ${S16_DIR}/hlds_run -game cstrike +rcon_password"
echo "  RCON     :  ${RCON_PW}  (salvat si in cstrike/server.cfg)"
echo "  Harta    :  ${S16_MAP}  (schimba cu: S16_MAP=jb_harta_ta bash tools/bootstrap.sh)"
echo ""
echo "  Urmatorii pasi (optionali):"
echo "   1. Pune hartile JB in ${S16_DIR}/cstrike/maps/ si actualizeaza mapcycle.txt"
echo "   2. Configureaza FastDL in cstrike/server.cfg (sv_downloadurl)"
echo "   3. Adauga admini in cstrike/addons/amxmodx/configs/users.ini"
echo "   4. Configureaza celulele hartii in configs/sectia16/cells.ini"
echo ""
