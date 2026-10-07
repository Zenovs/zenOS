pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "basis.js" as Logik
import "kanal.js" as KanalLogik

// Basis-Updates in der Oberfläche (Pakete der Ubuntu-Basis über zenos-basis): Abschnitt «Ubuntu-Basis» in
// Einstellungen › System › Updates, der stille Hinweis «Neustart nötig» in Leiste und System-Menü und die
// Mitteilungen. Die Logik steht in basis.js und ist dort getestet.
//
// - Gelesen wird ohne Rechte, was root schreibt: /var/lib/zenos/basis/stand.json (letzte Prüfung), letzte.json (letzte
//   Installation) und automatik.json (letzter Lauf der Automatik), der gemeinsame Notschalter
//   /etc/xdg/zenos/kanal-automatik-aus und /run/reboot-required(.pkgs). Die Dateien unter /var/lib bei jeder
//   Änderung (watchChanges), alles zusammen im Takt des Kanals: solange die Einstellungen oder ein Menü der Leiste
//   offen sind oder etwas läuft alle 3 s, sonst jede Minute. «Update läuft» kommt vom Übernahme-Marker
//   /run/zenos-basis/uebernahme, den Kanal.qml schon liest (eine Quelle für System-Menü, Einstellungen und Nachladen).
// - Bedient wird über pkexec mit dem Helfer zenos-kanal-bedienen (Argumentliste, keine Shell; polkit-Aktionen in
//   system/polkit/org.zenos.kanal.policy): basis-pruefen und basis-installieren LISTE ohne Passwort, nur in der aktiven
//   Sitzung am Gerät; basis-installieren-zustimmen LISTE (Kernel, Firmware, Bootloader, Entfernungen) jedes Mal mit
//   Passwort. LISTE ist der Hash der angezeigten Liste: installiert wird genau dieser Stand, ohne neues apt-get update.
//   Die Arbeit macht zenos-basis-installieren.service: Lädt die Oberfläche währenddessen neu, endet nur der Helfer.
// - Mitteilungen (notify-send, Absender zenOS), jede nur einmal, gemerkt in ~/.local/state/zenos/basis-meldungen.json:
//   installiert (still), kaputt (dringend), gescheitert und «Basis-Updates warten auf dich» (die Automatik sah Kernel,
//   Firmware, Bootloader oder Entfernungen). Zu «Neustart nötig» keine Mitteilung, nur der Hinweis in der Leiste.
// - Leitplanke (basis.js neustartHinweis): Der Hinweis erscheint nur bei voller Leiste, nie während der Bildschirm
//   geteilt wird, nie gesperrt.
Singleton {
    id: root

    // Fester Pfad wie in Kanal.qml: Die polkit-Aktionen gelten genau für dieses Programm
    readonly property string helfer: "/opt/zenos/scripts/bin/zenos-kanal-bedienen"
    readonly property string standPfad: "/var/lib/zenos/basis/stand.json"
    readonly property string letztePfad: "/var/lib/zenos/basis/letzte.json"
    readonly property string automatikPfad: "/var/lib/zenos/basis/automatik.json"
    readonly property string notschalterPfad: "/etc/xdg/zenos/kanal-automatik-aus"
    readonly property string neustartPfad: "/run/reboot-required"
    readonly property string neustartPaketePfad: "/run/reboot-required.pkgs"
    readonly property string gemeldetPfad: Pfade.zustand + "/basis-meldungen.json"

    // Lage (basis.js: standLesen, letzteLesen, automatikLesen); stand null: noch nie geprüft
    readonly property var stand: _stand
    readonly property var letzte: _letzte
    readonly property var automatik: _automatik
    readonly property bool veraltet: Logik.veraltet(_stand, _letzte)
    // Ergebnis der Prüfung (aktuell, bereit, zustimmung, gesperrt, fehler) oder «ungeprueft»
    readonly property string zustand: _stand ? _stand.ergebnis : "ungeprueft"
    // Ein Basis-Update läuft (apt, danach install.sh; Block-Inhibitor)
    readonly property bool updateLaeuft: Kanal.basisLaeuft
    readonly property string zustandTitel: Logik.zustandTitel(_stand, veraltet, _letzte, updateLaeuft)
    readonly property var zustandSymbol: Logik.zustandSymbol(_stand, veraltet, _letzte, updateLaeuft)
    readonly property string grundText: Logik.grundText(_stand, veraltet, _letzte, updateLaeuft, {
        zeitpunkt: Kanal.zeitpunkt,
        automatikAn: automatikAn
    })
    // [{ titel, wert }] für die Einstellungen (neu nur, wenn sich etwas geändert hat)
    readonly property var zeilen: _zeilen
    // Liste für «Jetzt installieren» bzw. «Mit Passwort installieren», sonst leer
    readonly property string installierenListe: Logik.installierenListe(_stand, veraltet)
    readonly property string zustimmungListe: Logik.zustimmungListe(_stand, veraltet)
    readonly property string knopfHinweis: Logik.knopfHinweis(_stand, veraltet)
    // Gemeinsamer Notschalter von Kanal und Basis (sudo zen kanal automatik aus)
    readonly property bool automatikAn: !_notschalter
    // Was für jeden Zeitpunkt gilt (unter «Automatisch installieren»)
    readonly property string automatikImmer: Logik.AUTOMATIK_IMMER
    // /run/reboot-required: { noetig, pakete }
    readonly property bool neustartNoetig: _neustart.noetig
    readonly property var neustartPakete: _neustart.pakete
    // Hinweis «Neustart nötig» in Leiste und System-Menü (Leitplanke in basis.js: volle Leiste, keine Freigabe, nicht
    // gesperrt)
    readonly property bool neustartHinweis: Logik.neustartHinweis(_neustart.noetig, Freigabe.aktiv, Zustaende.wirksam?.leiste ?? "normal", Oberflaeche.gesperrt)
    // Laufende Bedienung: "", "pruefen", "installieren", "zustimmen"
    readonly property string laeuft: _laeuft

    function aktualisieren(): void {
        standDatei.reload();
        letzteDatei.reload();
        automatikDatei.reload();
        notschalterDatei.reload();
        neustartDatei.reload();
        neustartPaketeDatei.reload();
    }

    function pruefen(): bool {
        return _starten("pruefen", Logik.befehl(helfer, "pruefen"));
    }

    // Nur für die Liste, die die Einstellungen gerade zeigen
    function installieren(liste: string): void {
        if (liste !== "" && liste === installierenListe)
            _starten("installieren", Logik.befehl(helfer, "installieren", liste));
    }

    function zustimmen(liste: string): void {
        if (liste !== "" && liste === zustimmungListe)
            _starten("zustimmen", Logik.befehl(helfer, "zustimmen", liste));
    }

    // --- intern ---

    property var _stand: null
    property var _letzte: null
    property var _automatik: null
    property bool _notschalter: false
    property bool _neustartDa: false
    property string _neustartText: ""
    property var _neustart: Logik.neustartLesen(false, "")
    property string _laeuft: ""
    property string _fertigAktion: ""
    property string _gemeldetText: ""
    property real _beginn: 0
    property int _code: -1
    property real _jetzt: Date.now()
    property var _zeilen: []
    property var _gemeldet: null

    function _zeilenNeu(): void {
        const z = Logik.zeilen(_stand, _letzte, _neustart, {
            automatik: _automatik,
            automatikAn: automatikAn,
            jetztMs: _jetzt
        });
        if (JSON.stringify(z) !== JSON.stringify(_zeilen))
            _zeilen = z;
    }

    function _neustartNeu(): void {
        const n = Logik.neustartLesen(_neustartDa, _neustartText);
        if (JSON.stringify(n) !== JSON.stringify(_neustart))
            _neustart = n;
        _zeilenNeu();
    }

    // Eine Bedienung zur Zeit, auch nicht neben einer des Kanals (root hält ohnehin dieselbe Sperre: Exit 75)
    function _starten(aktion: string, argv: var): bool {
        if (_laeuft !== "" || Kanal.laeuft !== "" || Oberflaeche.gesperrt || argv === null)
            return false;
        _laeuft = aktion;
        _code = -1;
        _beginn = Date.now();
        prozess.command = argv;
        prozess.running = true;
        return true;
    }

    function _fertig(): void {
        if (_laeuft === "")
            return;
        _fertigAktion = _laeuft;
        _laeuft = "";
        aktualisieren();
        rueckmeldung.restart();
    }

    function _rueckmelden(): void {
        const aktion = _fertigAktion;
        const zeilen = fehlerText.text.trim().split("\n");
        const neu = _letzte !== null && isFinite(_letzte.endeMs) && _letzte.endeMs >= _beginn - 2000;
        const lage = KanalLogik.installationLage(Kanal.stand, Kanal.letzte, Kanal.veraltet);
        const antwort = Logik.rueckmeldung(aktion, _code, {
            fehler: zeilen[zeilen.length - 1] ?? "",
            installiert: neu,
            stand: _stand,
            kanalProblem: lage === "kaputt" || lage === "unterbrochen"
        });
        // 3 abgelehnt oder gesperrt, 10 wartet, 75 läuft schon und 126 abgebrochen sind Zustände, keine Fehler
        if ([0, 3, 10, 75, 126].indexOf(_code) < 0)
            console.warn("Basis:", aktion, "endete mit Exit", _code, zeilen[zeilen.length - 1] ?? "");
        // Toast nur nach eigenem Klick (dieser Aufruf); Ergebnisse einer Installation kommen als Mitteilung
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
        } else if (art === "automatik") {
            const a = Logik.automatikLesen(t);
            if (JSON.stringify(a) !== JSON.stringify(_automatik))
                _automatik = a;
        }
        _zeilenNeu();
        _auswertenBald();
    }

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
            automatik: _automatik,
            veraltet: veraltet
        }, _gemeldet, Date.now());
        const text = Logik.gemeldetText(ergebnis.gemeldet);
        if (text !== Logik.gemeldetText(_gemeldet)) {
            _gemeldet = ergebnis.gemeldet;
            gemeldetDatei.setText(text);
        }
        for (const m of ergebnis.neu) {
            console.info("Basis: Mitteilung", m.schluessel, "·", m.titel);
            Quickshell.execDetached(KanalLogik.mitteilungBefehl(m));
        }
    }

    // Nach einem Basis-Update gleich neu lesen (letzte.json, stand.json, /run/reboot-required)
    onUpdateLaeuftChanged: {
        aktualisieren();
        _auswertenBald();
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
        id: automatikDatei

        path: root.automatikPfad
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._uebernehmen("automatik", text())
        onLoadFailed: root._uebernehmen("automatik", "")
    }

    // Nur, ob es ihn gibt (der Inhalt ist ein Kommentar)
    FileView {
        id: notschalterDatei

        path: root.notschalterPfad
        blockLoading: true
        printErrors: false
        onLoaded: {
            root._notschalter = true;
            root._zeilenNeu();
        }
        onLoadFailed: {
            root._notschalter = false;
            root._zeilenNeu();
        }
    }

    // Direkt unter /run: kein watchChanges (die Datei kommt und geht), nur der Takt
    FileView {
        id: neustartDatei

        path: root.neustartPfad
        blockLoading: true
        printErrors: false
        onLoaded: {
            root._neustartDa = true;
            root._neustartNeu();
        }
        onLoadFailed: {
            root._neustartDa = false;
            root._neustartNeu();
        }
    }

    FileView {
        id: neustartPaketeDatei

        path: root.neustartPaketePfad
        blockLoading: true
        printErrors: false
        onLoaded: {
            root._neustartText = text();
            root._neustartNeu();
        }
        onLoadFailed: {
            root._neustartText = "";
            root._neustartNeu();
        }
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
        onSaveFailed: error => console.warn("Basis: basis-meldungen.json nicht geschrieben:", FileViewError.toString(error))
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

    // Takt wie beim Kanal: offene Einstellungen, Menüs der Leiste oder eine laufende Bedienung alle 3 s, sonst jede
    // Minute («heute» und «gestern», /run/reboot-required nach unattended-upgrades)
    Timer {
        interval: Oberflaeche.einstellungenOffen || Oberflaeche.leisteMenueBildschirm !== "" || root._laeuft !== "" || root.updateLaeuft ? 3000 : 60000
        repeat: true
        running: true
        onTriggered: {
            root._jetzt = Date.now();
            root.aktualisieren();
            root._zeilenNeu();
            root._auswertenBald();
        }
    }

    IpcHandler {
        target: "basis"

        // Jeweils der zuletzt eingelesene Stand (ein Aufruf liest neu ein, das Ergebnis zählt erst für den nächsten)

        // Ergebnis der letzten Prüfung (aktuell, bereit, zustimmung, gesperrt, fehler) oder «ungeprueft»
        function status(): string {
            root.aktualisieren();
            return root.zustand;
        }

        // «ja», wenn /run/reboot-required besteht
        function neustart(): string {
            root.aktualisieren();
            return root.neustartNoetig ? "ja" : "nein";
        }

        // «ja», wenn Leiste und System-Menü «Neustart nötig» zeigen (nicht bei Freigabe, reduzierter Leiste, Sperre)
        function hinweis(): string {
            return root.neustartHinweis ? "ja" : "nein";
        }

        // Wie «Jetzt prüfen» in den Einstellungen (pkexec, apt-get update über die Unit): «gestartet», sonst «nicht
        // jetzt» (gesperrt oder eine Bedienung läuft schon)
        function pruefen(): string {
            return root.pruefen() ? "gestartet" : "nicht jetzt";
        }
    }
}
