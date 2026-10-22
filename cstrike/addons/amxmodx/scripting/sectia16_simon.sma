/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Simon / Warden:
*     - /simon sau bind +simon -> primul gardian care cere preia functia
*     - Meniul Simonului: Fluierat (inghet detinuti), Traseaza Linie (laser TE_BEAMPOINTS),
*       Deschide Celulele (targeturi din cells.ini / fallback generic), Muzica Gratuita (manele)
*     - glow auriu + HUD permanent cu numele Simonului
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Simon"
#define VERSION "1.0.0"
#define AUTHOR  "SECTIA 16"

#define TASK_SIMON_HUD 621100

new g_iSimon;
new g_iSpriteLaser;
new g_pCvarFreezeTime;

// targeturi de celule configurate per harta (cells.ini)
#define MAX_CELL_TARGETS 24
new g_szMapTargets[MAX_CELL_TARGETS][32];
new g_iMapTargets;

// muzica gratuita (spk paths fara extensie)
new const g_szSongs[][]  = { "sectia16/manea1", "sectia16/manea2" };
new const g_szTitles[][] = { "FARA NUMAR, BOSS!", "BA, IA ASCULTA ASTA!" };

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /simon",      "CmdSimon");
    register_clcmd("say_team /simon", "CmdSimon");
    register_clcmd("+simon",          "CmdSimon");
    register_clcmd("-simon",          "CmdIgnore");
    register_clcmd("say /meniu",      "CmdMenu");
    register_clcmd("say_team /meniu", "CmdMenu");

    register_event("HLTV",    "EventNewRound", "a", "1=0", "2=0");
    register_event("DeathMsg", "EventDeathMsg", "a");
    register_event("TeamInfo", "EventTeamInfo", "a");

    g_pCvarFreezeTime = register_cvar("s16_whistle_freeze", "3");

    set_task(1.0, "TaskSimonHud", TASK_SIMON_HUD, _, _, "b");
}

// nativii cross-plugin se inregistreaza AICI (nu in plugin_init) ca sa fie
// disponibili pluginurilor incarcate dupa acesta (days/lr ii folosesc)
public plugin_natives()
{
    register_library("sectia16_simon");
    register_native("s16_get_simon", "NativeGetSimon");
}

public plugin_cfg()
{
    LoadMapCells();
}

public plugin_precache()
{
    g_iSpriteLaser = precache_model("sprites/laserbeam.spr");

    S16_PrecacheSound("sectia16/fluierat");
    S16_PrecacheSound("sectia16/buzzer");
    S16_PrecacheSound("sectia16/manea1");
    S16_PrecacheSound("sectia16/manea2");
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

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    S16_RenderGlow(id, 255, 200, 0, 80);

    S16_PrintAll("^4[SECTIA 16]^3 %s^1 este noul SIMON! Ordinele lui sunt lege.", szName);
    S16_PlaySoundAll("sectia16/fluierat");

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
    formatex(szItem, charsmax(szItem), "\wFluierat / \rAtentie!^n\dFluier + inghet detinuti %d secunde", get_pcvar_num(g_pCvarFreezeTime));
    menu_additem(iMenu, szItem, "1");
    menu_additem(iMenu, "\wTraseaza \yLinie^n\dLaser rosu pe sol, in directia ta", "2");
    menu_additem(iMenu, "\wDeschide \rCelulele^n\dBuzzer + usi deschise", "3");
    menu_additem(iMenu, "\wMuzica \yGratuita^n\dManele pe boxele sectiei", "4");
    menu_additem(iMenu, "\rRenunta la Simon^n\dAltu' preia tigaia", "5");

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

    switch (szInfo[0])
    {
        case '1': ActionWhistle(id);
        case '2': ActionLaser(id);
        case '3': ActionCells(id, false);
        case '4': ActionMusic(id);
        case '5': ActionResign(id);
    }

    menu_destroy(iMenu);

    if (szInfo[0] != '5' && is_user_connected(id))
        ShowWardenMenu(id);

    return PLUGIN_HANDLED;
}

/* ====================================================
*   ACTIUNI WARDEN
*  ==================================================== */

ActionWhistle(const id)
{
    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    S16_PlaySoundAll("sectia16/fluierat");

    set_dhudmessage(255, 70, 0, -1.0, 0.25, 0, 6.0, 3.0);
    show_dhudmessage(0, "*** ATENTIE! DETINUTII SUNT INGHETATI ***");

    S16_PrintAll("^4[SECTIA 16]^1 Fluierat de la ^3%s^1! Detinutii stau pe loc ^3%d secunde^1.", szName, get_pcvar_num(g_pCvarFreezeTime));

    new Float:fFreeze = get_pcvar_float(g_pCvarFreezeTime);

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ae", "TERRORIST");
    for (new i = 0; i < iNum; i++)
    {
        S16_Freeze(iPlayers[i], fFreeze);
        S16_ScreenFade(iPlayers[i], 1, 1, 255, 90, 0, 90, 0x0001);
    }
}

ActionLaser(const id)
{
    new iAim[3];
    get_user_origin(id, iAim, 3);

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

    for (new i = 0; i < 3; i++)
    {
        fStart[i] = fAim[i] + fDir[i] * 450.0;
        fEnd[i]   = fAim[i] - fDir[i] * 450.0;
    }
    fStart[2] = fAim[2] + 6.0;
    fEnd[2]   = fAim[2] + 6.0;

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    write_coord(floatround(fStart[0]));
    write_coord(floatround(fStart[1]));
    write_coord(floatround(fStart[2]));
    write_coord(floatround(fEnd[0]));
    write_coord(floatround(fEnd[1]));
    write_coord(floatround(fEnd[2]));
    write_short(g_iSpriteLaser);
    write_byte(100);     // viata: 100 x 0.1s = 10 secunde
    write_byte(14);      // latime
    write_byte(0);       // amplitudine (0 = linie fixa)
    write_byte(255);     // R
    write_byte(40);      // G
    write_byte(40);      // B
    write_byte(220);     // luminozitate
    write_byte(35);      // viteza de scroll
    message_end();

    S16_PrintAll("^4[SECTIA 16]^1 Simonul a trasat o linie rosie pe sol. Cine o trece, plateste.");
}

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

ActionMusic(const id)
{
    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    new iIdx = random(sizeof(g_szSongs));

    if (!S16_CanPlay(g_szSongs[iIdx]))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Nu exista manele pe server. Pune fisiere in sound/sectia16/.");
        return;
    }

    client_cmd(0, "spk %s", g_szSongs[iIdx]);

    set_dhudmessage(255, 0, 255, -1.0, 0.32, 0, 8.0, 4.0);
    show_dhudmessage(0, "*** MUZICA GRATUITA: %s ***", g_szTitles[iIdx]);

    S16_PrintAll("^4[SECTIA 16]^1 Simonul ^3%s^1 a pornit muzica gratis in penitenciar!", szName);

    // petele de lumina de petrecere in celule
    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_connected(i))
            S16_ScreenFade(i, 2, 1, random_num(60, 255), random_num(60, 255), random_num(60, 255), 70, 0x0001);
    }
}

ActionResign(const id)
{
    if (g_iSimon != id)
        return;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    S16_RenderReset(id);
    g_iSimon = 0;

    S16_PrintAll("^4[SECTIA 16]^1 ^3%s^1 a renuntat la functia de Simon. Cine urmeaza? (/simon)", szName);
}

/* ====================================================
*   EVENTS / CLEANUP
*  ==================================================== */

public EventNewRound()
{
    g_iSimon = 0;
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
    if (id == g_iSimon)
    {
        g_iSimon = 0;
        S16_PrintAll("^4[SECTIA 16]^1 Simonul a evadat din server. Cine preia? (/simon)");
    }
}

/* ====================================================
*   HUD + NATIVE + CELLS.INI
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
