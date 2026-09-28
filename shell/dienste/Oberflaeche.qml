pragma Singleton

import QtQuick
import Quickshell

// Gemeinsamer Zustand der Oberfläche: was gerade offen ist.
Singleton {
    id: root

    property bool befehlsfeldOffen: false
    property bool zentraleOffen: false
    // Name des Bildschirms (ShellScreen.name), auf dem die Zentrale erscheint; leer = erster Bildschirm
    property string zentraleBildschirm: ""
    property bool einstellungenOffen: false
    // Seite der Einstellungen, z. B. "modi", "zustand", "allgemein"; leer = Startseite
    property string einstellungenSeite: ""
    property bool einrichtungOffen: false
    property bool modusWahlOffen: false
    property bool zustandWahlOffen: false
    // Wo die Modus-/Zustand-Wahl aufklappt: { bildschirm: ShellScreen.name, x: Fensterkoordinate } oder null
    // (null = Standardort). Die Leiste setzt es beim Klick auf einen Chip.
    property var wahlAnker: null
    // Name des Bildschirms, auf dem ein Menü der Leiste (System, Raster) offen ist; leer = keins.
    // Setzt nur die Leiste. Die Mitteilungskarten treten dort zurück, solange es offen ist.
    property string leisteMenueBildschirm: ""
    // true von Beginn der Sperre bis zum Entsperren; setzt nur sperre/Sperre.qml
    property bool gesperrt: false

    // Kurzer Hinweis (Toast), z. B. «Farbe kopiert». symbol: Name aus qs.komponenten/Symbol
    // (z. B. "warnung", "info"); leer = Standard (Haken).
    signal hinweisGezeigt(string text, string symbol)
    // Sperren anfordern (sperren()); die Sperre (sperre/Sperre.qml) reagiert darauf. Sie sendet es auch selbst
    // bei jedem Sperren (IPC, zen lock, Marker), Overlays und Menüs schliessen darauf.
    signal sperrenAngefordert

    // symbol ist optional: hinweis("Farbe kopiert"), hinweis("Raster lässt sich nicht setzen", "warnung")
    function hinweis(text: var, symbol: var): void {
        const t = typeof text === "string" ? text.trim() : "";
        const s = typeof symbol === "string" ? symbol.trim() : "";
        if (t.length > 0)
            hinweisGezeigt(t, s);
    }

    function sperren(): void {
        sperrenAngefordert();
    }

    function einstellungenOeffnen(seite: var): void {
        einstellungenSeite = typeof seite === "string" ? seite : "";
        einstellungenOffen = true;
    }
}
