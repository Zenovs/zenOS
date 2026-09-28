pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

// Persönliche Konfiguration unter ~/.config/zenos über zenos-konfig (prüft gegen das Schema,
// schreibt atomar). Hält Modi, Zustände und Raster als Listen bereit und lädt sie neu, sobald sich
// ein Ordner ändert, auch bei Änderungen von Hand.
// Ohne ~/.config/zenos (Greeter) bleibt alles leer: nichts wird gestartet, gelesen oder geschrieben.
//
// Arten: modi, zustaende, raster (Ordner, Einträge mit "id") · einstellungen, bildschirme, webapps,
// laufzeit (einzelne Dateien). Schreiben ist asynchron; fertig(ok, meldung) meldet das Ergebnis.
Singleton {
    id: root

    // true, sobald ~/.config/zenos existiert (Sitzung); im Greeter false
    readonly property bool verfuegbar: _rootExists
    // true, nachdem alles einmal gelesen wurde
    property bool geladen: false
    // true, wenn die Listen dabei fehlerfrei gelesen wurden (false, solange zenos-konfig scheitert)
    readonly property bool listenGelesen: _listsRead

    property var modi: []
    property var zustaende: []
    property var raster: []
    // Inhalt von bildschirme.json bzw. webapps.json oder null
    property var bildschirme: null
    property var webapps: null

    // laufzeit.json beim Start (synchron gelesen, damit das erste Bild stimmt), sonst {}
    readonly property var laufzeitStart: _runtimeAtStart

    signal geaendert(string art)
    // Ergebnis jedes Schreibens; meldung nennt nie Inhalte
    signal geschrieben(string art, string id, bool ok, string meldung)

    // Einträge einer Ordner-Art (Kopie der Liste)
    function liste(art: string): var {
        return _folderKinds.indexOf(art) >= 0 ? root[art].slice() : [];
    }

    // Ein Eintrag einer Ordner-Art oder null
    function eintrag(art: string, id: string): var {
        if (_folderKinds.indexOf(art) < 0)
            return null;
        return root[art].find(e => e.id === id) ?? null;
    }

    // Ganze Datei ersetzen. Ordner-Arten brauchen eine id, Datei-Arten nicht (id "").
    function schreiben(art: string, id: string, daten: var, fertig: var): void {
        _enqueue("schreibe", art, id, daten, fertig);
    }

    // Oberste Schlüssel zusammenführen (null entfernt einen Schlüssel), z. B. für laufzeit.json
    function aendern(art: string, id: string, teil: var, fertig: var): void {
        _enqueue("aendere", art, id, teil, fertig);
    }

    function loeschen(art: string, id: string, fertig: var): void {
        _enqueue("loesche", art, id, null, fertig);
    }

    // Wartet oder läuft für diesen Eintrag noch ein Schreib- oder Löschauftrag? (id "" bei Datei-Arten)
    function ausstehend(art: string, id: string): bool {
        const key = art + "/" + (id ?? "");
        return _running[key] === true || _waiting[key] !== undefined;
    }

    // Liste einer Ordner-Art neu lesen
    function neuLaden(art: string): void {
        if (!verfuegbar || _folderKinds.indexOf(art) < 0)
            return;
        if (_reading[art]) {
            _readAgain[art] = true;
            return;
        }
        _reading[art] = true;
        _run(["liste", art], "", (ok, text, meldung) => {
            _reading[art] = false;
            if (ok) {
                const list = _parse(text, null);
                _apply(art, list ?? []);
                // Scheiterte das erste Lesen, zählt ein späteres erfolgreiches der Modi
                if (art === "modi" && Array.isArray(list))
                    root._listsRead = true;
            } else if (meldung)
                console.warn("Konfig:", meldung);
            if (_readAgain[art]) {
                _readAgain[art] = false;
                neuLaden(art);
            }
        });
    }

    readonly property list<string> _folderKinds: ["modi", "zustaende", "raster"]
    readonly property list<string> _allKinds: ["modi", "zustaende", "raster", "einstellungen", "bildschirme", "webapps", "laufzeit"]
    readonly property var _idPattern: /^[a-z0-9]+(-[a-z0-9]+)*$/

    property bool _rootExists: false
    property bool _listsRead: false
    property var _runtimeAtStart: ({})
    property var _reading: ({})
    property var _readAgain: ({})
    // Schreibaufträge je Datei: einer läuft, weitere werden zusammengefasst
    property var _running: ({})
    property var _waiting: ({})
    property var _watchers: []
    property bool _watcherWarned: false

    function _parse(text: string, fallback: var): var {
        try {
            return JSON.parse(text);
        } catch (e) {
            return fallback;
        }
    }

    function _apply(art: string, daten: var): void {
        const value = art === "bildschirme" || art === "webapps" ? (daten && typeof daten === "object" && !Array.isArray(daten) ? daten : null) : (Array.isArray(daten) ? daten.filter(e => e && typeof e === "object" && typeof e.id === "string") : []);
        if (JSON.stringify(root[art]) === JSON.stringify(value))
            return;
        root[art] = value;
        root.geaendert(art);
    }

    function _enqueue(befehl: string, art: string, id: string, daten: var, fertig: var): void {
        const callback = typeof fertig === "function" ? fertig : null;
        const report = (ok, meldung) => {
            root.geschrieben(art, id ?? "", ok, meldung);
            if (callback)
                callback(ok, meldung);
        };
        if (!verfuegbar) {
            report(false, "Keine Konfiguration in dieser Sitzung");
            return;
        }
        if (_allKinds.indexOf(art) < 0 || (_folderKinds.indexOf(art) >= 0) !== (typeof id === "string" && _idPattern.test(id))) {
            console.warn("Konfig: ungültige Art oder ID", art);
            report(false, "Ungültige Art oder ID");
            return;
        }
        if (befehl !== "loesche" && (!daten || typeof daten !== "object" || Array.isArray(daten))) {
            report(false, "Erwartet wird ein Objekt");
            return;
        }
        const key = art + "/" + (id ?? "");
        const waiting = _waiting[key];
        if (waiting && befehl === "aendere" && (waiting.befehl === "aendere" || waiting.befehl === "schreibe")) {
            // Teiländerung in den wartenden Auftrag übernehmen (beim Schreiben: null entfernt)
            const d = waiting.daten;
            for (const k of Object.keys(daten)) {
                if (daten[k] === null && waiting.befehl === "schreibe")
                    delete d[k];
                else
                    d[k] = JSON.parse(JSON.stringify(daten[k]));
            }
            waiting.callbacks.push(report);
        } else if (waiting) {
            // Der neuere Auftrag ersetzt den wartenden (z. B. mehrmals Speichern beim Tippen)
            waiting.callbacks.forEach(cb => cb(true, ""));
            _waiting[key] = {
                befehl: befehl,
                art: art,
                id: id,
                daten: befehl === "loesche" ? null : JSON.parse(JSON.stringify(daten)),
                callbacks: [report]
            };
        } else {
            _waiting[key] = {
                befehl: befehl,
                art: art,
                id: id,
                daten: befehl === "loesche" ? null : JSON.parse(JSON.stringify(daten)),
                callbacks: [report]
            };
        }
        _optimistic(befehl, art, id, daten);
        _next(key);
    }

    // Listen sofort anpassen, damit die Oberfläche nicht auf zenos-konfig warten muss;
    // nach dem Schreiben wird ohnehin neu gelesen.
    function _optimistic(befehl: string, art: string, id: string, daten: var): void {
        if (_folderKinds.indexOf(art) < 0) {
            if ((art === "bildschirme" || art === "webapps") && befehl !== "aendere")
                _apply(art, befehl === "loesche" ? null : daten);
            return;
        }
        let list = root[art].filter(e => e.id !== id);
        if (befehl === "schreibe")
            list.push(Object.assign({}, daten, {
                id: id
            }));
        else if (befehl === "aendere") {
            const old = root[art].find(e => e.id === id) ?? {};
            const merged = Object.assign({}, old);
            for (const k of Object.keys(daten)) {
                if (daten[k] === null)
                    delete merged[k];
                else
                    merged[k] = daten[k];
            }
            merged.id = id;
            list.push(merged);
        }
        list.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
        _apply(art, list);
    }

    function _next(key: string): void {
        if (_running[key] || !_waiting[key])
            return;
        const job = _waiting[key];
        delete _waiting[key];
        _running[key] = true;
        const args = [job.befehl, job.art];
        if (job.id)
            args.push(job.id);
        const input = job.daten ? JSON.stringify(job.daten) : "";
        _run(args, input, (ok, text, meldung) => {
            _running[key] = false;
            if (!ok)
                console.warn("Konfig:", meldung || "zenos-konfig hat abgelehnt");
            job.callbacks.forEach(cb => cb(ok, ok ? "" : (meldung || "Nicht gespeichert")));
            // Nach einem Schreiben meldet sich der Ordner selbst; abgelehnt oder ohne Beobachtung neu lesen,
            // damit die vorab angepasste Liste wieder stimmt
            if (_folderKinds.indexOf(job.art) >= 0 && (!ok || _watchers.length === 0))
                neuLaden(job.art);
            else if (!ok && job.art === "bildschirme")
                bildschirmeDatei.reload();
            else if (!ok && job.art === "webapps")
                webappsDatei.reload();
            _next(key);
        });
    }

    // zenos-konfig mit Argumentliste; eingabe geht über stdin
    function _run(args: var, eingabe: string, fertig: var): void {
        const proc = konfigAufruf.createObject(root, {
            fertig: fertig,
            eingabe: eingabe
        });
        if (!proc) {
            fertig(false, "", "zenos-konfig konnte nicht gestartet werden");
            return;
        }
        proc.exec({
            command: [Pfade.bin + "/zenos-konfig"].concat(args)
        });
    }

    function _loadAll(): void {
        _run(["alle"], "", (ok, text, meldung) => {
            if (ok) {
                const d = _parse(text, {});
                for (const art of ["modi", "zustaende", "raster", "bildschirme", "webapps"])
                    _apply(art, d[art]);
                // Erst nach dem Übernehmen: wer darauf wartet, sieht schon die gelesene Liste
                if (Array.isArray(d.modi))
                    root._listsRead = true;
            } else {
                console.warn("Konfig:", meldung || "Konfiguration nicht lesbar");
            }
            root.geladen = true;
        });
    }

    function _createWatchers(): void {
        if (_watchers.length > 0)
            return;
        const component = Qt.createComponent(Qt.resolvedUrl("../modi/OrdnerBeobachter.qml"));
        if (component.status !== Component.Ready) {
            if (!_watcherWarned)
                console.warn("Konfig: Ordner werden nicht beobachtet (Qt.labs.folderlistmodel fehlt?)");
            _watcherWarned = true;
            return;
        }
        const list = [];
        for (const art of _folderKinds) {
            const watcher = component.createObject(root, {
                pfad: Pfade.konfig + "/" + art
            });
            if (!watcher)
                continue;
            watcher.geaendert.connect(() => root._changedIn(art));
            list.push(watcher);
        }
        _watchers = list;
    }

    property var _pending: ({})

    function _changedIn(art: string): void {
        _pending[art] = true;
        debounce.restart();
    }

    function _onRootChanged(): void {
        // Neu angelegte Ordner (modi/, zustaende/, raster/) erst jetzt beobachtbar
        for (const w of _watchers) {
            if (w.count === 0)
                w.neuVerbinden();
        }
    }

    property bool _startedOnce: false

    function _start(): void {
        if (!_rootExists || _startedOnce)
            return;
        _startedOnce = true;
        _createWatchers();
        _loadAll();
    }

    onVerfuegbarChanged: _start()

    Timer {
        id: debounce

        interval: 150
        onTriggered: {
            const arts = Object.keys(root._pending);
            root._pending = {};
            for (const art of arts)
                root.neuLaden(art);
        }
    }

    // Gibt es ~/.config/zenos? Ein Ordner meldet «NotAFile», ein fehlender «FileNotFound».
    // Beobachtet wird dabei auch ~/.config (für den Fall, dass der Ordner später entsteht).
    FileView {
        id: rootDir

        path: Pfade.konfig
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            root._onRootChanged();
        }
        onLoadFailed: error => root._rootExists = error === FileViewError.NotAFile
        onLoaded: root._rootExists = false
    }

    FileView {
        id: bildschirmeDatei

        path: root._rootExists ? Pfade.konfig + "/bildschirme.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._apply("bildschirme", root._parse(text(), null))
        onLoadFailed: root._apply("bildschirme", null)
    }

    FileView {
        id: webappsDatei

        path: root._rootExists ? Pfade.konfig + "/webapps.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._apply("webapps", root._parse(text(), null))
        onLoadFailed: root._apply("webapps", null)
    }

    FileView {
        id: runtimeFile

        path: Pfade.zustand + "/laufzeit.json"
        blockLoading: true
        printErrors: false
    }

    Component {
        id: konfigAufruf

        Process {
            id: proc

            property var fertig: null
            property string eingabe: ""
            property bool _started: false
            property bool _done: false

            function _finish(ok: bool, text: string, meldung: string): void {
                if (_done)
                    return;
                _done = true;
                try {
                    if (typeof fertig === "function")
                        fertig(ok, text, meldung);
                } catch (e) {
                    console.warn("Konfig:", e);
                }
                proc.destroy();
            }

            stdinEnabled: eingabe.length > 0
            stdout: StdioCollector {
                id: out
            }
            stderr: StdioCollector {
                id: err
            }

            onStarted: {
                _started = true;
                if (eingabe.length > 0) {
                    write(eingabe);
                    stdinEnabled = false;
                }
            }
            onExited: exitCode => _finish(exitCode === 0, out.text, err.text.trim().replace(/^zenos-konfig: /gm, ""))
            onRunningChanged: {
                if (!running && !_started)
                    _finish(false, "", "zenos-konfig nicht gestartet");
            }
        }
    }

    Component.onCompleted: {
        rootDir.text();
        _start();
        const text = runtimeFile.text();
        const runtime = text ? _parse(text, {}) : {};
        _runtimeAtStart = runtime && typeof runtime === "object" && !Array.isArray(runtime) ? runtime : {};
    }
}
