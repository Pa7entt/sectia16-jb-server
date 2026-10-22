/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Echipament CT & Munitie Infinita v2.0:
*
*     - Meniu de arme la spawn pentru gardieni: AK47, M4A1, MP5,
*       Famas, XM1014, M249 (+ kevlar + casti + defuser + Deagle).
*     - Munitie infinita STRICT pentru AK47 si Deagle, DOAR pentru
*       gardieni (CT). Daca un detinut ridica arma de jos, NU primeste
*       munitie infinita - verificam echipa la fiecare eveniment CurWeapon.
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Echipament CT"
#define VERSION "2.0.0"
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

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", true);

    register_event("CurWeapon", "EventCurWeapon", "be", "1=1");
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
    rg_set_user_bpammo(id, WEAPON_DEAGLE, 35);

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

    new iMenu = menu_create("\r[SECTIA 16] \yEchipament Gardian^n\dAlege-ti arma de serviciu", "EquipMenuHandler");

    new szItem[96], szInfo[6];

    for (new i = 0; i < WPN_COUNT; i++)
    {
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
    rg_set_user_bpammo(id, g_iWeaponIds[iWpn], 200);
    rg_give_item(id, "item_assaultsuit");

    S16_PlaySound(id, "sectia16/ding");
    S16_Print(id, "^4[SECTIA 16]^1 Ai primit ^3%s^1 + munitie. Ak47 si Deagle au ^4gloante infinite^1!", g_szWeaponNames[iWpn]);

    return PLUGIN_HANDLED;
}

/* ====================================================
*   MUNITIE INFINITA - STRICT AK47 + DEAGLE, STRICT CT
*
*   Verificarea echipei la FIECARE eveniment CurWeapon garanteaza
*   ca un detinut care ridica arma de jos NU beneficiaza de
*   munitie infinita.
*  ==================================================== */

public EventCurWeapon(const id)
{
    if (!is_user_alive(id))
        return;

    // STRICT gardieni - detinutii nu primesc nimic
    if (get_member(id, m_iTeam) != TEAM_CT)
        return;

    new iWeapon = read_data(2);

    if (iWeapon == CSW_AK47)
    {
        rg_set_user_bpammo(id, WEAPON_AK47, 90);
        rg_instant_reload_weapons(id);
    }
    else if (iWeapon == CSW_DEAGLE)
    {
        rg_set_user_bpammo(id, WEAPON_DEAGLE, 35);
        rg_instant_reload_weapons(id);
    }
}
