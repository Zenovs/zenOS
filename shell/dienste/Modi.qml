pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "../modi/zustandslogik.js" as Logik

// Modi (~/.config/zenos/modi/<id>.json) und der aktive Modus (laufzeit.json, Schlüssel «modus»).
// Ein Wechsel setzt den Akzent (Erscheinung liest Modi.aktiv), setzt das Raster des aktuellen
// Bildschirm-Profils, startet Zustände mit dem Auslöser «moduswechsel» und öffnet die Apps des Modus.
// Das Chrome-Profil nimmt zenos-chrome beim Start von Chrome aus laufzeit.json; die Apps starten
// deshalb erst, wenn dort der neue Modus steht. Chrome öffnet auch dann, wenn schon ein Chrome-Fenster
// da ist, nur nicht in diesem Profil (alle Profile haben dieselbe appId).
Singleton {
    id: root

    // Alle Modi (Objekte mit id), nach Name sortiert
    readonly property var liste: _sorted(Konfig.modi)
    // Objekt des aktiven Modus oder null
    readonly property var aktiv: _find(aktivId) ?? (!Konfig.listenGelesen && _startMode && _startMode.id === aktivId ? _startMode : null)
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
        const nr = ++_switchCount;
        // Apps erst nach dem Schreiben öffnen: zenos-chrome liest den Modus aus laufzeit.json. Bei
        // schnellem Hin und Her öffnet nur der letzte Wechsel. Lehnt zenos-konfig ab, öffnen sie
        // trotzdem (Akzent und Raster wechseln auch; Chrome nimmt dann wie beim Öffnen von Hand das
        // Profil, das in der Datei steht).
        Konfig.aendern("laufzeit", "", {
            modus: neu === "" ? null : neu
        }, () => {
            if (neu !== "" && nr === root._switchCount)
                root._openApps(root._find(neu));
        });
        gewechselt(alt, neu);
        if (neu === "")
            return;
        _applyRaster(_find(neu));
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

    // Bildschirm-Profil, das gerade gilt (Name aus bildschirme.json) oder "". Eine Quelle für alle:
    // Raster ordnet wie kanshi (feste Profile nur bei genau diesen Ausgängen, dann «*») und nimmt sonst
    // das zuletzt von kanshi angewendete Profil (laufzeit.json, live beobachtet).
    function aktuellesProfil(): string {
        return Raster.aktuellesProfil();
    }

    // Kopie des aktiven Modus aus dem Start (erstes Bild), nur bis die Listen gelesen sind
    property var _startMode: null
    // Zählt die Wechsel; nur der letzte öffnet Apps
    property int _switchCount: 0
    // Offene Fenster (für «Beim Wechsel öffnen»). Schon beim Start gebunden: ToplevelManager füllt sich
    // erst nach dem ersten Zugriff, asynchron. Im Greeter (ohne Konfiguration) nicht.
    readonly property var _windows: Konfig.verfuegbar ? ToplevelManager.toplevels : null
    // Chrome-Fenster mit dem Profil, in dem sie vermutlich laufen: dem chromeProfil des Modus, der beim
    // Erscheinen aktiv war (zenos-chrome startet Chrome in diesem Profil, auch beim Wechsel). Unter
    // Wayland haben alle Chrome-Fenster dieselbe appId, das Profil sieht man ihnen nicht an.
    // Einträge {fenster, profil}; geschlossene fallen bei der nächsten Änderung der Liste heraus.
    property var _chromeWindows: []

    // Ist die Datei des aktiven Modus weg (von Hand gelöscht, auch vor dem Start), gilt kein Modus
    // mehr, wie beim Löschen in den Einstellungen. Nicht, solange zenos-konfig ihn noch schreibt
    // (neu angelegt und gleich gewählt) und nicht, wenn die Listen nicht lesbar waren.
    function _checkActive(): void {
        if (aktivId === "" || !Konfig.verfuegbar || !Konfig.listenGelesen || _find(aktivId) || Konfig.ausstehend("modi", aktivId))
            return;
        wechseln("");
    }

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
        const offen = (_windows?.values ?? []).map(t => (t.appId ?? "").toLowerCase());
        for (const id of ids) {
            if (typeof id !== "string" || id.length === 0)
                continue;
            const entry = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id) ?? DesktopEntries.applications.values.find(e => (e.name ?? "").toLowerCase() === id.toLowerCase()) ?? null;
            if (!entry) {
                console.warn("Modi: App nicht gefunden (Beim Wechsel öffnen)");
                continue;
            }
            // Läuft sie schon, nicht noch einmal öffnen (ruhig bleiben). Ausnahme Chrome über
            // zenos-chrome mit einem Profil im Modus: nur, wenn schon ein Fenster in diesem Profil offen
            // ist; sonst öffnet zenos-chrome ein Fenster im Profil des neuen Modus.
            const kennungen = [entry.id, entry.startupClass, id].filter(k => typeof k === "string" && k.length > 0).map(k => k.toLowerCase().replace(/\.desktop$/, ""));
            if (offen.some(a => kennungen.indexOf(a) >= 0)) {
                const profil = _chromeProfile(modus);
                if (profil === "" || !_viaZenosChrome(entry) || _chromeOpenIn(profil))
                    continue;
            }
            Aktionen.appStarten(entry);
        }
    }

    function _chromeProfile(modus: var): string {
        return typeof modus?.chromeProfil === "string" ? modus.chromeProfil.trim() : "";
    }

    // Startet der Eintrag Chrome über zenos-chrome (nur dann gilt das Profil des Modus)?
    function _viaZenosChrome(entry: var): bool {
        const befehl = entry?.command ?? [];
        return befehl.length > 0 && /(^|\/)zenos-chrome$/.test(String(befehl[0]));
    }

    function _isChrome(fenster: var): bool {
        return /^google-chrome/.test((fenster?.appId ?? "").toLowerCase());
    }

    // Ist ein Chrome-Fenster offen, das im Profil (Anzeigename) erschienen ist?
    function _chromeOpenIn(profil: string): bool {
        const offen = _windows?.values ?? [];
        const p = profil.toLowerCase();
        return _chromeWindows.some(e => e.profil.toLowerCase() === p && offen.indexOf(e.fenster) >= 0);
    }

    // Neue Chrome-Fenster mit dem Profil des aktiven Modus merken, geschlossene vergessen
    function _trackChromeWindows(): void {
        const offen = _windows?.values ?? [];
        const bleibt = _chromeWindows.filter(e => offen.indexOf(e.fenster) >= 0);
        const profil = _chromeProfile(aktiv);
        for (const t of offen) {
            if (_isChrome(t) && !bleibt.some(e => e.fenster === t))
                bleibt.push({
                    fenster: t,
                    profil: profil
                });
        }
        if (bleibt.length !== _chromeWindows.length || bleibt.some((e, i) => _chromeWindows[i] !== e))
            _chromeWindows = bleibt;
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

    Connections {
        target: root._windows

        function onValuesChanged(): void {
            root._trackChromeWindows();
        }
    }

    Connections {
        target: Konfig

        function onGeladenChanged(): void {
            root._checkActive();
        }

        function onListenGelesenChanged(): void {
            root._checkActive();
        }

        function onGeaendert(art: string): void {
            if (art === "modi")
                root._checkActive();
        }
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
