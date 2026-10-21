/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Last Request (meniul ultimului detinut):
*     - Duel cu Deagle la Cap ....... 1v1 Deagle, doar headshot-uri (Ham_TraceAttack)
*     - Palme Sanatoase ............. duel de cutit la 35 HP
*     - Barbut / Zaruri ............. zar 1-6, zarul mic moare instant
*     - Cine Stie Castiga ........... intrebare din cultura pop romaneasca, raspuns in chat
*   Castigatorul: +100 HP, glow verde, +500 credite.
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <hamsandwich>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Last Request"
#define VERSION "1.0.0"
#define AUTHOR  "SECTIA 16"

#define TASK_TRIVIA_TIMEOUT 624100

enum (+= 1)
{
    LR_NONE = 0,
    LR_DEAGLE,
    LR_PALME,
    LR_BARBUT,
    LR_TRIVIA
}

new g_iLRType = LR_NONE;
new g_iLRT;
new g_iLRCT;
new bool:g_bLRActive;
new bool:g_bLRUsed;

// trivia
#define MAX_TRIVIA 40
new g_szTriviaQ[MAX_TRIVIA][96];
new g_szTriviaA[MAX_TRIVIA][96];
new g_iTriviaCount;
new g_iTriviaIdx;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /lr",      "CmdLastRequest");
    register_clcmd("say_team /lr", "CmdLastRequest");
    register_clcmd("say",          "CmdSay");
    register_clcmd("say_team",     "CmdSay");

    register_event("HLTV",     "EventNewRound", "a", "1=0", "2=0");
    register_event("DeathMsg", "EventDeathMsg", "a");

    RegisterHam(Ham_TraceAttack, "player", "OnTraceAttack", 0);
}

public plugin_cfg()
{
    LoadTrivia();
}

public plugin_precache()
{
    S16_PrecacheSound("sectia16/zar");
    S16_PrecacheSound("sectia16/win");
    S16_PrecacheSound("sectia16/lose");
}

/* ====================================================
*   OFERTA LR
*  ==================================================== */

public CmdLastRequest(id)
{
    if (!IsLastPrisoner(id))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Doar ultimul detinut in viata poate cere Last Request.");
        return PLUGIN_HANDLED;
    }

    ShowLRMenu(id);
    return PLUGIN_HANDLED;
}

bool:IsLastPrisoner(const id)
{
    if (!is_user_alive(id) || get_member(id, m_iTeam) != TEAM_TERRORIST)
        return false;

    if (g_bLRActive || g_bLRUsed)
        return false;

    if (s16_get_day() != -1)
        return false;

    if (S16_CountAlive(TEAM_TERRORIST) != 1 || S16_CountAlive(TEAM_CT) < 1)
        return false;

    return true;
}

ShowLRMenu(const id)
{
    new iMenu = menu_create("\r[SECTIA 16] \yLast Request^n\dAlege-ti soarta, detinute!", "LRMenuHandler");

    menu_additem(iMenu, "\wDuel cu \rDeagle la Cap^n\dDoar headshot-urile conta", "1");
    menu_additem(iMenu, "\wPalme \ySanatoase^n\dCutit la 35 HP, barbateste", "2");
    menu_additem(iMenu, "\wBarbut / \rZaruri^n\dZarul mic moare instant", "3");
    menu_additem(iMenu, "\wCine \yStie Castiga^n\dIntrebare cu raspuns in chat", "4");

    menu_setprop(iMenu, MPROP_EXITNAME, "Mai traiesc o clipa");

    menu_display(id, iMenu, 0);
}

public LRMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    if (!IsLastPrisoner(id))
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[3], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    // gardianul cel mai apropiat de detinut
    new iCT = FindNearestGuard(id);
    if (!iCT)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Nu exista gardiani in viata. Norocosule.");
        return PLUGIN_HANDLED;
    }

    switch (szInfo[0])
    {
        case '1': LRStart(LR_DEAGLE, id, iCT);
        case '2': LRStart(LR_PALME,  id, iCT);
        case '3': LRStart(LR_BARBUT, id, iCT);
        case '4': LRStart(LR_TRIVIA, id, iCT);
    }

    return PLUGIN_HANDLED;
}

FindNearestGuard(const id)
{
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ae", "CT");

    new iBest = 0;
    new Float:fBest = 999999.0;
    new Float:fMyOrigin[3], Float:fHisOrigin[3];

    pev(id, pev_origin, fMyOrigin);

    for (new i = 0; i < iNum; i++)
    {
        pev(iPlayers[i], pev_origin, fHisOrigin);
        new Float:fDist = get_distance_f(fMyOrigin, fHisOrigin);
        if (fDist < fBest)
        {
            fBest = fDist;
            iBest = iPlayers[i];
        }
    }

    return iBest;
}

/* ====================================================
*   PORNIRE LR
*  ==================================================== */

LRStart(const iType, const iT, const iCT)
{
    if (!is_user_alive(iT) || !is_user_alive(iCT))
        return;

    g_iLRType  = iType;
    g_iLRT      = iT;
    g_iLRCT    = iCT;
    g_bLRActive = true;
    g_bLRUsed   = true;

    new szT[32], szCT[32];
    get_user_name(iT, szT, charsmax(szT));
    get_user_name(iCT, szCT, charsmax(szCT));

    // arena izolata: gardianul e teleportat in fata detinutului, fata in fata
    PlaceFaceToFace(iT, iCT);

    S16_RenderGlow(iT, 255, 200, 0, 70);
    S16_RenderGlow(iCT, 255, 200, 0, 70);

    S16_PrintAll("^4[SECTIA 16]^1 LAST REQUEST: ^3%s^1 vs ^3%s^1! Nu interventionati in duel!", szT, szCT);

    switch (iType)
    {
        case LR_DEAGLE:
        {
            rg_remove_all_items(iT, false);
            rg_remove_all_items(iCT, false);
            rg_give_item(iT, "weapon_deagle");
            rg_give_item(iCT, "weapon_deagle");
            rg_set_user_bpammo(iT, WEAPON_DEAGLE, 35);
            rg_set_user_bpammo(iCT, WEAPON_DEAGLE, 35);
            set_pev(iT, pev_health, 100.0);
            set_pev(iCT, pev_health, 100.0);

            set_dhudmessage(255, 0, 0, -1.0, 0.22, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** DUEL CU DEAGLE LA CAP ***^nDoar headshot-urile trag!");
        }

        case LR_PALME:
        {
            S16_StripToKnife(iT);
            S16_StripToKnife(iCT);
            set_pev(iT, pev_health, 35.0);
            set_pev(iCT, pev_health, 35.0);

            set_dhudmessage(255, 200, 0, -1.0, 0.22, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** PALME SANATOASE ***^nCutit la 35 HP. Fara alergaturi!");
        }

        case LR_BARBUT:
        {
            S16_StripToKnife(iT);
            S16_StripToKnife(iCT);
            set_pev(iT, pev_health, 100.0);
            set_pev(iCT, pev_health, 100.0);

            set_dhudmessage(120, 255, 120, -1.0, 0.22, 0, 8.0, 4.0);
            show_dhudmessage(0, "*** BARBUT / ZARURI ***^nZarul mic moare instant!");

            set_task(2.0, "TaskRollDice");
        }

        case LR_TRIVIA:
        {
            S16_StripToKnife(iT);
            S16_StripToKnife(iCT);

            if (!g_iTriviaCount)
            {
                S16_PrintAll("^4[SECTIA 16]^1 Nu exista intrebari in trivia.ini! Se trece la Palme.");
                set_pev(iT, pev_health, 35.0);
                set_pev(iCT, pev_health, 35.0);
                g_iLRType = LR_PALME;
                return;
            }

            g_iTriviaIdx = random(g_iTriviaCount);

            set_dhudmessage(0, 200, 255, -1.0, 0.22, 0, 8.0, 4.0);
            show_dhudmessage(0, "*** CINE STIE CASTIGA ***^nPrimul care raspunde corect in chat castiga!");

            S16_PrintAll("^4[SECTIA 16]^3 INTREBARE:^1 %s", g_szTriviaQ[g_iTriviaIdx]);
            S16_PrintAll("^4[SECTIA 16]^1 Au ^330 de secunde^1. Tastati raspunsul in chat!");

            set_task(30.0, "TaskTriviaTimeout", TASK_TRIVIA_TIMEOUT);
        }
    }
}

PlaceFaceToFace(const iT, const iCT)
{
    new Float:fOrigin[3], Float:fDir[3], Float:fPos[3];
    pev(iT, pev_origin, fOrigin);

    velocity_by_aim(iT, 1, fDir);
    fDir[2] = 0.0;

    new Float:fLen = floatsqroot(fDir[0] * fDir[0] + fDir[1] * fDir[1]);
    if (fLen < 0.001)
    {
        fDir[0] = 1.0;
        fDir[1] = 0.0;
    }
    else
    {
        fDir[0] /= fLen;
        fDir[1] /= fLen;
    }

    fPos[0] = fOrigin[0] + fDir[0] * 120.0;
    fPos[1] = fOrigin[1] + fDir[1] * 120.0;
    fPos[2] = fOrigin[2];

    engfunc(EngFunc_SetOrigin, iCT, fPos);

    // se privesc fata in fata
    new Float:fYaw = floatatan(fDir[1] / fDir[0], radian) * 57.2957795;
    if (fDir[0] < 0.0)
        fYaw += 180.0;
    if (fYaw < 0.0)
        fYaw += 360.0;

    new Float:fAngT[3], Float:fAngCT[3];
    fAngT[0] = fYaw;
    fAngT[1] = 0.0;
    fAngT[2] = 0.0;
    fAngCT[0] = fYaw + 180.0;
    fAngCT[1] = 0.0;
    fAngCT[2] = 0.0;

    set_pev(iT, pev_angles, fAngT);
    set_pev(iT, pev_v_angle, fAngT);
    set_pev(iCT, pev_angles, fAngCT);
    set_pev(iCT, pev_v_angle, fAngCT);
}

/* ====================================================
*   HS-ONLY (Duel cu Deagle la Cap)
*  ==================================================== */

public OnTraceAttack(const this, const idattacker, Float:damage, Float:direction[3], const tracehandle, const damagebits)
{
    if (!g_bLRActive || g_iLRType != LR_DEAGLE)
        return HAM_IGNORED;

    if (this != g_iLRT && this != g_iLRCT)
        return HAM_IGNORED;

    // interventia unor terti in duel este blocata
    if (idattacker != g_iLRT && idattacker != g_iLRCT)
        return HAM_SUPERCEDE;

    // doar headshot-urile continua
    if (get_tr2(tracehandle, TR_iHitgroup) != HIT_HEAD)
        return HAM_SUPERCEDE;

    return HAM_IGNORED;
}

/* ====================================================
*   BARBUT
*  ==================================================== */

public TaskRollDice()
{
    if (!g_bLRActive || g_iLRType != LR_BARBUT || !is_user_alive(g_iLRT) || !is_user_alive(g_iLRCT))
        return;

    S16_PlaySoundAll("sectia16/zar");

    new iRollT  = random_num(1, 6);
    new iRollCT = random_num(1, 6);

    new szT[32], szCT[32];
    get_user_name(g_iLRT, szT, charsmax(szT));
    get_user_name(g_iLRCT, szCT, charsmax(szCT));

    set_dhudmessage(255, 215, 0, -1.0, 0.25, 0, 7.0, 4.0);
    show_dhudmessage(0, "BARBUT^n[DETINUT] %s: %d   -   %d :%s [GARDIAN]", szT, iRollT, iRollCT, szCT);

    if (iRollT == iRollCT)
    {
        S16_PrintAll("^4[SECTIA 16]^1 Egalitate ^3%d - %d^1! Se da din nou...", iRollT, iRollCT);
        set_task(2.5, "TaskRollDice");
        return;
    }

    new iLoser = (iRollT < iRollCT) ? g_iLRT : g_iLRCT;

    if (iRollT < iRollCT)
        S16_PrintAll("^4[SECTIA 16]^1 Detinutul a dat ^3%d^1, gardianul ^3%d^1. Detinutul moare!", iRollT, iRollCT);
    else
        S16_PrintAll("^4[SECTIA 16]^1 Gardianul a dat ^3%d^1, detinutul ^3%d^1. Gardianul moare!", iRollCT, iRollT);

    set_task(1.5, "TaskDiceKill", iLoser);
}

public TaskDiceKill(const iLoser)
{
    if (g_bLRActive && is_user_alive(iLoser))
        user_kill(iLoser);
}

/* ====================================================
*   TRIVIA
*  ==================================================== */

public CmdSay(id)
{
    if (!g_bLRActive || g_iLRType != LR_TRIVIA)
        return PLUGIN_CONTINUE;

    if (id != g_iLRT && id != g_iLRCT)
        return PLUGIN_CONTINUE;

    new szArgs[96];
    read_args(szArgs, charsmax(szArgs));
    remove_quotes(szArgs);
    trim(szArgs);

    if (!szArgs[0])
        return PLUGIN_CONTINUE;

    if (AnswerMatches(g_szTriviaA[g_iTriviaIdx], szArgs))
    {
        remove_task(TASK_TRIVIA_TIMEOUT);

        new iLoser = (id == g_iLRT) ? g_iLRCT : g_iLRT;
        new szName[32];
        get_user_name(id, szName, charsmax(szName));

        S16_PrintAll("^4[SECTIA 16]^3 %s^1 a raspuns corect: ^4%s^1. Celalalt moare!", szName, szArgs);

        set_task(1.0, "TaskDiceKill", iLoser);
    }

    return PLUGIN_CONTINUE;
}

public TaskTriviaTimeout()
{
    if (!g_bLRActive || g_iLRType != LR_TRIVIA)
        return;

    S16_PrintAll("^4[SECTIA 16]^1 Timpul a expirat! Nimeni nu a stiut. ^3Amandoi mor^1, pedagogic.");

    set_task(0.1, "TaskDiceKill", g_iLRT);
    set_task(0.1, "TaskDiceKill", g_iLRCT);
}

bool:AnswerMatches(const szAccepted[], const szInput[])
{
    new szAcc[96], szIn[96];
    copy(szAcc, charsmax(szAcc), szAccepted);
    copy(szIn, charsmax(szIn), szInput);

    S16_Lower(szAcc);
    S16_Lower(szIn);
    trim(szAcc);
    trim(szIn);

    if (!szIn[0])
        return false;

    // variante multiple separate prin virgula
    new iStart = 0;
    new iLen = strlen(szAcc);

    for (new i = 0; i <= iLen; i++)
    {
        if (szAcc[i] == ',' || szAcc[i] == 0)
        {
            new iPieceLen = i - iStart;

            if (iPieceLen > 0 && iPieceLen < 96)
            {
                new szPiece[96];
                for (new k = 0; k < iPieceLen; k++)
                    szPiece[k] = szAcc[iStart + k];
                szPiece[iPieceLen] = 0;

                trim(szPiece);

                if (equal(szPiece, szIn))
                    return true;
            }

            iStart = i + 1;
        }
    }

    return false;
}

/* ====================================================
*   FINAL LR & EVENTS
*  ==================================================== */

public EventDeathMsg()
{
    new iVictim = read_data(2);

    if (g_bLRActive && (iVictim == g_iLRT || iVictim == g_iLRCT))
    {
        new iWinner = (iVictim == g_iLRT) ? g_iLRCT : g_iLRT;
        LREnd(iWinner, iVictim);
        return;
    }

    // ofera automat LR ultimului detinut
    if (!g_bLRActive && !g_bLRUsed)
    {
        new iPlayers[MAX_PLAYERS], iNum;
        get_players(iPlayers, iNum, "ae", "TERRORIST");

        if (iNum == 1 && S16_CountAlive(TEAM_CT) >= 1)
        {
            new id = iPlayers[0];
            set_task(2.0, "TaskOfferLR", id);
        }
    }
}

public TaskOfferLR(id)
{
    if (!IsLastPrisoner(id))
        return;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    S16_PrintAll("^4[SECTIA 16]^1 ^3%s^1 este ultimul detinut! Are dreptul la ^4LAST REQUEST (/lr)^1.", szName);
    ShowLRMenu(id);
}

LREnd(const iWinner, const iLoser)
{
    if (!g_bLRActive)
        return;

    g_bLRActive = false;
    g_iLRType = LR_NONE;

    remove_task(TASK_TRIVIA_TIMEOUT);

    new iT = g_iLRT, iCT = g_iLRCT;
    g_iLRT = 0;
    g_iLRCT = 0;

    if (is_user_connected(iT))
        S16_RenderReset(iT);
    if (is_user_connected(iCT))
        S16_RenderReset(iCT);

    new szWinner[32], szLoser[32];
    get_user_name(iWinner, szWinner, charsmax(szWinner));
    get_user_name(iLoser, szLoser, charsmax(szLoser));

    if (is_user_alive(iWinner))
    {
        set_pev(iWinner, pev_health, 100.0);
        S16_RenderGlow(iWinner, 0, 255, 0, 90);
        s16_add_credits(iWinner, 500);
    }

    S16_PlaySoundAll("sectia16/win");

    set_dhudmessage(0, 255, 0, -1.0, 0.25, 0, 8.0, 5.0);
    show_dhudmessage(0, "*** %s A CASTIGAT LAST REQUEST-UL! ***^n%s s-a ales cu praful. +500 credite", szWinner, szLoser);
}

public EventNewRound()
{
    g_bLRActive = false;
    g_bLRUsed = false;
    g_iLRType = LR_NONE;
    g_iLRT = 0;
    g_iLRCT = 0;
}

/* ====================================================
*   TRIVIA.INI
*  ==================================================== */

LoadTrivia()
{
    new szPath[128];
    formatex(szPath, charsmax(szPath), "addons/amxmodx/configs/sectia16/trivia.ini");

    new hFile = fopen(szPath, "rt");
    if (!hFile)
        return;

    new szLine[192], szQ[96], szA[96];

    while (fgets(hFile, szLine, charsmax(szLine)) && g_iTriviaCount < MAX_TRIVIA)
    {
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
            continue;

        new iPos = contain(szLine, "|");
        if (iPos <= 0)
            continue;

        // intrebarea: caracterele de dinaintea separatorului "|"
        new j = 0;
        for (new k = 0; k < iPos && j < charsmax(szQ); k++, j++)
            szQ[j] = szLine[k];
        szQ[j] = 0;

        // raspunsul: caracterele de dupa separator
        j = 0;
        for (new k = iPos + 1; szLine[k] && j < charsmax(szA); k++, j++)
            szA[j] = szLine[k];
        szA[j] = 0;

        trim(szQ);
        trim(szA);

        if (!szQ[0] || !szA[0])
            continue;

        copy(g_szTriviaQ[g_iTriviaCount], charsmax(g_szTriviaQ[]), szQ);
        copy(g_szTriviaA[g_iTriviaCount], charsmax(g_szTriviaA[]), szA);
        g_iTriviaCount++;
    }

    fclose(hFile);

    log_amx("[SECTIA 16] Trivia incarcata: %d intrebari.", g_iTriviaCount);
}
