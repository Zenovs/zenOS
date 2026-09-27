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

    // true, sobald die Datei einmal gelesen (oder als fehlend erkannt) wurde
    property bool geladen: false
    // true, wenn die Datei existiert
    property bool vorhanden: false

    readonly property var _defaults: ({
            eingerichtet: false,
            name: "",
            ort: "",
            erscheinungsbild: "hell",
            tagAb: "07:00",
            nachtAb: "19:00",
            sperreNachMinuten: 5,
            mitteilungenStandard: "gebuendelt-60"
        })

    function speichern(): void {
        let content = {};
        const previous = root.vorhanden ? file.text() : "";
        if (previous) {
            try {
                const old = JSON.parse(previous);
                if (old && typeof old === "object" && !Array.isArray(old))
                    content = old;
            } catch (e) {
                console.warn("Einstellungen: bisherige Datei ist kein gültiges JSON und wird ersetzt");
            }
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
            root.vorhanden = true;
            root.geladen = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                // Datei wurde im Betrieb gelöscht: zurück auf die Standardwerte
                if (root.vorhanden)
                    root._resetToDefaults();
                root.vorhanden = false;
            } else {
                console.warn("Einstellungen: Datei nicht lesbar:", FileViewError.toString(error));
            }
            root.geladen = true;
        }
        onSaved: {
            // Ordner und Datei sind neu entstanden: Beobachtung neu aufsetzen
            if (!root.vorhanden) {
                root.vorhanden = true;
                reload();
            }
        }
        onSaveFailed: error => console.warn("Einstellungen: Speichern fehlgeschlagen:", FileViewError.toString(error))
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
