// Tests für die App-Leiste am rechten Rand (shell/appleiste/fenster.mjs).
// Ohne Abhängigkeiten: node --test test/einheiten/

import { test } from "node:test";
import assert from "node:assert/strict";
import {
    alsListe, appSchluessel, buchstabe, gruppieren, istOberflaeche, nameOhneStarter, verlaufNachfuehren, webAppHost, ziel
} from "../../shell/appleiste/fenster.mjs";

// Fenster wie Toplevel aus Quickshell: nur appId zählt, verglichen wird die Identität
function fenster(appId, titel) {
    return { appId: appId, titel: titel ?? appId };
}

function schluessel(ergebnis) {
    return ergebnis.gruppen.map(g => g.schluessel);
}

test("Fenster der Oberfläche gehören nicht in die Leiste", () => {
    assert.equal(istOberflaeche("org.quickshell"), true);
    assert.equal(istOberflaeche(" org.quickshell "), true);
    assert.equal(istOberflaeche("org.quickshell.zenos"), true);
    assert.equal(istOberflaeche("ORG.QUICKSHELL"), true);
    assert.equal(istOberflaeche("org.quickshellfremd"), false);
    assert.equal(istOberflaeche("kitty"), false);
    assert.equal(istOberflaeche(""), false);
    assert.equal(istOberflaeche(undefined), false);
});

test("Schlüssel einer App", () => {
    assert.equal(appSchluessel("Google-Chrome"), "google-chrome");
    assert.equal(appSchluessel(" code.desktop "), "code");
    assert.equal(appSchluessel(""), "");
    assert.equal(appSchluessel(null), "");
});

test("Gruppieren: ein Eintrag pro App, Fenster in Reihenfolge des Erscheinens", () => {
    const a1 = fenster("kitty", "eins");
    const b = fenster("google-chrome");
    const a2 = fenster("Kitty", "zwei");
    const e = fenster("org.quickshell", "Einstellungen");
    const r = gruppieren([a1, b, e, a2], []);
    assert.deepEqual(schluessel(r), ["kitty", "google-chrome"]);
    assert.deepEqual(r.reihenfolge, ["kitty", "google-chrome"]);
    assert.deepEqual(r.gruppen[0].fenster, [a1, a2]);
    assert.equal(r.gruppen[0].fenster[0], a1);
    assert.equal(r.gruppen[0].appId, "kitty");
    assert.deepEqual(r.gruppen[1].fenster, [b]);
});

test("Gruppieren: feste Reihenfolge nach dem ersten Öffnen, auch wenn sich die Liste umsortiert", () => {
    const mail = fenster("coremail");
    const chrome = fenster("google-chrome");
    const code = fenster("code");
    let r = gruppieren([mail, chrome], []);
    assert.deepEqual(r.reihenfolge, ["coremail", "google-chrome"]);
    // Neue App hinten, bestehende bleiben, auch wenn die Fensterliste anders sortiert ankommt
    r = gruppieren([code, chrome, mail], r.reihenfolge);
    assert.deepEqual(schluessel(r), ["coremail", "google-chrome", "code"]);
    // Chrome geschlossen: fällt heraus, die anderen rücken nicht um
    r = gruppieren([mail, code], r.reihenfolge);
    assert.deepEqual(schluessel(r), ["coremail", "code"]);
    // wieder geöffnet: hinten
    r = gruppieren([fenster("google-chrome"), mail, code], r.reihenfolge);
    assert.deepEqual(schluessel(r), ["coremail", "code", "google-chrome"]);
});

test("Gruppieren: späte appId, Fenster ohne appId und ungültige Eingaben", () => {
    const ohne = fenster("");
    const ohne2 = fenster(undefined);
    const r = gruppieren([ohne, fenster("foot"), ohne2, null], ["foot"]);
    assert.deepEqual(schluessel(r), ["foot", ""]);
    assert.deepEqual(r.gruppen[1].fenster, [ohne, ohne2]);
    // Bekommt das Fenster seine appId, wechselt es die Gruppe
    ohne.appId = "foot";
    const r2 = gruppieren([ohne, fenster("foot"), ohne2], r.reihenfolge);
    assert.deepEqual(schluessel(r2), ["foot", ""]);
    assert.equal(r2.gruppen[0].fenster.length, 2);
    assert.deepEqual(gruppieren(null, null), { reihenfolge: [], gruppen: [] });
    assert.deepEqual(gruppieren([], ["weg", 3, "weg"]), { reihenfolge: [], gruppen: [] });
    // doppelte Schlüssel in der alten Reihenfolge zählen einmal
    assert.deepEqual(gruppieren([fenster("a"), fenster("b")], ["b", "b", "a"]).reihenfolge, ["b", "a"]);
});

test("Listen aus QML sind nur array-ähnlich", () => {
    const a = fenster("kitty");
    const b = fenster("foot");
    // wie ToplevelManager.toplevels.values: Länge und Indizes, aber kein Array
    const liste = { length: 2, 0: a, 1: b };
    assert.deepEqual(alsListe(liste), [a, b]);
    assert.deepEqual(alsListe("ab"), []);
    assert.deepEqual(alsListe(undefined), []);
    assert.deepEqual(schluessel(gruppieren(liste, { length: 1, 0: "foot" })), ["foot", "kitty"]);
    assert.deepEqual(verlaufNachfuehren({ length: 1, 0: b }, a, liste), [a, b]);
    assert.equal(ziel({ length: 2, 0: a, 1: b }, null, { length: 1, 0: a }), a);
});

test("Gruppieren: nur Fenster der Oberfläche ergeben keine Gruppe", () => {
    assert.deepEqual(gruppieren([fenster("org.quickshell")], ["org.quickshell"]), { reihenfolge: [], gruppen: [] });
});

test("Verlauf: zuletzt aktiv zuerst, geschlossene und die Oberfläche fallen heraus", () => {
    const a = fenster("a");
    const b = fenster("b");
    const c = fenster("c");
    const e = fenster("org.quickshell");
    let v = verlaufNachfuehren([], a, [a, b, c]);
    assert.deepEqual(v, [a]);
    v = verlaufNachfuehren(v, b, [a, b, c]);
    assert.deepEqual(v, [b, a]);
    v = verlaufNachfuehren(v, a, [a, b, c]);
    assert.deepEqual(v, [a, b]);
    // kein aktives Fenster (z. B. Befehlsfeld offen) und die Einstellungen ändern nichts
    assert.deepEqual(verlaufNachfuehren(v, null, [a, b, c, e]), [a, b]);
    assert.deepEqual(verlaufNachfuehren(v, e, [a, b, c, e]), [a, b]);
    // a geschlossen
    assert.deepEqual(verlaufNachfuehren(v, null, [b, c]), [b]);
    assert.deepEqual(verlaufNachfuehren(null, undefined, null), []);
});

test("Ziel eines Klicks: zuletzt aktives Fenster der App", () => {
    const m1 = fenster("mail", "eins");
    const m2 = fenster("mail", "zwei");
    const browser = fenster("google-chrome");
    // Browser aktiv (z. B. im Vollbild), Mail hat zwei Fenster, zuletzt war m1 aktiv
    assert.equal(ziel([m1, m2], browser, [browser, m1, m2]), m1);
    assert.equal(ziel([m1, m2], browser, [browser, m2, m1]), m2);
    // ohne Verlauf: das zuletzt erschienene
    assert.equal(ziel([m1, m2], browser, []), m2);
    assert.equal(ziel([m1, m2], null, undefined), m2);
});

test("Ziel eines Klicks: App schon aktiv → nächstes Fenster der App, am Ende wieder das erste", () => {
    const a = fenster("kitty", "a");
    const b = fenster("kitty", "b");
    const c = fenster("kitty", "c");
    assert.equal(ziel([a, b, c], a, [a]), b);
    assert.equal(ziel([a, b, c], b, [b, a]), c);
    assert.equal(ziel([a, b, c], c, [c, b, a]), a);
    // nur ein Fenster: bleibt
    assert.equal(ziel([a], a, [a]), a);
    assert.equal(ziel([], a, [a]), null);
    assert.equal(ziel(null, a, [a]), null);
});

test("Web-Apps aus Chrome: Host aus der appId", () => {
    assert.equal(webAppHost("chrome-mail.example.com__-Default"), "mail.example.com");
    assert.equal(webAppHost("chrome-www.example.org__app-Profile_1"), "www.example.org");
    assert.equal(webAppHost("chrome-localhost__-Default"), "localhost");
    assert.equal(webAppHost("google-chrome"), "");
    assert.equal(webAppHost("chrome-ohnepunkt_-Default"), "");
    assert.equal(webAppHost(""), "");
});

test("Name ohne Starter und Anfangsbuchstabe", () => {
    assert.equal(nameOhneStarter("org.example.Notizen"), "Notizen");
    assert.equal(nameOhneStarter("org.example.Notizen.desktop"), "Notizen");
    assert.equal(nameOhneStarter("chrome-mail.example.com__-Default"), "mail.example.com");
    assert.equal(nameOhneStarter("test-mail"), "test-mail");
    assert.equal(nameOhneStarter("1Password"), "1Password");
    assert.equal(nameOhneStarter(""), "Fenster");
    assert.equal(nameOhneStarter(undefined), "Fenster");
    assert.equal(buchstabe("notizen"), "N");
    assert.equal(buchstabe(" über"), "Ü");
    assert.equal(buchstabe("𝔸pp"), "𝔸");
    assert.equal(buchstabe(""), "");
    assert.equal(buchstabe(null), "");
});
