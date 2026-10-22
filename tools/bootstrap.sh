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
#  Var.:   S16_DIR=...      directorul de instalare (implicit /home/csserver/server;
#                           userul care ruleaza serverul se deduce din director)
#          S16_USER=...     user dedicat (implicit: dedus din S16_DIR)
#          S16_PORT=27015   portul serverului
#          S16_MAP=jb_snow  harta de start (fallback automat pe de_dust2)
# ============================================================
set -euo pipefail

S16_SERVICE="sectia16"
S16_PORT="${S16_PORT:-27015}"
S16_MAP="${S16_MAP:-jb_snow}"
S16_REPO="Pa7entt/sectia16-jb-server"
STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"
WORKDIR="$(mktemp -d /tmp/sectia16.XXXXXX)"

# ------------------------------------------------------------

say()  { echo -e "\e[1;33m[s16]\e[0m $*"; }
die()  { echo -e "\e[1;31m[s16] EROARE:\e[0m $*" >&2; exit 1; }

on_exit() { rm -rf "${WORKDIR}"; }
trap on_exit EXIT

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo env S16_DIR="${S16_DIR:-}" S16_USER="${S16_USER:-}" \
                S16_PORT="${S16_PORT}" S16_MAP="${S16_MAP}" STEAMCMD_DIR="${STEAMCMD_DIR}" \
                bash "$0" "$@"
    fi
    die "ruleaza ca root (sudo)."
fi

# ---------- Directorul serverului (override: S16_DIR=...) ----------
if [ -z "${S16_DIR:-}" ]; then
    S16_DIR="/home/${S16_USER:-csserver}/server"
fi
S16_DIR="$(readlink -m "${S16_DIR%/}")"

# ---------- Userul care ruleaza serverul ----------
# Prioritate: S16_USER explicit > owner-ul directorului > dedus din /home/<user>/... > csserver
if [ -z "${S16_USER:-}" ]; then
    if [ -d "${S16_DIR}" ]; then
        _owner="$(stat -c %U "${S16_DIR}" 2>/dev/null || true)"
        if [ -n "${_owner}" ] && [ "${_owner}" != "root" ]; then
            S16_USER="${_owner}"
        fi
    fi
    if [ -z "${S16_USER:-}" ]; then
        case "${S16_DIR}" in
            /home/*)
                _u="$(printf '%s' "${S16_DIR}" | cut -d/ -f3)"
                if [ -n "${_u}" ] && id -u "${_u}" >/dev/null 2>&1; then
                    S16_USER="${_u}"
                fi
                ;;
        esac
    fi
fi
S16_USER="${S16_USER:-csserver}"
S16_GROUP="${S16_GROUP:-${S16_USER}}"
say "Director: ${S16_DIR}   User: ${S16_USER}   Port: ${S16_PORT}"

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

# ---------- helper: asset latest de pe GitHub (API + fallback HTML) ----------
gh_asset() {
    local repo="$1" pattern="$2" url
    url="$(python3 - "${repo}" "${pattern}" <<'PYEOF'
import json, re, sys, urllib.request

repo, pattern = sys.argv[1], sys.argv[2]

def fetch(url, accept="*/*"):
    req = urllib.request.Request(
        url, headers={"User-Agent": "sectia16-bootstrap", "Accept": accept})
    return urllib.request.urlopen(req, timeout=60)

# 1) API-ul GitHub (poate pica pe rate-limit)
try:
    data = json.loads(fetch("https://api.github.com/repos/%s/releases/latest" % repo,
                            "application/vnd.github+json").read().decode("utf-8", "replace"))
    for asset in data.get("assets", []):
        if re.search(pattern, asset["name"]):
            print(asset["browser_download_url"]); sys.exit(0)
except Exception:
    pass

# 2) fallback: pagina release-ului (redirect latest -> tag -> expanded_assets)
try:
    resp = fetch("https://github.com/%s/releases/latest" % repo, "text/html")
    tag = resp.geturl().rstrip("/").rsplit("/", 1)[-1]
    html = fetch("https://github.com/%s/releases/expanded_assets/%s" % (repo, tag),
                 "text/html").read().decode("utf-8", "replace")
    for m in re.finditer(r'href="([^"]*/releases/download/[^"]+)"', html):
        url = m.group(1)
        name = url.rsplit("/", 1)[-1]
        if re.search(pattern, name):
            print(url if url.startswith("http") else "https://github.com" + url)
            sys.exit(0)
except Exception:
    pass

sys.exit(1)
PYEOF
    )" || die "nu am gasit asset '${pattern}' in ${repo} (verifica conexiunea la GitHub)."
    echo "${url}"
}

# ---------- 5. ReHLDS (engine) ----------
say "5/10 - ReHLDS (ultimul release)..."
REHLDS_URL="$(gh_asset dreamstalker/rehlds '^rehlds-bin-.*\.zip$')"
say "       ${REHLDS_URL}"
curl -fsSL "${REHLDS_URL}" -o "${WORKDIR}/rehlds.zip"
unzip -q -o "${WORKDIR}/rehlds.zip" -d "${WORKDIR}/rehlds"
cp -f "${WORKDIR}/rehlds/bin/linux32/core.so"                "${S16_DIR}/"
cp -f "${WORKDIR}/rehlds/bin/linux32/engine_i486.so"         "${S16_DIR}/"
cp -f "${WORKDIR}/rehlds/bin/linux32/filesystem_stdio.so"    "${S16_DIR}/"
cp -f "${WORKDIR}/rehlds/bin/linux32/hlds_linux"             "${S16_DIR}/"
cp -f "${WORKDIR}/rehlds/bin/linux32/hltv"                   "${S16_DIR}/" 2>/dev/null || true
mkdir -p "${S16_DIR}/valve/dlls"
cp -f "${WORKDIR}/rehlds/bin/linux32/valve/dlls/director.so" "${S16_DIR}/valve/dlls/" 2>/dev/null || true
grep -aqi rehlds "${S16_DIR}/engine_i486.so" && say "       engine_i486.so = ReHLDS OK" || say "       ATENTIE: engine nu pare ReHLDS!"

# ---------- 6. metamod-r ----------
say "6/10 - metamod-r..."
METAMOD_URL="$(gh_asset theAsmodai/metamod-r '^metamod-bin-.*\.zip$')"
say "       ${METAMOD_URL}"
curl -fsSL "${METAMOD_URL}" -o "${WORKDIR}/metamod.zip"
unzip -q -o "${WORKDIR}/metamod.zip" -d "${WORKDIR}/metamod"
mkdir -p "${S16_DIR}/cstrike/addons/metamod"
cp -f "${WORKDIR}/metamod/addons/metamod/metamod_i386.so" "${S16_DIR}/cstrike/addons/metamod/"

# liblist.gam rescris CURAT (imun la fisiere corupte / garbled)
cat > "${S16_DIR}/cstrike/liblist.gam" <<'EOF'
game "Counter-Strike"
url_info "www.counter-strike.net"
url_dl ""
version "1.6"
size "184000000"
svonly "0"
secure "1"
type "multiplayer_only"
cldll "1"
gamedll "dlls/mp.dll"
gamedll_linux "addons/metamod/metamod_i386.so"
EOF

# ---------- 7. ReGameDLL_CS ----------
say "7/10 - ReGameDLL_CS..."
REGAMEDLL_URL="$(gh_asset s1lentq/ReGameDLL_CS '^regamedll-bin-.*\.zip$')"
say "       ${REGAMEDLL_URL}"
curl -fsSL "${REGAMEDLL_URL}" -o "${WORKDIR}/regamedll.zip"
unzip -q -o "${WORKDIR}/regamedll.zip" -d "${WORKDIR}/regamedll"
mkdir -p "${S16_DIR}/cstrike/dlls"
cp -f "${WORKDIR}/regamedll/bin/linux32/cstrike/dlls/cs.so" "${S16_DIR}/cstrike/dlls/cs.so"
cp -f "${WORKDIR}/regamedll/bin/linux32/cstrike/delta.lst"  "${S16_DIR}/cstrike/delta.lst"
grep -aqi regamedll "${S16_DIR}/cstrike/dlls/cs.so" && say "       cs.so = ReGameDLL OK" || say "       ATENTIE: cs.so nu pare ReGameDLL!"

# metamod-r incarca ReGameDLL in locul mp.dll (config.ini rescris curat)
cat > "${S16_DIR}/cstrike/addons/metamod/config.ini" <<'EOF'
; metamod-r - SECTIA 16
; ReGameDLL_CS in locul mp.dll vanilla
gamedll dlls/cs.so
EOF

# ---------- 8. AMX Mod X 1.10 + ReAPI ----------
say "8/10 - AMX Mod X 1.10.0.5487 + ReAPI..."
AMXX_TAG="1.10.0.5487"
curl -fsSL "https://github.com/alliedmodders/amxmodx/releases/download/${AMXX_TAG}/amxmodx-1.10.0-git5487-base-linux.tar.gz"    | tar -xz -C "${S16_DIR}/cstrike/"
curl -fsSL "https://github.com/alliedmodders/amxmodx/releases/download/${AMXX_TAG}/amxmodx-1.10.0-git5487-cstrike-linux.tar.gz" | tar -xz -C "${S16_DIR}/cstrike/"

# metamod incarca amxx
# AMXX 1.10.0.5487 livreaza amxmodx_mm_i386.so (nu amxmodx_mm.so) -
# detectam ce exista ca sa functioneze pe ambele scheme de denumire.
AMXX_MM="amxmodx_mm.so"
if [ -f "${S16_DIR}/cstrike/addons/amxmodx/dlls/amxmodx_mm_i386.so" ]; then
    AMXX_MM="amxmodx_mm_i386.so"
fi
echo "linux addons/amxmodx/dlls/${AMXX_MM}" > "${S16_DIR}/cstrike/addons/metamod/plugins.ini"

# ReAPI (modul AMXX)
say "       + ReAPI (modul)..."
REAPI_URL="$(gh_asset rehlds/ReAPI '^reapi-bin-.*\.zip$')"
say "       ${REAPI_URL}"
curl -fsSL "${REAPI_URL}" -o "${WORKDIR}/reapi.zip"
unzip -q -o "${WORKDIR}/reapi.zip" -d "${WORKDIR}/reapi"
mkdir -p "${S16_DIR}/cstrike/addons/amxmodx/modules"
cp -f "${WORKDIR}/reapi/addons/amxmodx/modules/reapi_amxx_i386.so" "${S16_DIR}/cstrike/addons/amxmodx/modules/"

# asiguram ca modulul reapi e listat explicit in modules.ini
MODULES_INI="${S16_DIR}/cstrike/addons/amxmodx/configs/modules.ini"
if [ -f "${MODULES_INI}" ] && ! grep -qE '^[[:space:]]*reapi[[:space:]]*$' "${MODULES_INI}"; then
    printf '\n; ReAPI (SECTIA 16 - necesar pluginurilor)\nreapi\n' >> "${MODULES_INI}"
fi

# ---------- 9. Repo-ul SECTIA 16 (configuri + pluginuri + sunete) ----------
say "9/10 - Repository SECTIA 16..."
if git clone --depth 1 "https://github.com/${S16_REPO}.git" "${WORKDIR}/repo" 2>/dev/null; then
    :
else
    curl -fsSL "https://github.com/${S16_REPO}/archive/refs/heads/main.tar.gz" | tar -xz -C "${WORKDIR}"
    mv "${WORKDIR}/sectia16-jb-server-main" "${WORKDIR}/repo"
fi

# pastram parola RCON existenta (daca e) inainte de overlay
OLD_RCON=""
if [ -f "${S16_DIR}/cstrike/server.cfg" ]; then
    OLD_RCON="$(sed -n 's/^rcon_password *"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "${S16_DIR}/cstrike/server.cfg" | tail -1 || true)"
fi

# overlay peste cstrike (configurile si plugins.ini ale noastre raman)
mkdir -p "${S16_DIR}/cstrike"
cp -r "${WORKDIR}/repo/cstrike/." "${S16_DIR}/cstrike/"

# parola RCON: cea veche sau una noua generata aleator
if [ -n "${OLD_RCON}" ]; then
    RCON_PW="${OLD_RCON}"
else
    RCON_PW="$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 20)"
fi
sed -i "s|^rcon_password .*|rcon_password \"${RCON_PW}\"|" "${S16_DIR}/cstrike/server.cfg"
if ! grep -q '^rcon_password' "${S16_DIR}/cstrike/server.cfg"; then
    echo "rcon_password \"${RCON_PW}\"" >> "${S16_DIR}/cstrike/server.cfg"
fi

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

# ---------- Verificare finala prin RCON ----------
say "Verific ca serverul raspunde si ca pluginurile s-au incarcat..."
BOOTED=0
for _ in $(seq 1 20); do
    if python3 "${WORKDIR}/repo/tools/rcon.py" 127.0.0.1 "${S16_PORT}" "${RCON_PW}" "version" >/dev/null 2>&1; then
        BOOTED=1
        break
    fi
    sleep 3
done

sleep 3
say "============================================================"
say " SECTIA 16 e LIVE."
say "============================================================"
echo ""
if [ "${BOOTED}" -eq 1 ]; then
    say "Pluginuri AMXX (verificat live prin RCON):"
    python3 "${WORKDIR}/repo/tools/rcon.py" 127.0.0.1 "${S16_PORT}" "${RCON_PW}" "amxx plugins" || true
else
    say "ATENTIE: serverul nu a raspuns la RCON in ~60s."
    say "Vezi log-ul: journalctl -u ${S16_SERVICE} -n 50 --no-pager"
fi
echo ""
echo "  Serviciu :  systemctl status ${S16_SERVICE}"
echo "  Live log :  journalctl -u ${S16_SERVICE} -f"
echo "  RCON     :  ${RCON_PW}  (salvat si in cstrike/server.cfg)"
echo "  Harta    :  ${S16_MAP}  (schimba cu: S16_MAP=jb_harta_ta)"
echo ""
echo "  Urmatorii pasi (optionali):"
echo "   1. Pune hartile JB in ${S16_DIR}/cstrike/maps/ si actualizeaza mapcycle.txt"
echo "   2. Configureaza FastDL in cstrike/server.cfg (sv_downloadurl)"
echo "   3. Adauga admini in cstrike/addons/amxmodx/configs/users.ini"
echo "   4. Configureaza celulele hartii in configs/sectia16/cells.ini"
echo ""
