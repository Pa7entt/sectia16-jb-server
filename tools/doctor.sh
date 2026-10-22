#!/usr/bin/env bash
# ============================================================
#  SECTIA 16 - doctor.sh - reparare RAPIDA fara reinstalare
#
#  Pentru cand HLDS e deja instalat dar serverul nu porneste corect:
#   - "Couldn't get DLL API" (liblist.gam corupt / engine ramas vanilla)
#   - pluginurile AMXX nu se incarca (stack incomplet / module lipsa)
#
#  Reaplica:  ReHLDS + metamod-r + ReGameDLL_CS + ReAPI + AMX Mod X 1.10
#             + overlay repo (pluginuri .amxx + configuri + sunete)
#  Rescrie:   liblist.gam CURAT, metamod config.ini, plugins.ini,
#             reapi in modules.ini
#  Reporneste serviciul systemd si VERIFICA pluginurile prin RCON.
#
#  Usage:  curl -fsSL https://raw.githubusercontent.com/Pa7entt/sectia16-jb-server/main/tools/doctor.sh | sudo S16_DIR="$HOME/Documents/sv" bash
#  Var.:  S16_DIR / S16_USER / S16_PORT / S16_MAP   (ca la bootstrap.sh)
# ============================================================
set -euo pipefail

S16_SERVICE="sectia16"
S16_PORT="${S16_PORT:-27015}"
S16_MAP="${S16_MAP:-jail_xmf}"
S16_REPO="Pa7entt/sectia16-jb-server"
WORKDIR="$(mktemp -d /tmp/sectia16-doctor.XXXXXX)"

# ------------------------------------------------------------

say()  { echo -e "\e[1;33m[s16]\e[0m $*"; }
die()  { echo -e "\e[1;31m[s16] EROARE:\e[0m $*" >&2; exit 1; }

on_exit() { rm -rf "${WORKDIR}"; }
trap on_exit EXIT

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo env S16_DIR="${S16_DIR:-}" S16_USER="${S16_USER:-}" \
                S16_PORT="${S16_PORT}" S16_MAP="${S16_MAP}" \
                bash "$0" "$@"
    fi
    die "ruleaza ca root (sudo)."
fi

# ---------- Directorul serverului (override: S16_DIR=...) ----------
if [ -z "${S16_DIR:-}" ]; then
    S16_DIR="/home/${S16_USER:-csserver}/server"
fi
S16_DIR="$(readlink -m "${S16_DIR%/}")"

# ---------- Userul care ruleaza serverul (ca la bootstrap) ----------
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
say "DOCTOR SECTIA 16 - reparare rapida"
say "Director: ${S16_DIR}   User: ${S16_USER}   Port: ${S16_PORT}"

# ---------- helper: asset latest de pe GitHub (API + fallback HTML) ----------
gh_asset() {
    local repo="$1" pattern="$2" url
    url="$(python3 - "${repo}" "${pattern}" <<'PYEOF'
import json, re, sys, urllib.request

repo, pattern = sys.argv[1], sys.argv[2]

def fetch(url, accept="*/*"):
    req = urllib.request.Request(
        url, headers={"User-Agent": "sectia16-doctor", "Accept": accept})
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

# ---------- 1/8 - sanitate ----------
say "1/8 - Verific mediul..."
command -v curl    >/dev/null 2>&1 || die "lipseste 'curl' (ruleaza bootstrap.sh complet)"
command -v unzip   >/dev/null 2>&1 || die "lipseste 'unzip' (ruleaza bootstrap.sh complet)"
command -v python3 >/dev/null 2>&1 || die "lipseste 'python3' (ruleaza bootstrap.sh complet)"
command -v tar     >/dev/null 2>&1 || die "lipseste 'tar' (ruleaza bootstrap.sh complet)"
[ -x "${S16_DIR}/hlds_run" ] || die "nu gasesc ${S16_DIR}/hlds_run - HLDS nu e instalat acolo. Ruleaza bootstrap.sh complet:  curl -fsSL https://raw.githubusercontent.com/Pa7entt/sectia16-jb-server/main/tools/bootstrap.sh | sudo S16_DIR=${S16_DIR} bash"
dpkg -s lib32stdc++6 >/dev/null 2>&1 || say "ATENTIE: lib32stdc++6 lipseste - daca serverul crapa, ruleaza bootstrap.sh complet."
id -u "${S16_USER}" >/dev/null 2>&1 || die "userul '${S16_USER}' nu exista."

# ---------- 2/8 - oprire ----------
say "2/8 - Opresc serverul (serviciu + instante manuale)..."
systemctl stop "${S16_SERVICE}" 2>/dev/null || true
pkill -f 'hlds_(linux|run)' 2>/dev/null || true
sleep 2

# ---------- 3/8 - ReHLDS (engine) ----------
say "3/8 - ReHLDS (ultimul release)..."
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

# ---------- 4/8 - metamod-r + liblist.gam curat ----------
say "4/8 - metamod-r + liblist.gam rescris curat..."
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

# ---------- 5/8 - ReGameDLL_CS ----------
say "5/8 - ReGameDLL_CS..."
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

# ---------- 6/8 - AMX Mod X 1.10 + ReAPI ----------
say "6/8 - AMX Mod X 1.10.0.5487 + ReAPI..."
AMXX_TAG="1.10.0.5487"
curl -fsSL "https://github.com/alliedmodders/amxmodx/releases/download/${AMXX_TAG}/amxmodx-1.10.0-git5487-base-linux.tar.gz"    | tar -xz -C "${S16_DIR}/cstrike/"
curl -fsSL "https://github.com/alliedmodders/amxmodx/releases/download/${AMXX_TAG}/amxmodx-1.10.0-git5487-cstrike-linux.tar.gz" | tar -xz -C "${S16_DIR}/cstrike/"

# AMXX 1.10.0.5487 livreaza amxmodx_mm_i386.so (nu amxmodx_mm.so) -
# detectam ce exista ca sa functioneze pe ambele scheme de denumire.
AMXX_MM="amxmodx_mm.so"
if [ -f "${S16_DIR}/cstrike/addons/amxmodx/dlls/amxmodx_mm_i386.so" ]; then
    AMXX_MM="amxmodx_mm_i386.so"
fi
echo "linux addons/amxmodx/dlls/${AMXX_MM}" > "${S16_DIR}/cstrike/addons/metamod/plugins.ini"

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

# ---------- 7/8 - overlay repo + configuratii ----------
say "7/8 - Repository SECTIA 16 (pluginuri + configuri + sunete)..."
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

mkdir -p "${S16_DIR}/cstrike"
cp -r "${WORKDIR}/repo/cstrike/." "${S16_DIR}/cstrike/"

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
    say "harta ${S16_MAP}.bsp nu exista - folosesc de_dust2 (ruleaza tools/get_maps.sh \"${S16_DIR}\")."
    S16_MAP="de_dust2"
fi

chown -R "${S16_USER}:${S16_GROUP}" "${S16_DIR}"

# ---------- 8/8 - systemd + pornire + verificare ----------
say "8/8 - Serviciu systemd ${S16_SERVICE} + pornire..."
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
Environment=TZ=Europe/Bucharest
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

# asteptam pornirea (Steam auth + harta + AMXX)
say "Astept pornirea serverului..."
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
say " DOCTOR TERMINAT."
say "============================================================"
echo ""
if [ "${BOOTED}" -eq 1 ]; then
    say "Versiune engine:"
    python3 "${WORKDIR}/repo/tools/rcon.py" 127.0.0.1 "${S16_PORT}" "${RCON_PW}" "version" || true
    echo ""
    say "Pluginuri AMXX (verificat live prin RCON):"
    AMXX_OUT="$(python3 "${WORKDIR}/repo/tools/rcon.py" 127.0.0.1 "${S16_PORT}" "${RCON_PW}" "amxx plugins" || true)"
    echo "${AMXX_OUT}"
    echo ""
    S16_COUNT="$(echo "${AMXX_OUT}" | grep -c 'sectia16_.*running')"
    S16_EXPECT="$(grep -c '^sectia16_' "${WORKDIR}/repo/cstrike/addons/amxmodx/configs/plugins.ini" 2>/dev/null)"
    [ "${S16_EXPECT}" -ge 1 ] 2>/dev/null || S16_EXPECT=12
    if [ "${S16_COUNT}" -ge "${S16_EXPECT}" ] && [ "${S16_EXPECT}" -gt 0 ]; then
        say "VERIFICARE OK: ${S16_COUNT} pluginuri SECTIA 16 running (v2.1 = ${S16_EXPECT})."
    else
        say "ATENTIE: doar ${S16_COUNT} din ${S16_EXPECT} pluginuri sectia16 ruleaza."
        say "Vezi: journalctl -u ${S16_SERVICE} -n 50 --no-pager"
    fi
else
    say "ATENTIE: serverul nu a raspuns la RCON in ~60s."
    say "Vezi log-ul: journalctl -u ${S16_SERVICE} -n 50 --no-pager"
    say "Daca problema persista, ruleaza bootstrap-ul complet:"
    say "  curl -fsSL https://raw.githubusercontent.com/Pa7entt/sectia16-jb-server/main/tools/bootstrap.sh | sudo S16_DIR=${S16_DIR} bash"
fi
echo ""
echo "  Serviciu :  systemctl status ${S16_SERVICE}"
echo "  Live log :  journalctl -u ${S16_SERVICE} -f"
echo "  RCON     :  ${RCON_PW}  (salvat si in cstrike/server.cfg)"
echo "  Harta    :  ${S16_MAP}"
echo ""
