pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.dienste

// Stand der proprietären Apps aus «zenos-apps status --json» (installiert, Version, verfügbar für
// diese Architektur) und die Auswahl zum Installieren. Installiert wird nie hier, sondern in einem
// Terminal-Fenster mit «zen apps installieren», das vorher alles zeigt und nachfragt.
Item {
    id: root

    // [{ id, name, hersteller, herkunft, groesseMb, installiert, version, verfuegbar, hinweis, neueste }]
    property var apps: []
    property var agent: ({
            konfiguriert: false,
            socket: false
        })
    property bool geladen: false
    property bool fehlgeschlagen: false
    // id → true für ausgewählte Apps (Standard: alles, was installierbar ist)
    property var auswahl: ({})
    // Bei jedem Laden auch die GitHub-Releases fragen (coremail, Nubix; zenos-apps merkt sich das
    // Ergebnis 12 Stunden)
    property bool netz: true

    readonly property var installierbar: apps.filter(a => a.verfuegbar && !a.installiert)
    readonly property var gewaehlt: installierbar.filter(a => auswahl[a.id] !== false).map(a => a.id)
    readonly property bool allesInstalliert: geladen && installierbar.length === 0
    // Apps, die «zen apps aktualisieren» selbst aktualisiert (die übrigen kommen über apt)
    readonly property var aktualisierbar: apps.filter(a => a.installiert && ["1password", "coremail", "nubix"].indexOf(a.id) >= 0).map(a => a.id)

    function laden(): void {
        _netzDa = false;
        if (!statusAufruf.running)
            statusAufruf.exec({
                command: [Pfade.bin + "/zenos-apps", "status", "--json"]
            });
        if (netz && !netzAufruf.running)
            netzAufruf.exec({
                command: [Pfade.bin + "/zenos-apps", "status", "--json", "--netz"]
            });
    }

    // Nur den lokalen Stand neu lesen (z. B. nach einer Installation im Terminal)
    function nachladen(): void {
        if (statusAufruf.running || netzAufruf.running)
            return;
        _netzDa = false;
        statusAufruf.exec({
            command: [Pfade.bin + "/zenos-apps", "status", "--json"]
        });
    }

    function waehlen(id: string, an: bool): void {
        const neu = Object.assign({}, auswahl);
        neu[id] = an;
        auswahl = neu;
    }

    // Öffnet ein Terminal mit «zen apps <befehl> --fenster <apps>»; das sudo-Passwort fragt es dort
    function imTerminal(befehl: string, ids: var): bool {
        const liste = (Array.isArray(ids) ? ids : []).filter(id => /^[a-z0-9]+$/.test(id));
        if (liste.length === 0 || ["installieren", "aktualisieren"].indexOf(befehl) < 0)
            return false;
        // Eigene systemd-Einheit: ein Neustart der Oberfläche darf apt und dpkg nicht mitten im Lauf beenden
        Aktionen.programmStarten(["kitty", "--title", befehl === "installieren" ? "zenOS · Apps installieren" : "zenOS · Apps aktualisieren", "-o", "remember_window_size=no", "-o", "initial_window_width=110c", "-o", "initial_window_height=36c", "--directory", Pfade.home, "--", Pfade.code + "/scripts/zen", "apps", befehl, "--fenster"].concat(liste), "zen-apps");
        return true;
    }

    // Das Ergebnis mit Release-Abfrage ist neuer als das ohne: danach kein Zurückfallen
    property bool _netzDa: false

    function _uebernehmen(text: string, vomNetz: bool): void {
        if (!vomNetz && _netzDa)
            return;
        try {
            const d = JSON.parse(text);
            if (!d || !Array.isArray(d.apps))
                throw new Error("Form");
            if (JSON.stringify(d.apps) !== JSON.stringify(apps))
                apps = d.apps;
            if (d.agent && typeof d.agent === "object")
                agent = d.agent;
            fehlgeschlagen = false;
            if (vomNetz)
                _netzDa = true;
            // Die Liste bleibt beim letzten bekannten Stand; zenos-apps fragt nach 10 Minuten wieder
            if (vomNetz && d.netzFehler === true)
                Oberflaeche.hinweis("Release-Angaben von GitHub nicht abrufbar (coremail, Nubix)", "warnung");
        } catch (e) {
            if (!geladen)
                fehlgeschlagen = true;
            console.warn("AppKatalog: Stand der Apps nicht lesbar");
        }
        geladen = true;
    }

    Process {
        id: statusAufruf

        // Endet zenos-apps ohne Ausgabe, gilt der Stand als nicht lesbar (_uebernehmen)
        stdout: StdioCollector {
            onStreamFinished: root._uebernehmen(text, false)
        }
    }

    Process {
        id: netzAufruf

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root._uebernehmen(text, true);
            }
        }
    }
}
