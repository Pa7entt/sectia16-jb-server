/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Bhop & Surf uncapped:
*     - hookchain RG_PM_Move (ReAPI) => reseteaza stamina de saritura (pm_fuser2 = 0.0)
*     - auto-bhop: tasta SPACE tinuta = saritura noua in fiecare cadru de contact
*     - depaseste clamp-ul clasic de 320 u/s prin sv_enablebunnyhopping (reaplicat la fiecare runda)
*     - surf curat: sv_airaccelerate 100 (game.cfg), tranzitii ramp fara pierdere de viteza
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Bhop & Surf"
#define VERSION "1.0.0"
#define AUTHOR  "SECTIA 16"

new g_pCvarEnabled;
new g_pCvarAuto;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    g_pCvarEnabled = register_cvar("s16_bhop",       "1");
    g_pCvarAuto    = register_cvar("s16_bhop_auto",  "1");

    RegisterHookChain(RG_PM_Move, "OnPM_Move", false);

    // HLTV = inceputul unei runde noi; cvar-urile pot fi suprascrise de server.cfg la mapchange,
    // asa ca le reimprospatam aici pentru consistenta miscarii.
    register_event("HLTV", "EventNewRound", "a", "1=0", "2=0");
}

public EventNewRound()
{
    if (get_pcvar_num(g_pCvarEnabled))
    {
        // elimina clamp-ul hardcodat de viteza la saritura
        server_cmd("sv_enablebunnyhopping 1");
        // ReGameDLL: auto-hop nativ ca backup peste hookchain-ul nostru
        server_cmd("sv_autobunnyhopping %d", get_pcvar_num(g_pCvarAuto));
    }
}

/*
*   Hookchain Pre pe miscarea fizica a jucatorului.
*   Ruleaza inainte de PM_Jump/PM_Friction => zero frictiune punitiva, zero stamina.
*/
public OnPM_Move(const player)
{
    if (!get_pcvar_num(g_pCvarEnabled))
        return HC_CONTINUE;

    // 1) resetam stamina bhop-ului (fuser2 = frana dupa saritura)
    set_pmove(pm_fuser2, 0.0);

    // 2) auto-bhop: scoatem IN_JUMP din oldbuttons => tasta tinuta e tratata ca apasare noua
    if (get_pcvar_num(g_pCvarAuto))
    {
        set_pmove(pm_oldbuttons, get_pmove(pm_oldbuttons) & ~IN_JUMP);
    }

    return HC_CONTINUE;
}
