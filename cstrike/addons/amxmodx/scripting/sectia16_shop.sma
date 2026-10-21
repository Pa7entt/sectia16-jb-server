/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Shop Secret (doar detinuti):
*     - Pila de Unghii ............ deschide discret o usa din apropiere
*     - Manea Loudspeaker ......... manea asurzitoare + gardienii surzi 5 secunde
*     - Palinca 70 Grade .......... viteza +170 si ecran verzui 8 secunde
*     - Manta Invizibila .......... 80% invizibilitate 5 secunde
*   Credite: +25/kill CT, +5/minut, +500 LR castigat, +300 Greva castigata.
*   Persistenta: vault (per SteamID).
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Shop Secret"
#define VERSION "1.0.0"
#define AUTHOR  "SECTIA 16"

#define TASK_MAINTAIN 622100
#define TASK_MINUTE   622200

enum (+= 1)
{
    ITEM_PILA = 0,
    ITEM_MANEA,
    ITEM_PALINCA,
    ITEM_MANTA,
    ITEM_COUNT
}

new g_iCredits[MAX_PLAYERS + 1];
new bool:g_bItemUsed[MAX_PLAYERS + 1][ITEM_COUNT];

new Float:g_flPalincaUntil[MAX_PLAYERS + 1];
new Float:g_flMantaUntil[MAX_PLAYERS + 1];
new bool:g_bPalincaOn[MAX_PLAYERS + 1];
new bool:g_bMantaOn[MAX_PLAYERS + 1];

new Float:g_flDeafenUntil;
new bool:g_bDeafening;

new g_pCvarKill;
new g_pCvarMinute;
new g_pCvarCost[ITEM_COUNT];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /shop",      "CmdShop");
    register_clcmd("say_team /shop", "CmdShop");

    register_event("HLTV",     "EventNewRound", "a", "1=0", "2=0");
    register_event("DeathMsg", "EventDeathMsg", "a");

    g_pCvarKill              = register_cvar("s16_credits_kill",   "25");
    g_pCvarMinute            = register_cvar("s16_credits_minute", "5");
    g_pCvarCost[ITEM_PILA]    = register_cvar("s16_cost_pila",    "500");
    g_pCvarCost[ITEM_MANEA]   = register_cvar("s16_cost_manea",   "750");
    g_pCvarCost[ITEM_PALINCA] = register_cvar("s16_cost_palinca", "400");
    g_pCvarCost[ITEM_MANTA]   = register_cvar("s16_cost_manta",   "900");

    register_library("sectia16_shop");
    register_native("s16_get_credits", "NativeGetCredits");
    register_native("s16_add_credits", "NativeAddCredits");

    set_task(60.0, "TaskMinuteCredits", TASK_MINUTE,   _, _, "b");
    set_task(0.25, "TaskMaintain",      TASK_MAINTAIN, _, _, "b");
}

public plugin_precache()
{
    S16_PrecacheSound("sectia16/manea_loud");
    S16_PrecacheSound("sectia16/palinca");
    S16_PrecacheSound("sectia16/buzzer");
}

/* ====================================================
*   CREDITE (vault)
*  ==================================================== */

public client_authorized(id)
{
    g_iCredits[id] = 0;
    arrayset(g_bItemUsed[id], false, ITEM_COUNT);
    g_flPalincaUntil[id] = 0.0;
    g_flMantaUntil[id] = 0.0;
    g_bPalincaOn[id] = false;
    g_bMantaOn[id] = false;

    new szAuth[40], szKey[64], szData[16];
    get_user_authid(id, szAuth, charsmax(szAuth));
    formatex(szKey, charsmax(szKey), "s16_credits_%s", szAuth);

    get_vaultdata(szKey, szData, charsmax(szData));
    if (szData[0])
        g_iCredits[id] = str_to_num(szData);
}

public client_disconnected(id)
{
    SaveCredits(id);

    g_iCredits[id] = 0;
    arrayset(g_bItemUsed[id], false, ITEM_COUNT);
    g_flPalincaUntil[id] = 0.0;
    g_flMantaUntil[id] = 0.0;
    g_bPalincaOn[id] = false;
    g_bMantaOn[id] = false;
}

SaveCredits(const id)
{
    if (is_user_bot(id))
        return;

    new szAuth[40], szKey[64], szData[16];
    get_user_authid(id, szAuth, charsmax(szAuth));
    formatex(szKey, charsmax(szKey), "s16_credits_%s", szAuth);
    formatex(szData, charsmax(szData), "%d", g_iCredits[id]);
    set_vaultdata(szKey, szData);
}

/* ====================================================
*   MENIU SHOP
*  ==================================================== */

public CmdShop(id)
{
    if (!is_user_alive(id) || get_member(id, m_iTeam) != TEAM_TERRORIST)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Shop-ul e doar pentru detinuti in viata.");
        return PLUGIN_HANDLED;
    }

    new szTitle[96];
    formatex(szTitle, charsmax(szTitle), "\r[SECTIA 16] \yShop Secret^n\dCredite: \r%d", g_iCredits[id]);

    new iMenu = menu_create(szTitle, "ShopHandler");

    new iCallback = menu_makecallback("ShopItemCallback");
    new szItem[128];

    formatex(szItem, charsmax(szItem), "\wPila de Unghii^n\dDeschide discret o usa apropiata \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_PILA]));
    menu_additem(iMenu, szItem, "0", _, iCallback);

    formatex(szItem, charsmax(szItem), "\wManea \rLoudspeaker^n\dGardienii surzi 5 secunde \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_MANEA]));
    menu_additem(iMenu, szItem, "1", _, iCallback);

    formatex(szItem, charsmax(szItem), "\wPalinca \y70 Grade^n\dViteza + ecran verzui 8 secunde \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_PALINCA]));
    menu_additem(iMenu, szItem, "2", _, iCallback);

    formatex(szItem, charsmax(szItem), "\wManta \dInvizibila^n\d80%% invizibilitate 5 secunde \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_MANTA]));
    menu_additem(iMenu, szItem, "3", _, iCallback);

    menu_setprop(iMenu, MPROP_EXITNAME, "Inchide");
    menu_display(id, iMenu, 0);

    return PLUGIN_HANDLED;
}

public ShopItemCallback(const id, const iMenu, const iItem)
{
    new iAccess, szInfo[3], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);

    new iIdx = str_to_num(szInfo);

    if (g_bItemUsed[id][iIdx] || g_iCredits[id] < get_pcvar_num(g_pCvarCost[iIdx]))
        return ITEM_DISABLED;

    return ITEM_ENABLED;
}

public ShopHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    if (!is_user_alive(id) || get_member(id, m_iTeam) != TEAM_TERRORIST)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[3], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    new iIdx = str_to_num(szInfo);
    new iCost = get_pcvar_num(g_pCvarCost[iIdx]);

    if (g_bItemUsed[id][iIdx])
    {
        S16_Print(id, "^4[SECTIA 16]^1 Ai folosit deja obiectul asta in runda curenta.");
        return PLUGIN_HANDLED;
    }

    if (g_iCredits[id] < iCost)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Nu ai destule credite. Iti trebuie ^3%d^1.", iCost);
        return PLUGIN_HANDLED;
    }

    new bool:bSuccess = false;

    switch (iIdx)
    {
        case ITEM_PILA:    bSuccess = BuyPila(id);
        case ITEM_MANEA:   bSuccess = BuyManea(id);
        case ITEM_PALINCA: bSuccess = BuyPalinca(id);
        case ITEM_MANTA:   bSuccess = BuyManta(id);
    }

    if (!bSuccess)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Achizitia a esuat, creditele raman la locul lor.");
        return PLUGIN_HANDLED;
    }

    g_iCredits[id] -= iCost;
    g_bItemUsed[id][iIdx] = true;
    SaveCredits(id);

    S16_Print(id, "^4[SECTIA 16]^1 Achizitie reusita! Credite ramase: ^3%d^1.", g_iCredits[id]);

    return PLUGIN_HANDLED;
}

/* ====================================================
*   OBIECTE
*  ==================================================== */

bool:BuyPila(const id)
{
    new Float:fMyOrigin[3], Float:fMin[3], Float:fMax[3], Float:fCenter[3];
    pev(id, pev_origin, fMyOrigin);

    new iBest = 0;
    new Float:fBestDist = 280.0;

    new const szClasses[][] = { "func_door", "func_door_rotating", "func_button" };

    for (new c = 0; c < sizeof(szClasses); c++)
    {
        new iEnt = -1;
        while ((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "classname", szClasses[c])) != 0)
        {
            pev(iEnt, pev_absmin, fMin);
            pev(iEnt, pev_absmax, fMax);

            fCenter[0] = (fMin[0] + fMax[0]) * 0.5;
            fCenter[1] = (fMin[1] + fMax[1]) * 0.5;
            fCenter[2] = (fMin[2] + fMax[2]) * 0.5;

            new Float:fDist = get_distance_f(fMyOrigin, fCenter);
            if (fDist < fBestDist)
            {
                fBestDist = fDist;
                iBest = iEnt;
            }
        }
    }

    if (!iBest)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Nu e nicio usa in raza de 280 de unitati. Piticanie!");
        return false;
    }

    dllfunc(DLLFunc_Use, iBest, id);

    S16_PlaySound(id, "sectia16/buzzer");
    S16_Print(id, "^4[SECTIA 16]^1 Ai pil it usa cu Pila de Unghii. Doar tu stii.");

    return true;
}

bool:BuyManea(const id)
{
    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    g_flDeafenUntil = get_gametime() + 5.0;

    client_cmd(0, "spk sectia16/manea_loud");

    set_dhudmessage(255, 0, 255, -1.0, 0.30, 0, 8.0, 4.0);
    show_dhudmessage(0, "*** MANEA LOUDSPEAKER! ***");

    S16_PrintAll("^4[SECTIA 16]^1 ^3%s^1 a activat MANEA LOUDSPEAKER! Gardienii sunt surzi ^3 5 secunde^1!", szName);

    for (new i = 1; i <= get_maxplayers(); i++)
    {
        if (is_user_connected(i))
        {
            S16_ScreenShake(i, (1 << 13), 5, (1 << 11));
            S16_ScreenFade(i, 2, 3, 255, 0, 255, 110, 0x0001);
        }
    }

    return true;
}

bool:BuyPalinca(const id)
{
    g_flPalincaUntil[id] = get_gametime() + 8.0;

    S16_PlaySoundAll("sectia16/palinca");
    S16_ScreenFade(id, 7, 1, 90, 220, 70, 90, 0x0001);

    S16_PrintAll("^4[SECTIA 16]^1 Cineva a baut ^3Palinca de 70 de Grade^1. Se misca caprintsit!");

    return true;
}

bool:BuyManta(const id)
{
    g_flMantaUntil[id] = get_gametime() + 5.0;

    S16_PrintAll("^4[SECTIA 16]^1 Un detinut s-a ascuns sub ^3Manta Invizibila^1. Bagati de seama!");

    return true;
}

/* ====================================================
*   TASK-URI
*  ==================================================== */

public TaskMinuteCredits()
{
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ace", "TERRORIST");

    new iAmount = get_pcvar_num(g_pCvarMinute);
    for (new i = 0; i < iNum; i++)
    {
        g_iCredits[iPlayers[i]] += iAmount;
    }
}

public TaskMaintain()
{
    new Float:fNow = get_gametime();

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ac");
    for (new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i];

        // Manta Invizibila
        if (g_flMantaUntil[id] > fNow)
        {
            g_bMantaOn[id] = true;
            S16_RenderInvisible(id, 50);   // ~80% invizibilitate
        }
        else if (g_bMantaOn[id])
        {
            g_bMantaOn[id] = false;
            S16_RenderReset(id);
        }

        // Palinca 70 Grade
        if (g_flPalincaUntil[id] > fNow)
        {
            g_bPalincaOn[id] = true;
            set_pev(id, pev_maxspeed, 420.0);
        }
        else if (g_bPalincaOn[id])
        {
            g_bPalincaOn[id] = false;
            rg_reset_maxspeed(id);
        }
    }

    // Manea Loudspeaker: toti jucatorii nu mai aud gardienii
    if (g_flDeafenUntil > fNow)
    {
        g_bDeafening = true;

        new iCTs[MAX_PLAYERS], iCTNum;
        get_players(iCTs, iCTNum, "ace", "CT");

        for (new a = 0; a < iNum; a++)
        {
            for (new c = 0; c < iCTNum; c++)
            {
                if (iPlayers[a] != iCTs[c])
                    rg_set_can_hear_player(iPlayers[a], iCTs[c], false);
            }
        }
    }
    else if (g_bDeafening)
    {
        g_bDeafening = false;

        new iAll[MAX_PLAYERS], iAllNum;
        get_players(iAll, iAllNum, "c");
        for (new a = 0; a < iAllNum; a++)
            rg_reset_can_hear_player(iAll[a]);
    }
}

public EventNewRound()
{
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");
    for (new i = 0; i < iNum; i++)
    {
        arrayset(g_bItemUsed[iPlayers[i]], false, ITEM_COUNT);
        g_flPalincaUntil[iPlayers[i]] = 0.0;
        g_flMantaUntil[iPlayers[i]] = 0.0;
    }
}

public EventDeathMsg()
{
    new iKiller = read_data(1);
    new iVictim = read_data(2);

    if (!iKiller || iKiller == iVictim || !is_user_connected(iKiller))
        return;

    if (get_member(iKiller, m_iTeam) != TEAM_TERRORIST || get_member(iVictim, m_iTeam) != TEAM_CT)
        return;

    new iAmount = get_pcvar_num(g_pCvarKill);
    if (read_data(3))
        iAmount += 10;   // bonus headshot

    g_iCredits[iKiller] += iAmount;
    SaveCredits(iKiller);

    S16_Print(iKiller, "^4[SECTIA 16]^1 +^3%d credite^1 pentru executie.", iAmount);
}

/* ====================================================
*   NATIVES
*  ==================================================== */

public NativeGetCredits(const iPlugin, const iParams)
{
    new id = get_param(1);

    if (id < 0 || id > MaxClients)
        return 0;

    return g_iCredits[id];
}

public NativeAddCredits(const iPlugin, const iParams)
{
    new id = get_param(1);

    if (id < 0 || id > MaxClients)
        return 0;

    new iAmount = get_param(2);
    g_iCredits[id] = clamp(g_iCredits[id] + iAmount, 0, 999999);

    if (iAmount > 0)
        S16_Print(id, "^4[SECTIA 16]^1 Ai primit ^3%d credite^1! Sold: ^3%d^1.", iAmount, g_iCredits[id]);

    return g_iCredits[id];
}
