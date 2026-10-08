.pragma library
.import "../modi/zustandslogik.js" as Logik
// Logik des Energiemanagements ohne QML: wirksame Werte aus einstellungen.json (begrenzt durch die
// Leitplanken in modi/zustandslogik.js), Zeitleiste ab der letzten Eingabe, Vorwarnung vor dem Ausschalten
// (in der Sitzung und am Login-Bildschirm) und die Wecktaste der Sperre. Getestet mit
// test/einheiten/energie.test.mjs (node).
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
// Eine ältere Vorwarnung gilt nicht mehr (z. B. weil der Helfer hängt): dann nie ausschalten. Gezählt in Takten zu 1 s
// (wie zenos-energie, VORWARNUNG_MAX, dort nach der Laufzeit), nicht mit der Uhr: Ein Sprung der Uhr verkürzt die
// Vorwarnung nie.
var VORWARNUNG_MAX_MS = 5 * 60000;
// So kurz nach dem Wecken verwirft die Sperre noch die erste Taste (das Signal «an» könnte knapp vor der Taste kommen,
// die geweckt hat). Kurz, damit ein Passwort nach dem Wecken mit Maus oder Touchpad ganz ankommt.
var WECKEN_SCHONFRIST_MS = 300;
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

// Am Login-Bildschirm (Zenos Entscheid, fest): nur sicher im Akkubetrieb, nach LP.loginAusschaltenMinuten ohne Eingabe
function loginAusschaltenAktiv(akku) {
    return imAkkubetrieb(akku);
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
// Zustand: { phase, seit, um, grund, takte }
//   aus:     keine Vorwarnung (grund: warum zuletzt abgebrochen, z. B. «eingabe» oder «netzteil»)
//   laeuft:  Vorwarnung sichtbar seit «seit», Uhrzeit des Ausschaltens «um» (nur zur Anzeige). Ausgeschaltet wird
//            nach 60 Takten zu 1 s (vorwarnungTakt), nie nach der Uhr.
//   warten:  Ausschalten war blockiert (grund), neuer Versuch um «um» (5 Min. später)
//   abgelehnt: logind hat das Ausschalten nach der Vorwarnung abgelehnt (grund). Bis zur nächsten Eingabe keine neue
//            Vorwarnung: Sonst ginge der Bildschirm die ganze Nacht alle 5 Min. für 60 s an.
// Zeiten in Millisekunden (Date.now()).

var _PHASEN = ["laeuft", "warten", "abgelehnt"];

function vorwarnung() {
    return { phase: "aus", seit: 0, um: 0, grund: "", takte: 0 };
}

function _phase(z) {
    return z !== null && typeof z === "object" && _PHASEN.indexOf(z.phase) >= 0 ? z.phase : "aus";
}

// Darf jetzt gefragt werden, ob ausgeschaltet werden darf? Nur ohne Vorwarnung und nach einer Blockade, nie nach
// einer Ablehnung durch logind (erst wieder nach einer Eingabe).
function vorwarnungPruefbar(z) {
    var phase = _phase(z);
    return phase === "aus" || phase === "warten";
}

// Vorwarnung beginnen. Läuft schon eine, bleibt sie, wie sie ist (die 60 s beginnen nicht neu).
function vorwarnungStarten(z, jetzt) {
    if (_phase(z) === "laeuft")
        return z;
    return { phase: "laeuft", seit: jetzt, um: jetzt + LP.vorwarnungSekunden * 1000, grund: "", takte: 0 };
}

// Ein Takt der laufenden Vorwarnung (Timer, 1 s). Ein Sprung der Uhr ändert nichts daran. Ein QML-Timer kann etwas zu
// früh feuern (im Container: 30 Takte in 29,8 s): Massgebend für die 60 s ist deshalb die Laufzeit seit dem Start in
// zenos-energie. Ist die Vorwarnung dort noch keine 60 s alt (Exit 4), fragt die Oberfläche im nächsten Takt erneut.
function vorwarnungTakt(z) {
    if (_phase(z) !== "laeuft")
        return z;
    var n = typeof z.takte === "number" && isFinite(z.takte) && z.takte >= 0 ? Math.floor(z.takte) : 0;
    return { phase: "laeuft", seit: z.seit, um: z.um, grund: "", takte: n + 1 };
}

// Abbrechen (Eingabe, Netzteil, entsperrt …)
function vorwarnungAbbrechen(z, grund) {
    return { phase: "aus", seit: 0, um: 0, grund: typeof grund === "string" ? grund : "", takte: 0 };
}

// Ausschalten war blockiert: später erneut prüfen
function vorwarnungBlockiert(z, jetzt, grund) {
    return { phase: "warten", seit: jetzt, um: jetzt + NEUER_VERSUCH_MS, grund: typeof grund === "string" ? grund : "", takte: 0 };
}

// logind hat das Ausschalten abgelehnt (polkit, eine andere Sitzung …): bis zur nächsten Eingabe nichts mehr
function vorwarnungAbgelehnt(z, jetzt, grund) {
    return { phase: "abgelehnt", seit: jetzt, um: 0, grund: typeof grund === "string" ? grund : "", takte: 0 };
}

// Was jetzt zu tun ist: «nichts», «ausschalten» (60 Takte Vorwarnung sind um), «abbrechen» (Vorwarnung zu alt oder
// kaputt: nie ausschalten) oder «neu-pruefen» (nach einer Blockade). Nach einer Ablehnung immer «nichts».
function vorwarnungSchritt(z, jetzt) {
    var phase = _phase(z);
    if (phase === "laeuft") {
        var takte = z.takte;
        if (typeof takte !== "number" || !isFinite(takte) || takte < 0 || takte * 1000 > VORWARNUNG_MAX_MS)
            return "abbrechen";
        return takte >= LP.vorwarnungSekunden ? "ausschalten" : "nichts";
    }
    if (phase === "warten") {
        if (!isFinite(z.um) || !isFinite(z.seit) || jetzt >= z.um || jetzt < z.seit)
            return "neu-pruefen";
    }
    return "nichts";
}

// Zeile auf der Sperre und am Login-Bildschirm (Uhrzeiten als «HH:mm», leer: keine). Der leere Akku (zenos-argon) hat
// Vorrang: Dort bricht nur das Netzteil ab.
function vorwarnungText(akkuUhrzeit, uhrzeit) {
    if (typeof akkuUhrzeit === "string" && akkuUhrzeit.length > 0)
        return "Akku fast leer: zenOS schaltet um " + akkuUhrzeit + " aus · Netzteil anschliessen bricht ab";
    if (typeof uhrzeit === "string" && uhrzeit.length > 0)
        return "zenOS schaltet um " + uhrzeit + " aus · Eine Taste bricht ab";
    return "";
}

// --- Wecktaste der Sperre -----------------------------------------------------
// Ist der Bildschirm dunkel, weckt ihn die erste Eingabe. Eine Taste dafür darf nicht ins Passwortfeld (ein
// Zeichen zu viel ergäbe einen Fehlversuch bei PAM). Verworfen wird genau eine Taste: die erste, solange es
// dunkel ist oder bis 300 ms nach dem Wecken (falls das Signal «an» knapp vor der Taste ankommt). Nie mehr als eine:
// Bliebe «dunkel» hängen, könnte man sonst kein Passwort mehr eingeben. Weckt die Maus oder das Touchpad, kommt das
// Passwort danach ganz an.
// Während der sichtbaren Vorwarnung vor dem Ausschalten wird nichts verworfen: Das Feld ist zu sehen, wer dann das
// Passwort tippt, soll entsperren (die Eingabe bricht die Vorwarnung ohnehin ab).
// Zustand: { dunkel, gewecktUm (ms, -1: nicht geweckt), offen (die Wecktaste steht noch aus) }

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

// Diese Taste verwerfen? Danach immer wecktasteGesehen() aufrufen.
function wecktasteVerwerfen(z, jetzt) {
    if (!z || typeof z !== "object" || z.offen !== true)
        return false;
    if (z.dunkel === true)
        return true;
    var seit = typeof z.gewecktUm === "number" && z.gewecktUm >= 0 ? jetzt - z.gewecktUm : -1;
    return seit >= 0 && seit < WECKEN_SCHONFRIST_MS;
}

// Nach jeder Taste: Die Wecktaste ist erledigt
function wecktasteGesehen(z) {
    var d = !!(z && z.dunkel === true);
    return { dunkel: d, gewecktUm: z && typeof z.gewecktUm === "number" ? z.gewecktUm : -1, offen: false };
}

// Gehaltene Wecktaste: Wer die Taste, die weckt, festhält, bekommt sie vom Client wiederholt (Wayland: QtWayland nach
// der Verzögerung des Compositors, bei labwc 600 ms, dann 25 je Sekunde, mit isAutoRepeat). Die Wiederholungen gehen
// an das Feld, das dann den Fokus hat. Sie werden verworfen, bis die Taste losgelassen wird; sonst landeten Zeichen
// im Passwortfeld, und ein gehaltenes Return meldete mit dem halben Passwort an. Nie eine andere Taste: Verworfen
// werden nur Wiederholungen genau dieser Taste. Ihr echtes Loslassen, ein echter Druck derselben Taste und die
// Wiederholung einer anderen beenden es. Der echte Druck einer anderen Taste kommt an, beendet es aber nicht:
// QtWayland wiederholt nur die zuletzt gedrückte Taste, die sich wiederholen darf (xkb_keymap_key_repeats). Eine
// solche Taste übernimmt die Wiederholung, die gehaltene wiederholt sich danach nicht mehr. Shift, Ctrl, Alt, AltGr,
// Super, Caps Lock, Num Lock und die Umschalter der Tastaturbelegung wiederholen sich nicht: Ihr Druck lässt die
// gehaltene Taste weiter wiederholen, und die Wiederholungen bleiben verworfen.
// Gebraucht im Login (greeter/Anmeldefenster.qml) und in der Sperre (über wecktasteSperre).
//   gehalten:   Code der verworfenen Wecktaste (nativeScanCode), -1: keine
//   druck:      true beim Drücken, false beim Loslassen
//   code:       nativeScanCode dieser Taste
//   wiederholt: isAutoRepeat
// Ergebnis: { verwerfen, gehalten } (gehalten: der neue Stand)
function wecktasteGehalten(gehalten, druck, code, wiederholt) {
    if (typeof gehalten !== "number" || gehalten < 0)
        return { verwerfen: false, gehalten: -1 };
    if (wiederholt === true) {
        if (code === gehalten)
            return { verwerfen: true, gehalten: gehalten };
        return { verwerfen: false, gehalten: -1 };
    }
    // Echt gedrückt oder losgelassen: dieselbe Taste (oder eine ohne gültigen Code, sie liesse sich nicht
    // unterscheiden) beendet es, eine andere nicht
    var mitCode = typeof code === "number" && isFinite(code) && code >= 0;
    if (!mitCode || code === gehalten)
        return { verwerfen: false, gehalten: -1 };
    return { verwerfen: false, gehalten: gehalten };
}

// Jede Taste im Passwortfeld der Sperre (sperre/Sperre.qml), beim Drücken und Loslassen. Dort gibt es keinen eigenen
// Wecker wie im Login: Alles geht durch das Feld. Verworfen werden die Wecktaste (genau ein Druck, wecktasteVerwerfen)
// und, solange sie gehalten wird, ihre Wiederholungen (wecktasteGehalten). Nie eine andere Taste, ihr Loslassen
// beendet es. Ein Loslassen zählt nie als Wecktaste. Ein Druck, der keine Wecktaste ist, lässt das Halten, wie es
// ist (wecktasteGehalten entscheidet, ob er es beendet).
//   z:        Weckzustand (weckzustand, bildschirmDunkel, bildschirmHell)
//   gehalten: Code der verworfenen Wecktaste, solange sie gehalten wird (-1: keine)
//   druck, code, wiederholt wie bei wecktasteGehalten, jetzt in ms (Date.now())
// Ergebnis: { verwerfen, z, gehalten } (z und gehalten: der neue Stand)
function wecktasteSperre(z, gehalten, druck, code, wiederholt, jetzt) {
    var g = wecktasteGehalten(gehalten, druck, code, wiederholt);
    if (g.verwerfen || druck !== true)
        return { verwerfen: g.verwerfen, z: z, gehalten: g.gehalten };
    var verwerfen = wecktasteVerwerfen(z, jetzt);
    // Ohne gültigen Code lässt sich die Taste nicht wiedererkennen: dann nur dieser eine Druck
    var mitCode = typeof code === "number" && isFinite(code) && code >= 0;
    var neu = verwerfen ? (mitCode ? code : -1) : g.gehalten;
    return { verwerfen: verwerfen, z: wecktasteGesehen(z), gehalten: neu };
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
