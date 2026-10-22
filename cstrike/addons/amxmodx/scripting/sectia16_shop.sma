/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Shop Secret v2.0 (doar detinuti):
*     - Vitamine din Cantina ...... +50 HP
*     - Feroarie .................. 100 AP + casti
*     - Pila de Unghii ............ deschide discret o usa din apropiere
*     - Palinca 70 Grade .......... viteza +170 si ecran verzui 8 secunde
*     - Manta Invizibila .......... 80% invizibilitate 5 secunde
*     - Contrabanda ................ Deagle cu 7 gloante
*   Creditele sunt gestionate de sectia16_core (vault per SteamID).
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Shop Secret"
#define VERSION "2.0.0"
#define AUTHOR  "SECTIA 16"

#define TASK_MAINTAIN 622100

enum (+= 1)
{
    ITEM_VITAMINE = 0,
    ITEM_FEROARIE,
    ITEM_PILA,
    ITEM_PALINCA,
    ITEM_MANTA,
    ITEM_CONTRABANDA,
    ITEM_COUNT
}

new bool:g_bItemUsed[MAX_PLAYERS + 1][ITEM_COUNT];

new Float:g_flPalincaUntil[MAX_PLAYERS + 1];
new Float:g_flMantaUntil[MAX_PLAYERS + 1];
new bool:g_bPalincaOn[MAX_PLAYERS + 1];
new bool:g_bMantaOn[MAX_PLAYERS + 1];

new g_pCvarCost[ITEM_COUNT];

// clasele de usi pentru Pila (global - amxxpc nu suporta const 2D local)
new const g_szDoorClasses[][] = { "func_door", "func_door_rotating", "func_button" };

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /shop",      "CmdShop");
    register_clcmd("say_team /shop", "CmdShop");

    register_event("HLTV", "EventNewRound", "a", "1=0", "2=0");

    g_pCvarCost[ITEM_VITAMINE]   = register_cvar("s16_cost_vitamine",   "600");
    g_pCvarCost[ITEM_FEROARIE]   = register_cvar("s16_cost_feroarie",   "500");
    g_pCvarCost[ITEM_PILA]       = register_cvar("s16_cost_pila",       "500");
    g_pCvarCost[ITEM_PALINCA]    = register_cvar("s16_cost_palinca",    "400");
    g_pCvarCost[ITEM_MANTA]      = register_cvar("s16_cost_manta",      "900");
    g_pCvarCost[ITEM_CONTRABANDA] = register_cvar("s16_cost_contrabanda", "1200");

    set_task(0.25, "TaskMaintain", TASK_MAINTAIN, _, _, "b");
}

public plugin_precache()
{
    S16_PrecacheSound("sectia16/palinca");
    S16_PrecacheSound("sectia16/buzzer");
    S16_PrecacheSound("sectia16/ding");
}

public client_disconnected(id)
{
    arrayset(g_bItemUsed[id], false, ITEM_COUNT);
    g_flPalincaUntil[id] = 0.0;
    g_flMantaUntil[id] = 0.0;
    g_bPalincaOn[id] = false;
    g_bMantaOn[id] = false;
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
    formatex(szTitle, charsmax(szTitle), "\r[SECTIA 16] \yShop Secret^n\dCredite: \r%d", s16_get_credits(id));

    new iMenu = menu_create(szTitle, "ShopHandler");

    new iCallback = menu_makecallback("ShopItemCallback");
    new szItem[128];

    formatex(szItem, charsmax(szItem), "\wVitamine din Cantina^n\d+50 HP, ca la bunica \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_VITAMINE]));
    menu_additem(iMenu, szItem, "0", _, iCallback);

    formatex(szItem, charsmax(szItem), "\wFeroarie^n\d100 AP + casti \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_FEROARIE]));
    menu_additem(iMenu, szItem, "1", _, iCallback);

    formatex(szItem, charsmax(szItem), "\wPila de Unghii^n\dDeschide discret o usa apropiata \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_PILA]));
    menu_additem(iMenu, szItem, "2", _, iCallback);

    formatex(szItem, charsmax(szItem), "\wPalinca \y70 Grade^n\dViteza + ecran verzui 8 secunde \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_PALINCA]));
    menu_additem(iMenu, szItem, "3", _, iCallback);

    formatex(szItem, charsmax(szItem), "\wManta \dInvizibila^n\d80%% invizibilitate 5 secunde \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_MANTA]));
    menu_additem(iMenu, szItem, "4", _, iCallback);

    formatex(szItem, charsmax(szItem), "\wContrabanda \r(Deagle)^n\dDeagle cu 7 gloante \r[%d]", get_pcvar_num(g_pCvarCost[ITEM_CONTRABANDA]));
    menu_additem(iMenu, szItem, "5", _, iCallback);

    menu_setprop(iMenu, MPROP_EXITNAME, "Inchide");
    menu_display(id, iMenu, 0);

    return PLUGIN_HANDLED;
}

public ShopItemCallback(const id, const iMenu, const iItem)
{
    new iAccess, szInfo[3], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);

    new iIdx = str_to_num(szInfo);

    if (g_bItemUsed[id][iIdx] || s16_get_credits(id) < get_pcvar_num(g_pCvarCost[iIdx]))
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

    if (!s16_spend_credits(id, iCost))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Nu ai destule credite. Iti trebuie ^3%d^1.", iCost);
        return PLUGIN_HANDLED;
    }

    new bool:bSuccess = false;

    switch (iIdx)
    {
        case ITEM_VITAMINE:    bSuccess = BuyVitamine(id);
        case ITEM_FEROARIE:    bSuccess = BuyFeroarie(id);
        case ITEM_PILA:        bSuccess = BuyPila(id);
        case ITEM_PALINCA:     bSuccess = BuyPalinca(id);
        case ITEM_MANTA:       bSuccess = BuyManta(id);
        case ITEM_CONTRABANDA: bSuccess = BuyContrabanda(id);
    }

    if (!bSuccess)
    {
        // refund
        s16_add_credits(id, iCost);
        S16_Print(id, "^4[SECTIA 16]^1 Achizitia a esuat, creditele raman la locul lor.");
        return PLUGIN_HANDLED;
    }

    g_bItemUsed[id][iIdx] = true;

    S16_Print(id, "^4[SECTIA 16]^1 Achizitie reusita! Credite ramase: ^3%d^1.", s16_get_credits(id));

    return PLUGIN_HANDLED;
}

/* ====================================================
*   OBIECTE
*  ==================================================== */

bool:BuyVitamine(const id)
{
    set_pev(id, pev_health, float(get_user_health(id) + 50));
    S16_PrintAll("^4[SECTIA 16]^1 Un detinut a mancat ^3Vitamine din Cantina^1. +50 HP!");
    return true;
}

bool:BuyFeroarie(const id)
{
    rg_set_user_armor(id, 100, ARMOR_VESTHELM);
    S16_PlaySound(id, "sectia16/ding");
    S16_PrintAll("^4[SECTIA 16]^1 Cineva si-a facut ^3Feroarie^1. 100 AP!");
    return true;
}

bool:BuyPila(const id)
{
    new Float:fMyOrigin[3], Float:fMin[3], Float:fMax[3], Float:fCenter[3];
    pev(id, pev_origin, fMyOrigin);

    new iBest = 0;
    new Float:fBestDist = 280.0;

    for (new c = 0; c < sizeof(g_szDoorClasses); c++)
    {
        new iEnt = -1;
        while ((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "classname", g_szDoorClasses[c])) != 0)
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

bool:BuyContrabanda(const id)
{
    rg_give_item(id, "weapon_deagle");
    rg_set_user_bpammo(id, WEAPON_DEAGLE, 0);

    S16_PrintAll("^4[SECTIA 16]^1 Un detinut a scos ^3Contrabanda^1 - Deagle cu 7 gloante!");

    return true;
}

/* ====================================================
*   TASK-URI
*  ==================================================== */

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
