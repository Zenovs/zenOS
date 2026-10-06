pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.dienste
import "../dienste/energie.js" as EnergieLogik
import "../dienste/geraet.js" as GeraetLogik
import "../modi/zustandslogik.js" as Logik

// Leerlauf am Login-Bildschirm (Zenos Entscheid zum Ausschalten, Antwort b; fest, ohne Einstellung):
// - Im Akkubetrieb (sicherer Messwert, lädt nicht; /run/zenos/geraet.json von zenos-argon) schaltet zenOS nach
//   LEITPLANKEN.loginAusschaltenMinuten (30) Min. ohne Eingabe aus. Gezählt wird ohne Rücksicht auf Idle-Hemmer.
// - Ist die Zeit um, fragt es «zenos-energie darf-ausschalten-login» (dieselben Wächter wie in der Sitzung: SSH, tmux,
//   Updates, Hemmer, logind, dazu keine andere offene Sitzung). Ja: Der Helfer legt den Marker an, die Zeile «zenOS
//   schaltet um 22:41 aus» steht 60 Takte zu 1 s lang da, dann prüft «zenos-energie ausschalten-login» alles erneut
//   und schaltet aus. Jede Eingabe und das Netzteil brechen ab (der Marker wird gelöscht). Ist etwas im Weg, wieder
//   nach 5 Min.; lehnt logind ab, erst nach der nächsten Eingabe.
// - Leerer Akku (zenos-argon, «akku.ausschaltenUm»): dieselbe Zeile mit der Uhrzeit, auch hier sichtbar. Sie hat
//   Vorrang, abbrechen kann nur das Netzteil.
// - Deckel (Argon ONE UP): Aufklappen meldet «aufgeklappt» (Bildschirm.qml schaltet den Bildschirm an). Zuklappen tut
//   hier nichts, angemeldet ist niemand.
// Die Logik steht in dienste/energie.js (wie in der Sitzung, dienste/Energie.qml). Prozesse nur mit Argumentlisten.
Scope {
    id: root

    // Zeile für den Login-Bildschirm, z. B. «zenOS schaltet um 22:41 aus · Eine Taste bricht ab» (leer: keine)
    readonly property string text: EnergieLogik.vorwarnungText(_akkuUhrzeit, _uhrzeit)
    // Die Zeile meldet den leeren Akku (Symbol und Farbe)
    readonly property bool akkuLeer: _akkuUhrzeit.length > 0
    // Sicher im Akkubetrieb: Dann zählt die Zeit bis zum Ausschalten
    readonly property bool zaehlt: EnergieLogik.loginAusschaltenAktiv(_geraet.akku)
    // Die Vorwarnung vor dem Ausschalten läuft (der Bildschirm muss dann an sein, Bildschirm.qml)
    readonly property bool vorwarnungLaeuft: _laeuft

    // Der Deckel wurde aufgeklappt (auch wenn das Zuklappen davor in einer Lücke lag)
    signal aufgeklappt

    // --- intern ---

    readonly property string _helfer: Pfade.bin + "/zenos-energie"
    readonly property string _markerPfad: Pfade.laufzeit + "/vorwarnung"
    property var _geraet: GeraetLogik.leer()
    property string _geraetText: ""
    property var _vorwarnung: EnergieLogik.vorwarnung()
    property int _pruefNummer: 0
    property bool _faehrtHerunter: false
    // Zuletzt bekannter Deckel { zustand, seit } (null: noch keiner), wie in dienste/Geraet.qml
    property var _deckelVorher: null

    readonly property bool _laeuft: _vorwarnung.phase === "laeuft"
    readonly property string _uhrzeit: _laeuft && _vorwarnung.um > 0 ? Qt.formatDateTime(new Date(_vorwarnung.um), "HH:mm") : ""
    readonly property string _akkuUhrzeit: _geraet.ausschaltenUm > 0 ? Qt.formatDateTime(new Date(_geraet.ausschaltenUm), "HH:mm") : ""

    function _lesen(): void {
        const jetzt = Date.now();
        const daten = GeraetLogik.lesen(root._geraetText, jetzt);
        if (JSON.stringify(daten) !== JSON.stringify(root._geraet))
            root._geraet = daten;
        const aktion = GeraetLogik.deckelAktion(root._deckelVorher, daten.deckel, jetzt);
        if (daten.deckel.vorhanden && daten.deckel.zustand !== "")
            root._deckelVorher = {
                zustand: daten.deckel.zustand,
                seit: daten.deckel.seit
            };
        // «sperren» heisst hier: wieder offen, das Zuklappen davor fiel in eine Lücke
        if (aktion === "aufklappen" || aktion === "sperren")
            root.aufgeklappt();
    }

    function _pruefen(): void {
        if (!root.zaehlt || !ausschaltMonitor.isIdle || pruefProzess.running || ausschaltProzess.running)
            return;
        if (!EnergieLogik.vorwarnungPruefbar(root._vorwarnung))
            return;
        root._pruefNummer += 1;
        pruefProzess.nummer = root._pruefNummer;
        pruefProzess.code = -1;
        pruefProzess.running = true;
    }

    function _geprueft(nummer: int, code: int, text: string): void {
        if (nummer !== root._pruefNummer || !root.zaehlt || !ausschaltMonitor.isIdle) {
            if (code === 0 && !markerLoeschen.running)
                markerLoeschen.running = true;
            return;
        }
        if (code === 0) {
            root._vorwarnung = EnergieLogik.vorwarnungStarten(EnergieLogik.vorwarnung(), Date.now());
            console.info("Login: Vorwarnung, schalte um", root._uhrzeit, "aus");
        } else {
            root._blockiert(root._grundAus(text, code));
        }
    }

    function _schritt(): void {
        if (root._faehrtHerunter)
            return;
        root._vorwarnung = EnergieLogik.vorwarnungTakt(root._vorwarnung);
        const schritt = EnergieLogik.vorwarnungSchritt(root._vorwarnung, Date.now());
        if (schritt === "ausschalten") {
            if (!root.zaehlt || ausschaltProzess.running)
                return;
            root._pruefNummer += 1;
            ausschaltProzess.nummer = root._pruefNummer;
            ausschaltProzess.code = -1;
            ausschaltProzess.running = true;
        } else if (schritt === "abbrechen") {
            root._abbrechen("veraltet");
        } else if (schritt === "neu-pruefen") {
            root._pruefen();
        }
    }

    function _ausgeschaltet(nummer: int, code: int, text: string): void {
        if (code === 0) {
            root._faehrtHerunter = true;
            console.info("Login: schalte aus");
            return;
        }
        // Nach der Laufzeit noch keine 60 s (der Takt war etwas schneller): Die Vorwarnung bleibt, im nächsten Takt erneut
        if (code === 4)
            return;
        if (nummer !== root._pruefNummer || !root._laeuft)
            return;
        const grund = root._grundAus(text, code);
        if (code === 3) {
            console.warn("Login: Ausschalten abgelehnt:", grund, "· erst nach der nächsten Eingabe wieder");
            root._vorwarnung = EnergieLogik.vorwarnungAbgelehnt(root._vorwarnung, Date.now(), grund);
        } else {
            root._blockiert(grund);
        }
    }

    function _blockiert(grund: string): void {
        console.info("Login: Ausschalten blockiert:", grund, "· neuer Versuch in 5 Min.");
        root._vorwarnung = EnergieLogik.vorwarnungBlockiert(root._vorwarnung, Date.now(), grund);
    }

    function _grundAus(text: string, code: int): string {
        const zeile = text.trim().split("\n").pop() ?? "";
        const grund = zeile.replace(/^nein:\s*/, "").trim();
        return grund.length > 0 ? grund : "zenos-energie endete mit " + code;
    }

    // Eingabe, Netzteil: Vorwarnung oder Warten enden, eine laufende Prüfung gilt nicht mehr, der Marker ist weg
    function _abbrechen(grund: string): void {
        root._pruefNummer += 1;
        const war = root._vorwarnung.phase;
        if (war !== "laeuft" && war !== "warten" && war !== "abgelehnt")
            return;
        root._vorwarnung = EnergieLogik.vorwarnungAbbrechen(root._vorwarnung, grund);
        if (!markerLoeschen.running)
            markerLoeschen.running = true;
        console.info("Login: Vorwarnung beendet:", grund);
    }

    onZaehltChanged: {
        if (!root.zaehlt)
            root._abbrechen("netzteil");
    }

    // /run/zenos/geraet.json: bei jeder Änderung und alle 5 s (prüft zugleich das Alter)
    FileView {
        id: geraetDatei

        path: "/run/zenos/geraet.json"
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            root._geraetText = text();
            root._lesen();
        }
        onLoadFailed: {
            root._geraetText = "";
            root._lesen();
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: geraetDatei.reload()
    }

    // Zählt ohne Rücksicht auf Hemmer, nur sicher im Akkubetrieb
    IdleMonitor {
        id: ausschaltMonitor

        enabled: root.zaehlt
        respectInhibitors: false
        timeout: Logik.LEITPLANKEN.loginAusschaltenMinuten * 60
        onIsIdleChanged: {
            if (isIdle)
                root._pruefen();
            else
                root._abbrechen("eingabe");
        }
    }

    // Während der Vorwarnung bricht jede Eingabe ab: scharf nach 1 s Ruhe
    IdleMonitor {
        enabled: root._laeuft
        respectInhibitors: false
        timeout: 1
        onIsIdleChanged: {
            if (!isIdle && root._laeuft)
                root._abbrechen("eingabe");
        }
    }

    // Takt der Vorwarnung (1 s) und des Wartens nach einer Blockade (5 s)
    Timer {
        interval: root._laeuft ? 1000 : 5000
        repeat: true
        running: root._laeuft || root._vorwarnung.phase === "warten"
        onTriggered: root._schritt()
    }

    Process {
        id: pruefProzess

        property int nummer: 0
        property int code: -1

        command: [root._helfer, "darf-ausschalten-login"]
        stdout: StdioCollector {
            id: pruefAusgabe
        }
        onExited: (code, status) => pruefProzess.code = status === 0 ? code : -1
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => root._geprueft(pruefProzess.nummer, pruefProzess.code, pruefAusgabe.text));
        }
    }

    Process {
        id: ausschaltProzess

        property int nummer: 0
        property int code: -1

        command: [root._helfer, "ausschalten-login"]
        stdout: StdioCollector {
            id: ausschaltAusgabe
        }
        onExited: (code, status) => ausschaltProzess.code = status === 0 ? code : -1
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => root._ausgeschaltet(ausschaltProzess.nummer, ausschaltProzess.code, ausschaltAusgabe.text));
        }
    }

    Process {
        id: markerLoeschen

        command: ["rm", "-f", "--", root._markerPfad]
    }
}
