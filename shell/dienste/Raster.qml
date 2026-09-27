pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

// Raster (~/.config/zenos/raster/<id>.json) und das aktive Raster (laufzeit.json, Schlüssel «raster»).
// setzen(id) erzeugt die labwc-Konfiguration neu (zenos-labwc --raster <id>); zenos-labwc hält das Raster
// in laufzeit.json fest, nur über «zenos-konfig aendere laufzeit» («modus» und «zustand» von Modi und
// Zustaende bleiben). Dieser Dienst schreibt laufzeit.json nie selbst, er liest sie nur. Wechselt kanshi
// beim Anschliessen eines Bildschirms das Profil, ruft es
// zenos-labwc --profil auf; die Änderung an laufzeit.json kommt hier über den Dateibeobachter an.
// Ändert sich das aktive Raster oder bildschirme.json (Einstellungen oder von Hand), werden labwc bzw.
// kanshi neu eingerichtet. Im Greeter (ohne ~/.config/zenos) wird nichts gestartet.
// IPC «raster»: setzen(id), aktiv(): string
Singleton {
    id: root

    // Standard ohne Eintrag in laufzeit.json (wie zenos-labwc)
    readonly property string standardId: "4er-grid"
    // Vorlagen in der Reihenfolge der Auswahl
    readonly property list<string> vorlagen: ["voll", "haelften", "drei-spalten", "4er-grid", "gross-plus-2"]

    // Alle Raster (Objekte mit id, name, kurz, abstand, bereiche): Vorlagen zuerst, dann nach Name
    readonly property var liste: _sorted(Konfig.raster)
    // ID des aktiven Rasters
    property string aktivId: standardId
    // Objekt des aktiven Rasters oder null
    readonly property var aktiv: liste.find(r => r.id === aktivId) ?? null
    // Zuletzt von kanshi angewendetes Bildschirm-Profil (laufzeit.json) oder ""
    property string profil: ""
    // Bildschirm-Profile aus bildschirme.json (nur Einträge mit Namen)
    readonly property var profile: Array.isArray(Konfig.bildschirme?.profile) ? Konfig.bildschirme.profile.filter(p => p && typeof p.name === "string" && p.name.length > 0) : []
    // Namen der angeschlossenen Bildschirme
    readonly property var ausgaenge: Quickshell.screens.map(s => s.name).filter(n => typeof n === "string" && n.length > 0)

    // Nach jedem Setzen (ok = labwc-Konfiguration geschrieben)
    signal gesetzt(string id, bool ok)

    // Aktives Raster wechseln (IPC, Leiste, Befehlsfeld, Modi)
    function setzen(id: string): void {
        if (!Konfig.verfuegbar)
            return;
        const neu = typeof id === "string" ? id : "";
        if (!_idPattern.test(neu) || !liste.some(r => r.id === neu)) {
            console.warn("Raster: unbekanntes Raster");
            return;
        }
        if (neu === aktivId && !_labwcBusy)
            return;
        const alt = aktivId;
        aktivId = neu;
        _labwc(["--raster", neu], ok => {
            if (!ok && root.aktivId === neu) {
                root.aktivId = alt;
                Oberflaeche.hinweis("Raster lässt sich nicht setzen", "warnung");
            }
            root.gesetzt(neu, ok);
        });
    }

    // Raster speichern (ganze Datei ohne id). fertig(ok, meldung) optional.
    function speichern(id: string, daten: var, fertig: var): void {
        Konfig.schreiben("raster", id, _clean(daten), fertig);
    }

    // Neues Raster anlegen; gibt die neue ID zurück (aus dem Namen, eindeutig)
    function anlegen(daten: var, fertig: var): string {
        if (!Konfig.verfuegbar)
            return "";
        const d = _clean(daten);
        const id = _uniqueId(_slug(d.name ?? ""));
        Konfig.schreiben("raster", id, d, fertig);
        return id;
    }

    // Raster löschen; war es aktiv, gilt danach der Standard (oder das erste übrige)
    function loeschen(id: string, fertig: var): void {
        if (!Konfig.verfuegbar)
            return;
        if (id === aktivId) {
            const rest = liste.filter(r => r.id !== id);
            const ersatz = rest.some(r => r.id === standardId) ? standardId : (rest[0]?.id ?? "");
            if (ersatz !== "")
                setzen(ersatz);
        }
        Konfig.loeschen("raster", id, fertig);
    }

    // bildschirme.json ersetzen; kanshi wird danach über die Dateiänderung neu eingerichtet
    function bildschirmeSpeichern(daten: var, fertig: var): void {
        Konfig.schreiben("bildschirme", "", daten, fertig);
    }

    // Raster, das ein Profil beim Anschliessen setzt (wie zenos-labwc: erster Ausgang mit Eintrag,
    // sonst «*»), ohne den Eintrag eines Modus; "" ohne Eintrag
    function standardFuerProfil(name: string): string {
        const p = profile.find(x => x.name === name);
        const raster = p?.raster && typeof p.raster === "object" ? p.raster : {};
        const ausg = Array.isArray(p?.ausgaenge) ? p.ausgaenge : [];
        for (const a of ausg.concat(["*"])) {
            const id = raster[a];
            if (typeof id === "string" && Konfig.raster.some(r => r.id === id))
                return id;
        }
        return "";
    }

    // Raster als Standard für das aktuelle Bildschirm-Profil festlegen (alle seine Ausgänge; labwc
    // kennt ein Raster für alle Bildschirme). Ohne Profile entsteht «Standard» für beliebige Bildschirme.
    function alsStandard(id: string, fertig: var): void {
        if (!Konfig.verfuegbar || !liste.some(r => r.id === id))
            return;
        const daten = Konfig.bildschirme && typeof Konfig.bildschirme === "object" ? JSON.parse(JSON.stringify(Konfig.bildschirme)) : {};
        if (!Array.isArray(daten.profile))
            daten.profile = [];
        const name = aktuellesProfil();
        let p = daten.profile.find(x => x && x.name === name);
        if (!p) {
            p = daten.profile.find(x => x && Array.isArray(x.ausgaenge) && x.ausgaenge.length === 1 && x.ausgaenge[0] === "*");
            if (!p) {
                p = {
                    name: daten.profile.some(x => x && x.name === "Standard") ? "Alle Bildschirme" : "Standard",
                    ausgaenge: ["*"]
                };
                daten.profile.push(p);
            }
        }
        const raster = {};
        for (const a of p.ausgaenge)
            raster[a] = id;
        p.raster = raster;
        bildschirmeSpeichern(daten, fertig);
    }

    // Profil, das kanshi bei den angeschlossenen Bildschirmen wählt (wie zenos-kanshi ordnet:
    // feste Ausgänge zuerst, dann Profile mit «*»); sonst das zuletzt angewendete.
    function aktuellesProfil(): string {
        const fest = profile.filter(p => Array.isArray(p.ausgaenge) && p.ausgaenge.indexOf("*") < 0);
        const offen = profile.filter(p => Array.isArray(p.ausgaenge) && p.ausgaenge.indexOf("*") >= 0);
        for (const p of fest.concat(offen)) {
            if (profilPasst(p))
                return p.name;
        }
        return profil;
    }

    // Passt ein Profil zu den angeschlossenen Bildschirmen?
    function profilPasst(p: var): bool {
        if (!p || !Array.isArray(p.ausgaenge) || p.ausgaenge.length === 0)
            return false;
        const namen = p.ausgaenge.filter(a => a !== "*");
        if (!namen.every(a => ausgaenge.indexOf(a) >= 0))
            return false;
        return p.ausgaenge.indexOf("*") >= 0 ? ausgaenge.length >= Math.max(1, namen.length) : ausgaenge.length === namen.length;
    }

    readonly property var _idPattern: /^[a-z0-9]+(-[a-z0-9]+)*$/

    property bool _labwcBusy: false
    property var _labwcQueue: null
    property bool _started: false
    property string _appliedRaster: ""
    property string _appliedScreens: ""

    function _sorted(list: var): var {
        const rank = id => {
            const i = vorlagen.indexOf(id);
            return i >= 0 ? i : vorlagen.length;
        };
        return (Array.isArray(list) ? list.slice() : []).filter(r => r && Array.isArray(r.bereiche)).sort((a, b) => {
            const d = rank(a.id) - rank(b.id);
            if (d !== 0)
                return d;
            const n = String(a.name ?? a.id).localeCompare(String(b.name ?? b.id), "de");
            return n !== 0 ? n : (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
        });
    }

    function _clean(daten: var): var {
        const d = daten && typeof daten === "object" ? JSON.parse(JSON.stringify(daten)) : {};
        delete d.id;
        return d;
    }

    function _slug(name: string): string {
        const s = String(name).toLowerCase().replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40).replace(/-+$/, "");
        return s.length > 0 ? s : "raster";
    }

    function _uniqueId(base: string): string {
        const belegt = id => Konfig.raster.some(r => r.id === id);
        if (!belegt(base))
            return base;
        for (let i = 2; i < 1000; i++) {
            if (!belegt(base + "-" + i))
                return base + "-" + i;
        }
        return base + "-" + Date.now();
    }

    function _fromRuntime(text: string): void {
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!d || typeof d !== "object")
            return;
        profil = typeof d.profil === "string" ? d.profil : "";
        // Während zenos-labwc läuft, gilt das gerade gewählte Raster (kein Zurückspringen)
        if (_labwcBusy)
            return;
        aktivId = typeof d.raster === "string" && _idPattern.test(d.raster) ? d.raster : standardId;
    }

    // zenos-labwc mit Argumentliste; nie zwei gleichzeitig, der letzte Wunsch gewinnt
    function _labwc(args: var, fertig: var): void {
        if (_labwcBusy) {
            // Ein noch wartender Wunsch ist überholt und entfällt
            _labwcQueue = {
                args: args,
                fertig: fertig
            };
            return;
        }
        _labwcBusy = true;
        _run([Pfade.bin + "/zenos-labwc"].concat(args), (ok, meldung) => {
            if (!ok)
                console.warn("Raster:", meldung || "zenos-labwc ist fehlgeschlagen");
            if (typeof fertig === "function")
                fertig(ok);
            root._labwcBusy = false;
            const next = root._labwcQueue;
            root._labwcQueue = null;
            if (next)
                root._labwc(next.args, next.fertig);
            else
                laufzeitDatei.reload();
        });
    }

    function _run(command: var, fertig: var): void {
        const proc = aufruf.createObject(root, {
            fertig: fertig
        });
        if (!proc) {
            fertig(false, "Prozess nicht erzeugt");
            return;
        }
        proc.exec({
            command: command,
            workingDirectory: Pfade.home
        });
    }

    // Änderungen an Rastern und Bildschirm-Profilen weitergeben (erst nach dem ersten Laden)
    function _check(): void {
        if (!Konfig.verfuegbar || !Konfig.geladen)
            return;
        const raster = JSON.stringify(aktiv);
        const screens = JSON.stringify(Konfig.bildschirme);
        if (!_started) {
            _started = true;
            _appliedRaster = raster;
            _appliedScreens = screens;
        }
        // Aktives Raster gelöscht: Standard (oder das erste) übernehmen
        if (liste.length > 0 && !aktiv && !_labwcBusy) {
            setzen(liste.some(r => r.id === standardId) ? standardId : liste[0].id);
            return;
        }
        if (raster !== _appliedRaster && aktiv) {
            // Läuft zenos-labwc gerade, später noch einmal prüfen
            if (_labwcBusy) {
                pruefTimer.restart();
            } else {
                _appliedRaster = raster;
                _labwc([], null);
            }
        }
        if (screens !== _appliedScreens) {
            _appliedScreens = screens;
            _run([Pfade.bin + "/zenos-kanshi"], (ok, meldung) => {
                if (!ok)
                    console.warn("Raster: kanshi-Konfiguration:", meldung || "zenos-kanshi ist fehlgeschlagen");
            });
        }
    }

    Timer {
        id: pruefTimer

        interval: 300
        onTriggered: root._check()
    }

    Connections {
        target: Konfig

        function onGeaendert(art: string): void {
            if (art === "raster" || art === "bildschirme")
                pruefTimer.restart();
        }

        function onGeladenChanged(): void {
            pruefTimer.restart();
        }
    }

    FileView {
        id: laufzeitDatei

        path: Pfade.zustand + "/laufzeit.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._fromRuntime(text())
    }

    Component {
        id: aufruf

        Process {
            id: proc

            property var fertig: null
            property bool _started: false
            property bool _done: false

            function _finish(ok: bool, meldung: string): void {
                if (_done)
                    return;
                _done = true;
                try {
                    if (typeof fertig === "function")
                        fertig(ok, meldung);
                } catch (e) {
                    console.warn("Raster:", e);
                }
                proc.destroy();
            }

            stderr: StdioCollector {
                id: fehlerText
            }

            onStarted: _started = true
            onExited: exitCode => _finish(exitCode === 0, fehlerText.text.trim().replace(/^zenos-(labwc|kanshi): /gm, ""))
            onRunningChanged: {
                if (!running && !_started)
                    _finish(false, "nicht gestartet");
            }
        }
    }

    IpcHandler {
        target: "raster"

        function setzen(id: string): void {
            root.setzen(id);
        }

        function aktiv(): string {
            return root.aktivId;
        }
    }

    Component.onCompleted: {
        const text = laufzeitDatei.text();
        if (text)
            _fromRuntime(text);
        pruefTimer.restart();
    }
}
