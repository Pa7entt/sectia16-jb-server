/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Simon / Warden v2.1:
*     - /simon sau bind +simon -> primul gardian care cere preia functia
*     - MENIUL SIMONULUI:
*         1. Alege Ziua .............. deschide meniul zilelor (/zi)
*         2. Muzica / Manele ......... submeniu: alege melodia / random / STOP
*         3. Fluierat ................ ATENTIE sonora - STRICT AUDITIV/VIZUAL,
*                                     FARA INGHET AREA DETINUTILOR
*         4. Trage Linia ............. laser continuu in directia privirii
*                                     (FIX CRASH: parametri TE_BEAMPOINTS
*                                     completi + validari limite harta)
*         5. FreeDay Individual ...... /fd [nume] - acordat unui detinut anume
*         6. Deschide Celulele ....... targeturi din cells.ini / fallback generic
*         7. Minge Fotbal ............ arunca / ridica mingea (fizica in
*                                     sectia16_ball.amxx)
*         8. Renunta la Simon
*     - glow auriu + HUD permanent cu numele Simonului
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Simon"
#define VERSION "2.1.0"
#define AUTHOR  "SECTIA 16"

#define TASK_SIMON_HUD   621100
#define TASK_LASER_DRAW  621200

// targeturi de celule configurate per harta (cells.ini)
#define MAX_CELL_TARGETS 24
new g_szMapTargets[MAX_CELL_TARGETS][32];
new g_iMapTargets;

// muzica din configs/sectia16/manele.ini (cale sub sound/ | titlu)
#define MAX_SONGS 32
new g_szSongPath[MAX_SONGS][96];
new g_szSongTitle[MAX_SONGS][64];
new g_iSongCount;

new g_iSimon;
new g_iSpriteLaser;
new bool:g_bLaserOn[MAX_PLAYERS + 1];
new Float:g_flNextWhistle = 0.0;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /simon",      "CmdSimon");
    register_clcmd("say_team /simon", "CmdSimon");
    register_clcmd("+simon",          "CmdSimon");
    register_clcmd("-simon",          "CmdIgnore");
    register_clcmd("say /meniu",      "CmdMenu");
    register_clcmd("say_team /meniu", "CmdMenu");
    register_clcmd("say /fd",         "CmdFreeDay");
    register_clcmd("say_team /fd",    "CmdFreeDay");
    register_clcmd("say /freeday",    "CmdFreeDay");
    register_clcmd("say_team /freeday", "CmdFreeDay");
    register_clcmd("say",             "CmdSay");
    register_clcmd("say_team",        "CmdSay");

    register_event("HLTV",     "EventNewRound", "a", "1=0", "2=0");
    register_event("DeathMsg", "EventDeathMsg", "a");
    register_event("TeamInfo", "EventTeamInfo", "a");

    set_task(1.0, "TaskSimonHud", TASK_SIMON_HUD, _, _, "b");
    set_task(0.2, "TaskLaserDraw", TASK_LASER_DRAW, _, _, "b");
}

public plugin_natives()
{
    register_library("sectia16_simon");
    register_native("s16_get_simon",   "NativeGetSimon");
    register_native("s16_manea_random", "NativeManeaRandom");
    register_native("s16_stop_music",  "NativeStopMusic");
}

public plugin_cfg()
{
    LoadMapCells();
    LoadSongs();
}

public plugin_precache()
{
    g_iSpriteLaser = precache_model("sprites/laserbeam.spr");

    S16_PrecacheSound("sectia16/fluierat");
    S16_PrecacheSound("sectia16/buzzer");
    S16_PrecacheSound("sectia16/ding");
    S16_PrecacheSound("sectia16/win");

    for (new i = 0; i < g_iSongCount; i++)
        S16_PrecacheMusic(g_szSongPath[i]);
}

/* ====================================================
*   CLAIM SIMON
*  ==================================================== */

public CmdIgnore()
{
    return PLUGIN_HANDLED;
}

public CmdSimon(id)
{
    if (g_iSimon == id && is_user_connected(g_iSimon))
    {
        ShowWardenMenu(id);
        return PLUGIN_HANDLED;
    }

    if (!is_user_alive(id) || get_member(id, m_iTeam) != TEAM_CT)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Doar un gardian in viata poate deveni Simon.");
        return PLUGIN_HANDLED;
    }

    if (g_iSimon && is_user_connected(g_iSimon) && is_user_alive(g_iSimon))
    {
        new szName[32];
        get_user_name(g_iSimon, szName, charsmax(szName));
        S16_Print(id, "^4[SECTIA 16]^1 Simonul rundei este deja ^3%s^1.", szName);
        return PLUGIN_HANDLED;
    }

    g_iSimon = id;
    g_bLaserOn[id] = false;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    S16_RenderGlow(id, 255, 200, 0, 80);

    S16_PrintAll("^4[SECTIA 16]^3 %s^1 este noul SIMON! Ordinele lui sunt lege.", szName);
    S16_PlaySoundAll("sectia16/ding");

    set_dhudmessage(255, 200, 0, -1.0, 0.22, 0, 6.0, 3.0);
    show_dhudmessage(0, "*** SIMON: %s ***", szName);

    ShowWardenMenu(id);
    return PLUGIN_HANDLED;
}

public CmdMenu(id)
{
    if (id != g_iSimon)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Doar Simonul are acces la meniul de comenzi.");
        return PLUGIN_HANDLED;
    }

    ShowWardenMenu(id);
    return PLUGIN_HANDLED;
}

/* ====================================================
*   MENIUL WARDEN-ULUI
*  ==================================================== */

ShowWardenMenu(const id)
{
    new szTitle[96];
    formatex(szTitle, charsmax(szTitle), "\r[SECTIA 16] \yMeniul Simonului^n\dDetinuti in viata: \r%d", S16_CountAlive(TEAM_TERRORIST));

    new iMenu = menu_create(szTitle, "WardenMenuHandler");

    new szItem[96];

    formatex(szItem, charsmax(szItem), "\wAlege \rZiua^n\dBox, Gun Day, Ascunselea, War, Zombie...");
    menu_additem(iMenu, szItem, "1");

    formatex(szItem, charsmax(szItem), "\wMuzica / \yManele^n\dAlege, da la intamplare sau opreste");
    menu_additem(iMenu, szItem, "2");

    formatex(szItem, charsmax(szItem), "\wFluierat \r(Atentie!)^n\dStrict auditiv - NU ingheata pe nimeni");
    menu_additem(iMenu, szItem, "3");

    if (g_bLaserOn[id])
        formatex(szItem, charsmax(szItem), "\wTraseaza \yLinia: \rOPRIT^n\dLaser rosu pe sol, in directia ta");
    else
        formatex(szItem, charsmax(szItem), "\wTraseaza \yLinia: \rACTIV^n\dLaser rosu pe sol, in directia ta");
    menu_additem(iMenu, szItem, "4");

    formatex(szItem, charsmax(szItem), "\wFreeDay \yIndividual^n\dAcorda freeday unui detinut (/fd)");
    menu_additem(iMenu, szItem, "5");

    formatex(szItem, charsmax(szItem), "\wDeschide \rCelulele^n\dBuzzer + usi deschise");
    menu_additem(iMenu, szItem, "6");

    if (s16_ball_exists())
        formatex(szItem, charsmax(szItem), "\wMinge \yFotbal: \rPE SOL^n\dApasa pentru a o ridica de pe teren");
    else
        formatex(szItem, charsmax(szItem), "\wMinge \yFotbal^n\dArunc-o in teren, la picioarele tale");
    menu_additem(iMenu, szItem, "7");

    menu_additem(iMenu, "\rRenunta la Simon^n\dAltu' preia tigaia", "8");

    menu_setprop(iMenu, MPROP_EXITNAME, "Inchide");

    menu_display(id, iMenu, 0);
}

public WardenMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    if (id != g_iSimon || !is_user_alive(id))
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[3], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    switch (szInfo[0])
    {
        case '1': client_cmd(id, "say /zi");
        case '2': ShowMusicMenu(id);
        case '3': ActionWhistle(id);
        case '4': ActionLaserToggle(id);
        case '5': ShowFreeDayMenu(id);
        case '6': ActionCells(id, false);
        case '7': ActionBall(id);
        case '8': ActionResign(id);
    }

    if (szInfo[0] != '8' && is_user_connected(id))
        ShowWardenMenu(id);

    return PLUGIN_HANDLED;
}

/* ====================================================
*   FLUIERAT - STRICT AUDITIV/VIZUAL, ZERO INGHET
*  ==================================================== */

ActionWhistle(const id)
{
    new Float:fNow = get_gametime();
    if (fNow < g_flNextWhistle)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Mai lasa fluierul o clipa, ti-au ramas urechile fisiate.");
        return;
    }
    g_flNextWhistle = fNow + 3.0;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    // strict auditiv + vizual: sunet + inel de atentie in jurul Simonului
    S16_PlaySoundAll("sectia16/fluierat");

    new Float:fOrigin[3];
    pev(id, pev_origin, fOrigin);
    S16_DrawRing(g_iSpriteLaser, fOrigin, 350.0, 255, 90, 0, 12, 10);

    set_dhudmessage(255, 70, 0, -1.0, 0.25, 0, 6.0, 3.0);
    show_dhudmessage(0, "*** FLUIERAT DE LA %s ***^nAtentie, detinuti!", szName);

    S16_PrintAll("^4[SECTIA 16]^1 Fluierat de la ^3%s^1! Doar atentie - nimeni nu e inghetat.", szName);
}

/* ====================================================
*   TRAGE LINIA - FIX CRASH TE_BEAMPOINTS
*
*   v1 crapa pentru ca mesajul TE_BEAMPOINTS era trimis fara
*   startframe + framerate (2 bytes mai putin decat citeste
*   parserul motorului) si fara validari. Acum:
*     - se deseneaza doar daca Simon e CONECTAT si IN VIATA
*     - punctele sunt clamp-uite si validate in limitele lumii
*     - mesajul se trimite prin S16_DrawBeam (parametri completi)
*  ==================================================== */

ActionLaserToggle(const id)
{
    g_bLaserOn[id] = !g_bLaserOn[id];

    if (g_bLaserOn[id])
    {
        S16_PrintAll("^4[SECTIA 16]^1 Simonul a pornit ^3linia laser^1. Cine o trece, plateste.");
        S16_PlaySound(id, "sectia16/ding");
    }
    else
    {
        S16_PrintAll("^4[SECTIA 16]^1 Linia laser a fost oprita.");
    }
}

public TaskLaserDraw()
{
    if (!g_iSimon)
        return;

    new id = g_iSimon;

    // validari stricte inainte de orice mesaj de retea
    if (!g_bLaserOn[id] || !is_user_connected(id) || !is_user_alive(id))
        return;

    new iAim[3];
    get_user_origin(id, iAim, 3);   // 3 = punctul de contact al privirii

    new Float:fAim[3], Float:fDir[3], Float:fStart[3], Float:fEnd[3];
    fAim[0] = float(iAim[0]);
    fAim[1] = float(iAim[1]);
    fAim[2] = float(iAim[2]);

    velocity_by_aim(id, 1, fDir);
    fDir[2] = 0.0;

    new Float:fLen = floatsqroot(fDir[0] * fDir[0] + fDir[1] * fDir[1]);
    if (fLen < 0.0001)
        return;

    fDir[0] /= fLen;
    fDir[1] /= fLen;

    // linia pe sol, simetric in jurul punctului privit
    for (new i = 0; i < 3; i++)
    {
        fStart[i] = fAim[i] + fDir[i] * 450.0;
        fEnd[i]   = fAim[i] - fDir[i] * 450.0;
    }
    fStart[2] = fAim[2] + 6.0;
    fEnd[2]   = fAim[2] + 6.0;

    // S16_DrawBeam: clamp + validare limite lume + parametri TE completi
    S16_DrawBeam(g_iSpriteLaser, fStart, fEnd, 255, 40, 40, 2, 14);
}

/* ====================================================
*   FREEDAY INDIVIDUAL (/fd [nume] sau meniu)
*  ==================================================== */

public CmdSay(id)
{
    new szArgs[96];
    read_args(szArgs, charsmax(szArgs));
    remove_quotes(szArgs);
    trim(szArgs);

    if (!szArgs[0])
        return PLUGIN_CONTINUE;

    // "/fd <nume>" sau "/freeday <nume>"
    if (equali(szArgs, "/fd ", 4) || equali(szArgs, "/freeday ", 9))
    {
        new szCmd[16], szTarget[64];
        argbreak(szArgs, szCmd, charsmax(szCmd), szTarget, charsmax(szTarget));
        trim(szTarget);

        if (szTarget[0])
        {
            GrantFreeDayByName(id, szTarget);
            return PLUGIN_HANDLED;
        }
    }

    return PLUGIN_CONTINUE;
}

public CmdFreeDay(id)
{
    if (id != g_iSimon)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Doar Simonul poate acorda FreeDay individual.");
        return PLUGIN_HANDLED;
    }

    ShowFreeDayMenu(id);
    return PLUGIN_HANDLED;
}

ShowFreeDayMenu(const id)
{
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ae", "TERRORIST");

    if (!iNum)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Nu sunt detinuti in viata carora sa le acorzi freeday.");
        return;
    }

    new iMenu = menu_create("\r[SECTIA 16] \yFreeDay Individual^n\dAlege detinutul norocos", "FreeDayMenuHandler");

    new szName[40], szInfo[6], szItem[72];
    for (new i = 0; i < iNum; i++)
    {
        get_user_name(iPlayers[i], szName, charsmax(szName));
        num_to_str(iPlayers[i], szInfo, charsmax(szInfo));

        if (s16_has_freeday(iPlayers[i]))
            formatex(szItem, charsmax(szItem), "\w%s \d[deja are FD]", szName);
        else
            formatex(szItem, charsmax(szItem), "\w%s", szName);

        menu_additem(iMenu, szItem, szInfo);
    }

    menu_setprop(iMenu, MPROP_EXITNAME, "Inapoi");
    menu_display(id, iMenu, 0);
}

public FreeDayMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    if (id != g_iSimon)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[6], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    new iTarget = str_to_num(szInfo);

    if (!is_user_alive(iTarget) || get_member(iTarget, m_iTeam) != TEAM_TERRORIST)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Detinutul nu mai e valabil.");
        return PLUGIN_HANDLED;
    }

    GrantFreeDay(id, iTarget);
    return PLUGIN_HANDLED;
}

GrantFreeDayByName(const id, const szTarget[])
{
    if (id != g_iSimon)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Doar Simonul poate acorda FreeDay individual.");
        return;
    }

    new iTarget = FindPlayerByName(szTarget);

    if (!iTarget || !is_user_alive(iTarget) || get_member(iTarget, m_iTeam) != TEAM_TERRORIST)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Nu am gasit detinutul ^3%s^1.", szTarget);
        return;
    }

    GrantFreeDay(id, iTarget);
}

GrantFreeDay(const id, const iTarget)
{
    if (s16_has_freeday(iTarget))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Detinutul are deja freeday.");
        return;
    }

    s16_set_freeday(iTarget, true);
    S16_RenderGlow(iTarget, 0, 255, 0, 60);

    new szT[32], szS[32];
    get_user_name(iTarget, szT, charsmax(szT));
    get_user_name(id, szS, charsmax(szS));

    S16_PrintAll("^4[SECTIA 16]^1 Simonul ^3%s^1 i-a acordat ^4FreeDay^1 lui ^3%s^1!", szS, szT);
    S16_Print(iTarget, "^4[SECTIA 16]^1 Ai primit ^4FreeDay^1! Nimeni nu-ti poate da ordine.");

    S16_PlaySound(iTarget, "sectia16/win");
}

FindPlayerByName(const szName[])
{
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");

    new szCheck[40];

    // potrivire exacta, apoi partiala
    for (new i = 0; i < iNum; i++)
    {
        get_user_name(iPlayers[i], szCheck, charsmax(szCheck));
        if (equali(szCheck, szName))
            return iPlayers[i];
    }

    for (new i = 0; i < iNum; i++)
    {
        get_user_name(iPlayers[i], szCheck, charsmax(szCheck));
        if (containi(szCheck, szName) != -1)
            return iPlayers[i];
    }

    return 0;
}

/* ====================================================
*   MUZICA / MANELE (submeniu)
*  ==================================================== */

ShowMusicMenu(const id)
{
    new szTitle[128];
    formatex(szTitle, charsmax(szTitle), "\r[SECTIA 16] \yMuzica / Manele^n\dMelodii: \r%d^n\dPune fisiere in sound/sectia16/manele/", g_iSongCount);

    new iMenu = menu_create(szTitle, "MusicMenuHandler");

    if (g_iSongCount)
    {
        new szItem[96], szInfo[6];
        for (new i = 0; i < g_iSongCount; i++)
        {
            num_to_str(i, szInfo, charsmax(szInfo));
            formatex(szItem, charsmax(szItem), "\w%s", g_szSongTitle[i]);
            menu_additem(iMenu, szItem, szInfo);
        }

        menu_additem(iMenu, "\yMelodie Random^n\dNoriqa decide pentru tine", "r");
    }
    else
    {
        menu_additem(iMenu, "\dNicio melodie disponibila", "x");
    }

    menu_additem(iMenu, "\rSTOP MUZICA^n\dOreste instant sunetul pentru toti", "s");

    menu_setprop(iMenu, MPROP_EXITNAME, "Inapoi");
    menu_display(id, iMenu, 0);
}

public MusicMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    if (id != g_iSimon || !is_user_alive(id))
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[6], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    if (szInfo[0] == 'x')
        return PLUGIN_HANDLED;

    if (szInfo[0] == 's')
    {
        S16_StopMusicAll();
        S16_PrintAll("^4[SECTIA 16]^1 Simonul a oprit muzica. Tacere in aula!");
        return PLUGIN_HANDLED;
    }

    if (szInfo[0] == 'r')
    {
        PlaySong(id, random(g_iSongCount));
        return PLUGIN_HANDLED;
    }

    PlaySong(id, str_to_num(szInfo));
    return PLUGIN_HANDLED;
}

PlaySong(const id, const iSong)
{
    if (iSong < 0 || iSong >= g_iSongCount)
        return;

    if (!S16_PlayMusicAll(g_szSongPath[iSong]))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Fisierul ^3%s^1 lipseste de pe server.", g_szSongPath[iSong]);
        return;
    }

    new szName[32];

    if (id > 0)
    {
        get_user_name(id, szName, charsmax(szName));
        S16_PrintAll("^4[SECTIA 16]^1 Simonul ^3%s^1 a pornit muzica in penitenciar!", szName);
    }
    else
    {
        // id = 0: pornita de un admin, prin meniul admin
        S16_PrintAll("^4[SECTIA 16]^1 Un admin a pornit muzica in penitenciar!");
    }

    set_dhudmessage(255, 0, 255, -1.0, 0.32, 0, 8.0, 4.0);
    show_dhudmessage(0, "*** MUZICA GRATUITA: %s ***", g_szSongTitle[iSong]);

    // petele de lumina de petrecere in celule
    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_connected(i))
            S16_ScreenFade(i, 2, 1, random_num(60, 255), random_num(60, 255), random_num(60, 255), 70, 0x0001);
    }
}

/* ====================================================
*   MINGE FOTBAL (fizica in sectia16_ball.amxx)
*  ==================================================== */

ActionBall(const id)
{
    if (s16_ball_exists())
    {
        s16_ball_remove();
        S16_PrintAll("^4[SECTIA 16]^1 Simonul a ridicat mingea de pe teren. Meciul s-a terminat.");
    }
    else if (s16_ball_spawn(id))
    {
        S16_PrintAll("^4[SECTIA 16]^1 Simonul a aruncat ^3mingea de fotbal^1 in teren! Dribbling, detinuti!");
        S16_PlaySoundAll("sectia16/ding");
    }
    else
    {
        S16_Print(id, "^4[SECTIA 16]^1 Mingea nu a putut fi aruncata - priveste catre sol, intr-un spatiu liber.");
    }
}

/* ====================================================
*   CELULE (cells.ini + fallback)
*  ==================================================== */

ActionCells(const id, const bool:bQuiet)
{
    new iCount = 0;
    new iEnt;
    new szTarget[32];

    // 1) targeturi configurate explicit pentru harta curenta
    for (new i = 0; i < g_iMapTargets; i++)
    {
        iEnt = -1;
        while ((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "targetname", g_szMapTargets[i])) != 0)
        {
            dllfunc(DLLFunc_Use, iEnt, id);
            iCount++;
        }
    }

    // 2) fallback: butoane/usile cu nume sugestiv de celula
    if (!iCount)
    {
        iEnt = -1;
        while ((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "classname", "func_button")) != 0)
        {
            pev(iEnt, pev_target, szTarget, charsmax(szTarget));
            if (szTarget[0] && IsCellName(szTarget))
            {
                dllfunc(DLLFunc_Use, iEnt, id);
                iCount++;
            }
        }

        iEnt = -1;
        while ((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "classname", "func_door")) != 0)
        {
            pev(iEnt, pev_targetname, szTarget, charsmax(szTarget));
            if (szTarget[0] && IsCellName(szTarget))
            {
                dllfunc(DLLFunc_Use, iEnt, id);
                iCount++;
            }
        }
    }

    if (bQuiet)
        return iCount;

    if (iCount)
    {
        S16_PlaySoundAll("sectia16/buzzer");
        S16_PrintAll("^4[SECTIA 16]^1 Simonul a deschis celulele! (^3%d usi^1)", iCount);

        set_dhudmessage(0, 255, 0, -1.0, 0.30, 0, 6.0, 3.0);
        show_dhudmessage(0, "*** CELULE DESCHISE - LA PERETE, DETINUTI! ***");
    }
    else
    {
        S16_Print(id, "^4[SECTIA 16]^1 Nu am gasit celule automate pe harta.");
        S16_Print(id, "^4[SECTIA 16]^1 Configureaza addons/amxmodx/configs/sectia16/cells.ini");
    }

    return iCount;
}

ActionResign(const id)
{
    if (g_iSimon != id)
        return;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    S16_RenderReset(id);
    g_iSimon = 0;
    g_bLaserOn[id] = false;

    S16_PrintAll("^4[SECTIA 16]^1 ^3%s^1 a renuntat la functia de Simon. Cine urmeaza? (/simon)", szName);
}

/* ====================================================
*   EVENTS / CLEANUP
*  ==================================================== */

public EventNewRound()
{
    g_iSimon = 0;

    for (new id = 1; id <= MaxClients; id++)
        g_bLaserOn[id] = false;
}

public EventDeathMsg()
{
    new iVictim = read_data(2);
    if (iVictim && iVictim == g_iSimon)
    {
        new szName[32];
        get_user_name(iVictim, szName, charsmax(szName));

        S16_RenderReset(iVictim);
        g_iSimon = 0;
        g_bLaserOn[iVictim] = false;

        S16_PrintAll("^4[SECTIA 16]^1 Simonul ^3%s^1 a fost lichidat! Gardienii raman fara sef.", szName);
    }
}

public EventTeamInfo()
{
    new id = read_data(1);
    if (id && id == g_iSimon)
    {
        new szTeam[12];
        read_data(2, szTeam, charsmax(szTeam));

        if (!equali(szTeam, "CT"))
        {
            S16_RenderReset(g_iSimon);
            g_iSimon = 0;
            S16_PrintAll("^4[SECTIA 16]^1 Simonul a parasit echipa gardienilor. (/simon)");
        }
    }
}

public client_disconnected(id)
{
    g_bLaserOn[id] = false;

    if (id == g_iSimon)
    {
        g_iSimon = 0;
        S16_PrintAll("^4[SECTIA 16]^1 Simonul a evadat din server. Cine preia? (/simon)");
    }
}

/* ====================================================
*   HUD + NATIVE + CONFIGS
*  ==================================================== */

public TaskSimonHud()
{
    if (!g_iSimon || !is_user_connected(g_iSimon) || !is_user_alive(g_iSimon))
        return;

    new szName[32];
    get_user_name(g_iSimon, szName, charsmax(szName));

    set_hudmessage(255, 200, 0, 0.02, 0.28, 0, 0.0, 1.05, 0.0, 0.0, 3);
    show_hudmessage(0, "SIMON: %s", szName);
}

public NativeGetSimon(const iPlugin, const iParams)
{
    return g_iSimon;
}

/* ====================================================
*   NATIVES MUZICA - control admin, independent de Simon
*  ==================================================== */

public NativeManeaRandom(const iPlugin, const iParams)
{
    if (g_iSongCount <= 0)
        return 0;

    PlaySong(0, random(g_iSongCount));
    return 1;
}

public NativeStopMusic(const iPlugin, const iParams)
{
    S16_StopMusicAll();
    S16_PrintAll("^4[SECTIA 16]^1 Muzica a fost oprita de un admin. Liniste in penitenciar!");
    return 1;
}

LoadMapCells()
{
    new szPath[128];
    formatex(szPath, charsmax(szPath), "addons/amxmodx/configs/sectia16/cells.ini");

    new hFile = fopen(szPath, "rt");
    if (!hFile)
        return;

    new szMap[32];
    get_mapname(szMap, charsmax(szMap));

    new szLine[96], szSection[32];
    szSection[0] = 0;
    new bool:bCollect = false;

    while (fgets(hFile, szLine, charsmax(szLine)))
    {
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
            continue;

        if (szLine[0] == '[')
        {
            new iLen = strlen(szLine);
            if (iLen > 0 && szLine[iLen - 1] == ']')
                szLine[iLen - 1] = 0;

            copy(szSection, charsmax(szSection), szLine[1]);
            bCollect = bool:equali(szSection, szMap);
            continue;
        }

        if (bCollect && g_iMapTargets < MAX_CELL_TARGETS)
        {
            copy(g_szMapTargets[g_iMapTargets], charsmax(g_szMapTargets[]), szLine);
            g_iMapTargets++;
        }
    }

    fclose(hFile);
}

// manele.ini: "cale_sub_sound/fisier.wav|Titlu"
LoadSongs()
{
    new szPath[128];
    formatex(szPath, charsmax(szPath), "addons/amxmodx/configs/sectia16/manele.ini");

    new hFile = fopen(szPath, "rt");
    if (!hFile)
    {
        log_amx("[SECTIA 16] manele.ini lipseste - meniul de muzica va fi gol.");
        return;
    }

    new szLine[192], szPathPart[96], szTitlePart[64];

    while (fgets(hFile, szLine, charsmax(szLine)) && g_iSongCount < MAX_SONGS)
    {
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
            continue;

        new iPos = contain(szLine, "|");
        if (iPos <= 0)
            continue;

        // calea fisierului (sub sound/, cu extensie)
        new j = 0;
        for (new k = 0; k < iPos && j < charsmax(szPathPart); k++, j++)
            szPathPart[j] = szLine[k];
        szPathPart[j] = 0;

        // titlul afisat in meniu
        j = 0;
        for (new k = iPos + 1; szLine[k] && j < charsmax(szTitlePart); k++, j++)
            szTitlePart[j] = szLine[k];
        szTitlePart[j] = 0;

        trim(szPathPart);
        trim(szTitlePart);

        if (!szPathPart[0] || !szTitlePart[0])
            continue;

        copy(g_szSongPath[g_iSongCount], charsmax(g_szSongPath[]), szPathPart);
        copy(g_szSongTitle[g_iSongCount], charsmax(g_szSongTitle[]), szTitlePart);
        g_iSongCount++;
    }

    fclose(hFile);

    log_amx("[SECTIA 16] Manele incarcate: %d melodii.", g_iSongCount);
}

stock bool:IsCellName(const szName[])
{
    static const szKeys[][] = { "cel", "cell", "jail", "usa", "box", "cage", "gate" };

    for (new i = 0; i < sizeof(szKeys); i++)
    {
        if (containi(szName, szKeys[i]) != -1)
            return true;
    }
    return false;
}
