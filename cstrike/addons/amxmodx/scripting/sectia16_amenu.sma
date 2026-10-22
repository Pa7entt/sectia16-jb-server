/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Meniu Admin v2.1 (exclusiv Admin/Owner):
*
*   Comenzi: /admin, /amenu (chat sau team-chat)
*
*     1. BOTI - adauga un bot / umple serverul / scoate un bot /
*        scoate toti botii. Detectare AUTOMATA a modulului de
*        boti instalat: YaPB, PodBot mm sau botii Condition Zero.
*     2. SANCTIUNI - meniu cu toti jucatorii:
*          - Kick
*          - Ban 30 de minute / Ban PERMANENT
*          - BanIP 30 de minute / BanIP PERMANENT
*          - BanCT: interdictie PERMANENTA de a intra la gardieni
*            (persista in configs/sectia16/banct.ini, supravietuieste
*            la restart; jucatorul e redirectat automat la detinuti)
*          - Gag 10 minute (chat + microfon oprite, expirare automata)
*     3. MUZICA - melodie random sau STOP MUZICA, independent de
*        Simon (nativi din sectia16_simon).
*     4. MINGE FOTBAL - arunca / ridica mingea (sectia16_ball).
*
*   Nota: banurile/kick-ul folosesc comenzile standard amx_ban /
*   amx_banip / amx_kick din admincmd.amxx (deja in plugins.ini).
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <cvars>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Meniu Admin"
#define VERSION "2.1.0"
#define AUTHOR  "SECTIA 16"

#define GAG_MINUTES 10       // durata gag-ului din meniu

// ----- module de boti -----
enum (+= 1)
{
    BOT_NONE = 0,
    BOT_YAPB,
    BOT_PODBOT,
    BOT_CZ
}

new g_iBotMod = BOT_NONE;

// ----- BanCT (interdictie CT, persistenta) -----
#define MAX_BANCT 64
new g_szBannedCT[MAX_BANCT][40];
new g_iBannedCT;

// ----- targetul curent din meniul de sanctiuni -----
new g_iPunishTarget[MAX_PLAYERS + 1];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /admin",      "CmdAdminMenu");
    register_clcmd("say_team /admin", "CmdAdminMenu");
    register_clcmd("say /amenu",      "CmdAdminMenu");
    register_clcmd("say_team /amenu", "CmdAdminMenu");

    // blocheaza intrarea la CT a celor cu interdictie (jointeam direct,
    // din bind/consola - meniul M e deja protejat in sectia16_mmenu)
    register_clcmd("jointeam", "CmdJoinTeam");
}

public plugin_natives()
{
    register_library("sectia16_amenu");
    register_native("s16_is_banned_ct", "NativeIsBannedCT");
}

public plugin_cfg()
{
    DetectBotMod();
    LoadBannedCT();
}

public client_disconnected(id)
{
    g_iPunishTarget[id] = 0;
}

/* ====================================================
*   MENIUL PRINCIPAL
*  ==================================================== */

public CmdAdminMenu(id)
{
    if (!s16_is_admin(id))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Meniul admin e doar pentru... admini. Tu esti doar un curios.");
        return PLUGIN_HANDLED;
    }

    ShowAdminMenu(id);
    return PLUGIN_HANDLED;
}

ShowAdminMenu(const id)
{
    new iMenu = menu_create("\r[SECTIA 16] \yMeniu Admin^n\dPuterea absoluta. Foloseste-o cu cap.", "AdminMenuHandler");

    new szItem[96], szBot[20];

    switch (g_iBotMod)
    {
        case BOT_YAPB:   copy(szBot, charsmax(szBot), "YaPB");
        case BOT_PODBOT: copy(szBot, charsmax(szBot), "PodBot");
        case BOT_CZ:     copy(szBot, charsmax(szBot), "Boti CZ");
        default:         copy(szBot, charsmax(szBot), "inexistenti");
    }

    formatex(szItem, charsmax(szItem), "\wBoti \y(%s)^n\dAdauga, umple, scoate - detectare automata", szBot);
    menu_additem(iMenu, szItem, "bots");

    formatex(szItem, charsmax(szItem), "\wSanctiuni \rJucatori^n\dKick, Ban, BanIP, BanCT, Gag");
    menu_additem(iMenu, szItem, "punish");

    formatex(szItem, charsmax(szItem), "\wControl \yMuzica^n\dIndependent de Simon");
    menu_additem(iMenu, szItem, "music");

    if (s16_ball_exists())
        formatex(szItem, charsmax(szItem), "\wMinge \yFotbal: \rPE SOL^n\dApasa pentru a o ridica de pe teren");
    else
        formatex(szItem, charsmax(szItem), "\wMinge \yFotbal^n\dArunc-o in teren, la picioarele tale");
    menu_additem(iMenu, szItem, "ball");

    menu_setprop(iMenu, MPROP_EXITNAME, "Inchide");
    menu_display(id, iMenu, 0);
}

public AdminMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    if (!s16_is_admin(id))
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[12], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    switch (szInfo[0])
    {
        case 'b': ShowBotsMenu(id);
        case 'p': ShowPunishMenu(id);
        case 'm': ShowMusicMenu(id);
        case 'a':
        {
            if (s16_ball_exists())
            {
                s16_ball_remove();
                S16_PrintAll("^4[SECTIA 16]^1 Un admin a ridicat mingea de pe teren.");
            }
            else if (s16_ball_spawn(id))
            {
                S16_PrintAll("^4[SECTIA 16]^1 Un admin a aruncat ^3mingea de fotbal^1 in teren!");
                S16_PlaySoundAll("sectia16/ding");
            }
            else
            {
                S16_Print(id, "^4[SECTIA 16]^1 Mingea nu a putut fi aruncata - priveste catre sol, intr-un spatiu liber.");
            }

            ShowAdminMenu(id);
        }
    }

    return PLUGIN_HANDLED;
}

/* ====================================================
*   BOTI (YaPB / PodBot mm / CZ - detectare automata)
*  ==================================================== */

DetectBotMod()
{
    if (cvar_exists("yb_version") || cvar_exists("yapb_version"))
        g_iBotMod = BOT_YAPB;
    else if (cvar_exists("pb_version"))
        g_iBotMod = BOT_PODBOT;
    else if (cvar_exists("bot_quota"))
        g_iBotMod = BOT_CZ;
    else
        g_iBotMod = BOT_NONE;

    switch (g_iBotMod)
    {
        case BOT_YAPB:   log_amx("[SECTIA 16] Boti detectati: YaPB.");
        case BOT_PODBOT: log_amx("[SECTIA 16] Boti detectati: PodBot mm.");
        case BOT_CZ:     log_amx("[SECTIA 16] Boti detectati: botii Condition Zero.");
        default:         log_amx("[SECTIA 16] Niciun modul de boti detectat (instaleaza YaPB pentru boti).");
    }
}

ShowBotsMenu(const id)
{
    new szBot[20];

    switch (g_iBotMod)
    {
        case BOT_YAPB:   copy(szBot, charsmax(szBot), "YaPB");
        case BOT_PODBOT: copy(szBot, charsmax(szBot), "PodBot");
        case BOT_CZ:     copy(szBot, charsmax(szBot), "Boti CZ");
        default:         copy(szBot, charsmax(szBot), "negasiti");
    }

    new szTitle[96];
    formatex(szTitle, charsmax(szTitle), "\r[SECTIA 16] \yBoti (%s)^n\dBotul e prietenul tau", szBot);

    new iMenu = menu_create(szTitle, "BotsMenuHandler");

    if (g_iBotMod == BOT_NONE)
    {
        menu_additem(iMenu, "\dNiciun bot instalat^n\dInstaleaza YaPB in addons/ (yapb)", "x");
    }
    else
    {
        menu_additem(iMenu, "\wAdauga un bot^n\dIntra la echipa cu mai putini jucatori", "add");
        menu_additem(iMenu, "\wUmple cu boti^n\dServerul plesneste de uniforme", "fill");
        menu_additem(iMenu, "\wScoate un bot^n\dCel mai neajutorat pleaca acasa", "kick");
        menu_additem(iMenu, "\rScoate TOTI botii^n\dRevolutia masinilor, amanata", "kickall");
    }

    menu_setprop(iMenu, MPROP_EXITNAME, "Inapoi");
    menu_display(id, iMenu, 0);
}

public BotsMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        ShowAdminMenu(id);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[12], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    if (!s16_is_admin(id) || szInfo[0] == 'x')
        return PLUGIN_HANDLED;

    new bool:bDone = false;

    switch (szInfo[0])
    {
        case 'a':   // add
        {
            BotCommand("add");
            S16_PrintAll("^4[SECTIA 16]^1 Un admin a chemat un bot in penitenciar.");
            bDone = true;
        }
        case 'f':   // fill
        {
            BotCommand("fill");
            S16_PrintAll("^4[SECTIA 16]^1 Un admin umple sectia cu boti. Sa inceapa paradea!");
            bDone = true;
        }
        case 'k':
        {
            if (szInfo[4] == 'a')   // kickall
            {
                BotCommand("kickall");
                S16_PrintAll("^4[SECTIA 16]^1 Un admin a exterminat toti botii. Odihniti-va, soldati de plastic.");
            }
            else
            {
                BotCommand("kick");
                S16_PrintAll("^4[SECTIA 16]^1 Un admin a concediat un bot.");
            }
            bDone = true;
        }
    }

    if (bDone)
        ShowBotsMenu(id);

    return PLUGIN_HANDLED;
}

// trimite comanda potrivita modulului de boti instalat
BotCommand(const szAction[])
{
    switch (g_iBotMod)
    {
        case BOT_YAPB:
        {
            if (equal(szAction, "add"))           server_cmd("yapb add");
            else if (equal(szAction, "fill"))     server_cmd("yapb fill");
            else if (equal(szAction, "kick"))     server_cmd("yapb kick");
            else if (equal(szAction, "kickall")) { server_cmd("yapb kickall"); server_cmd("yapb kickbots"); }
        }
        case BOT_PODBOT:
        {
            if (equal(szAction, "add"))           server_cmd("pb add");
            else if (equal(szAction, "fill"))     server_cmd("pb fill");
            else if (equal(szAction, "kick"))     server_cmd("pb remove");
            else if (equal(szAction, "kickall")) { server_cmd("pb removeall"); server_cmd("pb remove_bots"); }
        }
        case BOT_CZ:
        {
            if (equal(szAction, "add"))           server_cmd("bot_add");
            else if (equal(szAction, "fill"))     server_cmd("bot_quota %d", get_maxplayers());
            else if (equal(szAction, "kick"))     server_cmd("bot_kick");
            else if (equal(szAction, "kickall"))  server_cmd("bot_kick all");
        }
    }

    server_exec();
}

/* ====================================================
*   SANCTIUNI - lista de jucatori
*  ==================================================== */

ShowPunishMenu(const id)
{
    new iMenu = menu_create("\r[SECTIA 16] \ySanctiuni Jucatori^n\dAlege vinovatul", "PunishPlayerHandler");

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");

    new szName[48], szAuth[40], szItem[80];
    for (new i = 0; i < iNum; i++)
    {
        if (iPlayers[i] == id)
            continue;   // nu te sanctiuni singur

        get_user_name(iPlayers[i], szName, charsmax(szName));
        get_user_authid(iPlayers[i], szAuth, charsmax(szAuth));

        new szTags[40];
        szTags[0] = 0;

        if (s16_is_admin(iPlayers[i]))
            copy(szTags, charsmax(szTags), " \r[ADMIN]");
        else if (s16_is_vip(iPlayers[i]))
            copy(szTags, charsmax(szTags), " \y[VIP]");

        if (IsBannedCT(iPlayers[i]))
            add(szTags, charsmax(szTags), " \r[BanCT]");
        if (s16_is_gagged(iPlayers[i]))
            add(szTags, charsmax(szTags), " \d[GAG]");

        formatex(szItem, charsmax(szItem), "\w%s%s", szName, szTags);
        menu_additem(iMenu, szItem, szAuth);
    }

    menu_setprop(iMenu, MPROP_EXITNAME, "Inapoi");
    menu_display(id, iMenu, 0);
}

public PunishPlayerHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        ShowAdminMenu(id);
        return PLUGIN_HANDLED;
    }

    if (!s16_is_admin(id))
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szAuth[40], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szAuth, charsmax(szAuth), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    // cautam jucatorul dupa SteamID (supravietuieste la paginarea meniului)
    new iTarget = find_player("c", szAuth);

    if (!iTarget || !is_user_connected(iTarget))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Jucatorul a plecat printre primii.");
        ShowPunishMenu(id);
        return PLUGIN_HANDLED;
    }

    g_iPunishTarget[id] = iTarget;
    ShowPlayerActionsMenu(id, iTarget);

    return PLUGIN_HANDLED;
}

ShowPlayerActionsMenu(const id, const iTarget)
{
    new szName[32], szTitle[96];
    get_user_name(iTarget, szName, charsmax(szName));
    formatex(szTitle, charsmax(szTitle), "\r[SECTIA 16] \y%s^n\dCe-i facem astazi?", szName);

    new iMenu = menu_create(szTitle, "PlayerActionsHandler");

    menu_additem(iMenu, "\wKick^n\dIl arunci in strada, cu bagaj la purtator", "kick");
    menu_additem(iMenu, "\wBan \y30 de minute^n\dO lectie de bune maniere", "ban30");
    menu_additem(iMenu, "\rBan \yPERMANENT^n\dPuscarias pe viata", "ban0");
    menu_additem(iMenu, "\wBanIP \y30 de minute^n\dFara proxy, te rog", "banip30");
    menu_additem(iMenu, "\rBanIP \yPERMANENT^n\dAdresa lui devine legenda", "banip0");

    if (IsBannedCT(iTarget))
        menu_additem(iMenu, "\wScoate \yinterdictia CT^n\dIarta-i pacatele de gardian", "unbanct");
    else
        menu_additem(iMenu, "\wBanCT \y(interdictie gardian)^n\dPersistenta - nu mai intra la CT", "banct");

    if (s16_is_gagged(iTarget))
        menu_additem(iMenu, "\wScoate \ygag-ul^n\dIi dam vocea inapoi", "ungag");
    else
    {
        new szGagItem[96];
        formatex(szGagItem, charsmax(szGagItem), "\wGag \y%d minute^n\dChat + microfon, oprite la buton", GAG_MINUTES);
        menu_additem(iMenu, szGagItem, "gag");
    }

    menu_additem(iMenu, "\dInapoi la lista de jucatori", "back");

    menu_setprop(iMenu, MPROP_EXITNAME, "Anuleaza");
    menu_display(id, iMenu, 0);
}

public PlayerActionsHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    if (!s16_is_admin(id))
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[12], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    new iTarget = g_iPunishTarget[id];

    if (szInfo[0] == 'b')   // back
    {
        ShowPunishMenu(id);
        return PLUGIN_HANDLED;
    }

    if (!iTarget || !is_user_connected(iTarget))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Jucatorul a plecat intre timp.");
        ShowPunishMenu(id);
        return PLUGIN_HANDLED;
    }

    new szT[32], szS[32];
    get_user_name(iTarget, szT, charsmax(szT));
    get_user_name(id, szS, charsmax(szS));

    new iUserId = get_user_userid(iTarget);

    // sanctiunile prin comenzile standard admincmd.amxx
    if (equal(szInfo, "kick"))
    {
        server_cmd("amx_kick #%d ^"SECTIA 16 - meniu admin^"", iUserId);
        S16_PrintAll("^4[SECTIA 16]^1 Adminul ^3%s^1 l-a dat afara pe ^3%s^1.", szS, szT);
    }
    else if (equal(szInfo, "ban30"))
    {
        server_cmd("amx_ban 30 #%d ^"SECTIA 16 - meniu admin^"", iUserId);
        S16_PrintAll("^4[SECTIA 16]^1 Adminul ^3%s^1 l-a interzis 30 de minute pe ^3%s^1.", szS, szT);
    }
    else if (equal(szInfo, "ban0"))
    {
        server_cmd("amx_ban 0 #%d ^"SECTIA 16 - meniu admin^"", iUserId);
        S16_PrintAll("^4[SECTIA 16]^1 Adminul ^3%s^1 l-a interzis ^4PERMANENT^1 pe ^3%s^1.", szS, szT);
    }
    else if (equal(szInfo, "banip30"))
    {
        server_cmd("amx_banip 30 #%d ^"SECTIA 16 - meniu admin^"", iUserId);
        S16_PrintAll("^4[SECTIA 16]^1 Adminul ^3%s^1 i-a banat IP-ul 30 de minute lui ^3%s^1.", szS, szT);
    }
    else if (equal(szInfo, "banip0"))
    {
        server_cmd("amx_banip 0 #%d ^"SECTIA 16 - meniu admin^"", iUserId);
        S16_PrintAll("^4[SECTIA 16]^1 Adminul ^3%s^1 i-a banat IP-ul ^4PERMANENT^1 lui ^3%s^1.", szS, szT);
    }
    else if (equal(szInfo, "banct"))
    {
        AddBanCT(iTarget);
        S16_PrintAll("^4[SECTIA 16]^1 Adminul ^3%s^1 i-a dat ^3interdictie de gardian^1 lui ^3%s^1.", szS, szT);
    }
    else if (equal(szInfo, "unbanct"))
    {
        RemoveBanCT(iTarget);
        S16_PrintAll("^4[SECTIA 16]^1 Adminul ^3%s^1 a ridicat interdictia de gardian a lui ^3%s^1.", szS, szT);
    }
    else if (equal(szInfo, "gag"))
    {
        s16_set_gagged(iTarget, GAG_MINUTES);
        S16_PrintAll("^4[SECTIA 16]^1 Adminul ^3%s^1 i-a dat ^3gag %d minute^1 lui ^3%s^1.", szS, GAG_MINUTES, szT);
    }
    else if (equal(szInfo, "ungag"))
    {
        s16_set_gagged(iTarget, 0);
        S16_PrintAll("^4[SECTIA 16]^1 Adminul ^3%s^1 i-a scos gag-ul lui ^3%s^1.", szS, szT);
    }

    if (is_user_connected(iTarget))
        ShowPlayerActionsMenu(id, iTarget);
    else
        ShowPunishMenu(id);

    return PLUGIN_HANDLED;
}

/* ====================================================
*   BANCT - interdictia persistenta de gardian
*  ==================================================== */

public CmdJoinTeam(id)
{
    if (!IsBannedCT(id))
        return PLUGIN_CONTINUE;

    new szArg[8];
    read_argv(1, szArg, charsmax(szArg));
    new iTeam = str_to_num(szArg);

    // 2 = CT, 5 = auto-assign (care poate ajunge la CT)
    if (iTeam == 2 || iTeam == 5)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Ai ^3interdictie de gardian^1. Te lasam sa suferi ca detinut.");
        client_cmd(id, "jointeam 1");
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

bool:IsBannedCT(const id)
{
    new szAuth[40];
    get_user_authid(id, szAuth, charsmax(szAuth));
    return IsAuthBannedCT(szAuth);
}

bool:IsAuthBannedCT(const szAuth[])
{
    for (new i = 0; i < g_iBannedCT; i++)
    {
        if (equal(g_szBannedCT[i], szAuth))
            return true;
    }
    return false;
}

AddBanCT(const iTarget)
{
    new szAuth[40];
    get_user_authid(iTarget, szAuth, charsmax(szAuth));

    if (IsAuthBannedCT(szAuth) || g_iBannedCT >= MAX_BANCT)
        return;

    copy(g_szBannedCT[g_iBannedCT], charsmax(g_szBannedCT[]), szAuth);
    g_iBannedCT++;

    // persista in banct.ini (supravietuieste la restart)
    new szPath[128];
    formatex(szPath, charsmax(szPath), "addons/amxmodx/configs/sectia16/banct.ini");

    new hFile = fopen(szPath, "a");
    if (hFile)
    {
        fprintf(hFile, "%s^n", szAuth);
        fclose(hFile);
    }
}

RemoveBanCT(const iTarget)
{
    new szAuth[40];
    get_user_authid(iTarget, szAuth, charsmax(szAuth));

    new bool:bFound = false;

    for (new i = 0; i < g_iBannedCT; i++)
    {
        if (!bFound && equal(g_szBannedCT[i], szAuth))
            bFound = true;

        if (bFound && i + 1 < g_iBannedCT)
            copy(g_szBannedCT[i], charsmax(g_szBannedCT[]), g_szBannedCT[i + 1]);
    }

    if (bFound)
    {
        g_iBannedCT--;
        SaveBannedCT();
    }
}

SaveBannedCT()
{
    new szPath[128];
    formatex(szPath, charsmax(szPath), "addons/amxmodx/configs/sectia16/banct.ini");

    new hFile = fopen(szPath, "w");
    if (!hFile)
        return;

    for (new i = 0; i < g_iBannedCT; i++)
        fprintf(hFile, "%s^n", g_szBannedCT[i]);

    fclose(hFile);
}

LoadBannedCT()
{
    new szPath[128];
    formatex(szPath, charsmax(szPath), "addons/amxmodx/configs/sectia16/banct.ini");

    new hFile = fopen(szPath, "r");
    if (!hFile)
        return;

    new szLine[48];
    while (fgets(hFile, szLine, charsmax(szLine)) && g_iBannedCT < MAX_BANCT)
    {
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
            continue;

        copy(g_szBannedCT[g_iBannedCT], charsmax(g_szBannedCT[]), szLine);
        g_iBannedCT++;
    }

    fclose(hFile);

    if (g_iBannedCT)
        log_amx("[SECTIA 16] Interdictii CT incarcate: %d.", g_iBannedCT);
}

public NativeIsBannedCT(const iPlugin, const iParams)
{
    new id = get_param(1);

    if (id < 1 || id > MaxClients || !is_user_connected(id))
        return false;

    return IsBannedCT(id);
}

/* ====================================================
*   MUZICA (independent de Simon)
*  ==================================================== */

ShowMusicMenu(const id)
{
    new iMenu = menu_create("\r[SECTIA 16] \yControl Muzica (Admin)^n\dIndependent de Simon", "AdminMusicHandler");

    menu_additem(iMenu, "\wMelodie \yRandom^n\dNorocul decide manea", "rand");
    menu_additem(iMenu, "\rSTOP MUZICA^n\dOprirea instantanee pentru toti", "stop");

    menu_setprop(iMenu, MPROP_EXITNAME, "Inapoi");
    menu_display(id, iMenu, 0);
}

public AdminMusicHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        ShowAdminMenu(id);
        return PLUGIN_HANDLED;
    }

    if (!s16_is_admin(id))
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[12], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    switch (szInfo[0])
    {
        case 'r':
        {
            if (!s16_manea_random())
                S16_Print(id, "^4[SECTIA 16]^1 Nicio melodie disponibila (manele.ini e gol).");
        }
        case 's':
        {
            s16_stop_music();
        }
    }

    ShowMusicMenu(id);
    return PLUGIN_HANDLED;
}
