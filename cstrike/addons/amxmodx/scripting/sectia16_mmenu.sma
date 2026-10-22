/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Meniul Tastei M v2.1 - rescriere completa:
*
*   La apasarea tastei M (chooseteam) apare meniul personalizat:
*     1. Schimbare echipa: Detinut (T) / Gardian (CT) / Spectator
*        - CT-ul respecta interdictia BanCT (din meniul admin).
*     2. Selectie Model Player (VIP / Admin):
*        - alege oricare din modelele VIP instalate;
*        - se aplica automat la urmatorul spawn ca detinut.
*     3. Setari Glow:
*        - 7 culori solide - ACCESIBIL TUTUROR jucatorilor;
*        - MULTICOLOR / RAINBOW (culoare vie care se schimba
*          permanent) - exclusiv VIP / Admin;
*        - optiune OFF.
*     4. Viziune 3rd Person: comutarea intre camera din spate
*        si cea la persoana intai (camera proprie, cu protectie
*        anti-perete prin TraceLine).
*
*   Camera 3rd person: entitate info_target + EngFunc_SetView,
*   actualizata in RG_CBasePlayer_PostThink (fara module extra).
*
*   FIX v2.2: camera primeste un model (w_smokegrenade.mdl) si e
*   facuta invizibila prin rendermode - EF_NODRAW oprea transmiterea
*   entitatii catre client, deci SetView nu avea efect. Entitatea e
*   mutata cu EngFunc_SetOrigin (leaga entitatea in lume la fiecare
*   frame, obligatoriu pentru transmitere corecta).
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Meniu M (Echipe, Modele, Glow, 3rd Person)"
#define VERSION "2.2.0"
#define AUTHOR  "SECTIA 16"

// model mic, existent in orice instalare CS; entitatea camerei TREBUIE
// sa aiba modelindex != 0 ca sa fie transmisa clientului (SetView)
new const g_szCamModel[] = "models/w_smokegrenade.mdl";

#define TASK_GLOW_RAINBOW 628100

// ----- glow: 7 culori solide pentru TOTI + rainbow VIP/admin -----
#define GLOW_COUNT 7
#define GLOW_RAINBOW 7      // index special

new const g_szGlowNames[GLOW_COUNT][] =
{
    "Rosu", "Verde", "Albastru", "Galben", "Cyan", "Magenta", "Alb"
};

new const g_iGlowColors[GLOW_COUNT][3] =
{
    { 255,  40,  40 },
    {  40, 255,  40 },
    {  60, 120, 255 },
    { 255, 255,  40 },
    {  40, 255, 255 },
    { 255,  60, 220 },
    { 255, 255, 255 }
};

// ----- stare per jucator -----
new g_iGlowChoice[MAX_PLAYERS + 1];         // -1 = OFF, 0..6 culori, 7 = rainbow
new bool:g_bThirdPerson[MAX_PLAYERS + 1];
new g_iCamera[MAX_PLAYERS + 1];             // entitatea camerei (0 = n/a)
new Float:g_flNextSwitch[MAX_PLAYERS + 1];  // cooldown schimbare echipa

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("chooseteam", "CmdChooseTeam");

    register_event("HLTV", "EventNewRound", "a", "1=0", "2=0");
    register_event("DeathMsg", "EventDeathMsg", "a");

    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", true);
    RegisterHookChain(RG_CBasePlayer_PostThink, "OnPlayerPostThink", true);

    // efectul rainbow (doar pentru cei care l-au ales)
    set_task(0.25, "TaskRainbowGlow", TASK_GLOW_RAINBOW, _, _, "b");
}

public plugin_precache()
{
    precache_model(g_szCamModel);
}

public client_putinserver(id)
{
    g_iGlowChoice[id] = -1;
    g_flNextSwitch[id] = 0.0;
    g_bThirdPerson[id] = false;
    g_iCamera[id] = 0;
}

public client_disconnected(id)
{
    RemoveCamera(id);
    g_iGlowChoice[id] = -1;
    g_bThirdPerson[id] = false;
    g_flNextSwitch[id] = 0.0;
}

public EventNewRound()
{
    // glow-ul si viziunea persista; doar cooldown-ul se reseteaza
    for (new id = 1; id <= MaxClients; id++)
        g_flNextSwitch[id] = 0.0;
}

public EventDeathMsg()
{
    // mortul revine la prima persoane (camera pe cadavru e inutila)
    new id = read_data(2);

    if (is_user_connected(id) && g_bThirdPerson[id])
        SetThirdPerson(id, false);
}

public OnPlayerSpawn(const id)
{
    if (!is_user_alive(id))
        return;

    // reaplicam glow-ul ales (entitatea noua il poate pierde)
    if (g_iGlowChoice[id] >= 0 && g_iGlowChoice[id] < GLOW_COUNT)
        S16_RenderGlow(id, g_iGlowColors[g_iGlowChoice[id]][0], g_iGlowColors[g_iGlowChoice[id]][1], g_iGlowColors[g_iGlowChoice[id]][2], 60);

    // reaplicam camera 3rd person
    if (g_bThirdPerson[id])
        SetThirdPerson(id, true);
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
    new iMenu = menu_create("\r[SECTIA 16] \yMeniu Jucator^n\dEchipe, modele, glow si viziune", "MainMenuHandler");

    new szItem[96];

    formatex(szItem, charsmax(szItem), "\wSchimbare \yEchipa^n\dDetinut / Gardian / Spectator");
    menu_additem(iMenu, szItem, "team");

    // ----- modele -----
    new iVipModels = s16_get_vip_model_count();

    if (s16_is_vip(id) || s16_is_admin(id))
    {
        new iChoice = s16_get_model_choice(id);
        new szCurName[40];

        if (iChoice >= 0 && iChoice < iVipModels)
        {
            if (!s16_get_vip_model_name(iChoice, szCurName, charsmax(szCurName)))
                formatex(szCurName, charsmax(szCurName), "Model VIP %d", iChoice + 1);

            formatex(szItem, charsmax(szItem), "\wModele \yPlayer^n\dCurent: \r%s^n\d(%d modele disponibile)", szCurName, iVipModels);
        }
        else
        {
            formatex(szItem, charsmax(szItem), "\wModele \yPlayer^n\dCurent: \rAutomat (random)^n\d(%d modele disponibile)", iVipModels);
        }
    }
    else
    {
        formatex(szItem, charsmax(szItem), "\dModele Player^n\dDoar pentru \rVIP / Admini");
    }

    menu_additem(iMenu, szItem, "models");

    // ----- glow -----
    if (g_iGlowChoice[id] == GLOW_RAINBOW)
        formatex(szItem, charsmax(szItem), "\wSetari \yGlow^n\dCurent: \rMULTICOLOR (rainbow)");
    else if (g_iGlowChoice[id] >= 0)
        formatex(szItem, charsmax(szItem), "\wSetari \yGlow^n\dCurent: \r%s", g_szGlowNames[g_iGlowChoice[id]]);
    else
        formatex(szItem, charsmax(szItem), "\wSetari \yGlow^n\dCurent: \dOFF");

    menu_additem(iMenu, szItem, "glow");

    // ----- viziune -----
    if (g_bThirdPerson[id])
        formatex(szItem, charsmax(szItem), "\wViziune: \r3rd Person^n\dCamera din spate - apasa pentru 1st");
    else
        formatex(szItem, charsmax(szItem), "\wViziune: \y1st Person^n\dApasa pentru camera din spate (3rd)");

    menu_additem(iMenu, szItem, "view");

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

    new iAccess, szInfo[8], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    switch (szInfo[0])
    {
        case 't':   ShowTeamMenu(id);
        case 'm':   ShowModelsMenu(id);
        case 'g':   ShowGlowMenu(id);
        case 'v':
        {
            SetThirdPerson(id, !g_bThirdPerson[id]);

            if (g_bThirdPerson[id])
                S16_Print(id, "^4[SECTIA 16]^1 Viziune: ^3persoana a 3-a^1. Bine ai venit printre muritori.");
            else
                S16_Print(id, "^4[SECTIA 16]^1 Viziune: ^3persoana intai^1. Bine ai revenit in pielea ta.");
        }
    }

    return PLUGIN_HANDLED;
}

/* ====================================================
*   SCHIMBAREA ECHIPEI (respecta BanCT)
*  ==================================================== */

ShowTeamMenu(const id)
{
    new iMenu = menu_create("\r[SECTIA 16] \ySchimbare Echipa", "TeamMenuHandler");

    menu_additem(iMenu, "\wDetinut \r(T)^n\dViata de puscarie, credite si shop", "t");
    menu_additem(iMenu, "\wGardian \y(CT)^n\dPaza, ordine, echipament la spawn", "ct");
    menu_additem(iMenu, "\wSpectator^n\dDoar privesti suferinta", "spec");

    menu_setprop(iMenu, MPROP_EXITNAME, "Inapoi");
    menu_display(id, iMenu, 0);
}

public TeamMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        ShowMainMenu(id);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[8], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    switch (szInfo[0])
    {
        case 't':   SwitchTeam(id, TEAM_TERRORIST);
        case 'c':   SwitchTeam(id, TEAM_CT);
        case 's':   GoSpectator(id);
    }

    return PLUGIN_HANDLED;
}

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

    // interdictia BanCT (acordata de admini)
    if (team == TEAM_CT && s16_is_banned_ct(id))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Ai ^3interdictie de gardian^1. Discuta cu un admin pentru detalii.");
        return;
    }

    g_flNextSwitch[id] = fNow + 5.0;

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

    if (is_user_alive(id))
        user_silentkill(id);

    SetThirdPerson(id, false);      // spectatorul vede din ochii sai
    rg_set_user_team(id, TEAM_SPECTATOR, MODEL_UNASSIGNED, true);
}

/* ====================================================
*   MODELE PLAYER (VIP / Admin)
*  ==================================================== */

ShowModelsMenu(const id)
{
    if (!s16_is_vip(id) && !s16_is_admin(id))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Modelele custom sunt doar pentru ^3VIP^1 si ^3admini^1. Suporta-te cu bani sau cu functie.");
        return;
    }

    new iCount = s16_get_vip_model_count();

    if (!iCount)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Niciun model VIP instalat. Ruleaza ^3get_models.sh^1 pe server.");
        return;
    }

    new iMenu = menu_create("\r[SECTIA 16] \yModele Player^n\dVIP / Admin - se aplica ca detinut", "ModelsMenuHandler");

    new iCur = s16_get_model_choice(id);
    new szItem[96], szInfo[6], szModelName[40];

    if (iCur < 0)
        menu_additem(iMenu, "\yAutomat (random)^n\dNorocul decide modelul", "a");
    else
        menu_additem(iMenu, "\wAutomat (random)^n\dNorocul decide modelul", "a");

    for (new i = 0; i < iCount; i++)
    {
        num_to_str(i, szInfo, charsmax(szInfo));

        if (!s16_get_vip_model_name(i, szModelName, charsmax(szModelName)))
            formatex(szModelName, charsmax(szModelName), "Model VIP %d", i + 1);

        if (i == iCur)
            formatex(szItem, charsmax(szItem), "\y%s \r[ACTIV]", szModelName);
        else
            formatex(szItem, charsmax(szItem), "\w%s", szModelName);

        menu_additem(iMenu, szItem, szInfo);
    }

    menu_setprop(iMenu, MPROP_EXITNAME, "Inapoi");
    menu_display(id, iMenu, 0);
}

public ModelsMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        ShowMainMenu(id);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[6], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    if (!s16_is_vip(id) && !s16_is_admin(id))
        return PLUGIN_HANDLED;

    if (szInfo[0] == 'a')
    {
        s16_set_model_choice(id, -1);
        S16_Print(id, "^4[SECTIA 16]^1 Model: ^3automat (random)^1 la fiecare connect.");
        return PLUGIN_HANDLED;
    }

    new iChoice = str_to_num(szInfo);
    new iCount = s16_get_vip_model_count();

    if (iChoice < 0 || iChoice >= iCount)
        return PLUGIN_HANDLED;

    s16_set_model_choice(id, iChoice);

    new szModelName[40];
    if (!s16_get_vip_model_name(iChoice, szModelName, charsmax(szModelName)))
        formatex(szModelName, charsmax(szModelName), "Model VIP %d", iChoice + 1);

    S16_Print(id, "^4[SECTIA 16]^1 Model ales: ^3%s^1. Se aplica ca detinut (la spawn).", szModelName);

    return PLUGIN_HANDLED;
}

/* ====================================================
*   GLOW - culori solide PENTRU TOTI + rainbow VIP/Admin
*  ==================================================== */

ShowGlowMenu(const id)
{
    new iMenu = menu_create("\r[SECTIA 16] \ySetari Glow^n\dCulorile solide sunt pentru \yTOTI^n\dRainbow-ul e pentru \rVIP/Admini", "GlowMenuHandler");

    new szItem[96], szInfo[6];

    for (new i = 0; i < GLOW_COUNT; i++)
    {
        if (g_iGlowChoice[id] == i)
            formatex(szItem, charsmax(szItem), "\y%s \r[ACTIV]", g_szGlowNames[i]);
        else
            formatex(szItem, charsmax(szItem), "\w%s", g_szGlowNames[i]);

        num_to_str(i, szInfo, charsmax(szInfo));
        menu_additem(iMenu, szItem, szInfo);
    }

    // rainbow - exclusiv VIP / admin
    if (s16_is_vip(id) || s16_is_admin(id))
    {
        if (g_iGlowChoice[id] == GLOW_RAINBOW)
            menu_additem(iMenu, "\yMULTICOLOR (Rainbow) \r[ACTIV]^n\dCuloarea traieste cu tine", "r");
        else
            menu_additem(iMenu, "\wMULTICOLOR \y(Rainbow)^n\dCuloarea traieste cu tine", "r");
    }
    else
    {
        menu_additem(iMenu, "\dMULTICOLOR (Rainbow)^n\dDoar pentru \rVIP / Admini", "x");
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
        ShowMainMenu(id);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[6], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    if (szInfo[0] == 'x')
    {
        S16_Print(id, "^4[SECTIA 16]^1 Rainbow-ul e doar pentru ^3VIP^1 si ^3admini^1.");
        return PLUGIN_HANDLED;
    }

    if (szInfo[0] == 'o')   // off
    {
        g_iGlowChoice[id] = -1;

        if (is_user_alive(id))
            S16_RenderReset(id);

        S16_Print(id, "^4[SECTIA 16]^1 Glow oprit.");
        return PLUGIN_HANDLED;
    }

    if (szInfo[0] == 'r')   // rainbow
    {
        if (!s16_is_vip(id) && !s16_is_admin(id))
        {
            S16_Print(id, "^4[SECTIA 16]^1 Rainbow-ul e doar pentru ^3VIP^1 si ^3admini^1.");
            return PLUGIN_HANDLED;
        }

        g_iGlowChoice[id] = GLOW_RAINBOW;
        S16_Print(id, "^4[SECTIA 16]^1 Glow ^3MULTICOLOR^1 activ - esti curcubeul sectiei!");
        return PLUGIN_HANDLED;
    }

    // culoare solida - disponibila TUTUROR
    new iColor = str_to_num(szInfo);

    if (iColor < 0 || iColor >= GLOW_COUNT)
        return PLUGIN_HANDLED;

    g_iGlowChoice[id] = iColor;

    if (is_user_alive(id))
        S16_RenderGlow(id, g_iGlowColors[iColor][0], g_iGlowColors[iColor][1], g_iGlowColors[iColor][2], 60);

    S16_Print(id, "^4[SECTIA 16]^1 Glow setat: ^3%s^1.", g_szGlowNames[iColor]);

    return PLUGIN_HANDLED;
}

/* ====================================================
*   RAINBOW - ciclu de culori (task 0.25s, doar purtatori)
*  ==================================================== */

public TaskRainbowGlow()
{
    new iHueBase = floatround(get_gametime() * 144.0);

    for (new id = 1; id <= MaxClients; id++)
    {
        if (g_iGlowChoice[id] != GLOW_RAINBOW || !is_user_alive(id))
            continue;

        new iHue = (iHueBase + id * 47) % 360;
        new iR, iG, iB;
        HSVtoRGB(iHue, 255, 220, iR, iG, iB);

        S16_RenderGlow(id, iR, iG, iB, 60);
    }
}

HSVtoRGB(const iHue, const iSat, const iVal, &iR, &iG, &iB)
{
    new iRegion = iHue / 60;
    new iRem = (iHue - iRegion * 60) * 255 / 60;
    new iP = iVal * (255 - iSat) / 255;
    new iQ = iVal * (255 - iSat * iRem / 255) / 255;
    new iT = iVal * (255 - iSat * (255 - iRem) / 255) / 255;

    switch (iRegion)
    {
        case 0: { iR = iVal; iG = iT;   iB = iP;   }
        case 1: { iR = iQ;   iG = iVal; iB = iP;   }
        case 2: { iR = iP;   iG = iVal; iB = iT;   }
        case 3: { iR = iP;   iG = iQ;   iB = iVal; }
        case 4: { iR = iT;   iG = iP;   iB = iVal; }
        default:{ iR = iVal; iG = iP;   iB = iQ;   }
    }
}

/* ====================================================
*   VIZIUNE 3RD PERSON (camera + EngFunc_SetView)
*  ==================================================== */

SetThirdPerson(const id, const bool:bOn)
{
    g_bThirdPerson[id] = bOn;

    if (!bOn)
    {
        RemoveCamera(id);
        return;
    }

    if (!is_user_alive(id))
        return;

    RemoveCamera(id);   // daca exista una veche

    // camera noua: info_target invizibil prin render (NU prin EF_NODRAW,
    // care ar opri transmiterea entitatii catre client => SetView mort)
    new iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));

    if (!iEnt || !pev_valid(iEnt))
    {
        g_bThirdPerson[id] = false;
        return;
    }

    set_pev(iEnt, pev_classname, "sectia16_camera");
    set_pev(iEnt, pev_movetype, MOVETYPE_NOCLIP);
    set_pev(iEnt, pev_solid, SOLID_NOT);

    // modelindex != 0 e obligatoriu pentru ca entitatea sa ajunga la client
    engfunc(EngFunc_SetModel, iEnt, g_szCamModel);

    // invizibil: render transparent complet (efect client-side)
    set_pev(iEnt, pev_rendermode, kRenderTransTexture);
    set_pev(iEnt, pev_renderamt, 0.0);

    dllfunc(DLLFunc_Spawn, iEnt);

    // pozitie initiala + link in lume (EngFunc_SetOrigin leaga entitatea)
    new Float:fOrigin[3];
    pev(id, pev_origin, fOrigin);
    engfunc(EngFunc_SetOrigin, iEnt, fOrigin);

    g_iCamera[id] = iEnt;
    engfunc(EngFunc_SetView, id, iEnt);
}

RemoveCamera(const id)
{
    if (g_iCamera[id] && pev_valid(g_iCamera[id]))
        engfunc(EngFunc_RemoveEntity, g_iCamera[id]);

    g_iCamera[id] = 0;

    if (is_user_connected(id))
        engfunc(EngFunc_SetView, id, id);
}

// pozitioneaza camera in spatele jucatorului, cu protectie anti-perete
public OnPlayerPostThink(const id)
{
    if (!g_bThirdPerson[id] || !is_user_alive(id) || !g_iCamera[id] || !pev_valid(g_iCamera[id]))
        return;

    new Float:fOrigin[3], Float:fAngles[3];
    pev(id, pev_origin, fOrigin);
    pev(id, pev_v_angle, fAngles);      // unghiul real al privirii

    new Float:fFwd[3], Float:fRight[3], Float:fUp[3];
    S16_AngleVectors(fAngles, fFwd, fRight, fUp);   // stock Pawn (HLSDK)

    // punctul de plecare: putin deasupra capului
    new Float:fEyes[3];
    fEyes[0] = fOrigin[0];
    fEyes[1] = fOrigin[1];
    fEyes[2] = fOrigin[2] + 20.0;

    // pozitia dorita a camerei: in spate + sus
    new Float:fCam[3];
    fCam[0] = fEyes[0] - fFwd[0] * 75.0 + fUp[0] * 28.0;
    fCam[1] = fEyes[1] - fFwd[1] * 75.0 + fUp[1] * 28.0;
    fCam[2] = fEyes[2] - fFwd[2] * 75.0 + fUp[2] * 28.0;

    // nu lasam camera in perete: trasam o linie de la ochi la camera
    engfunc(EngFunc_TraceLine, fEyes, fCam, IGNORE_MONSTERS, id, 0);

    new Float:fFraction;
    get_tr2(0, TR_flFraction, fFraction);

    if (fFraction < 1.0)
    {
        new Float:fHit[3];
        get_tr2(0, TR_vecEndPos, fHit);

        // oprim camera in punctul de impact, trasa 8 unitati spre jucator
        fCam[0] = fHit[0] - fFwd[0] * 8.0;
        fCam[1] = fHit[1] - fFwd[1] * 8.0;
        fCam[2] = fHit[2] - fFwd[2] * 8.0;
    }

    // SetOrigin (nu set_pev) - relink-uia entitatea in lume la fiecare
    // frame, altfel clientul poate sa nu primeasca actualizarile de pozitie
    engfunc(EngFunc_SetOrigin, g_iCamera[id], fCam);
    set_pev(g_iCamera[id], pev_angles, fAngles);
    // camera e invizibila prin renderamt 0 (setat la creare)
}
