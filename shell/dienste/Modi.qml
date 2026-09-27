pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "../modi/zustandslogik.js" as Logik

// Modi (~/.config/zenos/modi/<id>.json) und der aktive Modus (laufzeit.json, Schlüssel «modus»).
// Ein Wechsel setzt den Akzent (Erscheinung liest Modi.aktiv), öffnet die Apps des Modus, setzt das
// Raster des aktuellen Bildschirm-Profils und startet Zustände mit dem Auslöser «moduswechsel».
// Das Chrome-Profil nimmt zenos-chrome beim Start von Chrome aus dem aktiven Modus.
Singleton {
    id: root

    // Alle Modi (Objekte mit id), nach Name sortiert
    readonly property var liste: _sorted(Konfig.modi)
    // Objekt des aktiven Modus oder null
    readonly property var aktiv: _find(aktivId) ?? (_startMode && _startMode.id === aktivId ? _startMode : null)
    // ID des aktiven Modus ("" = keiner)
    property string aktivId: _validId(Konfig.laufzeitStart?.modus) ? Konfig.laufzeitStart.modus : ""

    // Wird nach jedem Wechsel ausgelöst (alt, neu)
    signal gewechselt(string alt, string neu)

    // Modus wechseln. id "" = kein Modus (Standardakzent).
    function wechseln(id: string): void {
        if (!Konfig.verfuegbar)
            return;
        const neu = id ?? "";
        if (neu !== "" && !_find(neu)) {
            console.warn("Modi: unbekannter Modus");
            return;
        }
        if (neu === aktivId)
            return;
        const alt = aktivId;
        aktivId = neu;
        Konfig.aendern("laufzeit", "", {
            modus: neu === "" ? null : neu
        });
        gewechselt(alt, neu);
        if (neu === "")
            return;
        const modus = _find(neu);
        _openApps(modus);
        _applyRaster(modus);
    }

    // Modus speichern (ganze Datei). fertig(ok, meldung) optional.
    function speichern(id: string, daten: var, fertig: var): void {
        Konfig.schreiben("modi", id, _clean(daten), fertig);
    }

    // Neuen Modus anlegen; gibt die neue ID zurück (Dateiname aus dem Namen)
    function anlegen(daten: var, fertig: var): string {
        if (!Konfig.verfuegbar)
            return "";
        const d = _clean(daten);
        if (!d.name || !String(d.name).trim())
            d.name = "Neuer Modus";
        const id = Logik.slug(d.name, Konfig.modi.map(m => m.id), "modus");
        Konfig.schreiben("modi", id, d, fertig);
        return id;
    }

    // Modus löschen; ist er aktiv, gilt danach kein Modus
    function loeschen(id: string, fertig: var): void {
        if (id === aktivId)
            wechseln("");
        Konfig.loeschen("modi", id, fertig);
    }

    // Bildschirm-Profil, das gerade gilt (Name aus bildschirme.json) oder ""
    function aktuellesProfil(): string {
        const profile = Array.isArray(Konfig.bildschirme?.profile) ? Konfig.bildschirme.profile : [];
        const connected = Quickshell.screens.map(s => s.name);
        // «*» passt auf jeden Ausgang; genaue Profile gehen vor
        const passend = p => Array.isArray(p?.ausgaenge) && p.ausgaenge.length > 0 && p.ausgaenge.every(a => a === "*" || connected.indexOf(a) >= 0);
        const genau = p => passend(p) && p.ausgaenge.indexOf("*") < 0;
        const exact = profile.find(p => genau(p) && p.ausgaenge.length === connected.length);
        const any = exact ?? profile.find(genau) ?? profile.find(passend);
        if (any && typeof any.name === "string")
            return any.name;
        const gespeichert = Konfig.laufzeitStart?.profil;
        return typeof gespeichert === "string" ? gespeichert : "";
    }

    property var _startMode: null

    function _validId(id: var): bool {
        return typeof id === "string" && Logik.gueltigeId(id);
    }

    function _find(id: string): var {
        if (!id)
            return null;
        return Konfig.modi.find(m => m.id === id) ?? null;
    }

    function _sorted(list: var): var {
        return (Array.isArray(list) ? list.slice() : []).sort((a, b) => String(a.name ?? a.id).localeCompare(String(b.name ?? b.id), "de"));
    }

    // Nur bekannte Schlüssel ohne id speichern
    function _clean(daten: var): var {
        const d = daten && typeof daten === "object" ? JSON.parse(JSON.stringify(daten)) : {};
        delete d.id;
        return d;
    }

    function _openApps(modus: var): void {
        const ids = Array.isArray(modus?.oeffnen) ? modus.oeffnen : [];
        if (ids.length === 0)
            return;
        const offen = ToplevelManager.toplevels.values.map(t => (t.appId ?? "").toLowerCase());
        for (const id of ids) {
            if (typeof id !== "string" || id.length === 0)
                continue;
            const entry = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id) ?? DesktopEntries.applications.values.find(e => (e.name ?? "").toLowerCase() === id.toLowerCase()) ?? null;
            if (!entry) {
                console.warn("Modi: App nicht gefunden (Beim Wechsel öffnen)");
                continue;
            }
            // Läuft sie schon, nicht noch einmal öffnen (ruhig bleiben)
            const kennungen = [entry.id, entry.startupClass, id].filter(k => typeof k === "string" && k.length > 0).map(k => k.toLowerCase().replace(/\.desktop$/, ""));
            if (offen.some(a => kennungen.indexOf(a) >= 0))
                continue;
            Aktionen.appStarten(entry);
        }
    }

    function _applyRaster(modus: var): void {
        const raster = modus?.raster;
        if (!raster || typeof raster !== "object")
            return;
        const namen = Object.keys(raster);
        if (namen.length === 0)
            return;
        let profil = aktuellesProfil();
        // Ohne Bildschirm-Profile und mit genau einem Eintrag gilt dieser
        if (!profil && namen.length === 1 && !(Array.isArray(Konfig.bildschirme?.profile) && Konfig.bildschirme.profile.length > 0))
            profil = namen[0];
        // Eintrag des Profils, sonst «Standard» (gilt für alle Bildschirme ohne eigenen Eintrag)
        const rasterId = raster[profil] ?? raster["Standard"];
        if (typeof rasterId !== "string" || !Logik.gueltigeId(rasterId))
            return;
        if (typeof Raster.setzen === "function")
            Raster.setzen(rasterId);
    }

    // Den aktiven Modus beim Start sofort lesen, damit schon das erste Bild den richtigen Akzent hat
    FileView {
        id: startFile

        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        if (!_validId(aktivId) || !Konfig.verfuegbar)
            return;
        startFile.path = Pfade.konfig + "/modi/" + aktivId + ".json";
        try {
            const d = JSON.parse(startFile.text() || "null");
            if (d && typeof d === "object" && !Array.isArray(d))
                _startMode = Object.assign(d, {
                    id: aktivId
                });
        } catch (e) {
            // ungültige Datei: wird mit der Liste ohnehin übersprungen
        }
    }
}
