# SECTIA 16 — Jailbreak Counter-Strike 1.6

> **jb.sectia16.ro** — penitenciarul virtual de maximă securitate.
> Stack: **ReHLDS + ReGameDLL + ReAPI + AMX Mod X 1.10** (100% Pawn, zero SourcePawn).

[![Compile AMXX Plugins](https://github.com/Pa7entt/sectia16-jb-server/actions/workflows/compile.yml/badge.svg)](https://github.com/Pa7entt/sectia16-jb-server/actions/workflows/compile.yml)

---

## Ce e înăuntru

| Plugin | Descriere |
|---|---|
| `sectia16_core.amxx` | Bun venit, `/ajutor`, `/reguli` (MOTD), tips periodice. |
| `sectia16_bhop.amxx` | **Bhop & surf uncapped**: hookchain `RG_PM_Move` (ReAPI) → `pm_fuser2 = 0.0` + auto-hop prin `pm_oldbuttons`, peste `sv_enablebunnyhopping 1`. Fără clamp-ul de 320 u/s. |
| `sectia16_simon.amxx` | **Simon / Warden**: `/simon` sau bind `+simon`. Meniu: Fluierat (îngheață deținuții), Trasează Linie (laser `TE_BEAMPOINTS` pe sol), Deschide Celulele (targeturi din `cells.ini`), Muzică Gratuită (manele pe boxele secției). Glow auriu + HUD permanent. |
| `sectia16_days.amxx` | **Zile custom** (doar Simon, `/zi`): Ziua de Grătar (cuțite cu coadă de flăcări `TE_BEAMFOLLOW`, gardieni 2000 HP + „extinctoare” care îngheață), Protopopiat (AWP muniție infinită vs deținuți invizibili cu +150 viteză), Greva Foamei (gravitație 0.5, lovitură de foame la 10s, ultimul supraviețuitor câștigă 300 credite). |
| `sectia16_lr.amxx` | **Last Request**: Duel cu Deagle la Cap (doar headshot-uri, `Ham_TraceAttack`), Pălme Sănătoase (cutit 35 HP), Barbuț/Zaruri (zarul mic moare instant), Cine Știe Câștigă (trivia RO din `trivia.ini`, răspuns în chat). Câștigătorul: +100 HP, glow, +500 credite. |
| `sectia16_shop.amxx` | **Shop secret** (`/shop`, deținuți): Pilă de Unghii (deschide discret o ușă), Manea Loudspeaker (gărzile surde 5s — `rg_set_can_hear_player`), Pălincă 70° (viteză + fade 8s), Manta Invizibilă (80% invizibil 5s). Credite persistente în vault. |

Sunetele (fluierat, manele, clopote, zaruri, grătar etc.) sunt **generate procedural** — vezi `tools/gen_sounds.py`.

```
sectia16-jb-server/
├── .github/workflows/compile.yml     # CI: compilează .sma -> .amxx (AMXX 1.10) la fiecare push
├── cstrike/
│   ├── server.cfg                    # identitate, retea, tickrate 1000, FastDL
│   ├── game.cfg                      # ReGameDLL: bhop uncapped + surf + cvar-uri pluginuri
│   ├── mapcycle.txt
│   ├── sound/sectia16/*.wav          # efecte audio (generate, ~1.8 MB)
│   └── addons/amxmodx/
│       ├── scripting/                # SURSELE .sma (+ include/ cu sectia16.inc si include-urile ReAPI)
│       ├── plugins/                  # binarele .amxx (compilate automat de CI)
│       └── configs/
│           ├── plugins.ini
│           └── sectia16/             # trivia.ini (intrebari LR) + cells.ini (celule/harta)
└── tools/
    ├── bootstrap.sh                  # instalare completa Debian 13 (vezi mai jos)
    ├── gen_sounds.py                 # regenerarea efectelor sonore
    └── ci/                           # scripturile folosite de GitHub Actions
```

---

## Instalare — Debian 13 „Trixie” (64-bit)

### Varianta rapidă (o singură comandă)

Pe un server Debian 13 proaspăt, ca root:

```bash
curl -fsSL https://raw.githubusercontent.com/Pa7entt/sectia16-jb-server/main/tools/bootstrap.sh | sudo bash
```

Scriptul face totul: activează i386 multilib, instalează SteamCMD + HLDS (CS 1.6), ReHLDS, metamod-r, ReGameDLL_CS, ReAPI, AMX Mod X 1.10, clonează repo-ul, generează parolă RCON aleatoare și pornește serviciul `sectia16` (systemd, port 27015).

Hartă alternativă: `S16_MAP=jb_snow bash tools/bootstrap.sh` (fallback automat pe `de_dust2` dacă harta nu există).

### Varianta manuală (pășile din bootstrap)

```bash
# 1. i386 multilib + dependente
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install -y curl ca-certificates tar xz unzip git python3 \
                    libc6:i386 lib32gcc-s1 lib32stdc++6 lib32z1

# 2. utilizator dedicat
sudo useradd -m -s /bin/bash csserver

# 3. SteamCMD + HLDS (CS 1.6, ~1 GB)
sudo mkdir -p /opt/steamcmd
curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | sudo tar -xz -C /opt/steamcmd
sudo -u csserver /opt/steamcmd/steamcmd.sh +force_install_dir /home/csserver/server \
    +login anonymous +app_set_config 90 mod cstrike +app_update 90 validate +quit

# 4. ReHLDS (engine) - ultimul release: https://github.com/dreamstalker/rehlds/releases
#    dezarhiveaza bin/linux32/* peste /home/csserver/server/

# 5. metamod-r - https://github.com/theAsmodai/metamod-r/releases
#    addons/metamod/ in cstrike/ + liblist.gam:
#      gamedll_linux "addons/metamod/metamod_i386.so"

# 6. ReGameDLL_CS - https://github.com/s1lentq/ReGameDLL_CS/releases
#    bin/linux32/cstrike/dlls/cs.so -> cstrike/dlls/cs.so
#    in cstrike/addons/metamod/config.ini adauga:  gamedll dlls/cs.so

# 7. AMX Mod X 1.10 + modulul ReAPI
curl -fsSL https://github.com/alliedmodders/amxmodx/releases/download/1.10.0.5487/amxmodx-1.10.0-git5487-base-linux.tar.gz    | sudo tar -xz -C /home/csserver/server/cstrike/
curl -fsSL https://github.com/alliedmodders/amxmodx/releases/download/1.10.0.5487/amxmodx-1.10.0-git5487-cstrike-linux.tar.gz | sudo tar -xz -C /home/csserver/server/cstrike/
echo "linux addons/amxmodx/dlls/amxmodx_mm.so" | sudo tee /home/csserver/server/cstrike/addons/metamod/plugins.ini
#    ReAPI: addons/amxmodx/modules/reapi_amxx_i386.so din https://github.com/rehlds/ReAPI/releases

# 8. acest repo peste cstrike/
git clone https://github.com/Pa7entt/sectia16-jb-server.git /tmp/s16
sudo cp -r /tmp/s16/cstrike/. /home/csserver/server/cstrike/
sudo chown -R csserver:csserver /home/csserver/server
```

### systemd

```ini
# /etc/systemd/system/sectia16.service
[Unit]
Description=SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
After=network-online.target

[Service]
User=csserver
WorkingDirectory=/home/csserver/server
ExecStart=/home/csserver/server/hlds_run -game cstrike -port 27015 +map de_dust2 +maxplayers 32 -secure
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now sectia16
journalctl -u sectia16 -f     # log live
```

---

## Compilarea pluginurilor

**Automat (recomandat):** orice push care atinge `cstrike/` sau `tools/` declanșează
workflow-ul **Compile AMXX Plugins**, care compilează toate `sectia16_*.sma` cu
`amxxpc` 1.10 și comite binarele `.amxx` înapoi în repo (`[skip ci]`).

**Local (Debian/Ubuntu):**

```bash
sudo apt install -y libc6-i386 lib32stdc++6 lib32gcc-s1
bash tools/ci/setup_amxx.sh ~/toolchain-amxx          # descarca AMXX 1.10
bash tools/ci/compile.sh ~/toolchain-amxx/addons/amxmodx/scripting
```

Compilarea trebuie să treacă cu **zero erori și zero warning-uri** — asta e bariera de calitate a proiectului.

---

## Configurare post-instalare

1. **RCON** — schimbă `rcon_password` din `cstrike/server.cfg` (bootstrapul îl generează aleator).
2. **Hărți JB** — pune `jb_*.bsp` în `cstrike/maps/`, actualizează `mapcycle.txt` și pornește cu harta dorită (`systemctl edit sectia16` → `+map jb_harta`).
3. **Celule** — pentru precizie 100% pe harta ta, adaugă targetname-urile ușilor în `cstrike/addons/amxmodx/configs/sectia16/cells.ini` (altfel pluginul Simon folosește fallback-ul generic).
4. **Trivia** — adaugă/editează întrebări în `configs/sectia16/trivia.ini` (format: `întrebare | răspuns,variantă`).
5. **Admini** — `cstrike/addons/amxmodx/configs/users.ini`.
6. **FastDL** — urcă `cstrike/sound/sectia16/` (+ hărțile custom) pe un web server și setează `sv_downloadurl` în `server.cfg`.
7. **Modele custom** (opțional) — `models/sectia16/v_knife_flame.mdl` e încărcat automat de Ziua de Grătar dacă există (guard cu `file_exists`, zero erori dacă lipsește). Surse community: GameBanana & co.

## Cvar-uri utile

| Cvar | Implicit | Descriere |
|---|---|---|
| `s16_bhop` | `1` | bhop uncapped on/off |
| `s16_bhop_auto` | `1` | auto-bhop (SPACE ținut) |
| `s16_whistle_freeze` | `3` | secunde de îngheț la fluierat |
| `s16_credits_kill` | `25` | credite per gardian lichidat (+10 headshot) |
| `s16_credits_minute` | `5` | credite per minut de supraviețuire |
| `s16_cost_pila / _manea / _palinca / _manta` | `500/750/400/900` | prețuri shop |

## Convenții de cod (Pawn / AMXX 1.10)

- Doar **Pawn pentru AMX Mod X 1.10** — fără `char`, `view_as`, SourcePawn, C++.
- **ReAPI first**: `rg_set_user_team`, `rg_give_item`, `rg_remove_all_items`, `rg_set_user_bpammo`, `rg_set_can_hear_player`, hookchain-uri `RG_*` (`RG_PM_Move`, `RG_CBasePlayer_TakeDamage`); Fakemeta/Hamsandwich doar unde ReAPI nu are echivalent (render, teleporți, hitgroup-uri).
- Include obligatorii: `amxmodx`, `reapi`, `fakemeta` (+ `sectia16` pentru utilitare comune).
- Textele în joc sunt în **română fără diacritice** (limitare charset GoldSrc HUD/chat); diacriticele trăiesc doar în README și pe web.

## Depanare rapidă

| Simptom | Cauză / Soluție |
|---|---|
| `amxxpc: cannot execute` | lipsesc librăriile i386 → `sudo apt install libc6-i386 lib32stdc++6 lib32gcc-s1` |
| `[S16] Nu exista manele` | pune `sound/sectia16/*.wav` (sau rulează `python3 tools/gen_sounds.py`) |
| Pluginurile nu se încarcă | `meta list` în consolă — ReAPI cere ReHLDS **și** ReGameDLL active |
| `sv_autobunnyhopping: unknown command` | ReGameDLL nu e încărcat (verifică `gamedll dlls/cs.so` în metamod `config.ini`) |
| SteamCMD `No subscription` | rulează `+app_update 90` de 2-3 ori (bug cunoscut) sau adaugă `+app_set_config 90 mod cstrike` |

---

**SECTIA 16** © 2025 — construit din beton, laserbeams și manele. `jb.sectia16.ro`
