/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Minge de Fotbal v2.1:
*
*     - mingea apare la picioarele celui care o cere:
*       Simon (meniul sau) sau Admin (meniul admin);
*     - fizica COMPLETA:
*         * MOVETYPE_BOUNCE - sare din pereti, usi, jucatori;
*         * gravitatie proprie (cade natural, sare la poticnire);
*         * frictiune de rostogolire - se opreste singura, natural;
*     - IMPINSARE la atingere: mergi in mingea si ea pleaca in
*       fata ta (directia mergei + directia privirii);
*     - LOVIRE cu glontul: orice arma (AK, Deagle, AWP...);
*       trasul din mingea o azvarle in directia privirii;
*     - protectie anti-bug: daca iese din harta (gaura in sol,
*       bug de harta), revine SINGURA la punctul unde a fost
*       aruncata in teren;
*     - limita de viteza (anti-racheta) si cooldown de impingere
*       (anti-machine-gun cu mingea);
*     - dispare automat la finalul rundei.
*
*   MODEL: foloseste models/w_smokegrenade.mdl (rotund, exista
*   garantat pe orice server CS). Vrei o minge adevarata?
*   Pune orice .mdl la models/sectia16/ball.mdl - e preluat
*   automat, cu precache inclus.
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <hamsandwich>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Minge Fotbal"
#define VERSION "2.1.0"
#define AUTHOR  "SECTIA 16"

#define TASK_BALL_THINK 629100

new const BALL_CLASSNAME[]    = "sectia16_ball";
new const BALL_MODEL_CUSTOM[] = "models/sectia16/ball.mdl";
new const BALL_MODEL_FALLBACK[] = "models/w_smokegrenade.mdl";

// armele cu care mingea poate fi lovita cu glont (PrimaryAttack)
new const g_szShootable[][] =
{
    "weapon_ak47", "weapon_m4a1", "weapon_deagle", "weapon_glock18",
    "weapon_usp", "weapon_famas", "weapon_galil", "weapon_mp5navy",
    "weapon_xm1014", "weapon_m3", "weapon_awp", "weapon_scout",
    "weapon_mac10", "weapon_tmp", "weapon_ump45", "weapon_p90",
    "weapon_g3sg1", "weapon_sg550", "weapon_sg552", "weapon_aug",
    "weapon_elite", "weapon_fiveseven", "weapon_m249"
};

// fizica (unitati GoldSrc)
#define BALL_SIZE          6.0    // jumatatea boxei de coliziune
#define BALL_GRAVITY       0.8    // gravitatie proprie (800 * 0.8)
#define BALL_BOUNCE        0.55   // cat de elastic saritul e
#define BALL_MAX_SPEED     900.0  // plafonul de viteza
#define BALL_TOUCH_COOLDOWN 0.25  // secunde intre impingeri
#define BALL_KICK_POWER    620    // puterea loviturii cu glontul (unitati)
#define BALL_KICK_UP       180.0  // componenta verticala a loviturii
#define BALL_PUSH_SIDE     90.0   // impulsul din directia privirii (touch)

new g_iBall;                          // entitatea mingii (0 = nicio minge)
new Float:g_flBallSpawnPoint[3];      // punctul de siguranta (respawn)
new Float:g_flNextTouch;              // cooldown intre impingeri

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_event("HLTV", "EventNewRound", "a", "1=0", "2=0");
    register_logevent("EventRoundEnd", 2, "1=Round_End");

    // impingerea la atingere (fakemeta - nu necesita modulul engine)
    register_forward(FM_Touch, "BallTouch");

    // lovirea cu glontul: doar cand o arma TRAGE cu adevarat
    for (new i = 0; i < sizeof(g_szShootable); i++)
        RegisterHam(Ham_Weapon_PrimaryAttack, g_szShootable[i], "OnWeaponPrimaryPost", true);

    // fizica suplimentara: frictiune + limita viteza + anti-bug
    set_task(0.1, "TaskBallThink", TASK_BALL_THINK, _, _, "b");
}

public plugin_natives()
{
    register_library("sectia16_ball");
    register_native("s16_ball_spawn",  "NativeBallSpawn");
    register_native("s16_ball_remove", "NativeBallRemove");
    register_native("s16_ball_exists", "NativeBallExists");
}

public plugin_precache()
{
    if (file_exists(BALL_MODEL_CUSTOM))
        precache_model(BALL_MODEL_CUSTOM);
    else
        precache_model(BALL_MODEL_FALLBACK);
}

/* ====================================================
*   SPAWN / REMOVE
*  ==================================================== */

bool:SpawnBall(const id)
{
    if (!is_user_alive(id))
        return false;

    // pozitia: 55 de unitati in fata, in directia privirii
    new Float:fOrigin[3], Float:fDir[3], Float:fSpawn[3];
    pev(id, pev_origin, fOrigin);
    velocity_by_aim(id, 1, fDir);

    for (new i = 0; i < 3; i++)
        fSpawn[i] = fOrigin[i] + fDir[i] * 55.0;

    fSpawn[2] += 40.0;      // putin peste sol, sa cada natural

    // protectie limite lume (fix-crash, ca la laser)
    S16_ClampPoint(fSpawn);
    if (!S16_ValidPoint(fSpawn))
        return false;

    // nu insistam daca punctul e in perete: coboram la picioare
    engfunc(EngFunc_TraceLine, fOrigin, fSpawn, DONT_IGNORE_MONSTERS, id, 0);
    new Float:fFraction;
    get_tr2(0, TR_flFraction, fFraction);

    if (fFraction < 1.0)
    {
        fSpawn[0] = fOrigin[0] + fDir[0] * 20.0;
        fSpawn[1] = fOrigin[1] + fDir[1] * 20.0;
        fSpawn[2] = fOrigin[2] + 40.0;
    }

    // o singura minge pe teren
    RemoveBall();

    new iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (!iEnt || !pev_valid(iEnt))
        return false;

    new szModel[64];
    GetBallModel(szModel, charsmax(szModel));

    set_pev(iEnt, pev_classname, BALL_CLASSNAME);
    engfunc(EngFunc_SetModel, iEnt, szModel);

    set_pev(iEnt, pev_origin, fSpawn);
    set_pev(iEnt, pev_solid, SOLID_BBOX);
    set_pev(iEnt, pev_movetype, MOVETYPE_BOUNCE);
    set_pev(iEnt, pev_gravity, BALL_GRAVITY);
    set_pev(iEnt, pev_friction, BALL_BOUNCE);
    set_pev(iEnt, pev_takedamage, DAMAGE_NO);
    set_pev(iEnt, pev_dmg, 0.0);

    new Float:fMins[3], Float:fMaxs[3];
    fMins[0] = -BALL_SIZE; fMins[1] = -BALL_SIZE; fMins[2] = -BALL_SIZE;
    fMaxs[0] =  BALL_SIZE; fMaxs[1] =  BALL_SIZE; fMaxs[2] =  BALL_SIZE;
    engfunc(EngFunc_SetSize, iEnt, fMins, fMaxs);

    // memoram punctul de siguranta (aici revine daca iese din harta)
    for (new i = 0; i < 3; i++)
        g_flBallSpawnPoint[i] = fSpawn[i];

    g_flNextTouch = 0.0;
    g_iBall = iEnt;

    return true;
}

RemoveBall()
{
    if (g_iBall && pev_valid(g_iBall))
        engfunc(EngFunc_RemoveEntity, g_iBall);

    g_iBall = 0;
}

GetBallModel(szOut[], const iLen)
{
    if (file_exists(BALL_MODEL_CUSTOM))
        copy(szOut, iLen, BALL_MODEL_CUSTOM);
    else
        copy(szOut, iLen, BALL_MODEL_FALLBACK);
}

/* ====================================================
*   IMPINGERE LA ATINGERE (mergi in mingea -> ea pleaca)
*
*   Motorul apeleaza Touch(a, b) in AMBELE ordine, in functie
*   de cine s-a miscat spre celalalt: jucatorul merge in
*   mingea stationara -> Touch(jucator, minge); mingea zboarca
*   in jucator -> Touch(minge, jucator). Acoperim ambele.
*  ==================================================== */

public BallTouch(const iEnt, const iOther)
{
    if (!g_iBall || !pev_valid(g_iBall))
        return FMRES_IGNORED;

    new iPlayer = 0;

    if (iEnt == g_iBall && iOther >= 1 && iOther <= MaxClients)
        iPlayer = iOther;
    else if (iOther == g_iBall && iEnt >= 1 && iEnt <= MaxClients)
        iPlayer = iEnt;

    if (!iPlayer || !is_user_alive(iPlayer))
        return FMRES_IGNORED;

    new Float:fNow = get_gametime();
    if (fNow < g_flNextTouch)
        return FMRES_IGNORED;

    g_flNextTouch = fNow + BALL_TOUCH_COOLDOWN;

    // directia de impingere: viteza jucatorului + directia privirii
    new Float:fVel[3], Float:fDir[3], Float:fPush[3];
    pev(iPlayer, pev_velocity, fVel);
    velocity_by_aim(iPlayer, 1, fDir);

    for (new i = 0; i < 3; i++)
        fPush[i] = fVel[i] * 1.1 + fDir[i] * BALL_PUSH_SIDE;

    // hoppa! orice impingere ridica mingea putin in aer
    fPush[2] = 130.0 + floatabs(fVel[2]) * 0.4;

    set_pev(g_iBall, pev_velocity, fPush);
    return FMRES_IGNORED;
}

/* ====================================================
*   LOVIRE CU GLONTUL (tras in mingea -> zboarca)
*  ==================================================== */

public OnWeaponPrimaryPost(const iEnt)
{
    if (!g_iBall || !pev_valid(g_iBall))
        return HAM_IGNORED;

    new id = pev(iEnt, pev_owner);

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    // trasam din ochi, pe directia privirii (120 de unitati)
    new Float:fSrc[3], Float:fView[3], Float:fDir[3], Float:fEnd[3];
    pev(id, pev_origin, fSrc);
    pev(id, pev_view_ofs, fView);

    for (new i = 0; i < 3; i++)
        fSrc[i] += fView[i];

    velocity_by_aim(id, 120, fDir);

    for (new i = 0; i < 3; i++)
        fEnd[i] = fSrc[i] + fDir[i];

    engfunc(EngFunc_TraceLine, fSrc, fEnd, DONT_IGNORE_MONSTERS, id, 0);

    if (get_tr2(0, TR_pHit) != g_iBall)
        return HAM_IGNORED;

    // GOL! mingea zboarca in directia privirii
    new Float:fKick[3];
    velocity_by_aim(id, BALL_KICK_POWER, fKick);
    fKick[2] += BALL_KICK_UP;

    set_pev(g_iBall, pev_velocity, fKick);
    return HAM_IGNORED;
}

/* ====================================================
*   GANDIREA MINGII (0.1s): frictiune, viteza, anti-bug
*  ==================================================== */

public TaskBallThink()
{
    if (!g_iBall)
        return;

    if (!pev_valid(g_iBall))
    {
        g_iBall = 0;
        return;
    }

    new Float:fOrigin[3], Float:fVel[3];
    pev(g_iBall, pev_origin, fOrigin);
    pev(g_iBall, pev_velocity, fVel);

    // 1) anti-bug: a iesit din harta -> revine la punctul de spawn
    if (!S16_ValidPoint(fOrigin) || fOrigin[2] < -1500.0)
    {
        set_pev(g_iBall, pev_origin, g_flBallSpawnPoint);
        set_pev(g_iBall, pev_velocity, Float:{ 0.0, 0.0, 0.0 });
        return;
    }

    // 2) frictiunea de rostogolire (doar cand e pe sol)
    if (pev(g_iBall, pev_flags) & FL_ONGROUND)
    {
        fVel[0] *= 0.93;
        fVel[1] *= 0.93;

        if (floatabs(fVel[0]) < 3.0)
            fVel[0] = 0.0;
        if (floatabs(fVel[1]) < 3.0)
            fVel[1] = 0.0;

        set_pev(g_iBall, pev_velocity, fVel);
        return;
    }

    // 3) plafonul de viteza (anti-racheta)
    new Float:fSpeed = floatsqroot(fVel[0] * fVel[0] + fVel[1] * fVel[1] + fVel[2] * fVel[2]);

    if (fSpeed > BALL_MAX_SPEED)
    {
        new Float:fScale = BALL_MAX_SPEED / fSpeed;

        for (new i = 0; i < 3; i++)
            fVel[i] *= fScale;

        set_pev(g_iBall, pev_velocity, fVel);
    }
}

/* ====================================================
*   EVENIMENTE RUNDA
*  ==================================================== */

public EventNewRound()
{
    RemoveBall();
}

public EventRoundEnd()
{
    RemoveBall();
}

/* ====================================================
*   NATIVES (Simon + meniul admin)
*  ==================================================== */

public NativeBallSpawn(const iPlugin, const iParams)
{
    new id = get_param(1);

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return false;

    return SpawnBall(id);
}

public NativeBallRemove(const iPlugin, const iParams)
{
    if (!g_iBall)
        return 0;

    RemoveBall();
    return 1;
}

public NativeBallExists(const iPlugin, const iParams)
{
    return (g_iBall != 0 && pev_valid(g_iBall)) ? 1 : 0;
}
