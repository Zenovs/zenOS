.pragma library
.import "../dienste/energie.js" as EnergieLogik
// Bildschirm am Login-Bildschirm ohne QML (Zenos Entscheid vom 06.10.2026): Nach LEITPLANKEN.loginBildschirmAusMinuten
// (1) Min. ohne Eingabe geht er aus, am Netzteil wie am Akku. Die erste Taste, der erste Klick oder die erste
// Berührung weckt ihn nur und wird verworfen (die Wecktaste, wie in der Sperre: energie.js). Benutzt von
// greeter/Bildschirm.qml, getestet mit test/einheiten/login-bildschirm.test.mjs (node).
//
// Ausfallsicher: Scheitert das Ausschalten (wlopm fehlt, das Protokoll fehlt, wlopm meldet einen Fehler), wird sofort
// wieder eingeschaltet, und nach AUS_VERSUCHE Fehlschlägen in Folge versucht es dieser Login nicht mehr. Scheitert das
// Einschalten, obwohl der Bildschirm sicher dunkel ist, versucht es der Login AN_VERSUCHE Mal und startet sich dann neu
// (greetd startet den Greeter neu, ein neues labwc schaltet alle Bildschirme an).
//
// Am Login-Bildschirm ist niemand angemeldet: Dort darf der Bildschirm ohne Sperre ausgehen. In der Sitzung gilt
// weiter «dunkel heisst gesperrt» (zenos-bildschirm); dieser Weg steht nur in der Oberfläche des Logins.

var AUS_VERSUCHE = 3;
var AN_VERSUCHE = 3;
// Pause vor dem nächsten Versuch, einzuschalten (je Fehlschlag länger: 1 s, 2 s)
var AN_PAUSE_MS = 1000;
// wlopm darf so lange brauchen (Sekunden), dann gilt der Aufruf als gescheitert
var WLOPM_SEKUNDEN = 5;

// Zustand:
//   soll:    "an" | "aus"            wie der Bildschirm sein soll
//   ist:     "an" | "aus" | "unklar" wie er zuletzt sicher war (unklar: ein Aufruf ist gescheitert)
//   laeuft:  "" | "an" | "aus"       Aufruf unterwegs (immer nur einer)
//   dunkelSicher: wlopm hat das Ausschalten bestätigt, seither kein bestätigtes Einschalten
//   ausFehler, anFehler: gescheiterte Aufrufe in Folge
//   wiederUm: frühester nächster Versuch, einzuschalten (ms, Date.now())
//   weck:    Wecktaste { dunkel, gewecktUm, offen } (energie.js)
function zustand() {
    return {
        soll: "an",
        ist: "an",
        laeuft: "",
        dunkelSicher: false,
        ausFehler: 0,
        anFehler: 0,
        wiederUm: 0,
        weck: EnergieLogik.weckzustand()
    };
}

function _mit(z, aenderung) {
    var neu = {};
    var basis = z !== null && typeof z === "object" ? z : zustand();
    for (var k in basis)
        neu[k] = basis[k];
    for (var a in aenderung)
        neu[a] = aenderung[a];
    return neu;
}

// Die Minute ohne Eingabe ist um. Während der Vorwarnung vor dem Ausschalten bleibt er an (sie muss zu sehen sein),
// ebenso nach AUS_VERSUCHE gescheiterten Versuchen.
function leerlauf(z, vorwarnung) {
    if (vorwarnung === true || z.ausFehler >= AUS_VERSUCHE)
        return z;
    return _mit(z, { soll: "aus" });
}

// Eine Eingabe (Taste, Maus, Touchpad, Berührung): an. Ausgeschaltet wird erst wieder nach einer neuen Minute ohne
// Eingabe (leerlauf).
function eingabe(z) {
    return _mit(z, { soll: "an" });
}

// Ohne Eingabe wecken (Vorwarnung vor dem Ausschalten, Deckel aufgeklappt): an, und keine Wecktaste. Wer dann tippt,
// tippt ins Feld (es ist zu sehen).
function wecken(z) {
    return _mit(z, { soll: "an", weck: EnergieLogik.weckzustand() });
}

// Steht die Wecktaste aus? Dann wird die nächste Taste, der nächste Klick oder die nächste Berührung verworfen.
function wecktasteOffen(z) {
    return !!z && !!z.weck && z.weck.offen === true;
}

// Die Wecktaste ist verworfen (genau eine): Ab jetzt landet alles im Formular. Weckt den Bildschirm.
function verworfen(z) {
    return _mit(z, { soll: "an", weck: EnergieLogik.wecktasteGesehen(z.weck) });
}

// Der Bildschirm ist wieder an, und die Schonfrist danach ist um (energie.js, WECKEN_SCHONFRIST_MS): Kam bis jetzt
// keine Taste, war es die Maus oder das Touchpad, und es wird nichts mehr verworfen. Solange es dunkel ist, bleibt sie.
function schonfristVorbei(z) {
    if (!wecktasteOffen(z) || z.weck.dunkel === true)
        return z;
    return _mit(z, { weck: EnergieLogik.wecktasteGesehen(z.weck) });
}

// Welcher Aufruf jetzt? "aus", "an" oder "" (nichts, oder ein Aufruf läuft schon)
function naechster(z, jetzt) {
    if (!z || z.laeuft !== "")
        return "";
    if (z.soll === "aus" && z.ist === "an")
        return "aus";
    if (z.soll === "an" && z.ist !== "an") {
        if (z.anFehler >= AN_VERSUCHE || jetzt < z.wiederUm)
            return "";
        return "an";
    }
    return "";
}

// Ein Aufruf beginnt. Vor dem Ausschalten steht die Wecktaste schon aus: Eine Taste, die genau dann kommt, landet
// nicht im Feld.
function gestartet(z, befehl) {
    if (befehl === "aus")
        return _mit(z, { laeuft: "aus", weck: EnergieLogik.bildschirmDunkel(z.weck) });
    return _mit(z, { laeuft: befehl === "an" ? "an" : "" });
}

// Ein Aufruf ist fertig. ok: wlopm hat ihn ohne Fehler bestätigt (wlopmOk).
function fertig(z, befehl, ok, jetzt) {
    if (befehl === "aus") {
        if (ok === true)
            return _mit(z, { laeuft: "", ist: "aus", dunkelSicher: true, ausFehler: 0 });
        // Ausfallsicher: wieder an (vielleicht ist ein Teil schon dunkel), keine Wecktaste
        return _mit(z, {
            laeuft: "",
            ist: "unklar",
            soll: "an",
            ausFehler: z.ausFehler + 1,
            anFehler: 0,
            wiederUm: 0,
            weck: EnergieLogik.weckzustand()
        });
    }
    if (befehl === "an") {
        if (ok === true)
            return _mit(z, {
                laeuft: "",
                ist: "an",
                dunkelSicher: false,
                anFehler: 0,
                wiederUm: 0,
                weck: EnergieLogik.bildschirmHell(z.weck, jetzt)
            });
        var n = z.anFehler + 1;
        return _mit(z, { laeuft: "", ist: z.dunkelSicher ? "aus" : "unklar", anFehler: n, wiederUm: jetzt + n * AN_PAUSE_MS });
    }
    return z;
}

// Wartet ein neuer Versuch, einzuschalten? (Takt in Bildschirm.qml)
function wartet(z) {
    return !!z && z.laeuft === "" && z.soll === "an" && z.ist !== "an" && z.anFehler > 0 && z.anFehler < AN_VERSUCHE;
}

// Letzter Ausweg: Der Bildschirm ist sicher dunkel und lässt sich nicht einschalten. Dann beendet sich der Login, und
// greetd startet ihn neu (ein neues labwc schaltet alle Bildschirme an).
function neustartNoetig(z) {
    return !!z && z.laeuft === "" && z.soll === "an" && z.dunkelSicher === true && z.anFehler >= AN_VERSUCHE;
}

// Aufgegeben, ohne dass er sicher dunkel war (wlopm fehlt oder antwortet unbrauchbar): kein Neustart
function aufgegeben(z) {
    return !!z && z.laeuft === "" && z.soll === "an" && z.dunkelSicher !== true && z.ist !== "an" && z.anFehler >= AN_VERSUCHE;
}

// Bleibt der Bildschirm nach einem Wecken ohne Eingabe (Vorwarnung vorbei, Deckel auf) an, beginnt die Minute neu:
// Ohne Eingabe meldet der Leerlauf-Zähler des Compositors kein neues «idle».
function minuteNeu(z, idle, vorwarnung) {
    return !!z && idle === true && vorwarnung !== true && z.soll === "an" && z.ausFehler < AUS_VERSUCHE;
}

// Argumentliste für wlopm (nie über eine Shell): alle Bildschirme aus oder an, mit Zeitlimit
function befehl(was) {
    return ["timeout", String(WLOPM_SEKUNDEN), "wlopm", "--json", was === "aus" ? "--off" : "--on", "*"];
}

// Antwort von «wlopm --json --on|--off '*'»: nur ein Objekt mit leerer Fehlerliste ist Erfolg. wlopm endet auch bei
// Fehlern mit 0 (wie in zenos-bildschirm).
function wlopmOk(code, text) {
    if (code !== 0)
        return false;
    var daten;
    try {
        daten = JSON.parse(String(text));
    } catch (e) {
        return false;
    }
    return daten !== null && typeof daten === "object" && !Array.isArray(daten) && Array.isArray(daten.errors)
        && daten.errors.length === 0;
}
