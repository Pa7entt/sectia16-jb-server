/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Echipament CT & Reload Infinit v2.1:
*
*     - Meniu de arme la spawn pentru gardieni: AK47, M4A1, MP5,
*       Famas, XM1014, M249 (+ kevlar + casti + defuser + Deagle).
*
*     - RELOAD INFINIT (rezerva infinita) STRICT pentru AK47 si
*       Deagle, DOAR pentru gardieni (CT):
*         * jucatorul consuma incarcatorul si face animatia
*           NORMALA de reload (fara clip infinit, fara reload instant);
*         * la fiecare reload, rezerva (backpack ammo) este reumpluta
*           automat la maxim prin rg_set_user_bpammo;
*         * rezerva nu scade niciodata vizibil sub un incarcator.
*
*     - Detinutii NU beneficiaza: echipa este verificata in interiorul
*       hook-ului de reload (un T care ridica AK47/Deagle-ul de jos are
*       rezerva normala, limitata).
*
*     Implementare: Ham_Weapon_Reload (post) pe entitatile
*     weapon_ak47 / weapon_deagle. Post-hook-ul porneste inainte ca
*     motorul sa scada gloantele din rezerva (scaderea are loc la
*     finalul animatiei, in ItemPostFrame), deci refill-ul de aici
*     garanteaza ca niciodata rezerva nu se goleste.
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <hamsandwich>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Echipament CT & Reload Infinit"
#define VERSION "2.1.0"
#define AUTHOR  "SECTIA 16"

#define TASK_EQUIP_MENU 627100

enum (+= 1)
{
    WPN_AK47 = 0,
    WPN_M4A1,
    WPN_MP5,
    WPN_FAMAS,
    WPN_XM1014,
    WPN_M249,
    WPN_COUNT
}

new const g_szWeaponNames[WPN_COUNT][] =
{
    "AK47", "M4A1", "MP5 Navy", "Famas", "XM1014", "M249"
};

new const g_szWeaponEnts[WPN_COUNT][] =
{
    "weapon_ak47", "weapon_m4a1", "weapon_mp5navy", "weapon_famas", "weapon_xm1014", "weapon_m249"
};

new const WeaponIdType:g_iWeaponIds[WPN_COUNT] =
{
    WEAPON_AK47, WEAPON_M4A1, WEAPON_MP5N, WEAPON_FAMAS, WEAPON_XM1014, WEAPON_M249
};

// rezerva standard per arma (celelalte arme raman cu rezerva FINITA)
new const g_iWeaponBpammo[WPN_COUNT] =
{
    90, 90, 120, 90, 32, 200
};

// rezerva maxima pentru armele cu reload infinit
new const g_iInfiniteBpammo[2] = { 90, 35 };   // AK47, Deagle

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", true);

    // ===== RELOAD INFINIT: hook pe inceperea reload-ului =====
    // post = 1: rulam DUPA ce arma valideaza reload-ul (clip < max,
    // rezerva > 0), dar INAINTE ca motorul sa scada gloantele din
    // rezerva (scaderea are loc la finalul animatiei).
    RegisterHam(Ham_Weapon_Reload, "weapon_ak47",   "OnWeaponReloadPost", true);
    RegisterHam(Ham_Weapon_Reload, "weapon_deagle", "OnWeaponReloadPost", true);
}

public plugin_precache()
{
    S16_PrecacheSound("sectia16/ding");
}

/* ====================================================
*   SPAWN CT: echipament de baza + meniu de arme
*  ==================================================== */

public OnPlayerSpawn(const id)
{
    if (!is_user_alive(id) || get_member(id, m_iTeam) != TEAM_CT)
        return;

    // pachetul de baza al gardianului
    rg_give_item(id, "item_assaultsuit");    // kevlar + casti
    rg_give_item(id, "item_thighpack");      // defuse kit
    rg_give_item(id, "weapon_deagle");
    rg_set_user_bpammo(id, WEAPON_DEAGLE, g_iInfiniteBpammo[1]);

    // meniul de arme apare dupa putin timp (spawn-ul sa se aseze)
    remove_task(id + TASK_EQUIP_MENU);
    set_task(0.6, "TaskShowEquipMenu", id + TASK_EQUIP_MENU, _, _, "a", 1);
}

public TaskShowEquipMenu(const iTaskId)
{
    new id = iTaskId - TASK_EQUIP_MENU;

    if (!is_user_connected(id) || !is_user_alive(id) || get_member(id, m_iTeam) != TEAM_CT)
        return;

    ShowEquipMenu(id);
}

ShowEquipMenu(const id)
{
    // zilele cu arme restrictionate blocheaza meniul
    new iDay = s16_get_day();

    if (iDay == S16_DAY_BOX || iDay == S16_DAY_HNS || iDay == S16_DAY_ZOMBIE || iDay == S16_DAY_GRATAR)
    {
        S16_Print(id, "^4[SECTIA 16]^1 Ziua curenta restrictioneaza armele gardienilor. Doar cutitul!");
        return;
    }

    new iMenu = menu_create("\r[SECTIA 16] \yEchipament Gardian^n\dAK47 si Deagle au rezerva infinita", "EquipMenuHandler");

    new szItem[96], szInfo[6];

    for (new i = 0; i < WPN_COUNT; i++)
    {
        if (i == WPN_AK47)
            formatex(szItem, charsmax(szItem), "\w%s \y[rezerva infinita]", g_szWeaponNames[i]);
        else
            formatex(szItem, charsmax(szItem), "\w%s", g_szWeaponNames[i]);

        num_to_str(i, szInfo, charsmax(szInfo));
        menu_additem(iMenu, szItem, szInfo);
    }

    menu_additem(iMenu, "\dRaman cu ce am^n\dUsor de guler, greu de buzunare", "x");

    menu_setprop(iMenu, MPROP_EXITNAME, "Inchide");
    menu_display(id, iMenu, 0);
}

public EquipMenuHandler(const id, const iMenu, const iItem)
{
    if (iItem == MENU_EXIT || iItem < 0)
    {
        menu_destroy(iMenu);
        return PLUGIN_HANDLED;
    }

    new iAccess, szInfo[6], szName[64], iCallback;
    menu_item_getinfo(iMenu, iItem, iAccess, szInfo, charsmax(szInfo), szName, charsmax(szName), iCallback);
    menu_destroy(iMenu);

    if (!is_user_alive(id) || get_member(id, m_iTeam) != TEAM_CT)
        return PLUGIN_HANDLED;

    if (szInfo[0] == 'x')
        return PLUGIN_HANDLED;

    new iWpn = str_to_num(szInfo);

    if (iWpn < 0 || iWpn >= WPN_COUNT)
        return PLUGIN_HANDLED;

    rg_give_item(id, g_szWeaponEnts[iWpn]);
    rg_set_user_bpammo(id, g_iWeaponIds[iWpn], g_iWeaponBpammo[iWpn]);
    rg_give_item(id, "item_assaultsuit");

    S16_PlaySound(id, "sectia16/ding");

    if (iWpn == WPN_AK47)
        S16_Print(id, "^4[SECTIA 16]^1 Ai primit ^3AK47^1 cu ^4rezerva infinita^1 (reload normal, gloante fara fund).");
    else
        S16_Print(id, "^4[SECTIA 16]^1 Ai primit ^3%s^1 + %d gloante in rezerva.", g_szWeaponNames[iWpn], g_iWeaponBpammo[iWpn]);

    return PLUGIN_HANDLED;
}

/* ====================================================
*   RELOAD INFINIT - STRICT AK47 + DEAGLE, STRICT CT
*
*   Ham_Weapon_Reload (post) pe entitatea armei:
*     1. scoatem ownerul (pev_owner) si il validam;
*     2. STRICT CT (m_iTeam) - detinutul care fura arma de
*        jos NU primeste refill;
*     3. reumplem rezerva la maxim - motorul va scadea un
*        incarcator la finalul animatiei, deci rezerva pare
*        mereu plina. Animatia de reload rămane CEA NORMALA.
*  ==================================================== */

public OnWeaponReloadPost(const iEnt)
{
    if (pev_valid(iEnt) != 2)
        return HAM_IGNORED;

    new id = pev(iEnt, pev_owner);

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    // STRICT gardieni - detinutii au rezerva normala
    if (get_member(id, m_iTeam) != TEAM_CT)
        return HAM_IGNORED;

    new szClass[24];
    pev(iEnt, pev_classname, szClass, charsmax(szClass));

    if (equal(szClass, "weapon_ak47"))
        rg_set_user_bpammo(id, WEAPON_AK47, g_iInfiniteBpammo[0]);
    else if (equal(szClass, "weapon_deagle"))
        rg_set_user_bpammo(id, WEAPON_DEAGLE, g_iInfiniteBpammo[1]);
    else
        return HAM_IGNORED;

    return HAM_IGNORED;
}
