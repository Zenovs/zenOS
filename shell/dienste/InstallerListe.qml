pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "../installer/installer.js" as Logik

// Was über den zen Installer kam, mit «Entfernen …» (Einstellungen › Apps). Die Logik steht in installer/installer.js
// und ist dort getestet.
//
// - Gelesen wird ohne Rechte: «zenos-installer liste --json» (installiert.json, root-eigen und für alle lesbar, dazu der
//   Stand von dpkg). Neu gelesen beim ersten Zugriff, wenn sich installiert.json ändert, nach einer eigenen Entfernung
//   und wenn die Seite es verlangt (aktualisieren(): beim Öffnen, nach Änderungen an /var/lib/dpkg/status, im Takt).
// - Entfernen über pkexec mit dem Helfer zenos-installer-bedienen (fester Pfad, Argumentliste, keine Shell; polkit-Aktion
//   org.zenos.installer.entfernen, jedes Mal mit Passwort). Nur Pakete aus der Liste, eins zur Zeit, nie gesperrt. Die
//   Arbeit macht zenos-installer-entfernen@PAKET.service: Gehen die Einstellungen zu, läuft sie weiter. Solange der
//   Helfer läuft, fragt der Dienst alle 1,5 s «zenos-installer status --json» nach der Phase (wartet, entfernt).
// - Rückmeldung wie bei den Basis-Updates: ein Hinweis (Toast) nach dem eigenen Klick, nie eine Mitteilung; eine
//   abgebrochene Passwortabfrage bleibt still.
Singleton {
    id: root

    readonly property string helfer: Logik.HELFER
    readonly property string programm: Pfade.bin + "/zenos-installer"
    readonly property string listePfad: "/var/lib/zenos/installer/installiert.json"

    // [{ paket, name, version, zustand, seitMs }] (installer.js listeLesen); leer, solange nichts gelesen ist
    readonly property var liste: _liste
    readonly property bool gelesen: _gelesen
    readonly property bool fehlgeschlagen: _fehlgeschlagen
    // Paket, das gerade entfernt wird, sonst ""
    readonly property string laeuft: _laeuft
    // Zeilen für die Einstellungen (installer.js listeZeilen)
    readonly property var zeilen: Logik.listeZeilen(_liste, {
        laeuft: _laeuft,
        laufPhase: _laufPhase,
        polkitOffen: Oberflaeche.polkitOffen,
        frei: !Oberflaeche.gesperrt,
        jetztMs: _jetzt
    })

    function aktualisieren(): void {
        _jetzt = Date.now();
        if (lesen.running)
            _nochmal = true;
        else
            lesen.running = true;
    }

    // «Entfernen …» in den Einstellungen: nur ein Paket aus der Liste, eins zur Zeit, nie gesperrt
    function entfernen(paket: string): bool {
        if (_laeuft !== "" || Oberflaeche.gesperrt || !_liste.some(e => e.paket === paket))
            return false;
        const argv = Logik.entfernenBefehl(helfer, paket);
        if (argv === null)
            return false;
        const eintrag = _liste.find(e => e.paket === paket);
        _name = eintrag?.name ?? paket;
        _laeuft = paket;
        _laufPhase = "";
        _code = -1;
        _beginn = Date.now();
        entfernenProzess.command = argv;
        entfernenProzess.running = true;
        return true;
    }

    // --- intern ---

    property var _liste: []
    property bool _gelesen: false
    property bool _fehlgeschlagen: false
    property bool _nochmal: false
    property string _laeuft: ""
    property string _laufPhase: ""
    property string _name: ""
    property int _code: -1
    property real _beginn: 0
    property real _jetzt: Date.now()

    function _gelesenNeu(ausgabe: string, code: int): void {
        const l = code === 0 ? Logik.listeLesen(ausgabe) : null;
        if (l === null) {
            if (code !== 0)
                console.warn("InstallerListe: zenos-installer liste endete mit", code);
            _fehlgeschlagen = true;
        } else {
            _fehlgeschlagen = false;
            if (JSON.stringify(l) !== JSON.stringify(_liste))
                _liste = l;
        }
        _gelesen = true;
        if (_nochmal) {
            _nochmal = false;
            lesen.running = true;
        }
    }

    function _entfernt(): void {
        if (_laeuft === "")
            return;
        nachher.running = true;
    }

    function _rueckmelden(statusJson: string): void {
        if (_laeuft === "")
            return;
        const antwort = Logik.entfernenRueckmeldung(_code, {
            letzte: Logik.statusLesen(statusJson).letzte,
            paket: _laeuft,
            name: _name,
            beginnMs: _beginn,
            fehler: fehlerText.text
        });
        // 3 abgelehnt, 10 Stopp, 75 belegt und 126 abgebrochen sind Zustände, keine Fehler
        if ([0, 3, 10, 75, 126].indexOf(_code) < 0)
            console.warn("InstallerListe: Entfernen von", _laeuft, "endete mit Exit", _code, antwort?.text ?? "");
        _laeuft = "";
        _laufPhase = "";
        if (antwort !== null)
            Oberflaeche.hinweis(antwort.text, antwort.art);
        aktualisieren();
    }

    Component.onCompleted: aktualisieren()

    Process {
        id: lesen

        property int code: -1

        command: [root.programm, "liste", "--json"]
        workingDirectory: Pfade.home
        stdout: StdioCollector {
            id: listeAusgabe
        }

        onStarted: code = -1
        onExited: (code, status) => lesen.code = status !== 0 ? -1 : code
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => root._gelesenNeu(listeAusgabe.text, lesen.code));
        }
    }

    Process {
        id: entfernenProzess

        property bool gestartet: false

        workingDirectory: Pfade.home
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
            Qt.callLater(root._entfernt);
        }
    }

    // Phase der Unit, solange entfernt wird
    Process {
        id: laufAbfrage

        command: [root.programm, "status", "--json"]
        workingDirectory: Pfade.home
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._laeuft !== "")
                    root._laufPhase = Logik.laufPhase(Logik.statusLesen(text), "entfernen", root._laeuft);
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root._laeuft !== ""
        onTriggered: {
            if (!laufAbfrage.running)
                laufAbfrage.running = true;
        }
    }

    // Nach pkexec: letzte.json über status --json, dann die Rückmeldung
    Process {
        id: nachher

        command: [root.programm, "status", "--json"]
        workingDirectory: Pfade.home
        stdout: StdioCollector {
            id: nachherAusgabe
        }
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => root._rueckmelden(nachherAusgabe.text));
        }
    }

    // installiert.json ersetzt root atomar (wie letzte.json der Basis: neu laden, dann wird weiter beobachtet); fehlt sie
    // noch, sagt es der nächste Aufruf von aktualisieren()
    FileView {
        id: listeDatei

        path: root.listePfad
        printErrors: false
        watchChanges: true
        onFileChanged: {
            listeDatei.reload();
            root.aktualisieren();
        }
    }
}
