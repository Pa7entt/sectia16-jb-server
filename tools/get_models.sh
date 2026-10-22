#!/usr/bin/env bash
# ============================================================
#  SECTIA 16 - Modele de Jucatori (gamebanana)
#  Descarca modelele .mdl de pe gamebanana.com, le redenumeste
#  in structura models/player/sectia16_*/sectia16_*.mdl si le
#  instaleaza in cstrike/. models.ini e deja configurat in repo.
#
#  Usage:
#    ./get_models.sh                    -> instaleaza in /home/csserver/server
#    ./get_models.sh /cale/spre/server
#    S16_DIR=~/Documents/sv ./get_models.sh
#
#  Sloturi (vezi cstrike/addons/amxmodx/configs/sectia16/models.ini):
#    ct         gamebanana.com/mods/730051
#    ct_simon   gamebanana.com/mods/224557
#    t          gamebanana.com/mods/224530
#    t_rebel    gamebanana.com/mods/727403
#    t_freeday  gamebanana.com/mods/224468
#    vip        gamebanana.com/mods/724163 730210 730293
#               gamebanana.com/mods/cats/12761 719937 716248 723750
#
#  NOTA: gamebanana poate bloca descarcari automate (cloudflare).
#  Daca un download esueaza, ia arhiva manual din link-urile de mai
#  sus si pune .mdl-ul in calea afisata de script (aceeasi structura).
# ============================================================
set -euo pipefail

SERVER_DIR="${1:-${S16_DIR:-/home/csserver/server}}"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

if [ ! -d "${SERVER_DIR}/cstrike" ]; then
    echo "[s16] EROARE: ${SERVER_DIR}/cstrike nu exista. Da calea serverului ca argument."
    exit 1
fi

TMP="$(mktemp -d /tmp/sectia16-models.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

# slot | gamebanana mod id | destinatia .mdl
install_model() {
    local slot="$1" modid="$2" dest_rel="$3"
    local dest="${SERVER_DIR}/${dest_rel}"
    local dir
    dir="$(dirname "${dest}")"
    mkdir -p "${dir}"

    if [ -f "${dest}" ]; then
        echo "[s16] ${slot}: deja instalat (${dest_rel})"
        return 0
    fi

    echo "[s16] ${slot}: descarc gamebanana.com/mods/${modid} ..."
    local zip="${TMP}/${slot}.zip"
    if ! curl -fsSL --retry 2 -A "${UA}" -o "${zip}" "https://gamebanana.com/dl/${modid}"; then
        echo "[s16] ${slot}: DOWNLOAD ESUAT - descarca manual de pe gamebanana.com/mods/${modid}"
        echo "[s16]          si pune modelul in ${dest_rel}"
        return 1
    fi

    # dezarhivez si caut primul .mdl de player
    local xdir="${TMP}/${slot}"
    mkdir -p "${xdir}"
    if ! unzip -oq "${zip}" -d "${xdir}" 2>/dev/null; then
        if ! tar -xzf "${zip}" -C "${xdir}" 2>/dev/null; then
            echo "[s16] ${slot}: arhiva nu s-a putut dezarhiva (nici zip, nici tar.gz)"
            return 1
        fi
    fi

    local mdl
    mdl="$(find "${xdir}" -type f -iname '*.mdl' | head -1 || true)"
    if [ -z "${mdl}" ]; then
        echo "[s16] ${slot}: nu am gasit niciun .mdl in arhiva"
        return 1
    fi

    cp -f "${mdl}" "${dest}"
    echo "[s16] ${slot}: OK -> ${dest_rel}"
}

echo "[s16] Modele SECTIA 16 -> ${SERVER_DIR}"

install_model "ct"        "730051" "models/player/sectia16_ct/sectia16_ct.mdl"        || true
install_model "ct_simon"  "224557" "models/player/sectia16_ctsimon/sectia16_ctsimon.mdl" || true
install_model "t"         "224530" "models/player/sectia16_t/sectia16_t.mdl"           || true
install_model "t_rebel"   "727403" "models/player/sectia16_rebel/sectia16_rebel.mdl"   || true
install_model "t_freeday" "224468" "models/player/sectia16_freeday/sectia16_freeday.mdl" || true

install_model "vip1" "724163" "models/player/sectia16_vip1/sectia16_vip1.mdl" || true
install_model "vip2" "730210" "models/player/sectia16_vip2/sectia16_vip2.mdl" || true
install_model "vip3" "730293" "models/player/sectia16_vip3/sectia16_vip3.mdl" || true
install_model "vip4" "12761"  "models/player/sectia16_vip4/sectia16_vip4.mdl" || true
install_model "vip5" "719937" "models/player/sectia16_vip5/sectia16_vip5.mdl" || true
install_model "vip6" "716248" "models/player/sectia16_vip6/sectia16_vip6.mdl" || true
install_model "vip7" "723750" "models/player/sectia16_vip7/sectia16_vip7.mdl" || true

echo ""
echo "[s16] Rezumat:"
find "${SERVER_DIR}/models/player" -maxdepth 2 -name 'sectia16_*.mdl' 2>/dev/null | sort || true
echo "[s16] Modelele lipsa sunt ignorate automat de plugin (serverul ruleaza cu modele default)."
echo "[s16] NU uita: seteaza sv_downloadurl (FastDL) ca clientii sa descarce modelele!"
