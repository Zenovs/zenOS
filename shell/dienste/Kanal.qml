pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "kanal.js" as Logik

// Update-Kanal in der Oberfläche: Lage für Einstellungen › System › Updates, Mitteilungen und «Update läuft» im
// System-Menü. Die Logik steht in kanal.js und ist dort getestet.
//
// - Gelesen wird ohne Rechte, was root schreibt: /var/lib/zenos/kanal/stand.json (letzte Prüfung) und letzte.json
//   (letzte Installation), /etc/xdg/zenos/kanal-zeitpunkt (Zeitpunkt automatischer Updates) und
//   /run/zenos-kanal/uebernahme (gibt es nur, solange install.sh aus dem Kanal läuft, mit Block-Inhibitor:
//   Ausschalten und Neustart warten dann). Bei jeder Änderung (watchChanges), solange die Einstellungen oder ein Menü
//   der Leiste offen sind alle 3 s, sonst jede Minute.
// - Bedient wird über pkexec mit dem Helfer zenos-kanal-bedienen (Argumentliste, keine Shell; polkit-Aktionen in
//   system/polkit/org.zenos.kanal.policy): prüfen, jetzt installieren und den Zeitpunkt setzen ohne Passwort, nur in
//   der aktiven Sitzung am Gerät; zustimmen jedes Mal mit Passwort, nur für das gezeigte Tag-Objekt. Die Arbeit machen
//   Units: Lädt die Oberfläche währenddessen neu, endet nur der Helfer, die Installation läuft zu Ende.
// - Mitteilungen (notify-send, Absender zenOS), jede nur einmal je Zustand, gemerkt in
//   ~/.local/state/zenos/kanal-meldungen.json (über Neustarts): installiert (still), zurück, gescheitert, kaputt
//   und blockiert (dringend), Anker fehlt, abgelehnt, wartet auf Zustimmung, 14 Tage ohne Kontakt und beim Zeitpunkt
//   «hand» «Update bereit». Die Sperre zeigt davon nichts.
Singleton {
    id: root

    // Fester Pfad: Die polkit-Aktionen gelten genau für dieses Programm (pkexec vergleicht den echten Pfad).
    // Ein Arbeits-Checkout (ZENOS_CODE) zählt hier bewusst nicht.
    readonly property string helfer: "/opt/zenos/scripts/bin/zenos-kanal-bedienen"
    readonly property string standPfad: "/var/lib/zenos/kanal/stand.json"
    readonly property string letztePfad: "/var/lib/zenos/kanal/letzte.json"
    readonly property string zeitpunktPfad: "/etc/xdg/zenos/kanal-zeitpunkt"
    readonly property string uebernahmePfad: "/run/zenos-kanal/uebernahme"
    readonly property string gemeldetPfad: Pfade.zustand + "/kanal-meldungen.json"

    // Lage (kanal.js: standLesen, letzteLesen, zeitpunktLesen); stand null: noch nie geprüft
    readonly property var stand: _stand
    readonly property var letzte: _letzte
    readonly property var zeitpunkt: _zeitpunkt
    // Seit der letzten Prüfung wurde installiert: Die Angaben sind überholt, bis neu geprüft ist
    readonly property bool veraltet: Logik.veraltet(_stand, _letzte)
    // Zustand der Prüfung (aktuell, bereit, zustimmung, dev, anker_fehlt, blockiert, kein_kontakt, fehler) oder
    // «ungeprueft»
    readonly property string zustand: _stand ? _stand.zustand : "ungeprueft"
    readonly property string zustandTitel: Logik.zustandTitel(_stand, veraltet)
    readonly property var zustandSymbol: Logik.zustandSymbol(_stand, veraltet)
    readonly property string grundText: Logik.grundText(_stand, veraltet, _letzte)
    // [{ titel, wert }] für die Einstellungen
    readonly property var zeilen: Logik.zeilen(_stand, _zeitpunkt, _jetzt)
    readonly property bool kannInstallieren: !veraltet && Logik.kannInstallieren(_stand)
    // Tag-Objekt, dem «Zustimmen …» gilt, sonst leer
    readonly property string zustimmungObjekt: veraltet ? "" : Logik.zustimmungObjekt(_stand)
    readonly property string zustimmungText: veraltet ? "" : Logik.zustimmungText(_stand)
    readonly property string zeitpunktText: Logik.zeitpunktText(_zeitpunkt)
    // install.sh aus dem Kanal läuft (Block-Inhibitor): System-Menü «Update läuft»
    readonly property bool updateLaeuft: _uebernahme
    // Laufende Bedienung: "", "pruefen", "installieren", "zustimmen", "zeitpunkt"
    readonly property string laeuft: _laeuft
    // Während «zeitpunkt» läuft: die gewählte Art (die Segmente zeigen sie schon)
    readonly property string zeitpunktZiel: _laeuft === "zeitpunkt" ? _zielArt : ""

    function aktualisieren(): void {
        standDatei.reload();
        letzteDatei.reload();
        zeitpunktDatei.reload();
        uebernahmeDatei.reload();
    }

    function pruefen(): void {
        _starten("pruefen", Logik.befehl(helfer, "pruefen"));
    }

    function installieren(): void {
        if (kannInstallieren)
            _starten("installieren", Logik.befehl(helfer, "installieren"));
    }

    // Nur für das Objekt, das die Einstellungen gerade zeigen
    function zustimmen(objekt: string): void {
        if (objekt !== "" && objekt === zustimmungObjekt)
            _starten("zustimmen", Logik.befehl(helfer, "zustimmen", objekt));
    }

    // art: sperre | fenster | jederzeit | hand; von und bis (HH:MM) nur bei «fenster»
    function zeitpunktSetzen(art: string, von: string, bis: string): void {
        const argv = art === "fenster" ? Logik.befehl(helfer, "zeitpunkt", art, von, bis) : Logik.befehl(helfer, "zeitpunkt", art);
        if (argv === null)
            return;
        if (_zeitpunkt.art === art && (art !== "fenster" || (_zeitpunkt.von === von && _zeitpunkt.bis === bis)))
            return;
        _zielArt = art;
        _starten("zeitpunkt", argv);
    }

    // Grund, warum ein Zeitfenster nicht gilt (mindestens eine Stunde, HH:MM), sonst leer
    function fensterProblem(von: string, bis: string): string {
        return Logik.fensterProblem(von, bis);
    }

    // Erklärung zu einem Zeitpunkt (auch einem, der gerade erst gesetzt wird)
    function zeitpunktErklaerung(art: string, von: string, bis: string): string {
        return Logik.zeitpunktText({
            art: art,
            von: von,
            bis: bis
        });
    }

    // --- intern ---

    property var _stand: null
    property var _letzte: null
    property var _zeitpunkt: Logik.zeitpunktLesen(null)
    property bool _uebernahme: false
    property string _laeuft: ""
    property string _zielArt: ""
    property string _fertigAktion: ""
    // Inhalt von kanal-meldungen.json beim Start
    property string _gemeldetText: ""
    property real _beginn: 0
    property int _code: -1
    property real _jetzt: Date.now()
    // Gemerkte Mitteilungen; geladen erst nach dem Start (der Mitteilungsdienst braucht einen Moment)
    property var _gemeldet: null

    function _starten(aktion: string, argv: var): void {
        if (_laeuft !== "" || Oberflaeche.gesperrt || argv === null)
            return;
        _laeuft = aktion;
        _code = -1;
        _beginn = Date.now();
        prozess.command = argv;
        prozess.running = true;
    }

    function _fertig(): void {
        if (_laeuft === "")
            return;
        _fertigAktion = _laeuft;
        _laeuft = "";
        _zielArt = "";
        // FileView liest auch mit blockLoading erst nach diesem Aufruf neu ein: Die Rückmeldung kommt danach
        aktualisieren();
        rueckmeldung.restart();
    }

    function _rueckmelden(): void {
        const aktion = _fertigAktion;
        const zeilen = fehlerText.text.trim().split("\n");
        const neu = _letzte !== null && isFinite(_letzte.endeMs) && _letzte.endeMs >= _beginn - 2000;
        const antwort = Logik.rueckmeldung(aktion, _code, {
            fehler: zeilen.join("\n"),
            installiert: neu,
            zustand: root.zustand
        });
        // 3 abgelehnt, 10 wartet, 75 läuft schon und 126 abgebrochen sind Zustände, keine Fehler
        if ([0, 3, 10, 75, 126].indexOf(_code) < 0)
            console.warn("Kanal:", aktion, "endete mit Exit", _code, zeilen[zeilen.length - 1] ?? "");
        if (antwort !== null)
            Oberflaeche.hinweis(antwort.text, antwort.art);
        _auswertenBald();
    }

    // t: Inhalt der Datei (leer, wenn sie fehlt oder unlesbar ist)
    function _uebernehmen(art: string, t: string): void {
        if (art === "stand") {
            const s = Logik.standLesen(t);
            if (JSON.stringify(s) !== JSON.stringify(_stand))
                _stand = s;
        } else if (art === "letzte") {
            const l = Logik.letzteLesen(t);
            if (JSON.stringify(l) !== JSON.stringify(_letzte))
                _letzte = l;
        } else if (art === "zeitpunkt") {
            const z = Logik.zeitpunktLesen(t);
            if (JSON.stringify(z) !== JSON.stringify(_zeitpunkt))
                _zeitpunkt = z;
        }
        _auswertenBald();
    }

    // Erst auswerten, wenn alles eingelesen ist: Nach einer Installation kommen letzte.json und stand.json kurz
    // nacheinander
    function _auswertenBald(): void {
        if (_gemeldet !== null)
            auswerten.restart();
    }

    function _melden(): void {
        // Nur in der Sitzung (im Greeter gibt es keinen Mitteilungsdienst und keine Konfiguration)
        if (_gemeldet === null || !Konfig.verfuegbar)
            return;
        const ergebnis = Logik.meldungen({
            stand: _stand,
            letzte: _letzte,
            zeitpunkt: _zeitpunkt,
            veraltet: veraltet
        }, _gemeldet, Date.now());
        const text = Logik.gemeldetText(ergebnis.gemeldet);
        if (text !== Logik.gemeldetText(_gemeldet)) {
            _gemeldet = ergebnis.gemeldet;
            gemeldetDatei.setText(text);
        }
        for (const m of ergebnis.neu) {
            console.info("Kanal: Mitteilung", m.schluessel, "·", m.titel);
            Quickshell.execDetached(Logik.mitteilungBefehl(m));
        }
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
        id: standDatei

        path: root.standPfad
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._uebernehmen("stand", text())
        onLoadFailed: root._uebernehmen("stand", "")
    }

    FileView {
        id: letzteDatei

        path: root.letztePfad
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._uebernehmen("letzte", text())
        onLoadFailed: root._uebernehmen("letzte", "")
    }

    FileView {
        id: zeitpunktDatei

        path: root.zeitpunktPfad
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._uebernehmen("zeitpunkt", text())
        onLoadFailed: root._uebernehmen("zeitpunkt", "")
    }

    // Der Ordner /run/zenos-kanal besteht nur während einer Installation: kein watchChanges, nur der Takt
    FileView {
        id: uebernahmeDatei

        path: root.uebernahmePfad
        blockLoading: true
        printErrors: false
        onLoaded: root._uebernahme = true
        onLoadFailed: root._uebernahme = false
    }

    // Gelesen wird nur beim Start (der Timer danach übernimmt den Inhalt), dann nur geschrieben
    FileView {
        id: gemeldetDatei

        path: root.gemeldetPfad
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoaded: if (root._gemeldet === null) root._gemeldetText = text()
        onSaveFailed: error => console.warn("Kanal: kanal-meldungen.json nicht geschrieben:", FileViewError.toString(error))
    }

    Timer {
        id: rueckmeldung

        interval: 400
        onTriggered: root._rueckmelden()
    }

    Timer {
        id: auswerten

        interval: 2000
        onTriggered: root._melden()
    }

    // Nach dem Start kurz warten, bis der Mitteilungsdienst bereit ist; dann die gemerkten Mitteilungen lesen
    Timer {
        interval: 5000
        running: true
        onTriggered: {
            root._gemeldet = Logik.gemeldetLesen(root._gemeldetText);
            root._melden();
        }
    }

    // Offene Einstellungen oder Menüs der Leiste: alle 3 s neu lesen (der Ordner der Übernahme lässt sich nicht
    // beobachten), sonst jede Minute (14 Tage ohne Kontakt, «heute» und «gestern»)
    Timer {
        interval: Oberflaeche.einstellungenOffen || Oberflaeche.leisteMenueBildschirm !== "" || root._laeuft !== "" ? 3000 : 60000
        repeat: true
        running: true
        onTriggered: {
            root._jetzt = Date.now();
            root.aktualisieren();
            root._auswertenBald();
        }
    }

    IpcHandler {
        target: "kanal"

        // Jeweils der zuletzt eingelesene Stand (die Dateien werden beobachtet bzw. alle 3 s bis 60 s gelesen; ein
        // Aufruf liest neu ein, das Ergebnis zählt erst für den nächsten).

        // Zustand der letzten Prüfung (aktuell, bereit, zustimmung, dev, anker_fehlt, blockiert, kein_kontakt,
        // fehler) oder «ungeprueft»
        function status(): string {
            root.aktualisieren();
            return root.zustand;
        }

        // «sperre», «jederzeit», «hand» oder «fenster 02:00-05:00»
        function zeitpunkt(): string {
            root.aktualisieren();
            const z = root.zeitpunkt;
            return z.art === "fenster" ? "fenster " + z.von + "-" + z.bis : z.art;
        }

        // «ja», solange install.sh aus dem Kanal läuft
        function laeuft(): string {
            root.aktualisieren();
            return root.updateLaeuft ? "ja" : "nein";
        }
    }
}
