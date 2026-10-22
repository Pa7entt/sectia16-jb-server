/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Core v2.0 - starea centrala a penitenciarului:
*     - CREDITE (vault per SteamID): castig din kill-uri (+25/+10 HS) si +5/minut
*     - FREEDAY: flag runda curenta + coada "freeday garantat runda viitoare"
*       (recompensa Last Request, aplicata automat la inceputul rundei)
*     - REBEL: detinut care a atacat un gardian (model dedicat)
*     - VIP (flag "t") / Admin (flag "y")
*     - VOCE LR: participantii la Last Request primesc microfon
*     - bun venit, /ajutor, /reguli MOTD, tips
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Core"
#define VERSION "2.0.0"
#define AUTHOR  "SECTIA 16"

#define TASK_MINUTE 514100

// flag "t" = VIP | flag "y" = admin
#define S16_VIP_FLAGS   ADMIN_LEVEL_H
#define S16_ADMIN_FLAGS ADMIN_ADMIN

new const g_szTips[][] =
{
    "Gardieni: scrie /simon sa preiei controlul penitenciarului.",
    "Detinuti: aduna credite si scrie /shop pentru unelte secrete.",
    "Ultimul detinut in viata poate cere /lr (Last Request).",
    "Scrie /reguli pentru regulamentul complet al sectiei.",
    "Simon poate acorda FreeDay individual: /fd [nume].",
    "Apasa tasta M pentru meniul jucatorului (echipe + glow).",
    "Tine SPACE apasat - bhop-ul e uncapped pe SECTIA 16!",
    "Duminica e FREEday GLOBAL - nimeni nu da ordine.",
    "Microfon: gardieni, Simon, admini, VIP si LR. Restul: liniste!",
    "Castigi un duel LR? alegi intre 3000 de credite si FreeDay maine."
};

// starea per jucator
new g_iCredits[MAX_PLAYERS + 1];
new bool:g_bFreeday[MAX_PLAYERS + 1];
new bool:g_bQueuedFD[MAX_PLAYERS + 1];
new bool:g_bRebel[MAX_PLAYERS + 1];
new bool:g_bLRVoice[MAX_PLAYERS + 1];

new g_pCvarKill;
new g_pCvarHsBonus;
new g_pCvarMinute;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_cvar("sectia16_version", VERSION, FCVAR_SERVER | FCVAR_SPONLY);

    register_clcmd("say /ajutor",  "CmdHelp");
    register_clcmd("say /help",    "CmdHelp");
    register_clcmd("say /comenzi", "CmdHelp");
    register_clcmd("say /reguli",  "CmdRules");
    register_clcmd("say /credite", "CmdCredits");

    register_event("HLTV",     "EventNewRound", "a", "1=0", "2=0");
    register_event("DeathMsg", "EventDeathMsg", "a");
    register_event("TeamInfo", "EventTeamInfo", "a");

    // detectia rebelilor: detinut care raneste un gardian
    RegisterHookChain(RG_CBasePlayer_TakeDamage, "OnTakeDamage", false);

    g_pCvarKill     = register_cvar("s16_credits_kill",   "25");
    g_pCvarHsBonus  = register_cvar("s16_credits_hs",     "10");
    g_pCvarMinute   = register_cvar("s16_credits_minute", "5");

    set_task(180.0, "TaskTip", _, _, _, "b");
    set_task(60.0,  "TaskMinuteCredits", TASK_MINUTE, _, _, "b");
}

// toti nativii se inregistreaza AICI (nu in plugin_init) ca sa fie
// disponibili pluginurilor incarcate dupa acesta
public plugin_natives()
{
    register_library("sectia16_core");

    register_native("s16_get_credits",  "NativeGetCredits");
    register_native("s16_add_credits",  "NativeAddCredits");
    register_native("s16_spend_credits","NativeSpendCredits");
    register_native("s16_set_freeday",  "NativeSetFreeday");
    register_native("s16_has_freeday",  "NativeHasFreeday");
    register_native("s16_queue_freeday","NativeQueueFreeday");
    register_native("s16_set_rebel",    "NativeSetRebel");
    register_native("s16_is_rebel",     "NativeIsRebel");
    register_native("s16_is_vip",       "NativeIsVip");
    register_native("s16_is_admin",     "NativeIsAdmin");
    register_native("s16_set_lr_voice", "NativeSetLRVoice");
    register_native("s16_is_lr_voice",  "NativeIsLRVoice");
    register_native("s16_get_weekday",  "NativeGetWeekday");
}

/* ====================================================
*   CREDITE (vault, per SteamID)
*  ==================================================== */

public client_authorized(id)
{
    g_iCredits[id]  = 0;
    g_bFreeday[id]  = false;
    g_bQueuedFD[id] = false;
    g_bRebel[id]    = false;
    g_bLRVoice[id]  = false;

    if (is_user_bot(id) || is_user_hltv(id))
        return;

    new szAuth[40], szKey[64], szData[16];
    get_user_authid(id, szAuth, charsmax(szAuth));
    formatex(szKey, charsmax(szKey), "s16_credits_%s", szAuth);

    get_vaultdata(szKey, szData, charsmax(szData));
    if (szData[0])
        g_iCredits[id] = str_to_num(szData);
}

public client_putinserver(id)
{
    if (is_user_bot(id) || is_user_hltv(id))
        return;

    set_task(6.0, "TaskWelcome", id);
}

public client_disconnected(id)
{
    SaveCredits(id);

    g_iCredits[id]  = 0;
    g_bFreeday[id]  = false;
    g_bQueuedFD[id] = false;
    g_bRebel[id]    = false;
    g_bLRVoice[id]  = false;
}

SaveCredits(const id)
{
    if (is_user_bot(id))
        return;

    new szAuth[40], szKey[64], szData[16];
    get_user_authid(id, szAuth, charsmax(szAuth));
    formatex(szKey, charsmax(szKey), "s16_credits_%s", szAuth);
    formatex(szData, charsmax(szData), "%d", g_iCredits[id]);
    set_vaultdata(szKey, szData);
}

/* ====================================================
*   RUNDĂ NOUĂ: freeday din coada LR + resetari
*  ==================================================== */

public EventNewRound()
{
    for (new id = 1; id <= MaxClients; id++)
    {
        if (!is_user_connected(id))
            continue;

        // recompensa LR: freeday garantat runda viitoare -> acum
        if (g_bQueuedFD[id] && get_member(id, m_iTeam) == TEAM_TERRORIST)
        {
            g_bFreeday[id] = true;
            S16_Print(id, "^4[SECTIA 16]^1 FreeDay-ul promis incepe ^3ACUM^1. Distreaza-te!");
        }
        else
        {
            g_bFreeday[id] = false;
        }

        g_bQueuedFD[id] = false;
        g_bRebel[id]    = false;
        g_bLRVoice[id]  = false;
    }
}

public EventTeamInfo()
{
    new id = read_data(1);
    if (!id || id > MaxClients)
        return;

    new szTeam[12];
    read_data(2, szTeam, charsmax(szTeam));

    if (!equali(szTeam, "TERRORIST"))
    {
        // a parasit echipa detinutilor -> flagurile de detinut se curata
        g_bFreeday[id] = false;
        g_bRebel[id]   = false;
    }
}

public EventDeathMsg()
{
    new iKiller = read_data(1);
    new iVictim = read_data(2);

    if (!iKiller || iKiller == iVictim || !is_user_connected(iKiller))
        return;

    if (get_member(iKiller, m_iTeam) != TEAM_TERRORIST || get_member(iVictim, m_iTeam) != TEAM_CT)
        return;

    new iAmount = get_pcvar_num(g_pCvarKill);
    if (read_data(3))
        iAmount += get_pcvar_num(g_pCvarHsBonus);

    g_iCredits[iKiller] = clamp(g_iCredits[iKiller] + iAmount, 0, 999999);
    SaveCredits(iKiller);

    S16_Print(iKiller, "^4[SECTIA 16]^1 +^3%d credite^1 pentru executie. Sold: ^3%d^1.", iAmount, g_iCredits[iKiller]);
}

public TaskMinuteCredits()
{
    new iPlayers[MAX_PLAYERS], iNum;
    get_players(iPlayers, iNum, "ce", "TERRORIST");

    new iAmount = get_pcvar_num(g_pCvarMinute);
    for (new i = 0; i < iNum; i++)
        g_iCredits[iPlayers[i]] = clamp(g_iCredits[iPlayers[i]] + iAmount, 0, 999999);
}

/* ====================================================
*   REBELI (TakeDamage: T raneste CT)
*  ==================================================== */

public OnTakeDamage(const this, const pevInflictor, const pevAttacker, Float:flDamage, const bitsDamageType)
{
    if (flDamage <= 0.0)
        return HC_CONTINUE;

    if (pevAttacker <= 0 || pevAttacker > MaxClients || pevAttacker == this)
        return HC_CONTINUE;

    if (!is_user_alive(this) || !is_user_alive(pevAttacker))
        return HC_CONTINUE;

    if (get_member(this, m_iTeam) != TEAM_CT || get_member(pevAttacker, m_iTeam) != TEAM_TERRORIST)
        return HC_CONTINUE;

    // in timpul LR-ului nu exista rebeliune
    if (g_bLRVoice[this] || g_bLRVoice[pevAttacker])
        return HC_CONTINUE;

    if (!g_bRebel[pevAttacker])
    {
        g_bRebel[pevAttacker] = true;

        new szName[32];
        get_user_name(pevAttacker, szName, charsmax(szName));
        S16_PrintAll("^4[SECTIA 16]^3 %s^1 e ^4REBEL^1! A atacat un gardian.", szName);
    }

    return HC_CONTINUE;
}

/* ====================================================
*   MENIURI / INFO
*  ==================================================== */

public CmdCredits(id)
{
    S16_Print(id, "^4[SECTIA 16]^1 Ai ^3%d credite^1. Aduni credite din executii si timp suplimentar.", g_iCredits[id]);
    return PLUGIN_HANDLED;
}

public TaskWelcome(id)
{
    if (!is_user_connected(id))
        return;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    S16_Print(id, "^4[SECTIA 16]^1 Bine ai venit in penitenciar, ^3%s^1!", szName);
    S16_Print(id, "^4[SECTIA 16]^1 Scrie ^3/ajutor^1 pentru comenzi si ^3/reguli^1 pentru regulament.");
    S16_Print(id, "^4[SECTIA 16]^1 Gardiani: ^3/simon^1 | Detinuti: ^3/shop^1 | Ultimul detinut: ^3/lr^1 | Meniu: tasta ^3M^1");
}

public CmdHelp(id)
{
    S16_Print(id, "^4[SECTIA 16]^1 Comenzi disponibile:");
    S16_Print(id, "^3/simon^1 - devii Simon (doar gardiani) | ^3/meniu^1 - meniul Simonului");
    S16_Print(id, "^3/zi^1 - zile custom (doar Simon) | ^3/fd [nume]^1 - FreeDay individual (Simon)");
    S16_Print(id, "^3/lr^1 - Last Request (ultimul detinut) | ^3/shop^1 - shop secret (detinuti)");
    S16_Print(id, "^3/mic^1 - acorda microfon unui detinut (Simon/admin) | ^3/credite^1 - sold curent");
    S16_Print(id, "^3/reguli^1 - regulamentul sectiei | tasta ^3M^1 - echipe + setari glow");
    return PLUGIN_HANDLED;
}

public CmdRules(id)
{
    new szMotd[1536];

    new iLen = 0;
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<html><body bgcolor='#111111' text='#dddddd' font='Tahoma'>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<h1 style='color:#ff9900'>SECTIA 16 - REGULAMENT</h1>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<h2 style='color:#ffffff'>Gardieni (CT)</h2><ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Nu dai freekill. Fara dovada = ban.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Ordinele Simonului se dau o singura data, apoi se aplica.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Freeday individual se acorda doar de Simon (/fd).</li></ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<h2 style='color:#ffffff'>Detinuti (T)</h2><ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Respecti ordinele sau suporti consecintele.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Cine ataca un gardian devine REBEL.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Ultimul detinut are dreptul la Last Request (/lr).</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Duminica e FREEday GLOBAL - nimeni nu da ordine.</li></ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<h2 style='color:#ffffff'>Microfon</h2><ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Gardienii, Simon, adminii si VIP-ii vorbesc liber.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Detinutii tac, exceptie: microfon acordat sau Last Request.</li></ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<h2 style='color:#ffffff'>Generale</h2><ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Bhop-ul e permis. Script-urile de orice fel NU.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Manelele date de Simon sunt obligatorii. Nu se discuta.</li></ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<p style='color:#888888'>jb.sectia16.ro - penitenciar de maxima securitate din 2003.</p>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "</body></html>");

    show_motd(id, szMotd, "SECTIA 16 - Regulament");
    return PLUGIN_HANDLED;
}

public TaskTip()
{
    S16_PrintAll("^4[S16 TIP]^1 %s", g_szTips[random(sizeof(g_szTips))]);
}

/* ====================================================
*   NATIVES
*  ==================================================== */

public NativeGetCredits(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return 0;

    return g_iCredits[id];
}

public NativeAddCredits(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return 0;

    new iAmount = get_param(2);
    g_iCredits[id] = clamp(g_iCredits[id] + iAmount, 0, 999999);

    if (iAmount > 0 && is_user_connected(id))
        S16_Print(id, "^4[SECTIA 16]^1 Ai primit ^3%d credite^1! Sold: ^3%d^1.", iAmount, g_iCredits[id]);

    SaveCredits(id);
    return g_iCredits[id];
}

public NativeSpendCredits(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return false;

    new iAmount = get_param(2);

    if (g_iCredits[id] < iAmount)
        return false;

    g_iCredits[id] -= iAmount;
    SaveCredits(id);
    return true;
}

public NativeSetFreeday(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return;

    g_bFreeday[id] = get_param(2) != 0;
}

public NativeHasFreeday(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return false;

    return g_bFreeday[id];
}

public NativeQueueFreeday(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return;

    g_bQueuedFD[id] = true;
}

public NativeSetRebel(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return;

    g_bRebel[id] = get_param(2) != 0;
}

public NativeIsRebel(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return false;

    return g_bRebel[id];
}

public NativeIsVip(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients || !is_user_connected(id))
        return false;

    return bool:(get_user_flags(id) & S16_VIP_FLAGS);
}

public NativeIsAdmin(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients || !is_user_connected(id))
        return false;

    return bool:(get_user_flags(id) & S16_ADMIN_FLAGS);
}

public NativeSetLRVoice(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return;

    g_bLRVoice[id] = get_param(2) != 0;
}

public NativeIsLRVoice(const iPlugin, const iParams)
{
    new id = get_param(1);
    if (id < 0 || id > MaxClients)
        return false;

    return g_bLRVoice[id];
}

public NativeGetWeekday(const iPlugin, const iParams)
{
    // %w: 0 = Duminica, 1 = Luni ... 6 = Sambata (ora serverului)
    new szDay[4];
    get_time("%w", szDay, charsmax(szDay));
    return str_to_num(szDay);
}
