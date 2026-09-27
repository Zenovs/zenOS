.pragma library
// Logik der Zustände ohne QML: wirksamer Zustand (Vorlage + Anpassung des Modus + Leitplanken),
// Auslöser, Ende und Rückkehr. Getestet mit test/einheiten/zustaende.test.mjs (node).
//
// Laufzeit-Eintrag (laufzeit.json, Schlüssel «zustand»):
//   { id, seit, ende, endeArt, ausloeser, vorher }
//   seit/ende: ISO-Zeit (ende nur bei Timer), endeArt: manuell | timer | ausloeser-endet,
//   ausloeser: manuell | bildschirmfreigabe | uhrzeit | moduswechsel,
//   vorher: Eintrag, der nach einer automatischen Sitzung zurückkommt (oder null).

// Leitplanken sind Code, nicht Konfiguration. Kein Modus, kein Zustand und keine Einstellung ändert sie.
var LEITPLANKEN = Object.freeze({
    inhalteBeiFreigabe: false,
    sperreZeigtInhalte: false,
    sperreAbschaltbar: false,
    sperreMinutenMin: 1,
    sperreMinutenMax: 15,
    sperreMinutenStandard: 5
});

var WERTE = Object.freeze({
    leiste: Object.freeze(["normal", "reduziert", "aus"]),
    fenster: Object.freeze(["normal", "fokus"]),
    ende: Object.freeze(["manuell", "timer", "ausloeser-endet"]),
    ausloeser: Object.freeze(["manuell", "bildschirmfreigabe", "uhrzeit", "moduswechsel", "kalender"])
});

// Schlüssel eines Zustands, die ein Modus anpassen kann (alles ausser dem Namen)
var ANPASSBAR = Object.freeze(["mitteilungen", "leiste", "fenster", "heute", "widgets", "ausloeser", "ende"]);

// Schlüssel, mit denen eine Datei die Leitplanken aushebeln könnte. Im wirksamen Zustand werden sie
// entfernt und durch die festen Werte ersetzt.
var GESPERRT = Object.freeze(["inhalteBeiFreigabe", "sperreZeigtInhalte", "sperreAbschaltbar", "sperre",
    "sperreAktiv", "sperreNachMinuten", "inhalteVerbergen", "leitplanken"]);

var ID_MUSTER = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
var UHRZEIT_MUSTER = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
var MINUTEN_MAX = 1440;

// --- Hilfen -------------------------------------------------------------------

// Werte aus QML (z. B. modelData eines Repeaters) enthalten Listen als Sequenzen, für die
// Array.isArray falsch ist. Eine JSON-Kopie macht daraus gewöhnliche Objekte und Arrays.
function _rein(wert) {
    if (wert === null || wert === undefined || typeof wert !== "object")
        return wert;
    try {
        return JSON.parse(JSON.stringify(wert));
    } catch (e) {
        return null;
    }
}

function _objekt(wert) {
    return wert !== null && typeof wert === "object" && !Array.isArray(wert);
}

function kopie(wert) {
    return wert === undefined ? undefined : JSON.parse(JSON.stringify(wert));
}

function _ganzzahl(wert, min, max) {
    if (typeof wert !== "number" || !isFinite(wert) || Math.round(wert) !== wert)
        return null;
    return wert >= min && wert <= max ? wert : null;
}

function _zeit(iso) {
    if (typeof iso !== "string")
        return NaN;
    return new Date(iso).getTime();
}

function _iso(ms) {
    return new Date(ms).toISOString();
}

function gueltigeId(id) {
    return typeof id === "string" && id.length > 0 && id.length <= 64 && ID_MUSTER.test(id);
}

// --- Leitplanken --------------------------------------------------------------

// Minuten bis zur automatischen Sperre: immer 1–15, Standard 5
function sperreMinuten(wunsch) {
    var n = typeof wunsch === "number" ? wunsch : (typeof wunsch === "string" && wunsch.trim() !== "" ? Number(wunsch) : NaN);
    if (!isFinite(n))
        return LEITPLANKEN.sperreMinutenStandard;
    return Math.min(LEITPLANKEN.sperreMinutenMax, Math.max(LEITPLANKEN.sperreMinutenMin, Math.round(n)));
}

// Erzwingt die Leitplanken im wirksamen Zustand. kontext.freigabe: Bildschirm wird geteilt.
function leitplankenAnwenden(zustand, kontext) {
    if (!_objekt(zustand))
        return null;
    var erg = kopie(zustand);
    for (var i = 0; i < GESPERRT.length; i++)
        delete erg[GESPERRT[i]];
    erg.leitplanken = {
        inhalteBeiFreigabe: LEITPLANKEN.inhalteBeiFreigabe,
        sperreZeigtInhalte: LEITPLANKEN.sperreZeigtInhalte,
        sperreAbschaltbar: LEITPLANKEN.sperreAbschaltbar
    };
    // Bei Freigabe nie Inhalte, egal was der Zustand sagt
    erg.inhalteVerbergen = !!(kontext && kontext.freigabe) && !LEITPLANKEN.inhalteBeiFreigabe;
    return erg;
}

// --- Werte prüfen -------------------------------------------------------------

// Minuten aus «gebuendelt-<N>», sonst -1
function gebuendeltMinuten(wert) {
    var m = /^gebuendelt-([1-9][0-9]{0,3})$/.exec(typeof wert === "string" ? wert : "");
    if (!m)
        return -1;
    var n = Number(m[1]);
    return n <= MINUTEN_MAX ? n : -1;
}

function gueltigeMitteilungen(wert) {
    return wert === "alle" || wert === "nur-dringend" || wert === "keine" || gebuendeltMinuten(wert) > 0;
}

// «uhrzeit:HH:MM» → "HH:MM", sonst ""
function uhrzeitAus(ausloeser) {
    if (typeof ausloeser !== "string" || ausloeser.indexOf("uhrzeit:") !== 0)
        return "";
    var zeit = ausloeser.slice(8);
    return UHRZEIT_MUSTER.test(zeit) ? zeit : "";
}

function gueltigerAusloeser(wert) {
    if (typeof wert !== "string")
        return false;
    if (wert.indexOf("uhrzeit:") === 0)
        return uhrzeitAus(wert) !== "";
    return wert !== "uhrzeit" && WERTE.ausloeser.indexOf(wert) >= 0;
}

// Normalisiertes Ende oder null
function gueltigesEnde(ende) {
    if (!_objekt(ende) || WERTE.ende.indexOf(ende.art) < 0)
        return null;
    if (ende.art === "timer") {
        var minuten = _ganzzahl(ende.minuten, 1, MINUTEN_MAX);
        return minuten === null ? null : { art: "timer", minuten: minuten };
    }
    return { art: ende.art };
}

// Nur die gültigen Wertschlüssel (ohne Name). Ungültige Werte fallen weg.
function werte(quelle) {
    quelle = _rein(quelle);
    var erg = {};
    if (!_objekt(quelle))
        return erg;
    if (gueltigeMitteilungen(quelle.mitteilungen))
        erg.mitteilungen = quelle.mitteilungen;
    if (WERTE.leiste.indexOf(quelle.leiste) >= 0)
        erg.leiste = quelle.leiste;
    if (WERTE.fenster.indexOf(quelle.fenster) >= 0)
        erg.fenster = quelle.fenster;
    if (typeof quelle.heute === "boolean")
        erg.heute = quelle.heute;
    if (typeof quelle.widgets === "boolean")
        erg.widgets = quelle.widgets;
    if (Array.isArray(quelle.ausloeser)) {
        var liste = [];
        for (var i = 0; i < quelle.ausloeser.length; i++) {
            var a = quelle.ausloeser[i];
            if (gueltigerAusloeser(a) && liste.indexOf(a) < 0)
                liste.push(a);
        }
        erg.ausloeser = liste;
    }
    var ende = gueltigesEnde(quelle.ende);
    if (ende)
        erg.ende = ende;
    return erg;
}

// Zustand mit id und Name plus gültigen Werten, oder null
function normalisieren(zustand) {
    zustand = _rein(zustand);
    if (!_objekt(zustand))
        return null;
    var erg = werte(zustand);
    erg.id = typeof zustand.id === "string" ? zustand.id : "";
    erg.name = typeof zustand.name === "string" && zustand.name.trim() !== "" ? zustand.name : erg.id;
    return erg;
}

function _gleich(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
}

// --- Mischen ------------------------------------------------------------------

// Vorlage + Anpassung des Modus. «angepasst» nennt die Schlüssel, die vom Modus abweichen.
function mischen(vorlage, anpassung) {
    var basis = normalisieren(vorlage);
    if (!basis)
        return null;
    var erg = kopie(basis);
    var a = werte(anpassung);
    var angepasst = [];
    for (var i = 0; i < ANPASSBAR.length; i++) {
        var k = ANPASSBAR[i];
        if (a[k] === undefined)
            continue;
        if (!_gleich(a[k], basis[k]))
            angepasst.push(k);
        erg[k] = kopie(a[k]);
    }
    erg.angepasst = angepasst;
    return erg;
}

// Anpassung des Modus für einen Zustand (Objekt, evtl. leer)
function anpassungFuer(modus, zustandId) {
    modus = _rein(modus);
    if (!_objekt(modus) || !_objekt(modus.anpassungen))
        return {};
    var a = modus.anpassungen[zustandId];
    return _objekt(a) ? a : {};
}

// Wirksamer Zustand = Vorlage + Anpassung des aktiven Modus + Leitplanken (zuletzt)
function wirksam(vorlage, modus, kontext) {
    var gemischt = mischen(vorlage, anpassungFuer(modus, vorlage ? vorlage.id : ""));
    return gemischt ? leitplankenAnwenden(gemischt, kontext) : null;
}

// --- Angebot und Auslöser -----------------------------------------------------

function ausloeserVon(zustand) {
    var w = werte(zustand);
    return w.ausloeser && w.ausloeser.length > 0 ? w.ausloeser : ["manuell"];
}

// art: manuell | bildschirmfreigabe | moduswechsel | kalender | uhrzeit (jede Uhrzeit) | uhrzeit:HH:MM
function hatAusloeser(zustand, art) {
    var liste = ausloeserVon(zustand);
    if (art === "uhrzeit")
        return liste.some(function (a) {
            return uhrzeitAus(a) !== "";
        });
    return liste.indexOf(art) >= 0;
}

// Zustände, die der Modus anbietet (ohne Modus oder ohne Liste: alle)
function angeboten(liste, modus) {
    liste = _rein(liste);
    modus = _rein(modus);
    var alle = Array.isArray(liste) ? liste : [];
    if (!_objekt(modus) || !Array.isArray(modus.zustaende))
        return alle.slice();
    return alle.filter(function (z) {
        return z && modus.zustaende.indexOf(z.id) >= 0;
    });
}

// Von Hand startbar: angeboten und mit Auslöser «manuell»
function startbar(liste, modus) {
    return angeboten(liste, modus).filter(function (z) {
        return hatAusloeser(z, "manuell");
    });
}

// Erster angebotener Zustand mit diesem Auslöser, «bevorzugt» zuerst
function waehleFuer(liste, modus, art, bevorzugt) {
    var kandidaten = angeboten(liste, modus).filter(function (z) {
        return hatAusloeser(z, art);
    });
    for (var i = 0; i < kandidaten.length; i++) {
        if (kandidaten[i].id === bevorzugt)
            return kandidaten[i];
    }
    return kandidaten.length > 0 ? kandidaten[0] : null;
}

// --- Laufzeit -----------------------------------------------------------------

// «uhrzeit:07:30» → «uhrzeit», unbekannt → «manuell»
function ausloeserArt(ausloeser) {
    if (uhrzeitAus(ausloeser) !== "" || ausloeser === "uhrzeit")
        return "uhrzeit";
    return ausloeser === "bildschirmfreigabe" || ausloeser === "moduswechsel" ? ausloeser : "manuell";
}

function _ohneVorher(e) {
    var k = kopie(e);
    k.vorher = null;
    return k;
}

// Gilt ein wartender Eintrag noch? Timer: solange er läuft; manuell: ja; ausloeser-endet: nein.
function nochGueltig(e, jetzt) {
    if (!_objekt(e) || !gueltigeId(e.id))
        return false;
    if (e.endeArt === "timer")
        return _zeit(e.ende) > jetzt;
    return e.endeArt === "manuell";
}

// Neuer Eintrag für einen (wirksamen) Zustand
function eintrag(zustand, ausloeser, jetzt) {
    var ende = gueltigesEnde(zustand ? zustand.ende : null) || { art: "manuell" };
    return {
        id: zustand.id,
        seit: _iso(jetzt),
        ende: ende.art === "timer" ? _iso(jetzt + ende.minuten * 60000) : null,
        endeArt: ende.art,
        ausloeser: ausloeserArt(ausloeser),
        vorher: null
    };
}

// Starten. Eine automatische Sitzung (Bildschirmfreigabe) merkt sich den bisherigen Zustand,
// damit er danach zurückkommt, falls er dann noch gilt.
function starten(aktuell, zustand, ausloeser, jetzt) {
    aktuell = _rein(aktuell);
    zustand = _rein(zustand);
    var neu = eintrag(zustand, ausloeser, jetzt);
    if (_objekt(aktuell) && neu.ausloeser === "bildschirmfreigabe") {
        var vorher = aktuell.id === neu.id ? aktuell.vorher : _ohneVorher(aktuell);
        neu.vorher = vorher && nochGueltig(vorher, jetzt) ? _ohneVorher(vorher) : null;
    }
    return neu;
}

// Beenden: der gemerkte Zustand kommt zurück, falls er noch gilt, sonst keiner
function beenden(aktuell, jetzt) {
    aktuell = _rein(aktuell);
    if (!_objekt(aktuell) || !_objekt(aktuell.vorher))
        return null;
    return nochGueltig(aktuell.vorher, jetzt) ? _ohneVorher(aktuell.vorher) : null;
}

// Timer abgelaufen? Liefert den neuen Eintrag (evtl. unverändert).
function pruefen(aktuell, jetzt) {
    if (_objekt(aktuell) && aktuell.endeArt === "timer" && !(_zeit(aktuell.ende) > jetzt))
        return pruefen(beenden(aktuell, jetzt), jetzt);
    return aktuell || null;
}

// Der Auslöser (bildschirmfreigabe, moduswechsel) ist vorbei
function ausloeserEndet(aktuell, art, jetzt) {
    if (_objekt(aktuell) && aktuell.ausloeser === art && aktuell.endeArt === "ausloeser-endet")
        return beenden(aktuell, jetzt);
    return aktuell || null;
}

// Darf ein automatischer Auslöser starten? Die Bildschirmfreigabe immer; Uhrzeit und Moduswechsel
// nur, wenn nichts oder etwas anderes Automatisches läuft (nie über einen von Hand gestarteten
// Zustand oder eine laufende Sitzung).
function darfAutomatisch(aktuell, ausloeser) {
    var art = ausloeserArt(ausloeser);
    if (art === "bildschirmfreigabe")
        return true;
    if (!_objekt(aktuell))
        return true;
    return aktuell.ausloeser === "uhrzeit" || aktuell.ausloeser === "moduswechsel";
}

// Eintrag aus laufzeit.json prüfen (nach Neustart der Oberfläche). ids: vorhandene Zustände.
function wiederherstellen(gespeichert, ids, jetzt, freigabeAktiv) {
    gespeichert = _rein(gespeichert);
    ids = _rein(ids);
    if (!Array.isArray(ids))
        ids = [];
    function pruefeEintrag(e) {
        if (!_objekt(e) || !gueltigeId(e.id) || ids.indexOf(e.id) < 0)
            return null;
        var endeArt = WERTE.ende.indexOf(e.endeArt) >= 0 ? e.endeArt : "manuell";
        var ende = endeArt === "timer" ? _zeit(e.ende) : NaN;
        if (endeArt === "timer" && !isFinite(ende))
            return null;
        var seit = _zeit(e.seit);
        return {
            id: e.id,
            seit: isFinite(seit) ? _iso(seit) : _iso(jetzt),
            ende: endeArt === "timer" ? _iso(ende) : null,
            endeArt: endeArt,
            ausloeser: ausloeserArt(e.ausloeser),
            vorher: null
        };
    }
    var e = pruefeEintrag(gespeichert);
    if (!e)
        return null;
    e.vorher = _objekt(gespeichert.vorher) ? pruefeEintrag(gespeichert.vorher) : null;
    e = pruefen(e, jetzt);
    if (e && !freigabeAktiv)
        e = ausloeserEndet(e, "bildschirmfreigabe", jetzt);
    return e;
}

// Restzeit in Minuten (aufgerundet), -1 ohne Timer
function restMinuten(aktuell, jetzt) {
    if (!_objekt(aktuell) || aktuell.endeArt !== "timer")
        return -1;
    var rest = _zeit(aktuell.ende) - jetzt;
    return isFinite(rest) ? Math.max(0, Math.ceil(rest / 60000)) : -1;
}

// Millisekunden bis sich restMinuten ändert oder der Timer abläuft, -1 ohne Timer
function naechsteAenderung(aktuell, jetzt) {
    if (!_objekt(aktuell) || aktuell.endeArt !== "timer")
        return -1;
    var rest = _zeit(aktuell.ende) - jetzt;
    if (!isFinite(rest))
        return -1;
    if (rest <= 0)
        return 0;
    var bisMinute = rest % 60000;
    return bisMinute === 0 ? 60000 : bisMinute;
}

// --- IDs ----------------------------------------------------------------------

// Dateiname aus einem Anzeigenamen: klein, ohne Umlaute, nur a-z 0-9 und «-», eindeutig
function slug(name, vorhandene, rueckfall) {
    var s = String(name === undefined || name === null ? "" : name).toLowerCase()
        .replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss");
    if (typeof s.normalize === "function")
        s = s.normalize("NFD").replace(/[̀-ͯ]/g, "");
    s = s.replace(/[^a-z0-9]+/g, "-").replace(/^-+/, "").slice(0, 40).replace(/-+$/, "");
    if (s === "")
        s = gueltigeId(rueckfall) ? rueckfall : "eintrag";
    var liste = Array.isArray(vorhandene) ? vorhandene : [];
    var id = s;
    for (var n = 2; liste.indexOf(id) >= 0; n++)
        id = s + "-" + n;
    return id;
}

// --- Texte --------------------------------------------------------------------

function mitteilungenText(wert) {
    var n = gebuendeltMinuten(wert);
    if (n > 0)
        return "Mitteilungen gebündelt alle " + n + " Min.";
    switch (wert) {
    case "alle":
        return "Mitteilungen sofort";
    case "nur-dringend":
        return "Nur Dringendes";
    case "keine":
        return "Mitteilungen pausiert";
    }
    return "";
}

function ausloeserText(liste) {
    liste = _rein(liste);
    var l = Array.isArray(liste) && liste.length > 0 ? liste : ["manuell"];
    if (l.indexOf("bildschirmfreigabe") >= 0)
        return "Startet bei Bildschirmfreigabe";
    for (var i = 0; i < l.length; i++) {
        if (uhrzeitAus(l[i]) !== "")
            return "Startet um " + uhrzeitAus(l[i]);
    }
    if (l.indexOf("moduswechsel") >= 0)
        return "Startet beim Moduswechsel";
    return "Von Hand";
}

function endeText(ende) {
    var e = gueltigesEnde(ende) || { art: "manuell" };
    if (e.art === "timer")
        return e.minuten + " Min.";
    if (e.art === "ausloeser-endet")
        return "endet mit dem Auslöser";
    return "bis zum Beenden";
}

function _wertText(schluessel, wert) {
    switch (schluessel) {
    case "mitteilungen":
        return mitteilungenText(wert);
    case "leiste":
        return wert === "aus" ? "Leiste aus" : wert === "reduziert" ? "Leiste reduziert" : "Leiste normal";
    case "fenster":
        return wert === "fokus" ? "Nur das aktive Fenster im Vordergrund" : "Fenster normal";
    case "heute":
        return wert ? "«Heute» sichtbar" : "«Heute» ausgeblendet";
    case "widgets":
        return wert ? "Widgets an" : "Widgets aus";
    case "ausloeser":
        return ausloeserText(wert);
    case "ende":
        return "Dauer: " + endeText(wert);
    }
    return "";
}

// Kurzbeschreibung für die Tabelle «Zustände in diesem Modus»
function beschreibung(vorlage, anpassung, istAngeboten) {
    if (!istAngeboten)
        return "In diesem Modus nicht angeboten";
    var gemischt = mischen(vorlage, anpassung);
    if (!gemischt)
        return "";
    if (gemischt.angepasst.length > 0) {
        return gemischt.angepasst.map(function (k) {
            return _wertText(k, gemischt[k]);
        }).join(" · ") + " · sonst wie Vorlage";
    }
    var teile = [ausloeserText(gemischt.ausloeser)];
    if (gemischt.ende && gemischt.ende.art === "timer")
        teile.push(endeText(gemischt.ende));
    return teile.join(" · ") + " · wie Vorlage";
}
