#!/usr/bin/env bash
# ============================================================
#  SECTIA 16 - Modele de Jucatori (gamebanana.com)
#
#  Rezolva AUTOMAT link-ul real de download prin API-ul
#  gamebanana (apiv11) - pentru ca /dl/<fileid> NU este
#  acelasi numar cu /mods/<modid> - si instaleaza modelul
#  de player in structura models/player/sectia16_*.
#
#  Usage:
#    ./get_models.sh                      -> /home/csserver/server
#    ./get_models.sh /cale/spre/server
#    S16_DIR=~/Documents/sv ./get_models.sh
#    curl -fsSL https://raw.githubusercontent.com/Pa7entt/sectia16-jb-server/main/tools/get_models.sh | bash -s ~/Documents/sv
#
#  Sloturi (vezi cstrike/addons/amxmodx/configs/sectia16/models.ini):
#    ct         gamebanana.com/mods/730051  (CT Urban OMON)
#    ct_simon   gamebanana.com/mods/224557  (Creepy Horse Mask)
#    t          gamebanana.com/mods/224530  (Leet Prisoner v2)
#    t_rebel    gamebanana.com/mods/727403  (The Human Spider)
#    t_freeday  gamebanana.com/mods/224468  (Stylish Leet - Duminica)
#    vip1..vip7 gamebanana.com/mods/724163 730210 730293 227525(Goku)
#               719937 716248 723750
#
#  Depinde de: curl, unzip (zip) + unar/unrar/7z (rar).
#  Daca un model esueaza, serverul NU pica - pluginul ignora
#  modelele lipsa si foloseste modelele default.
# ============================================================
set -uo pipefail

SERVER_DIR="${1:-${S16_DIR:-/home/csserver/server}}"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
API="https://gamebanana.com/apiv11/Mod"
OK=0; FAIL=0

[ -d "${SERVER_DIR}/cstrike" ] || { echo "[s16] EROARE: ${SERVER_DIR}/cstrike nu exista. Da calea serverului ca argument."; exit 1; }

TMP="$(mktemp -d /tmp/sectia16-models.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

# ---------- unelte ----------
have() { command -v "$1" >/dev/null 2>&1; }

RAR_TOOL=""
for t in unar unrar 7z 7zz bsdtar; do have "$t" && { RAR_TOOL="$t"; break; }; done
if [ -z "${RAR_TOOL}" ]; then
    echo "[s16] AVERTISMENT: niciun extractor RAR gasit (unar/unrar/7z)."
    echo "[s16] Incerc sa instalez 'unar' (necesar pentru modelele .rar)..."
    if apt-get install -y unar >/dev/null 2>&1 || sudo apt-get install -y unar >/dev/null 2>&1; then
        RAR_TOOL="unar"; echo "[s16] 'unar' instalat."
    else
        echo "[s16] Nu am putut instala. Ruleaza manual:  sudo apt-get install -y unar"
        echo "[s16] Modelele .rar vor fi SARITE; cele .zip merg in continuare."
    fi
fi

# ---------- API gamebanana: mod id -> link real de download ----------
gb_resolve() {
    local modid="$1" json
    json="$(curl -fsSL --retry 2 -A "${UA}" "${API}/${modid}/ProfilePage" 2>/dev/null)" || return 1
    # python3 daca exista (parsing sigur), altfel grep
    if have python3; then
        printf '%s' "${json}" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin); files=d.get('_aFiles') or []
    if files: print(files[0].get('_sDownloadUrl',''))
except Exception: pass" 2>/dev/null
    else
        printf '%s' "${json}" | grep -oP '"_sDownloadUrl"\s*:\s*"\K[^"]+' | head -1
    fi
}

# ---------- dezarhivare universala (zip/rar/7z/tar) ----------
_try_extract() {
    local arc="$1" out="$2"
    mkdir -p "${out}"
    case "${arc}" in
        *.tar.gz|*.tgz) tar -xzf "${arc}" -C "${out}" 2>/dev/null ;;
        *.zip)
            unzip -oq "${arc}" -d "${out}" 2>/dev/null ;;
        *)
            case "${RAR_TOOL}" in
                unar)    unar -f -o "${out}" "${arc}" >/dev/null 2>&1 ;;
                unrar)   unrar x -y -o+ "${arc}" "${out}/" >/dev/null 2>&1 ;;
                7z|7zz)  "${RAR_TOOL}" x -y -o"${out}" "${arc}" >/dev/null 2>&1 ;;
                bsdtar)  bsdtar -xf "${arc}" -C "${out}" 2>/dev/null ;;
                *)       return 1 ;;
            esac ;;
    esac
}

UNAR_TRIED=0
extract_any() {
    local arc="$1" out="$2"
    _try_extract "${arc}" "${out}" && return 0
    # rar "solid" sau format exotic: instaleaza unar si reincearca o data
    if [ "${UNAR_TRIED}" -eq 0 ] && [ "${RAR_TOOL}" != "unar" ]; then
        UNAR_TRIED=1
        echo "[s16]    dezarhivatorul curent (${RAR_TOOL:-nimic}) a esuat - incerc 'unar' (suporta rar solid)..."
        if apt-get install -y unar >/dev/null 2>&1 || sudo apt-get install -y unar >/dev/null 2>&1; then
            RAR_TOOL="unar"
            _try_extract "${arc}" "${out}" && return 0
        fi
    fi
    return 1
}

# ---------- cauta modelul de PLAYER (exclude arme v_/w_/p_) ----------
# Prefera: cale cu /player/ > cel mai mare fisier .mdl
find_player_mdl() {
    local dir="$1" best="" bestsz=0 f sz
    while IFS= read -r -d '' f; do
        local base
        base="$(basename "${f}")"
        case "${base}" in
            v_*|w_*|p_*) continue ;;   # modele de arme, nu de player
        esac
        sz="$(stat -c%s "${f}" 2>/dev/null || echo 0)"
        if echo "${f}" | grep -qi '/player/'; then sz=$((sz + 100000000)); fi   # prioritate cale player
        if [ "${sz}" -gt "${bestsz}" ]; then best="${f}"; bestsz="${sz}"; fi
    done < <(find "${dir}" -type f -iname '*.mdl' -print0 2>/dev/null)
    [ -n "${best}" ] && printf '%s' "${best}"
}

# ---------- instaleaza un slot ----------
install_model() {
    local slot="$1" modid="$2" dest_rel="$3"
    local dest="${SERVER_DIR}/cstrike/${dest_rel}"
    mkdir -p "$(dirname "${dest}")"

    if [ -f "${dest}" ]; then
        echo "[s16] ${slot}: deja instalat (${dest_rel})"
        OK=$((OK+1)); return 0
    fi

    local name url
    name="$(basename "${dest}")"
    echo "[s16] ${slot}: gamebanana.com/mods/${modid} ..."

    url="$(gb_resolve "${modid}")"
    if [ -z "${url}" ]; then
        echo "[s16] ${slot}: API gamebanana inaccesibil - incearca mai tarziu"
        echo "[s16]          sau descarca manual de pe gamebanana.com/mods/${modid}"
        FAIL=$((FAIL+1)); return 1
    fi

    local arc="${TMP}/${slot}.arc"
    if ! curl -fsSL --retry 2 -A "${UA}" -o "${arc}" "${url}"; then
        echo "[s16] ${slot}: download esuat (${url})"
        FAIL=$((FAIL+1)); return 1
    fi

    local xdir="${TMP}/${slot}.x"
    if ! extract_any "${arc}" "${xdir}"; then
        echo "[s16] ${slot}: dezarhivare esuata - instaleaza 'unar' (sudo apt-get install -y unar)"
        FAIL=$((FAIL+1)); return 1
    fi

    local mdl
    mdl="$(find_player_mdl "${xdir}")"
    if [ -z "${mdl}" ]; then
        echo "[s16] ${slot}: niciun .mdl de player in arhiva - vezi gamebanana.com/mods/${modid}"
        FAIL=$((FAIL+1)); return 1
    fi

    cp -f "${mdl}" "${dest}"
    echo "[s16] ${slot}: OK  $(basename "${mdl}") -> ${dest_rel}"
    OK=$((OK+1))
}

echo "[s16] === SECTIA 16 - modele de jucatori ==="
echo "[s16] Server: ${SERVER_DIR}"
[ -n "${RAR_TOOL}" ] && echo "[s16] Extractor RAR: ${RAR_TOOL}"
echo ""

install_model "ct"       "730051" "models/player/sectia16_ct/sectia16_ct.mdl"
install_model "ct_simon" "224557" "models/player/sectia16_ctsimon/sectia16_ctsimon.mdl"
install_model "t"        "224530" "models/player/sectia16_t/sectia16_t.mdl"
install_model "t_rebel"  "727403" "models/player/sectia16_rebel/sectia16_rebel.mdl"
install_model "t_freeday" "224468" "models/player/sectia16_freeday/sectia16_freeday.mdl"
install_model "vip1"     "724163" "models/player/sectia16_vip1/sectia16_vip1.mdl"
install_model "vip2"     "730210" "models/player/sectia16_vip2/sectia16_vip2.mdl"
install_model "vip3"     "730293" "models/player/sectia16_vip3/sectia16_vip3.mdl"
install_model "vip4"     "227525" "models/player/sectia16_vip4/sectia16_vip4.mdl"
install_model "vip5"     "719937" "models/player/sectia16_vip5/sectia16_vip5.mdl"
install_model "vip6"     "716248" "models/player/sectia16_vip6/sectia16_vip6.mdl"
install_model "vip7"     "723750" "models/player/sectia16_vip7/sectia16_vip7.mdl"

echo ""
echo "[s16] === REZUMAT: ${OK} OK, ${FAIL} esuate ==="
find "${SERVER_DIR}/cstrike/models/player" -maxdepth 2 -name 'sectia16_*.mdl' 2>/dev/null | sort | sed 's/^/[s16]   /'
[ "${FAIL}" -gt 0 ] && echo "[s16] Modelele lipsa sunt IGNORATE automat de plugin (serverul ruleaza cu modele default)."
echo "[s16] IMPORTANT: pune modelele si pe FastDL (sv_downloadurl) ca clientii sa le descarce!"
exit 0
