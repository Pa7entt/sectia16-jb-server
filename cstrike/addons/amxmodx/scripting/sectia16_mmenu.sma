/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Meniul Tastei M v2.0:
*
*   La apasarea tastei M (chooseteam) apare un meniu personalizat:
*     - Schimbarea echipei (T / CT / Spectatori)
*     - Setari Glow personalizate (culoare stralucire, VIP/Admini;
*       optiune OFF disponibila pentru toata lumea)
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Meniu M (Echipe & Glow)"
#define VERSION "2.0.0"
#define AUTHOR  "SECTIA 16"

// culorile de glow
#define GLOW_COUNT 8
new const g_szGlowNames[GLOW_COUNT][] = { "Rosu", "Verde", "Albastru", "Galben", "Roz", "Cyan", "Alb", "Aurium" };
new const g_iGlowColors[GLOW_COUNT][3] =
{
    { 255, 30,  30 },
    {  30, 255,  30 },
    {  60, 120, 255 },
    { 255, 255,  30 },
    { 255,  60, 200 },
    {  60, 255, 255 },
    { 255, 255, 255 },
    { 255, 200,  10 }
};

new g_iGlowChoice[MAX_PLAYERS + 1];   // -1 = OFF
new Float:g_flNextSwitch[MAX_PLAYERS + 1];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("chooseteam", "CmdChooseTeam");

    register_event("HLTV", "EventNewRound", "a", "1=0", "2=0");
}

public client_putinserver(id)
{
    g_iGlowChoice[id] = -1;
    g_flNextSwitch[id] = 0.0;
}

public client_disconnected(id)
{
    g_iGlowChoice[id] = -1;
    g_flNextSwitch[id] = 0.0;
}

public EventNewRound()
{
    // glow-ul ales persista; doar cooldown-ul se reseteaza
    for (new id = 1; id <= MaxClients; id++)
        g_flNextSwitch[id] = 0.0;
}

/* ====================================================
*   MENIUL PRINCIPAL (tasta M)
*  ==================================================== */

public CmdChooseTeam(id)
{
    ShowMainMenu(id);
    return PLUGIN_HANDLED;
}

ShowMainMenu(const id)
{
    new iMenu = menu_create("\r[SECTIA 16] \yMeniu Jucator^n\dEchipe & setari personale", "MainMenuHandler");

    new szItem[96];

    formatex(szItem, charsmax(szItem), "\wDetinut \r(T)^n\dViata de puscarie, credite si shop");
    menu_additem(iMenu, szItem, "t");

    formatex(szItem, charsmax(szItem), "\wGardian \y(CT)^n\dPaza, ordine, echipament la spawn");
    menu_additem(iMenu, szItem, "ct");

    formatex(szItem, charsmax(szItem), "\wSpectator^n\dDoar privesti suferinta");
    menu_additem(iMenu, szItem, "spec");

    if (g_iGlowChoice[id] >= 0)
        formatex(szItem, charsmax(szItem), "\wSetari \yGlow^n\dCurent: \r%s", g_szGlowNames[g_iGlowChoice[id]]);
    else
        formatex(szItem, charsmax(szItem), "\wSetari \yGlow^n\dCurent: \dOFF");
    menu_additem(iMenu, szItem, "glow");

    menu_setprop(iMenu, MPROP_EXITNAME, "Inchide");
    menu_display(id, iMenu, 0);
}

public MainMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[6], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    switch (szInfo[0])
    {
        case 't':   SwitchTeam(id, TEAM_TERRORIST);
        case 'c':   SwitchTeam(id, TEAM_CT);
        case 's':   GoSpectator(id);
        case 'g':   ShowGlowMenu(id);
    }

    return PLUGIN_HANDLED;
}

/* ====================================================
*   SCHIMBAREA ECHIPEI
*  ==================================================== */

SwitchTeam(const id, const TeamName:team)
{
    new Float:fNow = get_gametime();

    if (fNow < g_flNextSwitch[id])
    {
        S16_Print(id, "^4[SECTIA 16]^1 Mai asteapta putin inainte sa schimbi echipa din nou.");
        return;
    }

    if (get_member(id, m_iTeam) == team)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Esti deja in echipa asta.");
        return;
    }

    g_flNextSwitch[id] = fNow + 5.0;

    // resetam glow-ul la schimbarea echipei (modelele isi vad de treaba lor)
    g_iGlowChoice[id] = -1;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    rg_set_user_team(id, team, MODEL_AUTO, true);

    if (is_user_alive(id))
        user_silentkill(id);

    switch (team)
    {
        case TEAM_TERRORIST: S16_PrintAll("^4[SECTIA 16]^3 %s^1 a intrat la puscariasii din sectie.", szName);
        case TEAM_CT:        S16_PrintAll("^4[SECTIA 16]^3 %s^1 s-a angajat ca gardian.", szName);
    }
}

GoSpectator(const id)
{
    new Float:fNow = get_gametime();

    if (fNow < g_flNextSwitch[id])
    {
        S16_Print(id, "^4[SECTIA 16]^1 Mai asteapta putin inainte sa schimbi echipa din nou.");
        return;
    }

    if (get_member(id, m_iTeam) == TEAM_SPECTATOR)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Esti deja spectator.");
        return;
    }

    g_flNextSwitch[id] = fNow + 5.0;
    g_iGlowChoice[id] = -1;

    if (is_user_alive(id))
        user_silentkill(id);

    rg_set_user_team(id, TEAM_SPECTATOR, MODEL_UNASSIGNED, true);
}

/* ====================================================
*   MENIUL GLOW
*  ==================================================== */

ShowGlowMenu(const id)
{
    new iMenu = menu_create("\r[SECTIA 16] \ySetari Glow^n\dGlow-ul e doar pentru \rVIP/Admini^n\dCelelalte pot folosi doar optiunea OFF", "GlowMenuHandler");

    new szItem[96], szInfo[6];

    if (s16_is_vip(id) || s16_is_admin(id))
    {
        for (new i = 0; i < GLOW_COUNT; i++)
        {
            if (g_iGlowChoice[id] == i)
                formatex(szItem, charsmax(szItem), "\r%s \y[ACTIV]", g_szGlowNames[i]);
            else
                formatex(szItem, charsmax(szItem), "\w%s", g_szGlowNames[i]);

            num_to_str(i, szInfo, charsmax(szInfo));
            menu_additem(iMenu, szItem, szInfo);
        }
    }
    else
    {
        menu_additem(iMenu, "\dGlow-ul e disponibil doar pentru VIP si admini", "x");
    }

    if (g_iGlowChoice[id] >= 0)
        menu_additem(iMenu, "\rOpreste Glow-ul^n\dRevii la normal", "off");
    else
        menu_additem(iMenu, "\rGlow: \dOFF^n\dEsti invizibil in multime", "off");

    menu_setprop(iMenu, MPROP_EXITNAME, "Inapoi");
    menu_display(id, iMenu, 0);
}

public GlowMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[6], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    if (szInfo[0] == 'x')
        return PLUGIN_HANDLED;

    if (szInfo[0] == 'o')   // off
    {
        g_iGlowChoice[id] = -1;

        if (is_user_alive(id))
            S16_RenderReset(id);

        S16_Print(id, "^4[SECTIA 16]^1 Glow oprit.");
        return PLUGIN_HANDLED;
    }

    // alegere culoare
    if (!s16_is_vip(id) && !s16_is_admin(id))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Glow-ul e doar pentru ^3VIP^1 si ^3admini^1. Suporta-te cu bani sau cu functie.");
        return PLUGIN_HANDLED;
    }

    new iColor = str_to_num(szInfo);

    if (iColor < 0 || iColor >= GLOW_COUNT)
        return PLUGIN_HANDLED;

    g_iGlowChoice[id] = iColor;

    if (is_user_alive(id))
        S16_RenderGlow(id, g_iGlowColors[iColor][0], g_iGlowColors[iColor][1], g_iGlowColors[iColor][2], 60);

    S16_Print(id, "^4[SECTIA 16]^1 Glow setat: ^3%s^1.", g_szGlowNames[iColor]);

    return PLUGIN_HANDLED;
}
