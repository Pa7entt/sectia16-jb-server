/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Zile v2.0:
*
*   ROLATIE AUTOMATA (ora serverului, timezone Europe/Bucharest):
*     Luni     - ZIUA BOX (toti cu cutitul, HP egal 100)
*     Marti    - GUN DAY (detinutii primesc arme aleatorii)
*     Miercuri - ASCUNSELEA (gardienii inghetati si orbi 40s)
*     Joi      - WAR DAY (detinutii primesc AK47, razboi general)
*     Vineri   - ZOMBIE DAY (detinutii zombii 500 HP, doar cutit)
*     Sambata  - ZI NORMALA (Simon alege ziua prin /zi)
*     Duminica - FREEday GLOBAL AUTOMAT (toti detinutii primesc
*                freeday + modelul dedicat de freeday)
*
*   Simon poate suprascrie ziua oricand prin meniul /zi
*   (exceptie Duminica - freeday-ul global e sacru).
*
*   Zilele custom clasice raman in meniu: Ziua de Gratar,
*   Protopopiat, Greva Foamei.
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Zile"
#define VERSION "2.0.0"
#define AUTHOR  "SECTIA 16"

#define TASK_FLAME   623100
#define TASK_EFFECTS 623200
#define TASK_SLAP    623300
#define TASK_AMMO    623400
#define TASK_AUTODAY 623500
#define TASK_HNS     623600

new g_iDay = S16_DAY_NONE;

new g_iSpriteFlame;
new g_iModelFlameKnife;

// armele pentru Gun Day (global - amxxpc nu suporta const 2D local)
new const g_szGunDayGuns[][] = { "weapon_ak47", "weapon_m4a1", "weapon_mp5navy", "weapon_sg552", "weapon_famas" };
new const WeaponIdType:g_iGunDayIds[] = { WEAPON_AK47, WEAPON_M4A1, WEAPON_MP5N, WEAPON_SG552, WEAPON_FAMAS };

// ziua automata a rundei (calculata la fiecare runda)
new g_iAutoDay = S16_DAY_NONE;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /zi",      "CmdDayMenu");
    register_clcmd("say_team /zi", "CmdDayMenu");

    register_event("HLTV",     "EventNewRound", "a", "1=0", "2=0");
    register_event("DeathMsg", "EventDeathMsg", "a");

    RegisterHookChain(RG_CBasePlayer_TakeDamage, "OnTakeDamage", false);
}

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
    S16_PrecacheSound("sectia16/ding");
}

/* ====================================================
*   RUNDĂ NOUĂ: ziua automata (rotatie / duminica)
*  ==================================================== */

public EventNewRound()
{
    EndDay();

    g_iAutoDay = GetWeekdayAutoDay();

    // Duminica = FREEday GLOBAL AUTOMAT
    if (g_iAutoDay == S16_DAY_SUNDAY_FD)
    {
        ApplySundayFreeDay();
        return;
    }

    // restul zilelor se aplica automat dupa 12 secunde
    // (celulele se deschid, detinutii se organizeaza)
    if (g_iAutoDay != S16_DAY_NONE)
        set_task(12.0, "TaskAutoDay", TASK_AUTODAY, _, _, "a", 1);
}

GetWeekdayAutoDay()
{
    new iDay = S16_DAY_NONE;

    switch (s16_get_weekday())
    {
        case 0: iDay = S16_DAY_SUNDAY_FD;   // Duminica
        case 1: iDay = S16_DAY_BOX;         // Luni
        case 2: iDay = S16_DAY_GUN;         // Marti
        case 3: iDay = S16_DAY_HNS;         // Miercuri
        case 4: iDay = S16_DAY_WAR;         // Joi
        case 5: iDay = S16_DAY_ZOMBIE;      // Vineri
        default: iDay = S16_DAY_NONE;       // Sambata - Simon alege
    }

    return iDay;
}

public TaskAutoDay()
{
    // Simon a ales deja o zi manuala? atunci rotatia nu mai suprascrie
    if (g_iDay != S16_DAY_NONE)
        return;

    StartDay(g_iAutoDay, true);
}

ApplySundayFreeDay()
{
    g_iDay = S16_DAY_SUNDAY_FD;

    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ce", "TERRORIST");

    for (new i = 0; i < iNum; i++)
    {
        if (!s16_has_freeday(iPlayers[i]))
            s16_set_freeday(iPlayers[i], true);
    }

    S16_PlaySoundAll("sectia16/win");

    set_dhudmessage(0, 255, 120, -1.0, 0.20, 0, 10.0, 6.0);
    show_dhudmessage(0, "*** DUMINICA - FREEDAY GLOBAL! ***^nToti detinutii sunt liberi. Nimeni nu da ordine!");

    S16_PrintAll("^4[SECTIA 16]^1 E ^4Duminica^1! FREEday global automat - detinutii primesc modelul de freeday.");
    S16_PrintAll("^4[SECTIA 16]^1 Gardienii doar pazesca. Fara ordine, fara restrictii!");
}

/* ====================================================
*   MENIU ZILE (Simon)
*  ==================================================== */

public CmdDayMenu(id)
{
    if (id != s16_get_simon())
    {
        S16_Print(id, "^4[SECTIA 16]^1 Doar Simonul poate declara zilele.");
        return PLUGIN_HANDLED;
    }

    if (!is_user_alive(id))
    {
        S16_Print(id, "^4[SECTIA 16]^1 Simonul mort nu mai declara nimic.");
        return PLUGIN_HANDLED;
    }

    if (g_iDay == S16_DAY_SUNDAY_FD)
    {
        S16_Print(id, "^4[SECTIA 16]^1 E ^4Duminica^1 - FREEday global! Nu se schimba nimic astazi.");
        return PLUGIN_HANDLED;
    }

    if (g_iDay != S16_DAY_NONE)
    {
        new szDay[40];
        GetDayName(g_iDay, szDay, charsmax(szDay));
        S16_Print(id, "^4[SECTIA 16]^1 Azi deja e ^3%s^1. Maine, maine.", szDay);
        return PLUGIN_HANDLED;
    }

    new iMenu = menu_create("\r[SECTIA 16] \yAlege Ziua^n\dRulatia auto poate fi suprascrisa", "DayMenuHandler");

    menu_additem(iMenu, "\wZiua \rBox^n\dCutite pentru toti, HP egal", "1");
    menu_additem(iMenu, "\wGun \yDay^n\dDetinutii primesc arme aleatorii", "2");
    menu_additem(iMenu, "\wAscunselea \r(HNS)^n\dGardienii inghetati si orbi 40s", "3");
    menu_additem(iMenu, "\wWar \rDay^n\dDetinutii primesc AK47, razboi!", "4");
    menu_additem(iMenu, "\wZombie \yDay^n\dDetinutii zombii, 500 HP, doar cutit", "5");
    menu_additem(iMenu, "\wZiua de \rGratar^n\dCutite in flacari vs 2000 HP", "6");
    menu_additem(iMenu, "\wProtopopiat \y(Apa Sfanta)^n\dAWP infinit vs invizibili", "7");
    menu_additem(iMenu, "\wGreva \rFoamei^n\dGravitatie 0.5, foamea loveste", "8");
    menu_additem(iMenu, "\dAnuleaza - ramane ziua din rotatie", "9");

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

    if (id != s16_get_simon() || g_iDay != S16_DAY_NONE || g_iDay == S16_DAY_SUNDAY_FD)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[3], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    switch (szInfo[0])
    {
        case '1': StartDay(S16_DAY_BOX, false);
        case '2': StartDay(S16_DAY_GUN, false);
        case '3': StartDay(S16_DAY_HNS, false);
        case '4': StartDay(S16_DAY_WAR, false);
        case '5': StartDay(S16_DAY_ZOMBIE, false);
        case '6': StartDay(S16_DAY_GRATAR, false);
        case '7': StartDay(S16_DAY_PROTOPOPIAT, false);
        case '8': StartDay(S16_DAY_GREVA, false);
        case '9':
        {
            remove_task(TASK_AUTODAY);
            S16_Print(id, "^4[SECTIA 16]^1 Zi normala. Plictiseala, ordine, beton.");
        }
    }

    return PLUGIN_HANDLED;
}

/* ====================================================
*   PORNIRE ZILE
*  ==================================================== */

StartDay(const iDay, const bool:bAuto)
{
    g_iDay = iDay;

    new szDay[40];
    GetDayName(iDay, szDay, charsmax(szDay));

    if (bAuto)
        S16_PrintAll("^4[SECTIA 16]^1 Ziua programata: ^3%s^1. Simonul poate schimba prin ^3/zi^1.", szDay);
    else
        S16_PrintAll("^4[SECTIA 16]^1 Simonul a declarat: ^3%s^1. Sa inceapa nebunia!", szDay);

    switch (iDay)
    {
        case S16_DAY_BOX:
        {
            S16_PlaySoundAll("sectia16/ding");

            set_dhudmessage(255, 200, 0, -1.0, 0.20, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** ZIUA BOX ***^nCutite pentru toti, HP egal. Box in arena!");

            new iPlayers[MAX_PLAYERS], iNum;
            get_players(iPlayers, iNum, "ae");
            for (new i = 0; i < iNum; i++)
            {
                S16_StripToKnife(iPlayers[i]);
                set_pev(iPlayers[i], pev_health, 100.0);
                rg_reset_maxspeed(iPlayers[i]);
            }
        }

        case S16_DAY_GUN:
        {
            set_dhudmessage(255, 80, 0, -1.0, 0.20, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** GUN DAY ***^nDetinutii primesc arme. Ultimul care supravietuieste castiga!");

            new iPlayers[MAX_PLAYERS], iNum;
            get_players(iPlayers, iNum, "ae", "TERRORIST");
            for (new i = 0; i < iNum; i++)
            {
                new iGun = random(sizeof(g_szGunDayGuns));
                rg_remove_all_items(iPlayers[i], false);
                rg_give_item(iPlayers[i], "weapon_knife");
                rg_give_item(iPlayers[i], g_szGunDayGuns[iGun]);
                rg_set_user_bpammo(iPlayers[i], g_iGunDayIds[iGun], 90);
            }

            set_task(0.5, "TaskDayEffects", TASK_EFFECTS, _, _, "b");
        }

        case S16_DAY_HNS:
        {
            set_dhudmessage(120, 200, 255, -1.0, 0.20, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** ASCUNSELEA ***^nGardienii inghetati si orbi 40 de secunde! Detinutii, ascundeti-va!");

            new iPlayers[MAX_PLAYERS], iNum;
            get_players(iPlayers, iNum, "ae", "TERRORIST");
            for (new i = 0; i < iNum; i++)
                S16_StripToKnife(iPlayers[i]);

            // gardienii inghetati si orbi
            get_players(iPlayers, iNum, "ae", "CT");
            for (new i = 0; i < iNum; i++)
            {
                S16_Freeze(iPlayers[i], 40.0);
                S16_ScreenFade(iPlayers[i], 6, 6, 0, 0, 0, 255, 0x0008);
            }

            set_task(40.0, "TaskHnsRelease", TASK_HNS, _, _, "a", 1);
        }

        case S16_DAY_WAR:
        {
            set_dhudmessage(255, 0, 0, -1.0, 0.20, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** WAR DAY ***^nDetinutii primesc AK47 + Deagle. Razboi general!");

            new iPlayers[MAX_PLAYERS], iNum;
            get_players(iPlayers, iNum, "ae", "TERRORIST");
            for (new i = 0; i < iNum; i++)
            {
                new id = iPlayers[i];
                rg_remove_all_items(id, false);
                rg_give_item(id, "weapon_knife");
                rg_give_item(id, "weapon_ak47");
                rg_give_item(id, "weapon_deagle");
                rg_set_user_bpammo(id, WEAPON_AK47, 90);
                rg_set_user_bpammo(id, WEAPON_DEAGLE, 35);
                set_pev(id, pev_health, 100.0);
                rg_set_user_armor(id, 100, ARMOR_VESTHELM);
            }

            get_players(iPlayers, iNum, "ae", "CT");
            for (new i = 0; i < iNum; i++)
                set_pev(iPlayers[i], pev_health, 100.0);
        }

        case S16_DAY_ZOMBIE:
        {
            set_dhudmessage(0, 255, 0, -1.0, 0.20, 0, 8.0, 5.0);
            show_dhudmessage(0, "*** ZOMBIE DAY ***^nDetinutii sunt zombii: 500 HP, doar cutit! Gardienii, aparati-va!");

            new iPlayers[MAX_PLAYERS], iNum;
            get_players(iPlayers, iNum, "ae", "TERRORIST");
            for (new i = 0; i < iNum; i++)
            {
                new id = iPlayers[i];
                S16_StripToKnife(id);
                set_pev(id, pev_health, 500.0);
                set_pev(id, pev_maxspeed, 290.0);
                S16_RenderGlow(id, 0, 255, 0, 40);
            }

            set_task(0.5, "TaskDayEffects", TASK_EFFECTS, _, _, "b");
        }

        case S16_DAY_GRATAR:
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

        case S16_DAY_PROTOPOPIAT:
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

        case S16_DAY_GREVA:
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
}

/* ====================================================
*   TASK-URI ZILE
*  ==================================================== */

public TaskHnsRelease()
{
    if (g_iDay != S16_DAY_HNS)
        return;

    S16_PlaySoundAll("sectia16/fluierat");

    set_dhudmessage(255, 200, 0, -1.0, 0.25, 0, 6.0, 4.0);
    show_dhudmessage(0, "*** GARDIENII AU DEZGHETAT! ***^nAscunselea a inceput!");

    S16_PrintAll("^4[SECTIA 16]^1 Gardienii s-au dezghetat. Ascunselea incepe!");
}

public TaskFlameTrails()
{
    if (g_iDay != S16_DAY_GRATAR)
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
    if (g_iDay == S16_DAY_NONE)
    {
        remove_task(TASK_EFFECTS);
        return;
    }

    if (g_iDay == S16_DAY_PROTOPOPIAT)
    {
        new iPlayers[MAX_PLAYERS], iNum;
        get_players(iPlayers, iNum, "ae", "TERRORIST");

        for (new i = 0; i < iNum; i++)
        {
            S16_RenderInvisible(iPlayers[i], 40);
            set_pev(iPlayers[i], pev_maxspeed, 400.0);   // +150 peste baza
        }
    }
    else if (g_iDay == S16_DAY_GREVA)
    {
        new iPlayers[MAX_PLAYERS], iNum;
        get_players(iPlayers, iNum, "a");

        for (new i = 0; i < iNum; i++)
            set_pev(iPlayers[i], pev_gravity, 0.5);
    }
}

public TaskInfiniteAmmo()
{
    if (g_iDay != S16_DAY_PROTOPOPIAT)
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
    if (g_iDay != S16_DAY_GREVA)
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
    if (S16_CountAlive(TEAM_TERRORIST) == 1 && iNum > 0)
        HungerStrikeWinner(iPlayers[0]);
}

HungerStrikeWinner(const id)
{
    if (g_iDay != S16_DAY_GREVA || !is_user_alive(id))
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
    if (g_iDay != S16_DAY_GRATAR)
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
    g_iDay = S16_DAY_NONE;

    remove_task(TASK_FLAME);
    remove_task(TASK_EFFECTS);
    remove_task(TASK_SLAP);
    remove_task(TASK_AMMO);
    remove_task(TASK_AUTODAY);
    remove_task(TASK_HNS);

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

public EventDeathMsg()
{
    if (g_iDay != S16_DAY_GREVA)
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
        case S16_DAY_BOX:         copy(szOut, iLen, "Ziua Box");
        case S16_DAY_GUN:         copy(szOut, iLen, "Gun Day");
        case S16_DAY_HNS:         copy(szOut, iLen, "Ascunselea");
        case S16_DAY_WAR:         copy(szOut, iLen, "War Day");
        case S16_DAY_ZOMBIE:      copy(szOut, iLen, "Zombie Day");
        case S16_DAY_GRATAR:      copy(szOut, iLen, "Ziua de Gratar");
        case S16_DAY_PROTOPOPIAT: copy(szOut, iLen, "Protopopiat (Apa Sfanta)");
        case S16_DAY_GREVA:       copy(szOut, iLen, "Greva Foamei");
        case S16_DAY_SUNDAY_FD:   copy(szOut, iLen, "Duminica - Freeday Global");
        default:                  copy(szOut, iLen, "Zi Normala");
    }
}
