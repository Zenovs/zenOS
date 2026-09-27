pragma Singleton

import QtQuick
import Quickshell

// Gemeinsamer Zustand der Oberfläche: was gerade offen ist.
Singleton {
    id: root

    property bool befehlsfeldOffen: false
    property bool zentraleOffen: false
    property bool einstellungenOffen: false
    // Seite der Einstellungen, z. B. "modi", "zustand", "allgemein"; leer = Startseite
    property string einstellungenSeite: ""
    property bool einrichtungOffen: false
    property bool modusWahlOffen: false
    property bool zustandWahlOffen: false

    // Kurzer Hinweis (Toast), z. B. «Farbe kopiert»
    signal hinweisGezeigt(string text)
    // Die Sperre (sperre/Sperre.qml) reagiert darauf
    signal sperrenAngefordert

    function hinweis(text: var): void {
        const t = typeof text === "string" ? text.trim() : "";
        if (t.length > 0)
            hinweisGezeigt(t);
    }

    function sperren(): void {
        sperrenAngefordert();
    }

    function einstellungenOeffnen(seite: var): void {
        einstellungenSeite = typeof seite === "string" ? seite : "";
        einstellungenOffen = true;
    }
}
