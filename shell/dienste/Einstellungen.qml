pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

// Benutzer-Einstellungen aus ~/.config/zenos/einstellungen.json.
// Fehlt die Datei, gelten die Standardwerte und eingerichtet ist false.
// Änderungen an der Datei werden live übernommen; speichern() schreibt sie
// und behält dabei Schlüssel, die dieser Dienst nicht kennt.
//
// Ungültige Datei (kein JSON-Objekt, z. B. nach einem Tippfehler von Hand, oder nicht lesbar): fehlerhaft
// ist true, ein Hinweis nennt zen doctor. Im Betrieb bleiben die bisherigen Werte. Beim Start gelten die
// Standardwerte, eingerichtet aber ist true: Die Einrichtung soll eine vorhandene Datei weder überdecken
// noch ersetzen. Das nächste speichern() sichert die ungültige Datei zuerst nach einstellungen.json.kaputt
// (gibt es die schon, mit Zeitstempel) und schreibt dann; eine nicht lesbare Datei bleibt unangetastet.
//
// scrollTempo ist der Wert für labwc (<scrollFactor>, erzeugt von zenos-labwc). scrollTempoWirksam folgt nicht
// der Eingabe, sondern dem, was in der Datei steht (gelesen oder gespeichert), geprüft wie in zenos-labwc. Ändert
// es sich, ruft der Dienst Raster zenos-labwc auf; so liest zenos-labwc nie einen älteren Stand als gemeint.
Singleton {
    id: root

    readonly property string pfad: Pfade.konfig + "/einstellungen.json"

    property alias eingerichtet: json.eingerichtet
    property alias name: json.name
    property alias ort: json.ort
    // "hell" | "dunkel" | "tageszeit"
    property alias erscheinungsbild: json.erscheinungsbild
    property alias tagAb: json.tagAb
    property alias nachtAb: json.nachtAb
    property alias sperreNachMinuten: json.sperreNachMinuten
    property alias mitteilungenStandard: json.mitteilungenStandard
    // Faktor für Touchpad und Mausrad, wie er in der Datei steht (Zahl, ungeprüft)
    property alias scrollTempo: json.scrollTempo

    // Grenzen wie config/schema/einstellungen.schema.json und zenos-labwc (der Einheitentest gleicht sie ab)
    readonly property real scrollTempoStandard: 1.0
    readonly property real scrollTempoMin: 0.25
    readonly property real scrollTempoMax: 3
    // Scroll-Tempo, das labwc nach zenos-labwc nutzt: aus der Datei; fehlt es oder ist es ungültig, 1.0.
    // Bei einer ungültigen Datei bleibt der bisherige Wert (wie in zenos-labwc).
    readonly property real scrollTempoWirksam: _scrollTempoDatei

    // true, sobald die Datei einmal gelesen (oder als fehlend erkannt) wurde
    property bool geladen: false
    // true, wenn die Datei existiert
    property bool vorhanden: false
    // true, wenn die Datei existiert, aber kein gültiges JSON-Objekt enthält oder nicht lesbar ist
    readonly property bool fehlerhaft: _fehlerhaft

    property bool _fehlerhaft: false
    property bool _unlesbar: false
    // Die Werte stammen aus der Datei (sie war seit dem Start einmal gültig)
    property bool _ausDatei: false
    // Zuletzt gelesener gültiger Inhalt: Ersetzt speichern() eine ungültige Datei, bleiben dessen
    // unbekannte Schlüssel erhalten
    property var _zuletztGueltig: null
    property real _scrollTempoDatei: 1.0

    readonly property var _defaults: ({
            eingerichtet: false,
            name: "",
            ort: "",
            erscheinungsbild: "hell",
            tagAb: "07:00",
            nachtAb: "19:00",
            sperreNachMinuten: 5,
            mitteilungenStandard: "gebuendelt-60",
            scrollTempo: 1.0
        })

    // Gültiges Scroll-Tempo oder der Standard, wie zenos-labwc: Zahl von scrollTempoMin bis scrollTempoMax,
    // auf zwei Nachkommastellen gerundet (so zeigt die Seite denselben Wert, den labwc bekommt)
    function scrollTempoPruefen(wert: var): real {
        if (typeof wert !== "number" || !isFinite(wert) || wert < scrollTempoMin || wert > scrollTempoMax)
            return scrollTempoStandard;
        return Math.round(wert * 100) / 100;
    }

    function speichern(): void {
        let content = {};
        if (root._fehlerhaft) {
            if (root._unlesbar) {
                console.warn("Einstellungen: Datei nicht lesbar, nicht gespeichert");
                Oberflaeche.hinweis("einstellungen.json ist nicht lesbar · nicht gespeichert", "warnung");
                return;
            }
            if (file.text().trim().length > 0) {
                const kopie = root._sichern();
                if (kopie.length === 0) {
                    console.warn("Einstellungen: ungültige Datei liess sich nicht sichern, nicht gespeichert");
                    Oberflaeche.hinweis("einstellungen.json ist ungültig · nicht gespeichert", "warnung");
                    return;
                }
                console.info("Einstellungen: ungültige Datei gesichert als", kopie);
                Oberflaeche.hinweis("einstellungen.json war ungültig · " + (kopie === "einstellungen.json.kaputt" ? "Kopie: " + kopie : "Kopie in ~/.config/zenos"), "warnung");
            }
            root._fehlerhaft = false;
            content = Object.assign({}, root._zuletztGueltig);
        } else if (root.vorhanden) {
            // Wird die Datei gerade ersetzt, ist noch die gesicherte ungültige Fassung geladen
            content = root._objekt(file.text()) ?? Object.assign({}, root._zuletztGueltig);
        }
        for (const key of Object.keys(root._defaults))
            content[key] = json[key];
        file.setText(JSON.stringify(content, null, 2) + "\n");
    }

    function _resetToDefaults(): void {
        for (const key of Object.keys(root._defaults)) {
            if (json[key] !== root._defaults[key])
                json[key] = root._defaults[key];
        }
    }

    // Inhalt als Objekt, null wenn er kein JSON-Objekt ist
    function _objekt(text: string): var {
        try {
            const daten = JSON.parse(text);
            if (daten && typeof daten === "object" && !Array.isArray(daten))
                return daten;
        } catch (e) {}
        return null;
    }

    function _alsUngueltig(unlesbar: bool): void {
        // Beim Start: keine Einrichtung über einer vorhandenen Datei (siehe oben)
        if (!root._ausDatei && !json.eingerichtet)
            json.eingerichtet = true;
        const neu = !root._fehlerhaft;
        root._fehlerhaft = true;
        root._unlesbar = unlesbar;
        root.vorhanden = true;
        if (neu)
            meldung.restart();
    }

    // Kopie der ungültigen Datei neben ihr: einstellungen.json.kaputt, gibt es die schon, mit Zeitstempel
    // (wie .vor-zenos im Installer). Liest und schreibt synchron, Bytes unverändert.
    // Gibt den Dateinamen zurück, leer bei einem Fehler.
    function _sichern(): string {
        const daten = file.data();
        let name = "einstellungen.json.kaputt";
        const kopie = sicherung.createObject(root, {
            path: Pfade.konfig + "/" + name
        }) as Sicherung;
        if (!kopie)
            return "";
        try {
            const alt = kopie.text();
            if (kopie.loaded) {
                // Dieselbe Kopie liegt schon da
                if (alt === file.text())
                    return name;
                name += "." + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
                kopie.path = Pfade.konfig + "/" + name;
            }
            kopie.setData(daten);
            return kopie.fehlgeschlagen ? "" : name;
        } finally {
            kopie.destroy();
        }
    }

    JsonAdapter {
        id: json

        property bool eingerichtet: false
        property string name: ""
        property string ort: ""
        property string erscheinungsbild: "hell"
        property string tagAb: "07:00"
        property string nachtAb: "19:00"
        property int sperreNachMinuten: 5
        property string mitteilungenStandard: "gebuendelt-60"
        // var: Ein ungültiger Wert von Hand (z. B. Text) bleibt beim Speichern so stehen, statt NaN zu werden
        property var scrollTempo: 1.0
    }

    FileView {
        id: file

        path: root.pfad
        adapter: json
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true

        onFileChanged: reload()
        onLoaded: {
            // Der JsonAdapter übergeht ungültigen Inhalt nur mit einer Warnung und behält die Werte
            const daten = root._objekt(file.text());
            if (daten === null) {
                root._alsUngueltig(false);
            } else {
                root._zuletztGueltig = daten;
                // Schlüssel von Hand entfernt: Der JsonAdapter behielte den alten Wert, die Seite zeigte ihn, und das
                // nächste speichern() schriebe ihn zurück. Wie zenos-labwc gilt dann der Standard.
                if (!("scrollTempo" in daten) && json.scrollTempo !== root.scrollTempoStandard)
                    json.scrollTempo = root.scrollTempoStandard;
                root._scrollTempoDatei = root.scrollTempoPruefen(daten.scrollTempo);
                root._ausDatei = true;
                root._fehlerhaft = false;
                root._unlesbar = false;
                meldung.stop();
            }
            root.vorhanden = true;
            root.geladen = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                // Datei wurde im Betrieb gelöscht: zurück auf die Standardwerte
                if (root.vorhanden)
                    root._resetToDefaults();
                root.vorhanden = false;
                root._zuletztGueltig = null;
                root._scrollTempoDatei = root.scrollTempoStandard;
                root._fehlerhaft = false;
                root._unlesbar = false;
                meldung.stop();
            } else {
                console.warn("Einstellungen: Datei nicht lesbar:", FileViewError.toString(error));
                root._alsUngueltig(true);
            }
            root.geladen = true;
        }
        onSaved: {
            // Eigenes Schreiben meldet kein onLoaded: Stand der Datei hier übernehmen
            const daten = root._objekt(file.text());
            if (daten !== null)
                root._scrollTempoDatei = root.scrollTempoPruefen(daten.scrollTempo);
            // Ordner und Datei sind neu entstanden: Beobachtung neu aufsetzen
            if (!root.vorhanden) {
                root.vorhanden = true;
                reload();
            }
        }
        onSaveFailed: error => console.warn("Einstellungen: Speichern fehlgeschlagen:", FileViewError.toString(error))
    }

    // Sicherung einer ungültigen Datei (siehe _sichern), je Aufruf neu: setData vergliche sonst mit einem alten Stand
    component Sicherung: FileView {
        property bool fehlgeschlagen: false

        preload: false
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: fehlgeschlagen = true
    }

    Component {
        id: sicherung

        Sicherung {}
    }

    // Ungültige Datei melden: nicht bei jedem Zwischenstand, den ein Editor beim Schreiben hinterlässt, und
    // beim Start erst, wenn die Hinweise bereitstehen
    Timer {
        id: meldung

        interval: 2000
        onTriggered: {
            if (!root._fehlerhaft)
                return;
            const folge = root._unlesbar ? "nicht lesbar" : "ungültig";
            const werte = root._ausDatei ? "bisherige Werte bleiben" : "es gelten Standardwerte";
            Oberflaeche.hinweis("einstellungen.json ist " + folge + " · " + werte + " · zen doctor", "warnung");
        }
    }

    // Fehlt der Ordner, kann die Datei nicht beobachtet werden: dann selten nachsehen.
    Timer {
        interval: 5000
        repeat: true
        running: root.geladen && !root.vorhanden
        onTriggered: file.reload()
    }

    // Synchron laden, damit das erste Bild schon stimmt (z. B. dunkel)
    Component.onCompleted: file.text()
}
