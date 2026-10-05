.pragma library
.import "../modi/zustandslogik.js" as Logik
// Logik des Energiemanagements ohne QML: wirksame Werte aus einstellungen.json (begrenzt durch die
// Leitplanken in modi/zustandslogik.js), Zeitleiste ab der letzten Eingabe, Vorwarnung vor dem Ausschalten
// und die Wecktaste der Sperre. Getestet mit test/einheiten/energie.test.mjs (node).
//
// Schlüssel in einstellungen.json (Schema: config/schema/einstellungen.schema.json):
//   bildschirmAusNachSperre  Minuten nach der Sperre, 1–10 (Standard 1)
//   ausschalten              nie | akku | immer (Standard akku: nur im Akkubetrieb)
//   ausschaltenNachMinuten   Minuten gesperrt ohne Eingabe, 30–240 (Standard 60)
//   einAusTaste              sperren | menue | ausschalten (Standard sperren)
// scripts/bin/zenos-idle liest bildschirmAusNachSperre genauso (test/einheiten/idle.test.py gleicht beide ab).
//
// Leitplanken (Code): Dunkel heisst gesperrt, der Bildschirm geht nie vor der Sperre aus. Ausschalten zählt
// erst ab der Sperre und kommt nie ohne Vorwarnung. Nichts hier verzögert die automatische Sperre.

var LP = Logik.LEITPLANKEN;

var AUSSCHALTEN = Object.freeze(["nie", "akku", "immer"]);
var EIN_AUS_TASTE = Object.freeze(["sperren", "menue", "ausschalten"]);
var STANDARD = Object.freeze({
    ausschalten: "akku",
    einAusTaste: "sperren"
});

// Ist das Ausschalten blockiert (SSH, tmux, Update …), versucht es zenOS nach dieser Zeit erneut
var NEUER_VERSUCH_MS = 5 * 60000;
// Eine ältere Vorwarnung gilt nicht mehr (z. B. nach einem Sprung der Uhr): dann nie ausschalten
var VORWARNUNG_MAX_MS = 5 * 60000;
// So lange nach dem Wecken verwirft die Sperre noch eine Taste (das Signal «an» kann vor der Taste kommen)
var WECKEN_SCHONFRIST_MS = 1000;
// So lange nach dem Wecken gilt ein Druck auf die Ein/Aus-Taste noch als Wecken (die Taste selbst weckt schon über
// die Eingabe, ihr Befehl kommt etwas später an) und schaltet den Bildschirm nicht gleich wieder aus
var TASTE_SCHONFRIST_MS = 2000;

// Zahl als Text: Ziffern mit Punkt oder Komma, wie in zenos-idle (sonst keine Zahl)
var ZAHL_TEXT = /^[+-]?(?:[0-9]+(?:[.,][0-9]*)?|[.,][0-9]+)$/;

// --- Werte --------------------------------------------------------------------

function _zahl(wunsch) {
    if (typeof wunsch === "number")
        return wunsch;
    if (typeof wunsch === "string") {
        var text = wunsch.trim();
        if (ZAHL_TEXT.test(text))
            return Number(text.replace(",", "."));
    }
    return NaN;
}

// Ganze Minuten von min bis max: gerundet und begrenzt, keine Zahl ergibt den Standard
function _minuten(wunsch, min, max, standard) {
    var n = _zahl(wunsch);
    if (!isFinite(n))
        return standard;
    return Math.min(max, Math.max(min, Math.round(n)));
}

// Minuten nach der Sperre, bis der Bildschirm ausgeht: immer 1–10, Standard 1
function bildschirmMinuten(wunsch) {
    return _minuten(wunsch, LP.bildschirmAusNachSperreMin, LP.bildschirmAusNachSperreMax, LP.bildschirmAusNachSperreStandard);
}

// Minuten gesperrt ohne Eingabe, bis zenOS ausschaltet: immer 30–240, Standard 60
function ausschaltenMinuten(wunsch) {
    return _minuten(wunsch, LP.ausschaltenMinutenMin, LP.ausschaltenMinutenMax, LP.ausschaltenMinutenStandard);
}

// nie | akku | immer, Unbekanntes ergibt den Standard
function ausschaltenArt(wunsch) {
    return AUSSCHALTEN.indexOf(wunsch) >= 0 ? wunsch : STANDARD.ausschalten;
}

// sperren | menue | ausschalten, Unbekanntes ergibt den Standard
function einAusTaste(wunsch) {
    return EIN_AUS_TASTE.indexOf(wunsch) >= 0 ? wunsch : STANDARD.einAusTaste;
}

// Wirksame Werte aus einstellungen.json (Objekt wie in der Datei, auch mit ungültigen Werten)
function wirksam(einstellungen) {
    var e = einstellungen !== null && typeof einstellungen === "object" ? einstellungen : {};
    return {
        sperreMinuten: Logik.sperreMinuten(e.sperreNachMinuten),
        bildschirmMinuten: bildschirmMinuten(e.bildschirmAusNachSperre),
        ausschalten: ausschaltenArt(e.ausschalten),
        ausschaltenMinuten: ausschaltenMinuten(e.ausschaltenNachMinuten),
        einAusTaste: einAusTaste(e.einAusTaste)
    };
}

// Sicher im Akkubetrieb? Nur mit gültiger Messung (Zustand «ok») und beim Entladen. Ein unbekannter Akku
// gilt als Netzteil (akku wie aus dienste/geraet.js: { vorhanden, prozent, laedt, zustand }).
function imAkkubetrieb(akku) {
    return akku !== null && typeof akku === "object" && akku.vorhanden === true && akku.zustand === "ok"
        && akku.laedt === false;
}

// Gilt das Ausschalten nach langer Sperre gerade? «akku» nur im Akkubetrieb.
function ausschaltenAktiv(art, akku) {
    var a = ausschaltenArt(art);
    if (a === "immer")
        return true;
    return a === "akku" && imAkkubetrieb(akku);
}

// --- Zeitleiste ---------------------------------------------------------------

// Was nach wie vielen Minuten ohne Eingabe geschieht: gesperrt, Bildschirm aus und ausgeschaltet (bei «immer»,
// bei «akku» nur mit Akku: ohne ihn schaltet zenOS nie aus). «aktiv» sagt beim Ausschalten, ob es gerade gilt (bei
// «akku» nur im Akkubetrieb).
function zeitleiste(einstellungen, akku) {
    var w = wirksam(einstellungen);
    var liste = [
        { was: "sperre", minuten: w.sperreMinuten, aktiv: true },
        { was: "bildschirm", minuten: w.sperreMinuten + w.bildschirmMinuten, aktiv: true }
    ];
    var mitAkku = akku !== null && typeof akku === "object" && akku.vorhanden === true;
    if (w.ausschalten === "immer" || (w.ausschalten === "akku" && mitAkku))
        liste.push({
            was: "ausschalten",
            minuten: w.sperreMinuten + w.ausschaltenMinuten,
            aktiv: ausschaltenAktiv(w.ausschalten, akku)
        });
    return liste;
}

function _dauerText(minuten) {
    if (minuten < 60 || minuten % 60 !== 0)
        return minuten + " Min.";
    return minuten === 60 ? "1 Std." : (minuten / 60) + " Std.";
}

// «Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min. · Aus nach 65 Min. im Akkubetrieb»
function zeitleisteText(einstellungen, akku) {
    var art = wirksam(einstellungen).ausschalten;
    return zeitleiste(einstellungen, akku).map(function (e) {
        if (e.was === "sperre")
            return "Gesperrt nach " + _dauerText(e.minuten);
        if (e.was === "bildschirm")
            return "Bildschirm aus nach " + _dauerText(e.minuten);
        return "Aus nach " + _dauerText(e.minuten) + (art === "akku" ? " im Akkubetrieb" : "");
    }).join(" · ");
}

// --- Vorwarnung vor dem Ausschalten -------------------------------------------
// Zustand: { phase, seit, um, grund }
//   aus:     keine Vorwarnung (grund: warum zuletzt abgebrochen, z. B. «eingabe» oder «netzteil»)
//   laeuft:  Vorwarnung sichtbar seit «seit», fällig um «um» (60 s später)
//   warten:  Ausschalten war blockiert (grund), neuer Versuch um «um» (5 Min. später)
// Zeiten in Millisekunden (Date.now()).

function vorwarnung() {
    return { phase: "aus", seit: 0, um: 0, grund: "" };
}

function _phase(z) {
    return z !== null && typeof z === "object" && (z.phase === "laeuft" || z.phase === "warten") ? z.phase : "aus";
}

// Vorwarnung beginnen. Läuft schon eine, bleibt sie, wie sie ist (die 60 s beginnen nicht neu).
function vorwarnungStarten(z, jetzt) {
    if (_phase(z) === "laeuft")
        return z;
    return { phase: "laeuft", seit: jetzt, um: jetzt + LP.vorwarnungSekunden * 1000, grund: "" };
}

// Abbrechen (Eingabe, Netzteil, entsperrt …)
function vorwarnungAbbrechen(z, grund) {
    return { phase: "aus", seit: 0, um: 0, grund: typeof grund === "string" ? grund : "" };
}

// Ausschalten war blockiert: später erneut prüfen
function vorwarnungBlockiert(z, jetzt, grund) {
    return { phase: "warten", seit: jetzt, um: jetzt + NEUER_VERSUCH_MS, grund: typeof grund === "string" ? grund : "" };
}

// Was jetzt zu tun ist: «nichts», «ausschalten» (60 s Vorwarnung sind um), «abbrechen» (Vorwarnung zu alt
// oder die Uhr ging zurück: nie ausschalten) oder «neu-pruefen» (nach einer Blockade)
function vorwarnungSchritt(z, jetzt) {
    var phase = _phase(z);
    if (phase === "laeuft") {
        var alter = jetzt - z.seit;
        if (!isFinite(alter) || alter < 0 || alter > VORWARNUNG_MAX_MS)
            return "abbrechen";
        return alter >= LP.vorwarnungSekunden * 1000 ? "ausschalten" : "nichts";
    }
    if (phase === "warten") {
        if (!isFinite(z.um) || !isFinite(z.seit) || jetzt >= z.um || jetzt < z.seit)
            return "neu-pruefen";
    }
    return "nichts";
}

// --- Wecktaste der Sperre -----------------------------------------------------
// Ist der Bildschirm dunkel, weckt ihn die erste Eingabe. Eine Taste dafür darf nicht ins Passwortfeld (ein
// Zeichen zu viel ergäbe einen Fehlversuch bei PAM). Verworfen wird genau eine Taste: die erste, solange es
// dunkel ist oder bis 1 s nach dem Wecken (das Signal «an» kann vor der Taste ankommen). Nie mehr als eine:
// Bliebe «dunkel» hängen, könnte man sonst kein Passwort mehr eingeben.
// Ebenso während der Vorwarnung vor dem Ausschalten: Der Bildschirm ging ohne Eingabe an, die erste Taste bricht
// die Vorwarnung ab und landet nicht im Feld (auch bis 1 s nach dem Ende, falls die Eingabe vor der Taste ankommt).
// Zustand: { dunkel, gewecktUm (ms, -1: nicht geweckt), offen (die Wecktaste steht noch aus), vorwarnung }

function weckzustand() {
    return { dunkel: false, gewecktUm: -1, offen: false };
}

// Der Bildschirm ist aus. War er schon dunkel, ändert sich nichts (eine Meldung doppelt gibt keine zweite
// Wecktaste).
function bildschirmDunkel(z) {
    if (z && z.dunkel === true)
        return z;
    return { dunkel: true, gewecktUm: -1, offen: true };
}

// Der Bildschirm ist wieder an. War er nicht dunkel, ändert sich nichts.
function bildschirmHell(z, jetzt) {
    if (!(z && z.dunkel === true))
        return z && typeof z === "object" ? z : weckzustand();
    return { dunkel: false, gewecktUm: jetzt, offen: z.offen === true };
}

// Die Vorwarnung ist sichtbar (der Bildschirm ging dafür an): Die nächste Taste bricht ab und wird verworfen
function vorwarnungGezeigt(z) {
    return { dunkel: false, gewecktUm: -1, offen: true, vorwarnung: true };
}

// Die Vorwarnung ist vorbei. Stand die Taste noch aus, gilt sie bis 1 s danach noch als Abbruchtaste.
function vorwarnungVorbei(z, jetzt) {
    if (!(z && z.vorwarnung === true))
        return z && typeof z === "object" ? z : weckzustand();
    return { dunkel: z.dunkel === true, gewecktUm: jetzt, offen: z.offen === true };
}

// Diese Taste verwerfen? Danach immer wecktasteGesehen() aufrufen.
function wecktasteVerwerfen(z, jetzt) {
    if (!z || typeof z !== "object" || z.offen !== true)
        return false;
    if (z.dunkel === true || z.vorwarnung === true)
        return true;
    var seit = typeof z.gewecktUm === "number" && z.gewecktUm >= 0 ? jetzt - z.gewecktUm : -1;
    return seit >= 0 && seit < WECKEN_SCHONFRIST_MS;
}

// Nach jeder Taste: Die Wecktaste ist erledigt
function wecktasteGesehen(z) {
    var d = !!(z && z.dunkel === true);
    return { dunkel: d, gewecktUm: z && typeof z.gewecktUm === "number" ? z.gewecktUm : -1, offen: false };
}

// --- Ein/Aus-Taste, gesperrt ----------------------------------------------------
// Ein kurzer Druck schaltet den Bildschirm an oder aus: «an», solange er dunkel ist oder eben (2 s) geweckt wurde
// (der Druck selbst weckt ihn schon als Eingabe), sonst «aus».
function tasteGesperrt(z, jetzt) {
    if (!z || typeof z !== "object")
        return "aus";
    if (z.dunkel === true)
        return "an";
    var seit = typeof z.gewecktUm === "number" && z.gewecktUm >= 0 ? jetzt - z.gewecktUm : -1;
    return seit >= 0 && seit < TASTE_SCHONFRIST_MS ? "an" : "aus";
}
