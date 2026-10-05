pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "energie.js" as EnergieLogik

// Energie der Sitzung: Bildschirm aus und an, die Sofort-Aktion «Bildschirm aus», die Höchstdauer, die ein
// Idle-Hemmer die automatische Sperre aufhalten darf, und das Ausschalten nach langer Sperre. Die Logik steht in
// energie.js und ist dort getestet.
//
// - aus(): Sofort-Aktion (System-Menü, Befehlsfeld, IPC «energie aus»; Super+Shift+L ruft «zen energie aus»
//   direkt auf). Über «zen energie aus»: zen lock, dann zenos-bildschirm aus. Geweckt wird über die Sperre
//   (sperre/Sperre.qml), bei jeder Eingabe und ohne Rücksicht auf Idle-Hemmer (ein Video hält das nicht auf).
// - bildschirm("aus" | "an"): zenos-bildschirm mit Argumentliste. «aus» sperrt dort immer zuerst (dunkel heisst
//   gesperrt). Es läuft immer nur ein Aufruf, der letzte Wunsch gilt. Gelingt er, kommt bildschirmGeschaltet.
//   Die Sperre nutzt das für «Bildschirm aus nach der Sperre» und zum Wecken.
// - Leitplanke (Code, nicht abschaltbar): Ein Idle-Hemmer (z. B. ein Video im Browser) hält die automatische
//   Sperre höchstens Leitplanken.sperreTrotzHemmerMinuten (60) ohne Eingabe auf, dann sperrt zenOS trotzdem
//   (IdleMonitor ohne Rücksicht auf Hemmer). Ohne Hemmer sperrt zenos-idle wie bisher nach 1–15 Min.
// - Ausschalten nach langer Sperre (ausschalten: nie | akku | immer, 30–240 Min.): Gezählt wird ab der Sperre, ohne
//   Rücksicht auf Idle-Hemmer, «akku» nur sicher im Akkubetrieb. Ist die Zeit um, fragt der Dienst
//   «zenos-energie darf-ausschalten» (Einstellung und Wächter: SSH, tmux, Updates, Hemmer, logind). Ja: Der Helfer
//   legt den Marker $XDG_RUNTIME_DIR/zenos/vorwarnung an, die Vorwarnung beginnt. Der Bildschirm geht an, die Sperre
//   zeigt ruhig die Uhrzeit des Ausschaltens. Nach 60 Takten zu 1 s (nie nach der Uhr) prüft «zenos-energie
//   ausschalten» alles erneut und schaltet aus; ist die Vorwarnung nach der Laufzeit noch keine 60 s alt (Exit 4), im
//   nächsten Takt erneut. Jede Eingabe, das Netzteil (bei «akku») und das Entsperren brechen ab
//   und löschen den Marker; der Helfer verbraucht ihn erst unmittelbar vor dem Ausschalten. Ist etwas im Weg,
//   versucht es der Dienst alle 5 Min. erneut, der Bildschirm bleibt dabei dunkel. Lehnt logind das Ausschalten ab
//   (Exit 3), erst nach der nächsten Eingabe wieder. Stürzt die Oberfläche ab, schaltet nichts aus.
// - Nach einem automatischen Aus zeigt die nächste Sitzung einmal eine ruhige Mitteilung (zenos-energie meldung).
// - Deckel (Argon ONE UP, Leitplanke: Zuklappen sperrt immer, nicht abschaltbar): Geraet meldet jeden Wechsel, den
//   zenos-argon an GPIO27 sieht. Zuklappen sperrt sofort und schaltet den Bildschirm aus (wie aus()), Aufklappen
//   schaltet ihn an. Kommt danach keine Eingabe, geht er nach «Bildschirm aus nach der Sperre» wieder aus. Hat die
//   Oberfläche das Zuklappen verpasst (zu und wieder offen zwischen zwei Lesungen), sperrt sie trotzdem.
// - Ausschalten bei leerem Akku macht zenos-argon selbst (Systemdienst, auch am Login-Bildschirm); Geraet zeigt die
//   Mitteilung, die Sperre die Uhrzeit.
// IPC «energie»: aus(), status(), vorwarnung() (Probe für Bilder und Tests: zeigt die Vorwarnung, schaltet nie aus)
Singleton {
    id: root

    // Wirksame Werte aus einstellungen.json, begrenzt durch die Leitplanken (genauso liest sie zenos-idle)
    readonly property var wirksam: EnergieLogik.wirksam({
        sperreNachMinuten: Einstellungen.sperreNachMinuten,
        bildschirmAusNachSperre: Einstellungen.bildschirmAusNachSperre,
        ausschalten: Einstellungen.ausschalten,
        ausschaltenNachMinuten: Einstellungen.ausschaltenNachMinuten,
        einAusTaste: Einstellungen.einAusTaste
    })
    readonly property int sperreMinuten: wirksam.sperreMinuten
    // Minuten nach der Sperre, bis der Bildschirm ausgeht (1–10)
    readonly property int bildschirmMinuten: wirksam.bildschirmMinuten
    // So lange hält ein Idle-Hemmer die Sperre höchstens auf (Leitplanke)
    readonly property int sperreTrotzHemmerMinuten: Leitplanken.sperreTrotzHemmerMinuten
    // nie | akku | immer
    readonly property string ausschaltenArt: wirksam.ausschalten
    // Minuten gesperrt ohne Eingabe, bis zenOS ausschaltet (30–240)
    readonly property int ausschaltenMinuten: wirksam.ausschaltenMinuten
    // sperren | menue | ausschalten
    readonly property string einAusTaste: wirksam.einAusTaste
    // Akku für die Zeitleiste: vorhanden, sobald er in dieser Sitzung einmal da war (sonst gilt «akku» als «nie»)
    readonly property var _akkuAnzeige: ({
            vorhanden: Geraet.akkuVorhanden,
            prozent: Geraet.akku.prozent,
            laedt: Geraet.akku.laedt,
            zustand: Geraet.akku.zustand
        })
    // Gilt das Ausschalten gerade? «akku» nur sicher im Akkubetrieb (unbekannter Akku gilt als Netzteil)
    readonly property bool ausschaltenAktiv: EnergieLogik.ausschaltenAktiv(ausschaltenArt, Geraet.akku)
    // «Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min. · Aus nach 65 Min. im Akkubetrieb»
    readonly property string zeitleisteText: EnergieLogik.zeitleisteText({
        sperreNachMinuten: Einstellungen.sperreNachMinuten,
        bildschirmAusNachSperre: Einstellungen.bildschirmAusNachSperre,
        ausschalten: Einstellungen.ausschalten,
        ausschaltenNachMinuten: Einstellungen.ausschaltenNachMinuten
    }, _akkuAnzeige)

    // Vorwarnung { phase: aus | laeuft | warten | abgelehnt, seit, um, grund, takte } aus energie.js
    readonly property bool vorwarnungLaeuft: _vorwarnung.phase === "laeuft"
    // Uhrzeit des Ausschaltens (ms seit 1970) während der Vorwarnung, sonst 0
    readonly property real ausschaltenUm: vorwarnungLaeuft ? _vorwarnung.um : 0
    // Warum zenOS gerade nicht ausschalten kann (neuer Versuch in 5 Min.), sonst leer
    readonly property string blockiertGrund: _vorwarnung.phase === "warten" ? _vorwarnung.grund : ""
    // Gesperrt, und das Ausschalten gilt: Dann zählt die Zeit bis zur Vorwarnung
    readonly property bool ausschaltenZaehlt: Oberflaeche.gesperrt && ausschaltenAktiv

    // zenos-bildschirm hat den Bildschirm aus- bzw. eingeschaltet ("aus" | "an")
    signal bildschirmGeschaltet(string was)
    // Die Vorwarnung ist sichtbar bzw. vorbei (grund: eingabe, entsperrt, netzteil, blockiert, probe …)
    signal vorwarnungGestartet
    signal vorwarnungBeendet(string grund)

    // Sofort sperren und den Bildschirm ausschalten
    function aus(): void {
        if (ausProzess.running)
            return;
        ausProzess.gestartet = false;
        ausProzess.running = true;
    }

    // was: "aus" | "an"
    function bildschirm(was: string): void {
        if (was !== "aus" && was !== "an")
            return;
        // Läuft genau dieser Wunsch schon, genügt das (z. B. zwei Monitore wecken zugleich)
        root._wunsch = bildschirmProzess.running && bildschirmProzess.was === was ? "" : was;
        root._naechster();
    }

    // --- intern ---

    readonly property string _zen: Pfade.code + "/scripts/zen"
    readonly property string _helfer: Pfade.bin + "/zenos-energie"
    readonly property string _markerPfad: Pfade.laufzeit + "/vorwarnung"
    // Nächster Aufruf von zenos-bildschirm ("aus", "an" oder "": keiner)
    property string _wunsch: ""
    property var _vorwarnung: EnergieLogik.vorwarnung()
    // Die laufende Vorwarnung ist eine Probe (IPC): Sie schaltet nie aus und legt keinen Marker an
    property bool _probe: false
    // zenos-energie ausschalten hat angenommen, das System fährt herunter: nichts mehr tun
    property bool _faehrtHerunter: false
    // Nummer der gültigen Prüfung: Eine Eingabe oder ein Abbruch dazwischen macht eine laufende Antwort ungültig
    property int _pruefNummer: 0

    function _naechster(): void {
        if (bildschirmProzess.running || root._wunsch === "")
            return;
        bildschirmProzess.was = root._wunsch;
        bildschirmProzess.gestartet = false;
        root._wunsch = "";
        bildschirmProzess.running = true;
    }

    // Leitplanke: trotz Idle-Hemmer spätestens jetzt sperren. Über zen lock (mit Notfall-Sperre, falls die
    // Oberfläche nicht sperren kann), mit Argumentliste.
    function _sperrenTrotzHemmer(): void {
        console.info("Energie:", root.sperreTrotzHemmerMinuten, "Min. ohne Eingabe, sperre trotz Idle-Hemmer (Leitplanke)");
        root._sperren();
    }

    function _sperren(): void {
        Quickshell.execDetached({
            command: [root._zen, "lock"],
            workingDirectory: Pfade.home
        });
    }

    // Deckel: "zuklappen" | "aufklappen" | "sperren" (aus Geraet, Logik in geraet.js)
    function _deckel(aktion: string): void {
        if (aktion === "zuklappen") {
            console.info("Energie: Deckel zu, sperre und schalte den Bildschirm aus");
            deckelWecken.stop();
            // zen energie aus sperrt immer zuerst (dunkel heisst gesperrt), eine Eingabe weckt wieder
            root.aus();
        } else if (aktion === "sperren") {
            console.info("Energie: Deckel zu und wieder offen (verpasst), sperre");
            root._sperren();
        } else if (aktion === "aufklappen") {
            console.info("Energie: Deckel offen, Bildschirm an");
            root.bildschirm("an");
            // Gesperrt und ohne Eingabe: nach «Bildschirm aus nach der Sperre» wieder dunkel
            if (Oberflaeche.gesperrt)
                deckelWecken.restart();
        }
    }

    // Die Zeit gesperrt ohne Eingabe ist um (oder ein neuer Versuch ist fällig): erst fragen, dann vorwarnen
    function _pruefen(): void {
        if (!root.ausschaltenZaehlt || !ausschaltMonitor.isIdle || pruefProzess.running || ausschaltProzess.running)
            return;
        // Nach einer Ablehnung durch logind erst nach der nächsten Eingabe wieder
        if (!EnergieLogik.vorwarnungPruefbar(root._vorwarnung))
            return;
        root._pruefNummer += 1;
        pruefProzess.nummer = root._pruefNummer;
        pruefProzess.code = -1;
        pruefProzess.command = [root._helfer, "darf-ausschalten"];
        pruefProzess.running = true;
    }

    function _geprueft(nummer: int, code: int, text: string): void {
        // Inzwischen Eingabe, entsperrt oder Netzteil: nichts mehr tun. Hat der Helfer schon «ja» gesagt, liegt sein
        // Marker da: weg damit (ohne Vorwarnung gilt er ohnehin nicht).
        if (nummer !== root._pruefNummer || !root.ausschaltenZaehlt || !ausschaltMonitor.isIdle) {
            if (code === 0 && !markerLoeschen.running)
                markerLoeschen.running = true;
            return;
        }
        if (code === 0)
            root._vorwarnen();
        else
            root._blockiert(root._grundAus(text, code));
    }

    // Den Marker (ohne ihn schaltet der Helfer nie aus) hat «zenos-energie darf-ausschalten» eben angelegt
    function _vorwarnen(): void {
        root._probe = false;
        root._vorwarnung = EnergieLogik.vorwarnungStarten(EnergieLogik.vorwarnung(), Date.now());
        console.info("Energie: Vorwarnung, schalte um", Qt.formatDateTime(new Date(root._vorwarnung.um), "HH:mm"), "aus");
        root.vorwarnungGestartet();
        root.bildschirm("an");
    }

    // Jede Sekunde während der Vorwarnung (ein Takt), alle 5 s beim Warten nach einer Blockade
    function _schritt(): void {
        if (root._faehrtHerunter)
            return;
        root._vorwarnung = EnergieLogik.vorwarnungTakt(root._vorwarnung);
        const schritt = EnergieLogik.vorwarnungSchritt(root._vorwarnung, Date.now());
        if (schritt === "ausschalten") {
            if (root._probe) {
                root._abbrechen("probe");
                return;
            }
            if (!root.ausschaltenZaehlt || ausschaltProzess.running)
                return;
            root._pruefNummer += 1;
            ausschaltProzess.nummer = root._pruefNummer;
            ausschaltProzess.code = -1;
            ausschaltProzess.command = [root._helfer, "ausschalten"];
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
            console.info("Energie: schalte aus");
            return;
        }
        // Nach der Laufzeit noch keine 60 s (der Takt war etwas schneller): Die Vorwarnung bleibt, im nächsten Takt erneut
        if (code === 4)
            return;
        // Inzwischen abgebrochen: nichts mehr tun (der Helfer hat den Marker gelöscht oder verbraucht)
        if (nummer !== root._pruefNummer || root._vorwarnung.phase !== "laeuft")
            return;
        const grund = root._grundAus(text, code);
        root.vorwarnungBeendet("blockiert");
        if (code === 3) {
            // logind hat abgelehnt: bis zur nächsten Eingabe keine neue Vorwarnung (sonst die ganze Nacht alle 5 Min.)
            console.warn("Energie: Ausschalten abgelehnt:", grund, "· erst nach der nächsten Eingabe wieder");
            root._vorwarnung = EnergieLogik.vorwarnungAbgelehnt(root._vorwarnung, Date.now(), grund);
        } else {
            root._blockiert(grund);
        }
        // Gesperrt und ohne Eingabe: wieder dunkel (die Vorwarnung hatte den Bildschirm eingeschaltet)
        if (Oberflaeche.gesperrt)
            root.bildschirm("aus");
    }

    function _blockiert(grund: string): void {
        console.info("Energie: Ausschalten blockiert:", grund, "· neuer Versuch in 5 Min.");
        root._vorwarnung = EnergieLogik.vorwarnungBlockiert(root._vorwarnung, Date.now(), grund);
    }

    // «nein: SSH-Sitzung offen» → «SSH-Sitzung offen»
    function _grundAus(text: string, code: int): string {
        const zeile = text.trim().split("\n").pop() ?? "";
        const grund = zeile.replace(/^nein:\s*/, "").trim();
        return grund.length > 0 ? grund : "zenos-energie endete mit " + code;
    }

    // Vorwarnung oder Warten beenden (Eingabe, entsperrt, Netzteil, Einstellung …). Eine laufende Prüfung gilt dann
    // nicht mehr. War die Vorwarnung sichtbar und ist noch gesperrt (ohne Eingabe), wird es wieder dunkel.
    function _abbrechen(grund: string): void {
        root._pruefNummer += 1;
        const war = root._vorwarnung.phase;
        if (war !== "laeuft" && war !== "warten" && war !== "abgelehnt")
            return;
        const g = grund !== "" ? grund : Oberflaeche.gesperrt ? "bedingung" : "entsperrt";
        const probe = root._probe;
        root._probe = false;
        root._vorwarnung = EnergieLogik.vorwarnungAbbrechen(root._vorwarnung, g);
        if (!probe && !markerLoeschen.running)
            markerLoeschen.running = true;
        console.info("Energie: Vorwarnung beendet:", g);
        if (war !== "laeuft")
            return;
        root.vorwarnungBeendet(g);
        if (g !== "eingabe" && g !== "entsperrt" && Oberflaeche.gesperrt)
            root.bildschirm("aus");
    }

    // IPC-Probe: Vorwarnung zeigen wie echt (Bildschirm an, Zeile auf der Sperre), aber nie ausschalten
    function _probeStarten(): string {
        if (!Oberflaeche.gesperrt)
            return "nicht gesperrt";
        if (root._vorwarnung.phase === "laeuft")
            return "läuft schon";
        root._pruefNummer += 1;
        root._probe = true;
        root._vorwarnung = EnergieLogik.vorwarnungStarten(EnergieLogik.vorwarnung(), Date.now());
        root.vorwarnungGestartet();
        root.bildschirm("an");
        return "Probe: Vorwarnung bis " + Qt.formatDateTime(new Date(root._vorwarnung.um), "HH:mm") + ", schaltet nicht aus";
    }

    // Netzteil oder Einstellung «nie»: Vorwarnung und Warten enden (die Probe nur beim Entsperren)
    onAusschaltenZaehltChanged: {
        if (!root.ausschaltenZaehlt && !root._probe)
            root._abbrechen("");
    }

    Connections {
        target: Oberflaeche

        function onGesperrtChanged(): void {
            if (!Oberflaeche.gesperrt) {
                root._abbrechen("entsperrt");
                deckelWecken.stop();
            }
        }
    }

    Connections {
        target: Geraet

        function onDeckelGeklappt(aktion: string): void {
            root._deckel(aktion);
        }
    }

    // Nach dem Aufklappen: Kommt keine Eingabe, geht der Bildschirm nach «Bildschirm aus nach der Sperre» wieder aus.
    // Die Leerlauf-Zähler von swayidle und der Sperre laufen dann nicht neu an (es gab keine Eingabe).
    Timer {
        id: deckelWecken

        interval: root.bildschirmMinuten * 60000
        onTriggered: {
            if (Oberflaeche.gesperrt && !Geraet.deckelZu)
                root.bildschirm("aus");
        }
    }

    // Jede Eingabe nach dem Aufklappen beendet deckelWecken (scharf nach 1 s Ruhe, wie das Wecken in der Sperre)
    IdleMonitor {
        enabled: deckelWecken.running
        respectInhibitors: false
        timeout: 1
        onIsIdleChanged: {
            if (!isIdle)
                deckelWecken.stop();
        }
    }

    Process {
        id: ausProzess

        property bool gestartet: false

        command: [root._zen, "energie", "aus"]
        workingDirectory: Pfade.home
        stderr: StdioCollector {
            id: ausFehler
        }

        onStarted: gestartet = true
        onExited: (code, status) => {
            if (code !== 0 || status !== 0)
                console.warn("Energie: zen energie aus endete mit", code, ausFehler.text.trim());
        }
        onRunningChanged: {
            if (!running && !gestartet)
                console.warn("Energie: zen liess sich nicht starten:", root._zen);
        }
    }

    Process {
        id: bildschirmProzess

        property string was: ""
        property bool gestartet: false

        command: [Pfade.bin + "/zenos-bildschirm", bildschirmProzess.was]
        workingDirectory: Pfade.home
        stderr: StdioCollector {
            id: bildschirmFehler
        }

        onStarted: gestartet = true
        onExited: (code, status) => {
            if (code === 0 && status === 0)
                root.bildschirmGeschaltet(bildschirmProzess.was);
            else
                console.warn("Energie: zenos-bildschirm", bildschirmProzess.was, "endete mit", code, bildschirmFehler.text.trim());
        }
        onRunningChanged: {
            if (running)
                return;
            if (!gestartet)
                console.warn("Energie: zenos-bildschirm liess sich nicht starten");
            Qt.callLater(root._naechster);
        }
    }

    // zenos-energie darf-ausschalten (Ausgabe «ja» oder «nein: Grund»)
    Process {
        id: pruefProzess

        property int nummer: 0
        property int code: -1

        workingDirectory: Pfade.home
        stdout: StdioCollector {
            id: pruefAusgabe
        }
        onExited: (code, status) => pruefProzess.code = status === 0 ? code : -1
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => root._geprueft(pruefProzess.nummer, pruefProzess.code, pruefAusgabe.text));
        }
    }

    // zenos-energie ausschalten (prüft alles erneut; Exit 0: das System fährt herunter)
    Process {
        id: ausschaltProzess

        property int nummer: 0
        property int code: -1

        workingDirectory: Pfade.home
        stdout: StdioCollector {
            id: ausschaltAusgabe
        }
        onExited: (code, status) => ausschaltProzess.code = status === 0 ? code : -1
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => root._ausgeschaltet(ausschaltProzess.nummer, ausschaltProzess.code, ausschaltAusgabe.text));
        }
    }

    // Marker der Vorwarnung löschen (Abbruch): Danach schaltet der Helfer nicht mehr aus, auch wenn er schon prüft
    Process {
        id: markerLoeschen

        command: ["rm", "-f", "--", root._markerPfad]
    }

    // Takt der Vorwarnung (1 s, ohne sichtbare Sekunden) und des Wartens nach einer Blockade (5 s)
    Timer {
        interval: root.vorwarnungLaeuft ? 1000 : 5000
        repeat: true
        running: root._vorwarnung.phase === "laeuft" || root._vorwarnung.phase === "warten"
        onTriggered: root._schritt()
    }

    // Höchstdauer trotz Idle-Hemmer (Leitplanke): zählt ohne Rücksicht auf Hemmer, nur ungesperrt
    IdleMonitor {
        enabled: !Oberflaeche.gesperrt
        respectInhibitors: false
        timeout: root.sperreTrotzHemmerMinuten * 60
        onIsIdleChanged: {
            if (isIdle && !Oberflaeche.gesperrt)
                root._sperrenTrotzHemmer();
        }
    }

    // Während der Vorwarnung (auch der Probe) bricht jede Eingabe ab: scharf nach 1 s Ruhe
    IdleMonitor {
        enabled: root.vorwarnungLaeuft
        respectInhibitors: false
        timeout: 1
        onIsIdleChanged: {
            if (!isIdle && root.vorwarnungLaeuft)
                root._abbrechen("eingabe");
        }
    }

    // Ausschalten nach langer Sperre: zählt ab der Sperre (bzw. der letzten Eingabe), ohne Rücksicht auf Hemmer
    IdleMonitor {
        id: ausschaltMonitor

        enabled: root.ausschaltenZaehlt
        respectInhibitors: false
        timeout: root.ausschaltenMinuten * 60
        onIsIdleChanged: {
            if (isIdle)
                root._pruefen();
            else
                root._abbrechen(root.ausschaltenZaehlt ? "eingabe" : "");
        }
    }

    // Nach einem automatischen Aus: einmal eine ruhige Mitteilung in der nächsten Sitzung. Kurz warten, bis der
    // Mitteilungsdienst bereit ist.
    Timer {
        interval: 5000
        running: Konfig.verfuegbar
        onTriggered: meldungProzess.running = true
    }

    Process {
        id: meldungProzess

        command: [root._helfer, "meldung"]
        workingDirectory: Pfade.home
        stdout: StdioCollector {
            onStreamFinished: {
                const zeilen = text.trim().split("\n").map(z => z.trim()).filter(z => z.length > 0);
                if (zeilen.length !== 2)
                    return;
                console.info("Energie:", zeilen[0], "·", zeilen[1]);
                Quickshell.execDetached(["notify-send", "--app-name=zenOS", "--icon=zenos", "--urgency=normal", "--category=system", "--", zeilen[0], zeilen[1]]);
            }
        }
    }

    IpcHandler {
        target: "energie"

        // Sperren und Bildschirm aus (wie Super+Shift+L)
        function aus(): void {
            root.aus();
        }

        // Wirksame Zeitleiste, z. B. «Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min.»
        function status(): string {
            return root.zeitleisteText;
        }

        // Probe der Vorwarnung (nur gesperrt): sichtbar wie echt, schaltet nie aus, eine Eingabe bricht ab
        function vorwarnung(): string {
            return root._probeStarten();
        }
    }
}
