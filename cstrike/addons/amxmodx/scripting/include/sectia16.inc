/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Include partajat: natives cross-plugin + utilitare comune.
*
*   Stack: ReHLDS + ReGameDLL + ReAPI + AMX Mod X 1.10
*/

#if defined _sectia16_included
    #endinput
#endif

#define _sectia16_included

#include <amxmodx>
#include <reapi>
#include <fakemeta>

/* ====================================================
*   NATIVES CROSS-PLUGIN
*  ==================================================== */

// sectia16_simon.amxx -> indexul Simonului curent (0 = nimeni)
native s16_get_simon();

// sectia16_days.amxx -> ziua activa (-1 = zi normala)
native s16_get_day();

// sectia16_shop.amxx -> creditele detinutului
native s16_get_credits(const id);

// sectia16_shop.amxx -> adauga/scade credite (poate fi negativ), returneaza soldul nou
native s16_add_credits(const id, const amount);

/* ====================================================
*   DEFINITII
*  ==================================================== */

#define TASK_S16_UNFREEZE 516000

/* ====================================================
*   CHAT COLORAT
*  ==================================================== */

stock S16_Print(const id, const szFmt[], any:...)
{
    new szMsg[192];
    vformat(szMsg, charsmax(szMsg), szFmt, 3);
    client_print_color(id, print_team_default, "%s", szMsg);
}

stock S16_PrintAll(const szFmt[], any:...)
{
    new szMsg[192];
    vformat(szMsg, charsmax(szMsg), szFmt, 2);
    client_print_color(0, print_team_default, "%s", szMsg);
}

/* ====================================================
*   RENDER (invizibilitate / glow)
*  ==================================================== */

stock S16_RenderInvisible(const id, const iAmount)
{
    set_pev(id, pev_rendermode, kRenderTransTexture);
    set_pev(id, pev_renderfx, kRenderFxNone);
    set_pev(id, pev_renderamt, float(iAmount));
}

stock S16_RenderGlow(const id, const r, const g, const b, const iAmount = 60)
{
    set_pev(id, pev_renderfx, kRenderFxGlowShell);
    set_pev(id, pev_rendermode, kRenderNormal);
    set_pev(id, pev_renderamt, float(iAmount));
    new Float:fColor[3];
    fColor[0] = float(r);
    fColor[1] = float(g);
    fColor[2] = float(b);
    set_pev(id, pev_rendercolor, fColor);
}

stock S16_RenderReset(const id)
{
    set_pev(id, pev_renderfx, kRenderFxNone);
    set_pev(id, pev_rendermode, kRenderNormal);
    set_pev(id, pev_renderamt, 255.0);
    new Float:fColor[3] = { 255.0, 255.0, 255.0 };
    set_pev(id, pev_rendercolor, fColor);
}

/* ====================================================
*   INGHET (FL_FROZEN)
*  ==================================================== */

stock S16_Freeze(const id, const Float:fSeconds)
{
    if (!is_user_alive(id))
        return;

    remove_task(id + TASK_S16_UNFREEZE);
    set_pev(id, pev_flags, pev(id, pev_flags) | FL_FROZEN);
    set_task(fSeconds, "S16_TaskUnfreeze", id + TASK_S16_UNFREEZE);
}

public S16_TaskUnfreeze(const iTaskId)
{
    new id = iTaskId - TASK_S16_UNFREEZE;
    if (is_user_alive(id))
        set_pev(id, pev_flags, pev(id, pev_flags) & ~FL_FROZEN);
}

/* ====================================================
*   SUNETE (cu protectie fisiere lipsa - zero erori runtime)
*  ==================================================== */

stock S16_PrecacheSound(const szSpkPath[])
{
    new szFile[96];
    formatex(szFile, charsmax(szFile), "%s.wav", szSpkPath);

    new szPath[144];
    formatex(szPath, charsmax(szPath), "sound/%s", szFile);

    if (file_exists(szPath))
        precache_sound(szFile);
}

stock bool:S16_CanPlay(const szSpkPath[])
{
    new szPath[144];
    formatex(szPath, charsmax(szPath), "sound/%s.wav", szSpkPath);
    return file_exists(szPath) != 0;
}

stock S16_PlaySoundAll(const szSpkPath[])
{
    if (S16_CanPlay(szSpkPath))
        client_cmd(0, "spk %s", szSpkPath);
}

stock S16_PlaySound(const id, const szSpkPath[])
{
    if (is_user_connected(id) && S16_CanPlay(szSpkPath))
        client_cmd(id, "spk %s", szSpkPath);
}

/* ====================================================
*   EFECTE ECRAN
*  ==================================================== */

// iFlags: 0x0001 = FFADE_OUT, 0x0000 = FFADE_IN, 0x0008 = FFADE_STAYOUT
stock S16_ScreenFade(const id, const iDurationSec, const iHoldSec, const r, const g, const b, const iAlpha, const iFlags = 0x0001)
{
    new iMsg = get_user_msgid("ScreenFade");

    if (id > 0)
        message_begin(MSG_ONE_UNRELIABLE, iMsg, _, id);
    else
        message_begin(MSG_BROADCAST, iMsg);

    write_short((iDurationSec & 0x07) << 12);
    write_short((iHoldSec & 0x07) << 12);
    write_short(iFlags);
    write_byte(r);
    write_byte(g);
    write_byte(b);
    write_byte(iAlpha);
    message_end();
}

stock S16_ScreenShake(const id, const iAmplitude, const iDurationSec, const iFrequency)
{
    new iMsg = get_user_msgid("ScreenShake");

    if (id > 0)
        message_begin(MSG_ONE_UNRELIABLE, iMsg, _, id);
    else
        message_begin(MSG_BROADCAST, iMsg);

    write_short(iAmplitude);
    write_short(iDurationSec << 11);
    write_short(iFrequency);
    message_end();
}

/* ====================================================
*   ECHIPAMENT
*  ==================================================== */

stock S16_StripToKnife(const id)
{
    rg_remove_all_items(id, false);
    rg_give_item(id, "weapon_knife");
}

/* ====================================================
*   ECHIPE & DIVERSE
*  ==================================================== */

stock S16_CountAlive(const TeamName:team)
{
    new iPlayers[MAX_PLAYERS], iNum;
    switch (team)
    {
        case TEAM_TERRORIST: get_players(iPlayers, iNum, "ae", "TERRORIST");
        case TEAM_CT:        get_players(iPlayers, iNum, "ae", "CT");
        default:             get_players(iPlayers, iNum, "a");
    }
    return iNum;
}

stock S16_Lower(szText[])
{
    for (new i = 0; szText[i]; i++)
    {
        if (szText[i] >= 'A' && szText[i] <= 'Z')
            szText[i] += 32;
    }
}
