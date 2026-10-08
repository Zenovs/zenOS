pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste as Dienste
import "installer.js" as Logik
import "../appleiste/fenster.mjs" as Fenster

// zen Installer: heruntergeladene Software (.deb) so einfach installieren wie auf dem Mac. Ein Doppelklick auf eine
// .deb (Thunar, Download aus Chrome oder Firefox, «Öffnen mit») startet zenos-installer.desktop → «zenos-installer
// oeffnen PFAD» → IPC «installer oeffnen PFAD»: Das Fenster zeigt, was kommt, «Installieren» fragt nach dem Passwort,
// danach «Öffnen». Die Logik steht in installer.js und ist dort getestet; das Fenster in InstallerInhalt.qml.
//
// - Ansehen ohne Rechte: «zenos-installer ansehen PFAD --json» (aus dem Arbeitsstand, ZENOS_CODE). Nichts wird
//   ausgeführt; apt simuliert nur.
// - Installieren: «pkexec /opt/zenos/scripts/bin/zenos-installer-bedienen installieren PFAD SHA256 PLAN» (fester Pfad
//   der polkit-Aktion, Passwort bei jedem Aufruf). Der Helfer kopiert genau die angezeigte Datei in die root-eigene
//   Ablage und wartet auf die Unit; während er läuft, fragt der Dienst alle 1,5 s «zenos-installer status --json» nach
//   der Phase (wartet, prüft, installiert). Danach zählt der Exit, die Einzelheiten kommen aus letzte.json.
// - Der Dienst lebt neben dem Fenster: Schliesst Zeno das Fenster, während installiert wird, läuft es weiter, und am
//   Ende kommt eine ruhige Mitteilung (nur dann; mit offenem Fenster zeigt es das Fenster).
// - Öffnet nichts während der Sperre und der Einrichtung (wie die Einstellungen). Bei einer Bildschirmfreigabe zeigt es
//   nur, was ohnehin auf dem Bildschirm steht (Dateiname, Paket); Mitteilungen hält die Freigabe zurück.
// - IPC «installer»: oeffnen(pfad) → offen, laeuft (eine Installation läuft, das Fenster zeigt sie), gesperrt,
//   einrichtung, ungueltig; status → zu, ansehen, bereit, installiert, abgelehnt, fehler, laeuft, fertig, gescheitert;
//   schliessen; liste → was Einstellungen › Apps zeigt (Dienst InstallerListe: dort auch «Entfernen …»).
Scope {
    id: root

    // Titel des Fensters; daran erkennt vorholen() es unter den Fenstern der Oberfläche
    readonly property string titel: "zen Installer"
    readonly property string programm: Dienste.Pfade.bin + "/zenos-installer"

    // "" (nichts), "ansehen", "ansicht", "laeuft", "ende"
    property string phase: ""
    property bool fensterOffen: false
    // Angefragter Pfad (geprüft) und was zenos-installer dazu sagt
    property string pfad: ""
    property var ansicht: null
    property var ende: null
    // Phase der laufenden Unit (wartet, prueft, installiert)
    property string laufPhase: ""

    // Alles, was das Fenster zeigt (installer.js bild)
    readonly property var bild: Logik.bild({
        phase: phase,
        pfad: pfad,
        ansicht: ansicht,
        ende: ende,
        laufPhase: laufPhase,
        polkitOffen: Dienste.Oberflaeche.polkitOffen
    })
    readonly property string status: Logik.statusText(phase, ansicht, ende)

    property int _nummer: 0
    property real _beginn: 0
    property int _code: -1

    // Doppelklick, «Öffnen mit», zen install, IPC. Antwort wie IPC oeffnen.
    function oeffnen(ziel: string): string {
        if (Dienste.Oberflaeche.gesperrt)
            return "gesperrt";
        // Nicht während der Einrichtung: Das Fenster läge unsichtbar hinter ihrer Vollfläche
        if (Dienste.Oberflaeche.einrichtungOffen)
            return "einrichtung";
        if (Logik.pfadProblem(ziel) !== "")
            return "ungueltig";
        if (phase === "laeuft") {
            _zeigen();
            return "laeuft";
        }
        pfad = ziel;
        _ansehen();
        _zeigen();
        return "offen";
    }

    function schliessen(): void {
        fensterOffen = false;
        // Eine laufende Installation läuft weiter (Mitteilung am Ende)
        if (phase !== "laeuft")
            _zuruecksetzen();
    }

    // Knopf im Fenster
    function ausfuehren(aktion: string): void {
        if (aktion === "installieren")
            installieren();
        else if (aktion === "programm")
            programmOeffnen();
        else if (aktion === "nochmal")
            _ansehen();
        else if (aktion === "schliessen")
            schliessen();
    }

    // Nur die angezeigte Ansicht, nie während der Sperre
    function installieren(): void {
        if (phase !== "ansicht" || installation.running || Dienste.Oberflaeche.gesperrt)
            return;
        const argv = Logik.befehl(Logik.HELFER, ansicht);
        if (argv === null)
            return;
        _code = -1;
        _beginn = Date.now();
        laufPhase = "";
        phase = "laeuft";
        installation.command = argv;
        installation.running = true;
    }

    // Erster Starter des Pakets, wie im Befehlsfeld in eigener Einheit. Kennt DesktopEntries ihn noch nicht (gerade
    // erst installiert), startet gio launch die Datei.
    function programmOeffnen(): void {
        const ziel = Logik.programmZiel(phase === "ende" && ende ? ende.programme : ansicht?.programme ?? []);
        if (ziel === null)
            return;
        const eintrag = DesktopEntries.byId(ziel.id);
        if (eintrag) {
            Dienste.Aktionen.appStarten(eintrag);
        } else {
            console.info("Installer: Starter", ziel.id, "noch nicht bekannt, starte über gio launch");
            Dienste.Aktionen.programmStarten(["gio", "launch", ziel.pfad], ziel.id);
        }
        schliessen();
    }

    // Schon offenes Fenster nach vorn holen (wie die Einstellungen): über wlr-foreign-toplevel, labwc hebt es
    function vorholen(): void {
        const t = Fenster.alsListe(ToplevelManager.toplevels.values).find(f => Fenster.istOberflaeche(f?.appId) && f?.title === root.titel);
        t?.activate();
    }

    function _zeigen(): void {
        Dienste.Oberflaeche.uebersichtSchliessen();
        if (fensterOffen)
            Qt.callLater(vorholen);
        else
            fensterOffen = true;
    }

    function _zuruecksetzen(): void {
        // Ein noch laufendes Ansehen zählt nicht mehr
        _nummer++;
        phase = "";
        ansicht = null;
        ende = null;
        laufPhase = "";
    }

    function _ansehen(): void {
        if (pfad === "")
            return;
        _nummer++;
        ansicht = null;
        ende = null;
        phase = "ansehen";
        ansehenVorlage.createObject(root, {
            nummer: _nummer,
            command: [programm, "ansehen", pfad, "--json"]
        });
    }

    function _angesehen(nummer: int, ausgabe: string, code: int): void {
        if (nummer !== _nummer || phase !== "ansehen")
            return;
        // Exit 0 bereit/installiert, 3 abgelehnt, 1 Fehler: Das JSON sagt es genauer
        if (code !== 0 && code !== 1 && code !== 3)
            console.warn("Installer: zenos-installer ansehen endete mit", code);
        ansicht = Logik.ansichtLesen(ausgabe, pfad);
        phase = "ansicht";
    }

    // Nach pkexec: letzte.json über status --json, dann das Ergebnis
    function _installiert(): void {
        if (phase !== "laeuft")
            return;
        nachher.running = true;
    }

    function _auswerten(statusJson: string): void {
        if (phase !== "laeuft")
            return;
        const e = Logik.abschluss(_code, {
            letzte: Logik.statusLesen(statusJson).letzte,
            sha256: ansicht?.sha256 ?? "",
            beginnMs: _beginn,
            fehler: fehlerText.text,
            name: Logik.anzeigeName(ansicht, pfad),
            programme: ansicht?.programme ?? []
        });
        laufPhase = "";
        // Passwortabfrage abgebrochen: zurück zur Ansicht, still
        if (e.art === "zurueck") {
            phase = "ansicht";
            if (!fensterOffen)
                _zuruecksetzen();
            return;
        }
        if ([0, 3, 10, 75, 126].indexOf(_code) < 0)
            console.warn("Installer: Installieren endete mit Exit", _code, e.satz);
        ende = e;
        phase = "ende";
        if (!fensterOffen) {
            const m = Logik.mitteilung(e);
            if (m !== null)
                Quickshell.execDetached(Logik.mitteilungBefehl(m));
            _zuruecksetzen();
        }
    }

    IpcHandler {
        target: "installer"

        // Pfad zu einer .deb (absolut); Antwort: offen, laeuft, gesperrt, einrichtung, ungueltig
        function oeffnen(pfad: string): string {
            return root.oeffnen(pfad);
        }

        // zu, ansehen, bereit, installiert, abgelehnt, fehler, laeuft, fertig, gescheitert
        function status(): string {
            return root.status;
        }

        function schliessen(): void {
            root.schliessen();
        }

        // Was Einstellungen › Apps unter «Über den zen Installer» zeigt: die Paketnamen mit Leerzeichen, sonst
        // «keine». Liest neu ein; das Ergebnis zählt erst für den nächsten Aufruf (wie IPC basis). Entfernen geht nur
        // über den Knopf dort.
        function liste(): string {
            Dienste.InstallerListe.aktualisieren();
            const namen = Dienste.InstallerListe.liste.map(e => e.paket);
            return namen.length > 0 ? namen.join(" ") : "keine";
        }
    }

    // Ein Prozess je Ansehen (ein neues Öffnen macht ein laufendes ungültig, statt auf sein Ende zu warten)
    Component {
        id: ansehenVorlage

        Process {
            id: ansehen

            property int nummer
            property int code: -1
            property bool gestartet: false

            workingDirectory: Dienste.Pfade.home
            running: true
            stdout: StdioCollector {
                id: ansehenAusgabe
            }

            onStarted: ansehen.gestartet = true
            onExited: (code, status) => ansehen.code = status !== 0 ? -1 : code
            onRunningChanged: {
                if (ansehen.running)
                    return;
                const nummer = ansehen.nummer;
                const code = ansehen.gestartet ? ansehen.code : -1;
                // Erst nach dem Ende des Datenstroms (StdioCollector), dann aufräumen
                Qt.callLater(() => {
                    root._angesehen(nummer, ansehenAusgabe.text, code);
                    ansehen.destroy();
                });
            }
        }
    }

    Process {
        id: installation

        property bool gestartet: false

        workingDirectory: Dienste.Pfade.home
        stderr: StdioCollector {
            id: fehlerText
        }

        onStarted: gestartet = true
        onExited: (code, status) => root._code = status !== 0 ? -1 : code
        onRunningChanged: {
            if (running)
                return;
            if (!gestartet)
                root._code = -1;
            gestartet = false;
            Qt.callLater(root._installiert);
        }
    }

    // Phase der Unit, solange installiert wird
    Process {
        id: laufAbfrage

        command: [root.programm, "status", "--json"]
        workingDirectory: Dienste.Pfade.home
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.phase === "laeuft")
                    root.laufPhase = Logik.laufPhase(Logik.statusLesen(text));
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.phase === "laeuft"
        onTriggered: {
            if (!laufAbfrage.running)
                laufAbfrage.running = true;
        }
    }

    Process {
        id: nachher

        command: [root.programm, "status", "--json"]
        workingDirectory: Dienste.Pfade.home
        stdout: StdioCollector {
            id: nachherAusgabe
        }
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => root._auswerten(nachherAusgabe.text));
        }
    }

    LazyLoader {
        active: root.fensterOffen

        FloatingWindow {
            id: fenster

            readonly property var _bildschirm: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

            title: root.titel
            color: Theme.flaeche
            implicitWidth: 640
            implicitHeight: Math.min(760, (_bildschirm?.height ?? 900) - Theme.leisteHoehe - Theme.titelzeile - 2 * Theme.a5)
            minimumSize: Qt.size(520, Math.min(480, implicitHeight))
            visible: true

            onClosed: root.schliessen()

            InstallerInhalt {
                anchors.fill: parent
                focus: true
                bild: root.bild
                ansehenNummer: root._nummer
                onAusgefuehrt: aktion => root.ausfuehren(aktion)
            }
        }
    }
}
