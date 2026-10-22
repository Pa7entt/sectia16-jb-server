# SECTIA 16 — Jailbreak Counter-Strike 1.6

> **jb.sectia16.ro** — penitenciarul virtual de maximă securitate.
> Stack: **ReHLDS + ReGameDLL + ReAPI + AMX Mod X 1.10** (100% Pawn, zero SourcePawn).
> **v2.0** — rescriere completă: 10 pluginuri, crash-fix TE_BEAMPOINTS, Duminică = FREEday global, modele, voce, meniu M, muniție infinită CT.

[![Compile AMXX Plugins](https://github.com/Pa7entt/sectia16-jb-server/actions/workflows/compile.yml/badge.svg)](https://github.com/Pa7entt/sectia16-jb-server/actions/workflows/compile.yml)

---

## Ce e înăuntru (v2.0)

| Plugin | Ce face |
|---|---|
| `sectia16_core.amxx` | **Starea centrală**: credite (vault per SteamID, +25/kill CT, +10 HS, +5/minut), freeday individual + coada „freeday garantat runda viitoare", flag REBEL (T care rănește gardian), VIP (flag `t`) / admin (flag `y`), voce LR, bun venit, `/ajutor`, `/reguli`, `/credite`. |
| `sectia16_bhop.amxx` | **Bhop & surf uncapped**: hookchain `RG_PM_Move` (ReAPI) → `pm_fuser2 = 0.0` + auto-hop prin `pm_oldbuttons`, peste `sv_enablebunnyhopping 1`. Fără clamp-ul de 320 u/s. |
| `sectia16_simon.amxx` | **Simon / Warden**: `/simon` sau bind `+simon`. Meniu: Alege Ziua, **Muzică/Manele** (listă dinamică din `manele.ini` + Random + **STOP MUZICĂ**), **Fluierat STRICT AUDITIV/VIZUAL — zero îngheț**, **Trage Linia** (laser continuu, vezi crash-fix-ul de mai jos), **FreeDay Individual** (`/fd [nume]`), Deschide Celulele (`cells.ini` + fallback). Glow auriu + HUD permanent. |
| `sectia16_days.amxx` | **Sistem de zile cu rotație automată**: Luni = Ziua Box, Marți = Gun Day, Miercuri = Ascunselea (gardieni înghețați+orbi 40s), Joi = War Day, Vineri = Zombie Day, Sâmbătă = zi normală (Simon alege prin `/zi`), **Duminică = FREEday GLOBAL AUTOMAT** (toți deținuții primesc freeday + modelul dedicat). Zilele clasice rămân: Grătar, Protopopiat, Greva Foamei. |
| `sectia16_lr.amxx` | **Last Request** (ultimul deținut, `/lr`): Deagle la Cap (doar headshot-uri), **Shot 4 Shot** (deagle cu un glonț, pe rând), **Cowboy** (înghețați 3s spate în spate), Pălme Sănătoase (cutit 35 HP), Barbuț/Zaruri, Trivia (`trivia.ini`). **Recompensă la câștig: +3000 credite SAU FreeDay garantat runda viitoare** (meniu cu timeout). Voce pentru ambii participanți în timpul LR-ului. |
| `sectia16_shop.amxx` | **Shop secret** (`/shop`, deținuți): Vitamine (+50 HP), Feroarie (100 AP + căști), Pilă de Unghii, Pălincă 70° (viteză), Manta Invizibilă, Contrabandă (Deagle). Creditele vin din core. |
| `sectia16_models.amxx` | **Modele de jucători** (`models.ini`): CT non-Simon, CT Simon, T normal, T rebel, T freeday (inclusiv Duminică), 7 modele VIP (random per sesiune). Pre-cache + asignare automată; **modelele lipsă sunt ignorate — serverul nu pica niciodată**. |
| `sectia16_voice.amxx` | **Reguli microfon**: gardienii vorbesc liber oricând; teroriștii doar admin/VIP/microfon acordat (`/mic`, Simon sau admin, resetat pe rundă)/voce LR. `sv_alltalk 1` + mut per-pereche prin `rg_set_can_hear_player`, recalculat la orice schimbare. |
| `sectia16_ctequip.amxx` | **Echipament CT**: meniu de arme la spawn (AK47, M4A1, MP5, Famas, XM1014, M249) + kevlar/căști/defuser/Deagle. **Muniție infinită STRICT pentru AK47 + Deagle, STRICT pentru gardieni** — echipa se verifică la fiecare `CurWeapon`, deci un T care ridică arma de jos NU primește muniție infinită. |
| `sectia16_mmenu.amxx` | **Meniul tastei M** (`chooseteam` interceptat): schimbare echipă (T / CT / Spectatori) + **Setări Glow** (8 culori + OFF, doar VIP/Admini pot activa). |

Sunetele (fluierat, ding, manele, clopote, zaruri, grătar etc.) sunt **generate procedural** — vezi `tools/gen_sounds.py`. Fără mesaje generice de tipul „This server is using AMX Mod X" (`amxx.cfg` curat + `imessage`/`scrollmsg` dezactivate).

### Fix-ul de crash „Tragerea liniei" (TE_BEAMPOINTS / TE_BEAMCYLINDER)

v1 trimitea mesajul TE_BEAMPOINTS **fără** parametrii `startframe` + `framerate` — mesajul rămânea cu 2 bytes mai scurt decât citește parserul motorului → `Host_Error` / crash. v2:

1. **S16_DrawBeam / S16_DrawRing** (`include/sectia16.inc`) — ordinea **completă și corectă** a parametrilor TE_;
2. **S16_ValidPoint / S16_ClampPoint** — fiecare punct e clamp-uit și validat în limitele lumii (±4096);
3. verificări `is_user_connected` / `is_user_alive` / `pev_valid` înainte de orice mesaj de rețea;
4. laserul se desenează doar într-un task dedicat, cu validări la fiecare cadru.

```
sectia16-jb-server/
├── .github/workflows/compile.yml     # CI: compilează .sma -> .amxx (AMXX 1.10) la fiecare push
├── cstrike/
│   ├── server.cfg                    # identitate, retea, tickrate 1000, FastDL, sv_alltalk 1
│   ├── game.cfg                      # ReGameDLL: bhop uncapped + surf + cvar-uri pluginuri
│   ├── mapcycle.txt                  # harti jailbreak oficiale (pachetul loadcs.com)
│   ├── sound/sectia16/*.wav          # efecte audio (generate, ~1.9 MB)
│   └── addons/amxmodx/
│       ├── scripting/                # SURSELE .sma (+ include/ cu sectia16.inc si include-urile ReAPI)
│       ├── plugins/                  # binarele .amxx (compilate automat de CI)
│       └── configs/
│           ├── plugins.ini           # 11 pluginuri baza curate + 10 SECTIA 16 (core PRIMUL)
│           ├── amxx.cfg              # versiune CURATA (zero mesaje generice)
│           └── sectia16/
│               ├── models.ini        # caile modelelor (CT/Simon/T/Rebel/FreeDay/VIP)
│               ├── manele.ini        # playlist-ul Simonului (wav + mp3)
│               ├── trivia.ini        # 20 intrebari RO pentru LR Trivia
│               └── cells.ini         # targeturi celule per harta
└── tools/
    ├── bootstrap.sh                  # instalare completa Debian 13 (vezi mai jos)
    ├── doctor.sh                     # reparare rapida fara SteamCMD
    ├── get_maps.sh                   # pachetul oficial de harti JB de la loadcs.com (~100 MB)
    ├── get_models.sh                 # modelele gamebanana -> models/player/sectia16_*
    ├── gen_sounds.py                 # regenerarea efectelor sonore
    ├── rcon.py                       # client RCON GoldSrc (UDP)
    └── ci/                           # scripturile folosite de GitHub Actions
```

---

## Instalare — Debian 13 „Trixie" (64-bit)

### Varianta rapidă (o singură comandă)

Pe un server Debian 13 proaspăt, ca root:

```bash
curl -fsSL https://raw.githubusercontent.com/Pa7entt/sectia16-jb-server/main/tools/bootstrap.sh | sudo bash
```

Scriptul face totul: activează i386 multilib, instalează SteamCMD + HLDS (CS 1.6), ReHLDS, metamod-r, ReGameDLL_CS, ReAPI, AMX Mod X 1.10, clonează repo-ul, generează parolă RCON aleatoare și pornește serviciul `sectia16` (systemd, port 27015). La final verifică live, prin RCON, că pluginurile s-au încărcat.

Hartă alternativă: `S16_MAP=jail_xmf bash tools/bootstrap.sh` (fallback automat pe `de_dust2` dacă harta nu există).

Director personalizat (ex. `~/Documents/sv`) — userul care rulează serverul se deduce automat din cale:

```bash
curl -fsSL https://raw.githubusercontent.com/Pa7entt/sectia16-jb-server/main/tools/bootstrap.sh | sudo S16_DIR="$HOME/Documents/sv" bash
```

Variabile suportate: `S16_DIR` (director instalare), `S16_USER` (user dedicat, dedus automat), `S16_PORT` (implicit 27015), `S16_MAP` (implicit `jail_xmf`). Re-rularea scriptului = update complet (validate Steam + overlay repo + restart); parola RCON existentă se păstrează.

### Hărțile jailbreak (loadcs.com)

După bootstrap, instalează pachetul oficial de harti JB (30+ hărți + wad-uri + skybox-uri, ~100 MB):

```bash
sudo bash tools/get_maps.sh "$HOME/Documents/sv"
# sau: S16_DIR="$HOME/Documents/sv" bash tools/get_maps.sh
```

`mapcycle.txt` din repo conține deja selecția (jail_xmf, jail_armageddon, jail_beach_v3, jail_rats, jb_oasis, jb_snow etc.).

### Modelele de jucători (gamebanana)

```bash
sudo bash tools/get_models.sh "$HOME/Documents/sv"
```

Descarcă și instalează automat: CT (mods/730051), CT Simon (mods/224557), T (mods/224530), T rebel (mods/727403), T freeday (mods/224468) și 7 modele VIP (mods/724163, 730210, 730293, cats/12761, 719937, 716248, 723750). Dacă gamebanana blochează descărcarea automată, scriptul afișează link-ul și calea exactă pentru instalare manuală. **Modelele lipsă nu afectează deloc serverul** — pluginul folosește modelele default CS.

### Reparare rapidă (fără reinstalare)

Dacă serverul pornește fără pluginuri sau crapă cu `Couldn't get DLL API` (liblist.gam corupt, engine rămas vanilla, stack incomplet), rulează `doctor.sh` — reaplică ReHLDS + metamod-r + ReGameDLL_CS + ReAPI + AMX 1.10 + overlay-ul repo-ului, rescrie `liblist.gam` curat și verifică pluginurile prin RCON (~2 minute, fără SteamCMD):

```bash
curl -fsSL https://raw.githubusercontent.com/Pa7entt/sectia16-jb-server/main/tools/doctor.sh | sudo S16_DIR="$HOME/Documents/sv" bash
```

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
# AMXX 1.10.0.5487: binarul e amxmodx_mm_i386.so (verifica numele din dlls/)
echo "linux addons/amxmodx/dlls/amxmodx_mm_i386.so" | sudo tee /home/csserver/server/cstrike/addons/metamod/plugins.ini
#    ReAPI: addons/amxmodx/modules/reapi_amxx_i386.so din https://github.com/rehlds/ReAPI/releases

# 8. acest repo peste cstrike/ + hartile JB
git clone https://github.com/Pa7entt/sectia16-jb-server.git /tmp/s16
sudo cp -r /tmp/s16/cstrike/. /home/csserver/server/cstrike/
sudo bash /tmp/s16/tools/get_maps.sh /home/csserver/server
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
Environment=TZ=Europe/Bucharest
ExecStart=/home/csserver/server/hlds_run -game cstrike -port 27015 +map jail_xmf +maxplayers 32 -secure
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

> `TZ=Europe/Bucharest` e important: **Duminica = FREEday global** se decide după ora serverului (`get_time("%w")`).

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now sectia16
journalctl -u sectia16 -f     # log live
```

---

## Comenzi în joc

| Comandă | Cine | Ce face |
|---|---|---|
| `/simon` | gardian | devii Simon (+ `bind v +simon`) |
| `/meniu` | Simon | meniul Simonului (zile, muzică, fluierat, linie, freeday, celule) |
| `/zi` | Simon | alege/suprascrie ziua (blocat duminică) |
| `/fd [nume]` | Simon | FreeDay individual (meniu sau cu nume) |
| `/mic` | Simon/admin | acordă/retrage microfon unui deținut |
| `/lr` | ultimul deținut | Last Request (6 dueluri + recompensă) |
| `/shop` | deținut | shop secret (6 obiecte) |
| `/credite` | oricine | sold curent |
| `/ajutor`, `/reguli` | oricine | comenzi / regulament MOTD |
| tasta **M** | oricine | meniu personal: echipe + setări glow (VIP/admin) |

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

Compilarea trebuie să treacă cu **zero erori și zero warning-uri** — asta e bariera de calitate a proiectului. v2.0 a fost verificată suplimentar **end-to-end pe server real** (ReHLDS 3.15 + metamod-r + ReGameDLL 5.30 + AMXX 1.10.0.5487 + ReAPI): 21/21 pluginuri running, zero erori runtime, supraviețuiesc mapchange-ului.

## Configurare post-instalare

1. **RCON** — schimbă `rcon_password` din `cstrike/server.cfg` (bootstrapul îl generează aleator).
2. **Hărți JB** — `bash tools/get_maps.sh` (pachetul oficial loadcs.com); `mapcycle.txt` e deja complet.
3. **Modele** — `bash tools/get_models.sh` sau manual în căile din `configs/sectia16/models.ini`; **VIP = flag `t`**, admin = flag `y` în `users.ini`.
4. **Manele** — pune fișiere `.wav`/`.mp3` în `cstrike/sound/sectia16/manele/` și adaugă-le în `configs/sectia16/manele.ini` (format: `cale_sub_sound/fisier|Titlu`). Pachetul propriu: limewire.com/d/HBrpN#TokiqHVuhn.
5. **Celule** — targetname-urile ușilor în `configs/sectia16/cells.ini` (altfel fallback generic).
6. **Trivia** — întrebări în `configs/sectia16/trivia.ini` (format: `întrebare|răspuns,variantă`).
7. **FastDL** — urcă `sound/sectia16/` + `models/` + hărțile pe un web server și setează `sv_downloadurl`. Fără FastDL, clienții descarcă cu sv_allowdownload (lent).
8. **Client** — pentru melodii `.mp3`, jucătorii trebuie să aibă `MP3 volume` > 0 în setările audio.

## Cvar-uri utile

| Cvar | Implicit | Descriere |
|---|---|---|
| `s16_bhop` | `1` | bhop uncapped on/off |
| `s16_bhop_auto` | `1` | auto-bhop (SPACE ținut) |
| `s16_credits_kill` | `25` | credite per gardian lichidat (+`s16_credits_hs` la headshot) |
| `s16_credits_minute` | `5` | credite per minut de supraviețuire |
| `s16_cost_vitamine / _feroarie / _pila / _palinca / _manta / _contrabanda` | `600/500/500/400/900/1200` | prețuri shop |

## Convenții de cod (Pawn / AMXX 1.10)

- Doar **Pawn pentru AMX Mod X 1.10** — fără `char`, `view_as`, SourcePawn, C++.
- **ReAPI first**: `rg_set_user_team`, `rg_set_user_model`, `rg_give_item`, `rg_remove_all_items`, `rg_set_user_bpammo`, `rg_set_can_hear_player`, `rg_reset_can_hear_player`, hookchain-uri `RG_*` (`RG_PM_Move`, `RG_CBasePlayer_TakeDamage`, `RG_CBasePlayer_Spawn`); Fakemeta/Hamsandwich doar unde ReAPI nu are echivalent (render, trace, hitgroup-uri, `Ham_Weapon_PrimaryAttack` pentru Shot 4 Shot).
- Nativii cross-plugin se înregistrează în `plugin_natives()` (nu `plugin_init`) — altfel consumatorii nu se leagă la încărcare.
- Orice mesaj TE_* (temp entity) trece prin `S16_DrawBeam`/`S16_DrawRing` — parametri compleți + validări de limite ale lumii (fix-ul de crash).
- Include obligatorii: `amxmodx`, `reapi`, `fakemeta` (+ `sectia16` pentru utilitare comune).
- Textele în joc sunt în **română fără diacritice** (limitare charset GoldSrc HUD/chat).

## Depanare rapidă

| Simptom | Cauză / Soluție |
|---|---|
| `amxxpc: cannot execute` | lipsesc librăriile i386 → `sudo apt install libc6-i386 lib32stdc++6 lib32gcc-s1` |
| `unknown native s16_*` | `sectia16_core.amxx` trebuie să fie prima în `plugins.ini` |
| Pluginurile nu se încarcă | `meta list` în consolă — ReAPI cere ReHLDS **și** ReGameDLL active; rulează `doctor.sh` |
| `sv_autobunnyhopping: unknown command` | ReGameDLL nu e încărcat (verifică `gamedll dlls/cs.so` în metamod `config.ini`) |
| Crash la linia lui Simon | imposibil în v2 (fix TE_BEAMPOINTS); dacă reapare, verifică ziua din `console.log` |
| Duminica nu pornește freeday-ul | serverul nu e pe ora RO → `Environment=TZ=Europe/Bucharest` în systemd |
| Manelele nu se aud | fișierele trebuie să existe în `sound/sectia16/` + intrare în `manele.ini`; mp3 cere volum > 0 la client |
| SteamCMD `No subscription` | rulează `+app_update 90` de 2-3 ori (bug cunoscut) sau adaugă `+app_set_config 90 mod cstrike` |

---

**SECTIA 16** © 2025 — construit din beton, laserbeams (validați) și manele. `jb.sectia16.ro`
