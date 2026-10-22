/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Include partajat: natives cross-plugin + utilitare comune.
*
*   Stack: ReHLDS + ReGameDLL + ReAPI + AMX Mod X 1.10
*
*   v2.0 - rescriere completa:
*     - FIX CRASH TE_BEAMPOINTS / TE_BEAMCYLINDER: ordinea CORECTA a parametrilor
*       (startframe + framerate obligatorii) + validari stricte de limite ale hartii,
*       valabilitate entitati si is_user_connected / is_user_alive inainte de orice
*       mesaj de retea (S16_DrawBeam / S16_DrawRing).
*     - nativi noi: freeday individual / coada freeday, rebel, VIP/admin, voce LR.
*/

#if defined _sectia16_included
    #endinput
#endif

#define _sectia16_included

#include <amxmodx>
#include <reapi>
#include <fakemeta>

/* ====================================================
*   ZILE (detinute de sectia16_days.amxx)
*  ==================================================== */

enum (+= 1)
{
    S16_DAY_NONE = -1,
    S16_DAY_BOX = 0,        // Luni     - Ziua Box (cutite, HP egal)
    S16_DAY_GUN,            // Marti    - Gun Day (detinuti inarmati)
    S16_DAY_HNS,            // Miercuri - Ascunselea (gardieni inghetati+orbiri)
    S16_DAY_WAR,            // Joi      - War Day (razboi general)
    S16_DAY_ZOMBIE,         // Vineri   - Zombie Day (detinuti zombii 500 HP)
    S16_DAY_GRATAR,         // Ziua de Gratar (cutite in flacari vs 2000 HP)
    S16_DAY_PROTOPOPIAT,    // Protopopiat (AWP infinit vs invizibili)
    S16_DAY_GREVA,          // Greva Foamei (gravitatie + foamea loveste)
    S16_DAY_SUNDAY_FD       // Duminica - FREEday GLOBAL automat
}

/* ====================================================
*   NATIVES CROSS-PLUGIN
*  ==================================================== */

// ===== sectia16_core.amxx =================================

// credite (vault, per SteamID)
native s16_get_credits(const id);
native s16_add_credits(const id, const amount);
native bool:s16_spend_credits(const id, const amount);

// freeday individual (runda curenta)
native s16_set_freeday(const id, const bool:on);
native bool:s16_has_freeday(const id);

// freeday garantat runda viitoare (recompensa Last Request)
native s16_queue_freeday(const id);

// rebel (detinut care a atacat un gardian)
native s16_set_rebel(const id, const bool:on);
native bool:s16_is_rebel(const id);

// VIP = flag "t" (ADMIN_LEVEL_H) | Admin = flag "y" (ADMIN_ADMIN)
native bool:s16_is_vip(const id);
native bool:s16_is_admin(const id);

// permisiune de voce in timpul Last Request-ului
native s16_set_lr_voice(const id, const bool:on);
native bool:s16_is_lr_voice(const id);

// ziua saptamanii pe server: 0 = Duminica ... 6 = Sambata
native s16_get_weekday();

// ===== sectia16_simon.amxx =================================

// indexul Simonului curent (0 = nimeni)
native s16_get_simon();

// ===== sectia16_days.amxx ==================================

// ziua activa (S16_DAY_NONE = -1 inseamna zi normala)
native s16_get_day();

/* ====================================================
*   DEFINITII
*  ==================================================== */

#define TASK_S16_UNFREEZE 516000

// limitele lumii GoldSrc (harta standard: +/- 4096 unitati)
#define S16_WORLD_MIN  -4096.0
#define S16_WORLD_MAX   4096.0

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
*   VALIDARI GEOMETRIE - FIX CRASH TE_BEAMPOINTS/CYLINDER
*
*   Orice mesaj de retea cu coordonate trece obligatoriu prin:
*     1) S16_ValidPoint  - punct in limitele lumii
*     2) S16_ClampPoint  - aducere forte in limite
*     3) S16_DrawBeam / S16_DrawRing - ordinea CORECTA si
*        COMPLETA a parametrilor TE_ (startframe + framerate
*        erau omisi in v1 -> mesaj cu 2 bytes mai scurt decat
*        citeste parserul motorului = Host_Error / crash).
*  ==================================================== */

stock bool:S16_ValidPoint(const Float:fPoint[3])
{
    for (new i = 0; i < 3; i++)
    {
        if (fPoint[i] > S16_WORLD_MAX || fPoint[i] < S16_WORLD_MIN)
            return false;
    }
    return true;
}

stock S16_ClampPoint(Float:fPoint[3])
{
    for (new i = 0; i < 3; i++)
    {
        if (fPoint[i] > S16_WORLD_MAX - 96.0)
            fPoint[i] = S16_WORLD_MAX - 96.0;
        else if (fPoint[i] < S16_WORLD_MIN + 96.0)
            fPoint[i] = S16_WORLD_MIN + 96.0;
    }
}

// TE_BEAMPOINTS (id engine = 0): linie sigura intre doua puncte validate.
stock bool:S16_DrawBeam(const iSprite, Float:fStart[3], Float:fEnd[3], const iR, const iG, const iB, const iLife, const iWidth)
{
    if (!iSprite)
        return false;

    S16_ClampPoint(fStart);
    S16_ClampPoint(fEnd);

    if (!S16_ValidPoint(fStart) || !S16_ValidPoint(fEnd))
        return false;

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMPOINTS);
    write_coord(floatround(fStart[0]));
    write_coord(floatround(fStart[1]));
    write_coord(floatround(fStart[2]));
    write_coord(floatround(fEnd[0]));
    write_coord(floatround(fEnd[1]));
    write_coord(floatround(fEnd[2]));
    write_short(iSprite);
    write_byte(0);          // starting frame
    write_byte(0);          // frame rate
    write_byte(iLife);      // viata (unitati de 0.1s)
    write_byte(iWidth);     // latime
    write_byte(0);          // amplitudine (0 = linie fixa)
    write_byte(iR);
    write_byte(iG);
    write_byte(iB);
    write_byte(200);        // luminozitate
    write_byte(30);         // viteza de scroll
    message_end();

    return true;
}

// TE_BEAMCYLINDER (id engine = 21): inel/cilindru sigur in jurul unui punct.
stock bool:S16_DrawRing(const iSprite, Float:fCenter[3], const Float:fRadius, const iR, const iG, const iB, const iLife, const iWidth)
{
    if (!iSprite || fRadius <= 0.0 || fRadius > 900.0)
        return false;

    S16_ClampPoint(fCenter);

    if (!S16_ValidPoint(fCenter))
        return false;

    new Float:fEnd[3];
    fEnd[0] = fCenter[0];
    fEnd[1] = fCenter[1];
    fEnd[2] = fCenter[2] + fRadius;

    S16_ClampPoint(fEnd);

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMCYLINDER);
    write_coord(floatround(fCenter[0]));
    write_coord(floatround(fCenter[1]));
    write_coord(floatround(fCenter[2]));
    write_coord(floatround(fEnd[0]));
    write_coord(floatround(fEnd[1]));
    write_coord(floatround(fEnd[2]));
    write_short(iSprite);
    write_byte(0);          // starting frame
    write_byte(0);          // frame rate
    write_byte(iLife);      // viata (unitati de 0.1s)
    write_byte(iWidth);     // latime
    write_byte(0);          // amplitudine
    write_byte(iR);
    write_byte(iG);
    write_byte(iB);
    write_byte(200);        // luminozitate
    write_byte(30);         // viteza de scroll
    message_end();

    return true;
}

/* ====================================================
*   SUNETE (cu protectie fisiere lipsa - zero erori runtime)
*  ==================================================== */

// pre-cache .wav (szSpkPath = cale fara "sound/" si fara ".wav")
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

// muzica (wav sau mp3). szRelPath = cale sub sound/, cu extensie.
// ex: "sectia16/manele/manea1.wav" sau "sectia16/manele/guta.mp3"
stock S16_PrecacheMusic(const szRelPath[])
{
    new szPath[160];
    formatex(szPath, charsmax(szPath), "sound/%s", szRelPath);

    if (!file_exists(szPath))
        return;

    new iLen = strlen(szRelPath);
    if (iLen > 4 && equali(szRelPath[iLen - 4], ".mp3"))
        precache_generic(szPath);   // mp3: intrare in tabelul de download
    else
        precache_sound(szRelPath);  // wav: pre-cache clasic
}

stock bool:S16_PlayMusicAll(const szRelPath[])
{
    new szPath[160];
    formatex(szPath, charsmax(szPath), "sound/%s", szRelPath);

    if (!file_exists(szPath))
        return false;

    new iLen = strlen(szRelPath);
    if (iLen > 4 && equali(szRelPath[iLen - 4], ".mp3"))
    {
        client_cmd(0, "mp3 play sound/%s", szRelPath);
    }
    else
    {
        new szSpk[160];
        copy(szSpk, charsmax(szSpk), szRelPath);
        if (iLen > 4 && equali(szSpk[iLen - 4], ".wav"))
            szSpk[iLen - 4] = 0;
        client_cmd(0, "spk %s", szSpk);
    }

    return true;
}

// opreste INSTANT orice sunet/muzica pentru toti clientii
stock S16_StopMusicAll()
{
    client_cmd(0, "mp3 stop");
    client_cmd(0, "stopsound");
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
