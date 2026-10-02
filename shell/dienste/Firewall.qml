pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Firewall (ufw): Zustand lesen, ein- und ausschalten. Standardmässig ist sie an (install.sh).
//
// - Gelesen wird ohne Root-Rechte: ENABLED in /etc/ufw/ufw.conf (an = startet auch beim Hochfahren) und der
//   bewusste Zustand in /var/lib/zenos/firewall («zustand=aus» nach dem Ausschalten über den Schalter oder
//   «zen firewall deaktivieren»; install.sh lässt sie dann aus).
// - Geschaltet wird über pkexec mit dem Helfer zenos-firewall (Argumentliste, keine Shell). polkit erlaubt
//   Einschalten in der aktiven Sitzung ohne Passwort, Ausschalten nur nach dem Passwort, jedes Mal
//   (system/polkit/org.zenos.firewall.policy). Die Abfrage zeigt der polkit-Agent der Oberfläche
//   (polkit/Polkit.qml); dieser Dienst sieht das Passwort nie.
// - Ergebnis: Signal geschaltet(ok, meldung). Abbrechen im Passwortdialog ist kein Fehler (ok false, keine
//   Meldung), alles andere meldet zusätzlich einen Hinweis.
Singleton {
    id: root

    // Fester Pfad: Die polkit-Aktionen gelten genau für dieses Programm (pkexec vergleicht den echten Pfad).
    // Ein Arbeits-Checkout (ZENOS_CODE) zählt hier bewusst nicht.
    readonly property string helfer: "/opt/zenos/scripts/bin/zenos-firewall"

    // ufw ist installiert (ufw.conf lesbar)
    readonly property bool bekannt: _confText !== ""
    readonly property bool aktiv: /^ENABLED=["']?yes["']?\s*$/m.test(_confText)
    // Bewusst ausgeschaltet (Schalter oder zen firewall deaktivieren); seit: ISO 8601 oder leer
    readonly property bool bewusstAus: _zustand === "aus"
    readonly property string seit: _seit
    // Ein Wechsel läuft (pkexec, womöglich mit Passwortabfrage); ziel: true = einschalten
    readonly property bool laeuft: _laeuft
    readonly property bool ziel: _ziel

    signal geschaltet(bool ok, string meldung)

    property string _confText: ""
    property string _zustand: ""
    property string _seit: ""
    property bool _laeuft: false
    property bool _ziel: false
    property int _code: -1

    function einschalten(): void {
        _starten(true);
    }

    function ausschalten(): void {
        _starten(false);
    }

    // Dateien neu lesen (z. B. beim Öffnen der Einstellungen; ufw ersetzt ufw.conf beim Schalten)
    function aktualisieren(): void {
        confDatei.reload();
        zustandDatei.reload();
    }

    function _starten(ein: bool): void {
        if (_laeuft)
            return;
        _ziel = ein;
        _code = -1;
        _laeuft = true;
        prozess.command = ["pkexec", helfer, ein ? "ein" : "aus"];
        prozess.running = true;
    }

    function _fertig(): void {
        if (!_laeuft)
            return;
        _laeuft = false;
        aktualisieren();
        const code = _code;
        const zeilen = fehlerText.text.trim().split("\n");
        // Letzte Zeile des Helfers ohne seinen Namen, z. B. «Firewall bleibt aus: SSH-Verbindung aus …»
        const grund = (zeilen[zeilen.length - 1] ?? "").replace(/^zenos-firewall:\s*/, "").trim();
        let meldung = "";
        if (code === 0) {
            geschaltet(true, "");
            return;
        }
        if (code === 126) {
            // Passwortdialog abgebrochen: ruhig, der Schalter springt zurück
            geschaltet(false, "");
            return;
        }
        if (code < 0)
            meldung = "Firewall: pkexec lässt sich nicht starten (install.sh ausführen)";
        else if (code === 127 && /authentication agent/i.test(fehlerText.text))
            // pkexec fand keinen polkit-Agenten (Oberfläche nicht als Agent angemeldet: zenos-ipc polkit agent)
            meldung = "Firewall: keine Passwortabfrage verfügbar (polkit-Agent nicht angemeldet)";
        else if (code === 127)
            meldung = "Firewall: nicht erlaubt (nur in der aktiven Sitzung am Gerät)";
        else if (code === 3 && grund !== "")
            meldung = grund;
        else if (code === 4)
            meldung = "Firewall: ufw fehlt (install.sh ausführen)";
        else
            meldung = "Firewall liess sich nicht " + (_ziel ? "einschalten" : "ausschalten") + (grund !== "" ? ": " + grund : "");
        console.warn("Firewall:", meldung, "(Exit " + code + ")");
        Oberflaeche.hinweis(meldung, "warnung");
        geschaltet(false, meldung);
    }

    Process {
        id: prozess

        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: fehlerText
        }
        onExited: code => root._code = code
        onRunningChanged: {
            if (!running)
                Qt.callLater(root._fertig);
        }
    }

    FileView {
        id: confDatei

        path: "/etc/ufw/ufw.conf"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._confText = text()
        onLoadFailed: root._confText = ""
    }

    FileView {
        id: zustandDatei

        path: "/var/lib/zenos/firewall"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const t = text();
            const z = t.match(/^zustand=(an|aus)\s*$/m);
            const s = t.match(/^seit=([0-9][0-9T:+-]{9,31})\s*$/m);
            root._zustand = z ? z[1] : "";
            root._seit = s ? s[1] : "";
        }
        onLoadFailed: {
            root._zustand = "";
            root._seit = "";
        }
    }
}
