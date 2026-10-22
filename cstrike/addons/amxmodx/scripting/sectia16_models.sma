/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Modele de Jucatori v2.0:
*
*   Asignare AUTOMATA (configs/sectia16/models.ini):
*     [ct]         - CT non-Simon   (gamebanana.com/mods/730051)
*     [ct_simon]   - CT Simon       (gamebanana.com/mods/224557)
*     [t]          - Terorist normal (gamebanana.com/mods/224530)
*     [t_rebel]    - Terorist rebel (gamebanana.com/mods/727403)
*     [t_freeday]  - Terorist freeday (gamebanana.com/mods/224468)
*     [vip]        - Modele VIP (random per sesiune):
*                     gamebanana.com/mods/724163, 730210, 730293,
*                     gamebanana.com/mods/cats/12761, 719937, 716248, 723750
*
*   Prioritate: Simon > CT normal | FreeDay > Rebel > VIP > normal.
*   Modelele lipsa sunt ignorate cu brio (serverul NU pica daca
*   nu ai pus inca fisierele .mdl - se folosesc modelele default).
*
*   Instalare modele: tools/get_models.sh sau manual, in
*   structura models/player/sectia16_NUME/sectia16_NUME.mdl
*   (exact caile din models.ini).
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Modele Jucatori"
#define VERSION "2.0.0"
#define AUTHOR  "SECTIA 16"

#define TASK_APPLY_MODELS 625100

#define MAX_VIP_MODELS 8
#define MAX_MODELS_INI 32
#define MAX_PATH_LEN 96

enum (+= 1)
{
    SLOT_NONE = 0,
    SLOT_CT,
    SLOT_CT_SIMON,
    SLOT_T,
    SLOT_T_REBEL,
    SLOT_T_FREEDAY,
    SLOT_VIP_FIRST   // VIP-urile merg dupa acest index
}

// sloturi + modelele VIP
new g_szModelPath[MAX_MODELS_INI][MAX_PATH_LEN];
new g_iModelCount;
new g_iSlotFirst[SLOT_VIP_FIRST + 1];   // primul index al fiecarui slot
new g_iSlotCount[SLOT_VIP_FIRST + 1];   // cate modele are fiecare slot

// slotul curent al fiecarui jucator (0 = default CS)
new g_iCurSlot[MAX_PLAYERS + 1];
new g_iVipPick[MAX_PLAYERS + 1];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_event("HLTV", "EventNewRound", "a", "1=0", "2=0");

    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", true);

    set_task(1.0, "TaskApplyModels", TASK_APPLY_MODELS, _, _, "b");
}

public plugin_precache()
{
    LoadModelsIni();
}

public client_putinserver(id)
{
    g_iCurSlot[id] = SLOT_NONE;

    // modelul VIP se alege o data pe sesiune
    if (g_iSlotCount[SLOT_VIP_FIRST] > 0)
        g_iVipPick[id] = random(g_iSlotCount[SLOT_VIP_FIRST]);
    else
        g_iVipPick[id] = 0;
}

public client_disconnected(id)
{
    g_iCurSlot[id] = SLOT_NONE;
}

public EventNewRound()
{
    // modelul se reaplica la spawn; curatam cache-ul
    for (new id = 1; id <= MaxClients; id++)
        g_iCurSlot[id] = SLOT_NONE;
}

public OnPlayerSpawn(const id)
{
    if (is_user_alive(id))
        ApplyModel(id);
}

public TaskApplyModels()
{
    // watcher: prinde schimbarile mid-round (Simon nou, freeday acordat, rebel)
    for (new id = 1; id <= MaxClients; id++)
    {
        if (!is_user_alive(id))
            continue;

        ApplyModel(id);
    }
}

/* ====================================================
*   ASIGNARE MODELE
*  ==================================================== */

ApplyModel(const id)
{
    new iSlot = SLOT_NONE;

    switch (get_member(id, m_iTeam))
    {
        case TEAM_CT:
        {
            iSlot = (s16_get_simon() == id) ? SLOT_CT_SIMON : SLOT_CT;
        }
        case TEAM_TERRORIST:
        {
            if (s16_has_freeday(id))
                iSlot = SLOT_T_FREEDAY;
            else if (s16_is_rebel(id))
                iSlot = SLOT_T_REBEL;
            else if (s16_is_vip(id) && g_iSlotCount[SLOT_VIP_FIRST] > 0)
                iSlot = SLOT_VIP_FIRST + (g_iVipPick[id] % g_iSlotCount[SLOT_VIP_FIRST]);
            else
                iSlot = SLOT_T;
        }
    }

    if (iSlot == g_iCurSlot[id])
        return;

    g_iCurSlot[id] = iSlot;

    new iIdx = 0;

    if (iSlot >= SLOT_VIP_FIRST)
        iIdx = g_iSlotFirst[SLOT_VIP_FIRST] + (iSlot - SLOT_VIP_FIRST);
    else if (iSlot > SLOT_NONE)
        iIdx = g_iSlotFirst[iSlot];

    if (iSlot == SLOT_NONE || !g_szModelPath[iIdx][0])
    {
        // modelul lipseste -> revenim la modelul default CS
        rg_reset_user_model(id);
        return;
    }

    rg_set_user_model(id, g_szModelPath[iIdx]);
}

/* ====================================================
*   MODELS.INI
*  ==================================================== */

LoadModelsIni()
{
    new szPath[128];
    formatex(szPath, charsmax(szPath), "addons/amxmodx/configs/sectia16/models.ini");

    new hFile = fopen(szPath, "rt");
    if (!hFile)
    {
        log_amx("[SECTIA 16] models.ini lipseste - se folosesc modelele default CS.");
        return;
    }

    new szLine[MAX_PATH_LEN + 8], szSection[24], szModel[MAX_PATH_LEN];
    szSection[0] = 0;

    new iCurSlot = -1;

    while (fgets(hFile, szLine, charsmax(szLine)) && g_iModelCount < MAX_MODELS_INI)
    {
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
            continue;

        if (szLine[0] == '[')
        {
            new iLen = strlen(szLine);
            if (iLen > 1 && szLine[iLen - 1] == ']')
            {
                szLine[iLen - 1] = 0;
                copy(szSection, charsmax(szSection), szLine[1]);

                iCurSlot = SectionToSlot(szSection);
            }
            continue;
        }

        if (iCurSlot < 0)
            continue;

        copy(szModel, charsmax(szModel), szLine);
        trim(szModel);

        if (!szModel[0])
            continue;

        // modelul trebuie sa existe pe server, altfel il sarim
        if (!file_exists(szModel))
        {
            log_amx("[SECTIA 16] Model lipsa (ignorat): %s", szModel);
            continue;
        }

        // limita de modele VIP
        if (iCurSlot == SLOT_VIP_FIRST && g_iSlotCount[SLOT_VIP_FIRST] >= MAX_VIP_MODELS)
            continue;

        if (g_iSlotCount[iCurSlot] == 0)
            g_iSlotFirst[iCurSlot] = g_iModelCount;

        copy(g_szModelPath[g_iModelCount], charsmax(g_szModelPath[]), szModel);
        g_iModelCount++;
        g_iSlotCount[iCurSlot]++;

        // pre-cache: clientii vor descarca modelul (sv_allowdownload / FastDL)
        precache_model(szModel);
    }

    fclose(hFile);

    log_amx("[SECTIA 16] Modele incarcate: ct=%d ctsimon=%d t=%d trebel=%d tfreeday=%d vip=%d",
        g_iSlotCount[SLOT_CT], g_iSlotCount[SLOT_CT_SIMON], g_iSlotCount[SLOT_T],
        g_iSlotCount[SLOT_T_REBEL], g_iSlotCount[SLOT_T_FREEDAY], g_iSlotCount[SLOT_VIP_FIRST]);
}

SectionToSlot(const szSection[])
{
    if (equali(szSection, "ct"))         return SLOT_CT;
    if (equali(szSection, "ct_simon"))   return SLOT_CT_SIMON;
    if (equali(szSection, "t"))          return SLOT_T;
    if (equali(szSection, "t_rebel"))    return SLOT_T_REBEL;
    if (equali(szSection, "t_freeday"))  return SLOT_T_FREEDAY;
    if (equali(szSection, "vip"))        return SLOT_VIP_FIRST;
    return -1;
}
