/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Reguli Microfon v2.0:
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
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Reguli Microfon"
#define VERSION "2.0.0"
#define AUTHOR  "SECTIA 16"

#define TASK_VOICE_RECHECK 626100

// cine a primit microfon acordat manual
new bool:g_bMicGranted[MAX_PLAYERS + 1];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /mic",      "CmdMic");
    register_clcmd("say_team /mic", "CmdMic");

    register_event("HLTV",     "EventNewRound", "a", "1=0", "2=0");
    register_event("TeamInfo", "EventTeamInfo", "a");

    // recalcul periodic de siguranta (ieftin: doar perechile blocate)
    set_task(2.0, "TaskVoiceRecheck", TASK_VOICE_RECHECK, _, _, "b");
}

public plugin_cfg()
{
    // toata lumea aude toata lumea; cine e mutat il mutam noi per pereche
    server_cmd("sv_alltalk 1");
    server_exec();
}

public client_disconnected(id)
{
    g_bMicGranted[id] = false;
}

public EventNewRound()
{
    // microfoanele acordate se reseteaza la fiecare runda
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

bool:CanPlayerTalk(const id)
{
    if (!is_user_connected(id))
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

// aplica matricea de audiere: muta toti teroristii neautorizati
public TaskVoiceRecheck()
{
    VoiceRecheck();
}

VoiceRecheck()
{
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");

    // 1) resetam toate overrride-urile
    for (new i = 0; i < iNum; i++)
        rg_reset_can_hear_player(iPlayers[i]);

    // 2) mutam, pentru fiecare ascultator, teroristii fara voie
    for (new i = 0; i < iNum; i++)
    {
        new iSender = iPlayers[i];

        if (get_member(iSender, m_iTeam) != TEAM_TERRORIST)
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
