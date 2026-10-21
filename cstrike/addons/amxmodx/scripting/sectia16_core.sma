/*
*   SECTIA 16 - Jailbreak CS 1.6 (jb.sectia16.ro)
*   Core: mesaje de bun venit, ajutor, regulament MOTD, tips.
*/

#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <sectia16>

#pragma semicolon 1
#pragma tabsize 4

#define PLUGIN  "SECTIA 16 | Core"
#define VERSION "1.0.0"
#define AUTHOR  "SECTIA 16"

new const g_szTips[][] =
{
    "Gardieni: scrie /simon sa preiei controlul penitenciarului.",
    "Detinuti: aduna credite si scrie /shop pentru unelte secrete.",
    "Ultimul detinut in viata poate cere /lr (Last Request).",
    "Scrie /reguli pentru regulamentul complet al sectiei.",
    "Simon poate activa zile custom cu /zi.",
    "Tine SPACE apasat - bhop-ul e uncapped pe SECTIA 16!",
    "Manelele date de Simon prin Muzica Gratuita sunt obligatorii. Nu se discuta."
};

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("say /ajutor",  "CmdHelp");
    register_clcmd("say /help",    "CmdHelp");
    register_clcmd("say /comenzi", "CmdHelp");
    register_clcmd("say /reguli",  "CmdRules");

    set_task(180.0, "TaskTip", _, _, _, "b");
}

public client_putinserver(id)
{
    if (is_user_bot(id) || is_user_hltv(id))
        return;

    set_task(6.0, "TaskWelcome", id);
}

public TaskWelcome(id)
{
    if (!is_user_connected(id))
        return;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    S16_Print(id, "^4[SECTIA 16]^1 Bine ai venit in penitenciar, ^3%s^1!", szName);
    S16_Print(id, "^4[SECTIA 16]^1 Scrie ^3/ajutor^1 pentru comenzi si ^3/reguli^1 pentru regulament.");
    S16_Print(id, "^4[SECTIA 16]^1 Gardieni: ^3/simon^1 | Detinuti: ^3/shop^1 | Ultimul detinut: ^3/lr^1");
}

public CmdHelp(id)
{
    S16_Print(id, "^4[SECTIA 16]^1 Comenzi disponibile:");
    S16_Print(id, "^3/simon^1 - devii Simon (doar gardiani) | ^3/meniu^1 - meniul Simonului");
    S16_Print(id, "^3/zi^1 - zile custom (doar Simon) | ^3/lr^1 - Last Request (ultimul detinut)");
    S16_Print(id, "^3/shop^1 - shop secret (doar detinuti) | ^3/reguli^1 - regulamentul sectiei");
    S16_Print(id, "^4[TIP]^1 Bind optional: bind v ^"+simon^1");
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
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Celulele se deschid doar la fluierat.</li></ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<h2 style='color:#ffffff'>Detinuti (T)</h2><ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Respecti ordinele sau suporti consecintele.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Fara rebeliune in primele 15 secunde dupa deschidere.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Ultimul detinut are dreptul la Last Request (/lr).</li></ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<h2 style='color:#ffffff'>Generale</h2><ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Fara reclamatii pe chat - foloseste /ajutor.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Bhop-ul e permis. Script-urile de orice fel NU.</li>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<li>Manelele luate la shootout sunt considerate tortura autorizata.</li></ol>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "<p style='color:#888888'>jb.sectia16.ro - penitenciar de maxima securitate din 2003.</p>");
    iLen += formatex(szMotd[iLen], charsmax(szMotd) - iLen, "</body></html>");

    show_motd(id, szMotd, "SECTIA 16 - Regulament");
    return PLUGIN_HANDLED;
}

public TaskTip()
{
    S16_PrintAll("^4[S16 TIP]^1 %s", g_szTips[random(sizeof(g_szTips))]);
}
