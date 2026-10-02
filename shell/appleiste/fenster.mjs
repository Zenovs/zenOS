// Fenster und Apps der App-Leiste ohne QML: nach App gruppieren, feste Reihenfolge, Ziel eines Klicks,
// Namen ohne Starter. Getestet mit node (test/einheiten/appleiste.test.mjs).
// Fenster sind Toplevel-Objekte aus Quickshell (oder in den Tests {appId}); verglichen wird nur ihre Identität.

// Listen aus QML (z. B. ToplevelManager.toplevels.values) sind keine echten Arrays, nur «array-ähnlich»
// (Array.isArray ist dort false): als Array nehmen, alles andere als leere Liste.
export function alsListe(wert) {
    if (Array.isArray(wert))
        return wert;
    if (wert && typeof wert === "object" && typeof wert.length === "number")
        return Array.from(wert);
    return [];
}

// Fenster der zenOS-Oberfläche selbst (Quickshell, z. B. die Einstellungen): nie in der App-Leiste
export function istOberflaeche(appId) {
    return /^org\.quickshell(\.|$)/i.test(String(appId ?? "").trim());
}

// Schlüssel einer App: appId klein, ohne «.desktop». Leer, wenn das Fenster keine appId hat (dann teilen sich
// alle solchen Fenster eine Gruppe).
export function appSchluessel(appId) {
    return String(appId ?? "").trim().toLowerCase().replace(/\.desktop$/, "");
}

// Fenster nach App gruppieren, in fester, ruhiger Reihenfolge.
// fenster: offene Fenster in der Reihenfolge ihres Erscheinens, jedes mit appId.
// reihenfolge: Schlüssel der Apps vom letzten Aufruf (Reihenfolge, in der ihr erstes Fenster erschien).
// Ergebnis { reihenfolge, gruppen: [{ schluessel, appId, fenster: [...] }] }: Apps behalten ihren Platz, neue kommen
// hinten dazu, Apps ohne Fenster fallen heraus (öffnet man sie wieder, stehen sie hinten). Fenster der Oberfläche
// fehlen. Die Fenster einer Gruppe stehen in der Reihenfolge ihres Erscheinens.
export function gruppieren(fenster, reihenfolge) {
    const liste = alsListe(fenster);
    const nachSchluessel = new Map();
    for (const f of liste) {
        if (!f)
            continue;
        const appId = typeof f.appId === "string" ? f.appId.trim() : "";
        if (istOberflaeche(appId))
            continue;
        const s = appSchluessel(appId);
        let gruppe = nachSchluessel.get(s);
        if (!gruppe) {
            gruppe = {
                schluessel: s,
                appId: appId,
                fenster: []
            };
            nachSchluessel.set(s, gruppe);
        }
        gruppe.fenster.push(f);
    }
    const neu = [];
    for (const s of alsListe(reihenfolge)) {
        if (typeof s === "string" && nachSchluessel.has(s) && neu.indexOf(s) < 0)
            neu.push(s);
    }
    for (const s of nachSchluessel.keys()) {
        if (neu.indexOf(s) < 0)
            neu.push(s);
    }
    return {
        reihenfolge: neu,
        gruppen: neu.map(s => nachSchluessel.get(s))
    };
}

// Verlauf der aktiven Fenster (zuletzt aktiv zuerst): das aktive nach vorn, geschlossene fallen heraus.
// offen: alle offenen Fenster. Fenster der Oberfläche zählen nicht (sie würden die Apps nur verdrängen).
export function verlaufNachfuehren(verlauf, aktiv, offen) {
    const offene = alsListe(offen);
    const neu = [];
    if (aktiv && offene.indexOf(aktiv) >= 0 && !istOberflaeche(aktiv.appId))
        neu.push(aktiv);
    for (const f of alsListe(verlauf)) {
        if (f && offene.indexOf(f) >= 0 && neu.indexOf(f) < 0)
            neu.push(f);
    }
    return neu;
}

// Fenster, das ein Klick auf eine App nach vorne holt. fensterDerApp in der Reihenfolge ihres Erscheinens.
// Ist ein Fenster der App aktiv und hat sie mehrere: das nächste (nach dem letzten wieder das erste). Sonst das
// zuletzt aktive Fenster der App (verlauf: zuletzt aktiv zuerst), sonst das zuletzt erschienene. null ohne Fenster.
export function ziel(fensterDerApp, aktiv, verlauf) {
    const liste = alsListe(fensterDerApp).filter(f => f);
    if (liste.length === 0)
        return null;
    const i = aktiv ? liste.indexOf(aktiv) : -1;
    if (i >= 0)
        return liste[(i + 1) % liste.length];
    for (const f of alsListe(verlauf)) {
        if (liste.indexOf(f) >= 0)
            return f;
    }
    return liste[liste.length - 1];
}

// Host einer Web-App aus Chrome («chrome-mail.example.com__-Default» → «mail.example.com»), sonst ""
export function webAppHost(appId) {
    const m = /^chrome-([a-z0-9-]+(?:\.[a-z0-9-]+)+|localhost)_/i.exec(String(appId ?? "").trim());
    return m ? m[1].toLowerCase() : "";
}

// Anzeigename, wenn es keinen Starter gibt: bei Web-Apps der Host, bei umgekehrten Domains der letzte Teil
// («org.example.Notizen» → «Notizen»), sonst die appId. Ohne appId «Fenster».
export function nameOhneStarter(appId) {
    const id = String(appId ?? "").trim().replace(/\.desktop$/i, "");
    if (id === "")
        return "Fenster";
    const host = webAppHost(id);
    if (host !== "")
        return host;
    const teile = id.split(".");
    if (teile.length >= 3 && /^[a-z]{2,}$/.test(teile[0]) && teile[teile.length - 1] !== "")
        return teile[teile.length - 1];
    return id;
}

// Anfangsbuchstabe für Apps ohne Symbol (gross, auch bei Zeichen ausserhalb der BMP)
export function buchstabe(name) {
    const zeichen = Array.from(String(name ?? "").trim());
    return zeichen.length > 0 ? zeichen[0].toUpperCase() : "";
}
