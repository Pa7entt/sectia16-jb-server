/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Reguli Microfon & Gag v2.1:
*
*     - Gardienii (CT) pot vorbi liber oricand (inclusiv Simon).
*     - Teroristii sunt restrictionati in mod normal:
*         * pot vorbi doar adminii, VIP-ii,
*         * detinutii care au primit microfon de la Simon/Admin (/mic),
*         * participantii la Last Request (voce LR).
*     - sv_alltalk 1 (toti aud toti) - mute-ul se face per pereche
*       prin rg_set_can_hear_player, recalculat la orice schimbare.
*     - /mic [nume] sau meniu - Simon/Admin acorda sau retrage microfonul
*       unui detinut (se reseteaza la fiecare runda).
*
*     NOU v2.1 - SISTEM GAG (pentru meniul admin):
*     - gag = mut COMPLET (chat + microfon), pentru X minute;
*     - chiar si un gardian poate fi pus sub gag de un admin;
*     - expirarea e automata (verificata la fiecare 2 secunde),
*       iar jucatorul e anuntat cand i se da vocea inapoi;
*     - nativele s16_set_gagged / s16_is_gagged sunt folosite de
*       meniul admin (sectia16_amenu).
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Reguli Microfon & Gag"
#define VERSION "2.1.0"
#define AUTHOR  "SECTIA 16"

#define TASK_VOICE_RECHECK 626100

// cine a primit microfon acordat manual
new bool:g_bMicGranted[MAX_PLAYERS + 1];

// gag: timestamp-ul (gametime) pana cand tine. 0.0 = fara gag
new Float:g_flGagUntil[MAX_PLAYERS + 1];
new Float:g_flNextGagNotice[MAX_PLAYERS + 1];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /mic",      "CmdMic");
    register_clcmd("say_team /mic", "CmdMic");

    // gag-ul blocheaza chat-ul complet (inclusiv comenzile /...)
    register_clcmd("say",      "CmdSayGag");
    register_clcmd("say_team", "CmdSayGag");

    register_event("HLTV",     "EventNewRound", "a", "1=0", "2=0");
    register_event("TeamInfo", "EventTeamInfo", "a");

    // recalcul periodic de siguranta + expirare automata gag
    set_task(2.0, "TaskVoiceRecheck", TASK_VOICE_RECHECK, _, _, "b");
}

public plugin_natives()
{
    register_library("sectia16_voice");
    register_native("s16_set_gagged", "NativeSetGagged");
    register_native("s16_is_gagged",  "NativeIsGagged");
}

public plugin_cfg()
{
    // toata lumea aude toata lumea; cine e mutat il mutam noi per pereche
    server_cmd("sv_alltalk 1");
    server_exec();
}

public client_putinserver(id)
{
    g_flGagUntil[id] = 0.0;
    g_flNextGagNotice[id] = 0.0;
}

public client_disconnected(id)
{
    g_bMicGranted[id] = false;
    g_flGagUntil[id] = 0.0;
    g_flNextGagNotice[id] = 0.0;
}

public EventNewRound()
{
    // microfoanele acordate se reseteaza la fiecare runda;
    // gag-ul este temporizat pe minute, NU se reseteaza pe runda
    for (new id = 1; id <= MaxClients; id++)
        g_bMicGranted[id] = false;
}

public EventTeamInfo()
{
    // schimbarea echipei poate schimba permisiunile
    VoiceRecheck();
}

/* ====================================================
*   CINE ARE VOCE
*  ==================================================== */

bool:IsGaggedNow(const id)
{
    return bool:(g_flGagUntil[id] > 0.0 && get_gametime() < g_flGagUntil[id]);
}

bool:CanPlayerTalk(const id)
{
    if (!is_user_connected(id))
        return false;

    // gag-ul adminului are prioritate absoluta - chiar si gardienii tac
    if (IsGaggedNow(id))
        return false;

    switch (get_member(id, m_iTeam))
    {
        case TEAM_CT:
            return true;    // gardienii vorbesc liber oricand

        case TEAM_TERRORIST:
        {
            // admin / VIP / voce LR / microfon acordat
            if (s16_is_admin(id) || s16_is_vip(id))
                return true;

            if (s16_is_lr_voice(id))
                return true;

            if (g_bMicGranted[id])
                return true;

            return false;
        }
    }

    return true;    // spectatori etc. - ii lasam in pace
}

/* ====================================================
*   GAG - blocarea chat-ului (cu anunt anti-spam)
*  ==================================================== */

public CmdSayGag(id)
{
    if (!IsGaggedNow(id))
        return PLUGIN_CONTINUE;

    new Float:fNow = get_gametime();

    if (fNow >= g_flNextGagNotice[id])
    {
        g_flNextGagNotice[id] = fNow + 5.0;
        S16_Print(id, "^4[SECTIA 16]^1 Esti ^3gag-uit^1 de un admin. Mai tac %.0f minute.", (g_flGagUntil[id] - fNow) / 60.0);
    }

    return PLUGIN_HANDLED;
}

/* ====================================================
*   MATRICEA DE AUDIERE
*  ==================================================== */

public TaskVoiceRecheck()
{
    // 1) expirarea automata a gag-urilor
    new Float:fNow = get_gametime();

    for (new id = 1; id <= MaxClients; id++)
    {
        if (g_flGagUntil[id] > 0.0 && fNow >= g_flGagUntil[id])
        {
            g_flGagUntil[id] = 0.0;

            if (is_user_connected(id))
                S16_Print(id, "^4[SECTIA 16]^1 Gag-ul a expirat. Poti vorbi iar - data viitoare cuminti.");
        }
    }

    // 2) reaplicam matricea de audiere
    VoiceRecheck();
}

VoiceRecheck()
{
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");

    // 1) resetam toate override-urile
    for (new i = 0; i < iNum; i++)
        rg_reset_can_hear_player(iPlayers[i]);

    // 2) mutam, pentru fiecare ascultator, vorbitorii fara voie
    for (new i = 0; i < iNum; i++)
    {
        new iSender = iPlayers[i];

        if (get_member(iSender, m_iTeam) != TEAM_TERRORIST && !IsGaggedNow(iSender))
            continue;

        if (CanPlayerTalk(iSender))
            continue;

        for (new j = 0; j < iNum; j++)
        {
            new iListener = iPlayers[j];

            if (iListener == iSender)
                continue;

            rg_set_can_hear_player(iListener, iSender, false);
        }
    }
}

/* ====================================================
*   /mic - acordarea microfonului de catre Simon/Admin
*  ==================================================== */

public CmdMic(id)
{
    if (s16_get_simon() != id && !s16_is_admin(id))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Doar Simonul sau un admin poate acorda microfonul.");
        return PLUGIN_HANDLED;
    }

    ShowMicMenu(id);
    return PLUGIN_HANDLED;
}

ShowMicMenu(const id)
{
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ae", "TERRORIST");

    if (!iNum)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Nu sunt detinuti in viata.");
        return;
    }

    new iMenu = menu_create("\r[SECTIA 16] \yMicrofoane Detinuti^n\dAcorda / retrage microfonul", "MicMenuHandler");

    new szName[48], szInfo[6], szItem[72];
    for (new i = 0; i < iNum; i++)
    {
        get_user_name(iPlayers[i], szName, charsmax(szName));
        num_to_str(iPlayers[i], szInfo, charsmax(szInfo));

        if (g_bMicGranted[iPlayers[i]])
            formatex(szItem, charsmax(szItem), "\w%s \y[MIC ON]", szName);
        else
            formatex(szItem, charsmax(szItem), "\w%s \d[mic off]", szName);

        menu_additem(iMenu, szItem, szInfo);
    }

    menu_setprop(iMenu, MPROP_EXITNAME, "Inchide");
    menu_display(id, iMenu, 0);
}

public MicMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[6], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    new iTarget = str_to_num(szInfo);

    if (!is_user_connected(iTarget) || !is_user_alive(iTarget) || get_member(iTarget, m_iTeam) != TEAM_TERRORIST)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Detinutul nu mai e valabil.");
        return PLUGIN_HANDLED;
    }

    g_bMicGranted[iTarget] = !g_bMicGranted[iTarget];

    new szT[32], szS[32];
    get_user_name(iTarget, szT, charsmax(szT));
    get_user_name(id, szS, charsmax(szS));

    if (g_bMicGranted[iTarget])
    {
        S16_PrintAll("^4[SECTIA 16]^1 ^3%s^1 i-a acordat microfonul lui ^3%s^1. Vorbeste cuminti!", szS, szT);
    }
    else
    {
        S16_PrintAll("^4[SECTIA 16]^1 ^3%s^1 i-a luat microfonul lui ^3%s^1. Tacere!", szS, szT);
    }

    VoiceRecheck();

    // reopen
    ShowMicMenu(id);

    return PLUGIN_HANDLED;
}

/* ====================================================
*   NATIVES GAG (folosite de meniul admin)
*  ==================================================== */

public NativeSetGagged(const iPlugin, const iParams)
{
    new id = get_param(1);

    if (id < 1 || id > MaxClients || !is_user_connected(id))
        return 0;

    new iMinutes = get_param(2);

    if (iMinutes > 0)
    {
        g_flGagUntil[id] = get_gametime() + iMinutes * 60.0;
        g_flNextGagNotice[id] = 0.0;
    }
    else
    {
        g_flGagUntil[id] = 0.0;
    }

    VoiceRecheck();
    return 1;
}

public NativeIsGagged(const iPlugin, const iParams)
{
    new id = get_param(1);

    if (id < 1 || id > MaxClients || !is_user_connected(id))
        return false;

    return IsGaggedNow(id);
}
