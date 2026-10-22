/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Zile Custom (activate doar de Simon prin /zi):
*
*   ZIUA DE GRATAR:
*     - Detinuti: cutite cu coada de flacari (TE_BEAMFOLLOW)
*     - Gardieni: 2000 HP + armura 200 + "extinctor" (M3) care ingheata detinutii 2.5s la lovitura
*
*   PROTOPOPIAT (Ziua Apei Sfinte):
*     - Gardieni: AWP cu munitie infinita
*     - Detinuti: invizibili + viteza +150
*
*   GREVA FOAMEI:
*     - Gravitatie 0.5x, foamea loveste detinutii la fiecare 10 secunde
*     - Ultimul detinut supravietuitor castiga 300 credite + statut de erou
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Zile Custom"
#define VERSION "1.0.0"
#define AUTHOR  "SECTIA 16"

#define TASK_FLAME   623100
#define TASK_EFFECTS 623200
#define TASK_SLAP    623300
#define TASK_AMMO    623400

enum (+= 1)
{
    DAY_NONE = -1,
    DAY_GRATAR = 0,
    DAY_PROTOPOPIAT,
    DAY_GREVA
}

new g_iDay = DAY_NONE;

new g_iSpriteFlame;
new g_iModelFlameKnife;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /zi",      "CmdDayMenu");
    register_clcmd("say_team /zi", "CmdDayMenu");

    register_event("HLTV",     "EventNewRound", "a", "1=0", "2=0");
    register_event("DeathMsg", "EventDeathMsg", "a");

    RegisterHookChain(RG_CBasePlayer_TakeDamage, "OnTakeDamage", false);
}

// nativul cross-plugin se inregistreaza AICI (nu in plugin_init)
// ca sa fie disponibil pluginurilor incarcate dupa acesta (lr il foloseste)
public plugin_natives()
{
    register_library("sectia16_days");
    register_native("s16_get_day", "NativeGetDay");
}

public plugin_precache()
{
    g_iSpriteFlame = precache_model("sprites/laserbeam.spr");

    if (file_exists("models/sectia16/v_knife_flame.mdl"))
    {
        precache_model("models/sectia16/v_knife_flame.mdl");
        g_iModelFlameKnife = engfunc(EngFunc_AllocString, "models/sectia16/v_knife_flame.mdl");
    }

    S16_PrecacheSound("sectia16/gratar");
    S16_PrecacheSound("sectia16/clopote");
    S16_PrecacheSound("sectia16/zar");
    S16_PrecacheSound("sectia16/win");
}

/* ====================================================
*   MENIU ZILE
*  ==================================================== */

public CmdDayMenu(id)
{
    if (id != s16_get_simon())
    {
        S16_Print(id, "^4[SECTIA 16]^1 Doar Simonul poate declara zilele custom.");
        return PLUGIN_HANDLED;
    }

    if (!is_user_alive(id))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Simonul mort nu mai declara nimic.");
        return PLUGIN_HANDLED;
    }

    if (g_iDay != DAY_NONE)
    {
        new szDay[40];
        GetDayName(g_iDay, szDay, charsmax(szDay));
        S16_Print(id, "^4[SECTIA 16]^1 Azi deja e ^3%s^1. Maini, maini.", szDay);
        return PLUGIN_HANDLED;
    }

    new iMenu = menu_create("\r[SECTIA 16] \yZile Custom^n\dAlege programul de azi", "DayMenuHandler");

    menu_additem(iMenu, "\wZiua de \rGratar^n\dCutite in flacari vs 2000 HP", "1");
    menu_additem(iMenu, "\wProtopopiat \y(Apa Sfanta)^n\dAWP infinit vs invizibili", "2");
    menu_additem(iMenu, "\wGreva \rFoamei^n\dGravitatie 0.5, foamea loveste", "3");
    menu_additem(iMenu, "\dAnuleaza ziua speciala", "4");

    menu_setprop(iMenu, MPROP_EXITNAME, "Inchide");
    menu_display(id, iMenu, 0);

    return PLUGIN_HANDLED;
}

public DayMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    if (id != s16_get_simon() || g_iDay != DAY_NONE)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[3], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    switch (szInfo[0])
    {
        case '1': StartDay(DAY_GRATAR);
        case '2': StartDay(DAY_PROTOPOPIAT);
        case '3': StartDay(DAY_GREVA);
        case '4': S16_Print(id, "^4[SECTIA 16]^1 Zi normala. Plictiseala, ordine, beton.");
    }

    return PLUGIN_HANDLED;
}

/* ====================================================
*   PORNIRE ZILE
*  ==================================================== */

StartDay(const iDay)
{
    g_iDay = iDay;

    switch (iDay)
    {
        case DAY_GRATAR:
        {
            S16_PlaySoundAll("sectia16/gratar");

            set_dhudmessage(255, 80, 0, -1.0, 0.20, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** ZIUA DE GRATAR ***^nDetinuti cu cutite in flacari! Gardieni: 2000 HP + extinctoare!");

            new iPlayers[MAX_PLAYERS], iNum;
            get_players(iPlayers, iNum, "ae", "TERRORIST");
            for (new i = 0; i < iNum; i++)
            {
                S16_StripToKnife(iPlayers[i]);
                if (g_iModelFlameKnife)
                    set_pev(iPlayers[i], pev_viewmodel, g_iModelFlameKnife);
            }

            get_players(iPlayers, iNum, "ae", "CT");
            for (new i = 0; i < iNum; i++)
            {
                new id = iPlayers[i];
                rg_remove_all_items(id, false);
                rg_give_item(id, "weapon_m3");
                rg_set_user_bpammo(id, WEAPON_M3, 96);
                set_pev(id, pev_health, 2000.0);
                rg_set_user_armor(id, 200, ARMOR_VESTHELM);
            }

            set_task(1.5, "TaskFlameTrails", TASK_FLAME, _, _, "b");
            set_task(0.5, "TaskDayEffects", TASK_EFFECTS, _, _, "b");
        }

        case DAY_PROTOPOPIAT:
        {
            S16_PlaySoundAll("sectia16/clopote");

            set_dhudmessage(255, 255, 80, -1.0, 0.20, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** PROTOPOPIAT - APA SFANTA ***^nGardienii au AWP cu munitie infinita! Detinutii sunt invizibili si rapizi!");

            new iPlayers[MAX_PLAYERS], iNum;
            get_players(iPlayers, iNum, "ae", "CT");
            for (new i = 0; i < iNum; i++)
            {
                new id = iPlayers[i];
                rg_remove_all_items(id, false);
                rg_give_item(id, "weapon_awp");
                rg_set_user_bpammo(id, WEAPON_AWP, 30);
            }

            get_players(iPlayers, iNum, "ae", "TERRORIST");
            for (new i = 0; i < iNum; i++)
                S16_StripToKnife(iPlayers[i]);

            set_task(0.5, "TaskDayEffects", TASK_EFFECTS, _, _, "b");
            set_task(0.7, "TaskInfiniteAmmo", TASK_AMMO, _, _, "b");
        }

        case DAY_GREVA:
        {
            set_dhudmessage(120, 200, 255, -1.0, 0.20, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** GREVA FOAMEI ***^nGravitatie 0.5x! Foamea loveste detinutii la fiecare 10 secunde!^nUltimul supravietuitor castiga!");

            new iPlayers[MAX_PLAYERS], iNum;
            get_players(iPlayers, iNum, "ae", "TERRORIST");
            for (new i = 0; i < iNum; i++)
                S16_StripToKnife(iPlayers[i]);

            set_task(10.0, "TaskHungerSlap", TASK_SLAP, _, _, "b");
        }
    }

    new szDay[40];
    GetDayName(iDay, szDay, charsmax(szDay));
    S16_PrintAll("^4[SECTIA 16]^1 Simonul a declarat: ^3%s^1. Sa inceapa nebunia!", szDay);
}

/* ====================================================
*   TASK-URI ZILE
*  ==================================================== */

public TaskFlameTrails()
{
    if (g_iDay != DAY_GRATAR)
    {
        remove_task(TASK_FLAME);
        return;
    }

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ae", "TERRORIST");

    for (new i = 0; i < iNum; i++)
    {
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
        write_byte(TE_BEAMFOLLOW);
        write_short(iPlayers[i]);
        write_short(g_iSpriteFlame);
        write_byte(12);    // viata: 1.2 secunde
        write_byte(6);     // latime
        write_byte(255);   // R
        write_byte(120);   // G
        write_byte(20);    // B
        write_byte(190);   // transparenta
        message_end();
    }
}

public TaskDayEffects()
{
    if (g_iDay == DAY_NONE)
    {
        remove_task(TASK_EFFECTS);
        return;
    }

    if (g_iDay == DAY_PROTOPOPIAT)
    {
        new iPlayers[MAX_PLAYERS], iNum;
        get_players(iPlayers, iNum, "ae", "TERRORIST");

        for (new i = 0; i < iNum; i++)
        {
            S16_RenderInvisible(iPlayers[i], 40);
            set_pev(iPlayers[i], pev_maxspeed, 400.0);   // +150 peste baza
        }
    }
    else if (g_iDay == DAY_GREVA)
    {
        new iPlayers[MAX_PLAYERS], iNum;
        get_players(iPlayers, iNum, "a");

        for (new i = 0; i < iNum; i++)
            set_pev(iPlayers[i], pev_gravity, 0.5);
    }
}

public TaskInfiniteAmmo()
{
    if (g_iDay != DAY_PROTOPOPIAT)
    {
        remove_task(TASK_AMMO);
        return;
    }

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ae", "CT");

    for (new i = 0; i < iNum; i++)
    {
        rg_set_user_bpammo(iPlayers[i], WEAPON_AWP, 30);
        rg_instant_reload_weapons(iPlayers[i]);
    }
}

public TaskHungerSlap()
{
    if (g_iDay != DAY_GREVA)
    {
        remove_task(TASK_SLAP);
        return;
    }

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ae", "TERRORIST");

    for (new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i];
        new iDmg = random_num(3, 15);

        // impuns de foame
        new Float:fVel[3];
        pev(id, pev_velocity, fVel);
        fVel[0] += random_float(-140.0, 140.0);
        fVel[1] += random_float(-140.0, 140.0);
        fVel[2] += 110.0;
        set_pev(id, pev_velocity, fVel);

        if (S16_CanPlay("sectia16/zar"))
            emit_sound(id, CHAN_VOICE, "sectia16/zar.wav", 0.7, ATTN_NORM, 0, random_num(80, 120));

        new iHp = get_user_health(id) - iDmg;
        if (iHp <= 0)
            user_kill(id);
        else
            set_pev(id, pev_health, float(iHp));

        client_print(id, print_center, "[GREVA FOAMEI] -%d HP de foame", iDmg);
    }

    // ultimul detinut supravietuitor
    if (S16_CountAlive(TEAM_TERRORIST) == 1)
        HungerStrikeWinner(iPlayers[0]);
}

HungerStrikeWinner(const id)
{
    if (g_iDay != DAY_GREVA || !is_user_alive(id))
        return;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    set_pev(id, pev_health, 100.0);
    S16_RenderGlow(id, 0, 255, 0, 90);
    s16_add_credits(id, 300);

    S16_PlaySoundAll("sectia16/win");

    set_dhudmessage(0, 255, 0, -1.0, 0.25, 0, 8.0, 5.0);
    show_dhudmessage(0, "*** %s A SUPRAVIETUIT GREVEI FOAMEI! ***^nEroul Sectiei 16! +300 credite", szName);

    EndDay(id);
}

/* ====================================================
*   DAMAGE HOOK (extinctor Ziua de Gratar)
*  ==================================================== */

public OnTakeDamage(const this, const pevInflictor, const pevAttacker, Float:flDamage, const bitsDamageType)
{
    if (g_iDay != DAY_GRATAR)
        return HC_CONTINUE;

    if (pevAttacker == this || pevAttacker <= 0 || pevAttacker > MaxClients)
        return HC_CONTINUE;

    if (!is_user_alive(this) || !is_user_alive(pevAttacker))
        return HC_CONTINUE;

    if (get_member(this, m_iTeam) != TEAM_TERRORIST || get_member(pevAttacker, m_iTeam) != TEAM_CT)
        return HC_CONTINUE;

    // Extinctorul gardianului ingheata detinutul lovit
    S16_Freeze(this, 2.5);
    S16_ScreenFade(this, 1, 1, 40, 120, 255, 130, 0x0001);

    return HC_CONTINUE;
}

/* ====================================================
*   RESET & EVENTS
*  ==================================================== */

EndDay(const iSkipRender = 0)
{
    g_iDay = DAY_NONE;

    remove_task(TASK_FLAME);
    remove_task(TASK_EFFECTS);
    remove_task(TASK_SLAP);
    remove_task(TASK_AMMO);

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "c");

    for (new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i];

        if (is_user_alive(id))
        {
            set_pev(id, pev_gravity, 1.0);
            rg_reset_maxspeed(id);

            if (id != iSkipRender)
                S16_RenderReset(id);
        }
    }
}

public EventNewRound()
{
    EndDay();
}

public EventDeathMsg()
{
    if (g_iDay != DAY_GREVA)
        return;

    // detinutii mor si de foame (user_kill) - verificam castigatorul la fiecare moarte
    if (S16_CountAlive(TEAM_TERRORIST) == 1)
    {
        new iPlayers[MAX_PLAYERS], iNum;
        get_players(iPlayers, iNum, "ae", "TERRORIST");
        if (iNum == 1)
            HungerStrikeWinner(iPlayers[0]);
    }
}

/* ====================================================
*   NATIVE + UTIL
*  ==================================================== */

public NativeGetDay(const iPlugin, const iParams)
{
    return g_iDay;
}

GetDayName(const iDay, szOut[], const iLen)
{
    switch (iDay)
    {
        case DAY_GRATAR:      copy(szOut, iLen, "Ziua de Gratar");
        case DAY_PROTOPOPIAT: copy(szOut, iLen, "Protopopiat (Apa Sfanta)");
        case DAY_GREVA:       copy(szOut, iLen, "Greva Foamei");
        default:              copy(szOut, iLen, "Zi Normala");
    }
}
