pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../dienste/energie.js" as EnergieLogik
import "../modi/zustandslogik.js" as Logik
import "bildschirm.js" as BildschirmLogik

// Bildschirm am Login-Bildschirm (Zenos Entscheid vom 06.10.2026, fest, ohne Einstellung): nach
// LEITPLANKEN.loginBildschirmAusMinuten (1) Min. ohne Eingabe aus, am Netzteil wie am Akku. Logik in bildschirm.js.
// - Gezählt wird im Compositor (IdleMonitor, ohne Rücksicht auf Idle-Hemmer): Jede Eingabe beginnt die Minute neu,
//   auch Tippen im Passwortfeld.
// - Aus und an mit wlopm (wlr-output-power-management), als Argumentliste mit Zeitlimit. Ausfallsicher: Scheitert
//   das Ausschalten, geht er gleich wieder an, nach drei Fehlschlägen in Folge bleibt er an. Ist er sicher dunkel und
//   geht nicht mehr an, beendet sich der Login, und greetd startet ihn neu (neues labwc, alle Bildschirme an).
// - Wecktaste: Ab dem Ausschalten steht sie aus. Die erste Taste, der erste Klick oder die erste Berührung weckt nur
//   und wird verworfen, genau eine (Anmeldefenster: Wecker mit dem Tastaturfokus, Klickfang über allem). Bis
//   WECKEN_SCHONFRIST_MS nach dem Einschalten gilt das noch; weckte die Maus, kommt danach alles an. Wird die Taste
//   gehalten, verwirft das Anmeldefenster auch ihre Wiederholungen, bis sie losgelassen wird.
// - Ohne Eingabe wecken (_wecken): Vorwarnung vor dem Ausschalten (Leerlauf, an, solange sie läuft), ihr Ende, Deckel
//   aufgeklappt, ein neuer Bildschirm. An, ohne Wecktaste (wer tippt, tippt ins Feld), und mindestens eine Minute an,
//   auch wenn der Compositor seine Minute früher beendet. Kommt keine Eingabe, geht er danach wieder aus.
// - Zeichen im Passwortfeld bleiben, wie sie sind; das Passwort fasst dieser Teil nie an. Prozesse nur mit
//   Argumentlisten.
Scope {
    id: root

    required property Leerlauf leerlauf

    // Die nächste Taste, der nächste Klick oder die nächste Berührung weckt nur und wird verworfen
    readonly property bool wecktasteOffen: BildschirmLogik.wecktasteOffen(_z)

    // --- intern ---

    readonly property int _minuten: Logik.LEITPLANKEN.loginBildschirmAusMinuten
    property var _z: BildschirmLogik.zustand()
    property bool _aufgegebenGemeldet: false
    property bool _endet: false
    // Die Bildschirme beim letzten Wechsel (neue wecken)
    property var _bildschirme: []

    // Die Wecktaste kam (Taste, Klick oder Berührung) und ist verworfen. Weckt den Bildschirm.
    function verworfen(was: string): void {
        if (!root.wecktasteOffen)
            return;
        console.info("Login: Wecktaste verworfen (" + was + ")");
        root._z = BildschirmLogik.verworfen(root._z);
        nachWecken.stop();
        root._weiter();
    }

    // Die Minute ohne Eingabe ist um
    function _leerlauf(): void {
        const vorher = root._z.soll;
        root._z = BildschirmLogik.leerlauf(root._z, root.leerlauf.vorwarnungLaeuft);
        if (vorher !== "aus" && root._z.soll === "aus")
            console.info("Login:", root._minuten, "Min. ohne Eingabe, Bildschirm aus");
        root._weiter();
    }

    function _eingabe(): void {
        nachWecken.stop();
        root._z = BildschirmLogik.eingabe(root._z);
        root._weiter();
    }

    // Ohne Eingabe wecken (Vorwarnung, Deckel, neuer Bildschirm): an, ohne Wecktaste, und eine Minute lang an. Kommt
    // keine Eingabe, geht er danach aus (nachWecken). Ein «idle» des Compositors in dieser Minute ändert nichts.
    function _wecken(grund: string): void {
        console.info("Login: Bildschirm an (" + grund + ")");
        root._z = BildschirmLogik.wecken(root._z);
        nachWecken.restart();
        root._weiter();
    }

    function _weiter(): void {
        if (root._endet)
            return;
        if (BildschirmLogik.neustartNoetig(root._z)) {
            // Letzter Ausweg: greetd startet den Login neu, ein neues labwc schaltet alle Bildschirme an
            console.warn("Login: Bildschirm geht nicht mehr an, starte den Login neu");
            root._endet = true;
            Qt.exit(1);
            return;
        }
        if (BildschirmLogik.aufgegeben(root._z)) {
            if (!root._aufgegebenGemeldet)
                console.warn("Login: wlopm antwortet nicht brauchbar, der Bildschirm bleibt an");
            root._aufgegebenGemeldet = true;
            return;
        }
        if (wlopm.running)
            return;
        const befehl = BildschirmLogik.naechster(root._z, Date.now());
        if (befehl === "")
            return;
        root._z = BildschirmLogik.gestartet(root._z, befehl);
        wlopm.befehl = befehl;
        wlopm.code = -1;
        wlopm.command = BildschirmLogik.befehl(befehl);
        wlopm.running = true;
    }

    function _fertig(befehl: string, code: int, text: string): void {
        const ok = BildschirmLogik.wlopmOk(code, text);
        root._z = BildschirmLogik.fertig(root._z, befehl, ok, Date.now());
        if (ok && befehl === "an") {
            root._aufgegebenGemeldet = false;
            if (root.wecktasteOffen)
                schonfrist.restart();
        } else if (!ok) {
            const zeile = text.trim().replace(/\s+/g, " ");
            console.warn("Login: wlopm", befehl === "aus" ? "--off" : "--on", "gescheitert (Exit " + code + (zeile.length > 0 ? ": " + zeile : "") + ")", befehl === "aus" ? "· der Bildschirm bleibt an" : "· neuer Versuch");
        }
        root._weiter();
    }

    Connections {
        target: root.leerlauf

        function onVorwarnungLaeuftChanged(): void {
            root._wecken(root.leerlauf.vorwarnungLaeuft ? "Vorwarnung" : "Vorwarnung vorbei");
        }

        function onAufgeklappt(): void {
            root._wecken("Deckel offen");
        }
    }

    // Ein neuer Bildschirm (angesteckt, oder nach dem Ausstecken wieder da): labwc schaltet ihn ein, sein
    // Anmeldefenster wartete sonst noch auf die Wecktaste. Wecken wie beim Deckel; Ausstecken ändert nichts.
    Connections {
        target: Quickshell

        function onScreensChanged(): void {
            const jetzt = BildschirmLogik.liste(Quickshell.screens);
            const dazu = BildschirmLogik.bildschirmDazu(root._bildschirme, jetzt);
            root._bildschirme = jetzt;
            if (dazu)
                root._wecken("Bildschirm neu");
        }
    }

    // Eine Minute ohne Eingabe (Taste, Maus, Touchpad, Berührung), ohne Rücksicht auf Idle-Hemmer
    IdleMonitor {
        id: ausMonitor

        respectInhibitors: false
        timeout: root._minuten * 60
        onIsIdleChanged: {
            if (isIdle)
                root._leerlauf();
            else
                root._eingabe();
        }
    }

    // Die Minute nach einem Wecken ohne Eingabe. Ist danach weiter keine Eingabe gekommen, geht er aus (der Compositor
    // meldet ohne Eingabe kein neues «idle», und eines in dieser Minute galt nicht).
    Timer {
        id: nachWecken

        interval: root._minuten * 60000
        onTriggered: {
            root._z = BildschirmLogik.wachVorbei(root._z);
            if (ausMonitor.isIdle)
                root._leerlauf();
        }
    }

    // Kurz nach dem Einschalten gilt die Wecktaste noch (das Signal der Eingabe kann knapp vor der Taste kommen)
    Timer {
        id: schonfrist

        interval: EnergieLogik.WECKEN_SCHONFRIST_MS
        onTriggered: root._z = BildschirmLogik.schonfristVorbei(root._z)
    }

    // Neuer Versuch, einzuschalten (Pause je Fehlschlag länger)
    Timer {
        interval: 250
        repeat: true
        running: BildschirmLogik.wartet(root._z)
        onTriggered: root._weiter()
    }

    Process {
        id: wlopm

        property string befehl: ""
        property int code: -1

        stdout: StdioCollector {
            id: wlopmAusgabe
        }
        onExited: (code, status) => wlopm.code = status === 0 ? code : -1
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => root._fertig(wlopm.befehl, wlopm.code, wlopmAusgabe.text));
        }
    }

    Component.onCompleted: root._bildschirme = BildschirmLogik.liste(Quickshell.screens)
}
