pragma Singleton

import QtQuick
import Quickshell

// Gemeinsamer Zustand der Oberfläche: was gerade offen ist.
Singleton {
    id: root

    property bool befehlsfeldOffen: false
    // Ansicht des Befehlsfelds: "" = Suche (Super+Leertaste), "apps" = Übersicht der installierten Apps
    // (Klick auf das Zeichen in der Leiste). Bleibt beim Schliessen stehen, damit beim Ausblenden nichts
    // springt; jedes Öffnen setzt sie neu (befehlsfeldApps() bzw. das Befehlsfeld selbst).
    property string befehlsfeldAnsicht: ""
    // Klickfläche des Zeichens in der Leiste in Bildschirmkoordinaten (die Leiste liegt oben über die ganze
    // Breite); leer, solange das Zeichen fehlt (Leiste «aus»). Setzt nur die Leiste. Das Befehlsfeld nimmt
    // sie als Ursprung fürs Aufgleiten und als Klickfläche über seiner Abdunklung.
    property rect zeichenBereich: Qt.rect(0, 0, 0, 0)
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
    // Fensterübersicht (Super+Tab). Nur über uebersichtOeffnen(), uebersichtSchliessen() und uebersichtUmschalten()
    // setzen. Es ist immer nur eine Fläche offen: Öffnet die Übersicht, weichen Befehlsfeld, Modus- und Zustand-Wahl
    // und Zentrale; öffnet eine von ihnen, ein Menü der Leiste oder die Einstellungen, schliesst die Übersicht. Sperre
    // und Einrichtung schliessen sie ebenfalls.
    property bool uebersichtOffen: false

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

    // Befehlsfeld in der Apps-Ansicht öffnen (Klick auf das Zeichen, IPC befehlsfeld apps). Ist es in der
    // Suche offen, wechselt es in die Apps-Ansicht. umschalten: ist die Apps-Ansicht schon offen, schliessen.
    // Während der Sperre und der Einrichtung öffnet sich nichts (wie beim Befehlsfeld selbst).
    function befehlsfeldApps(umschalten: bool): void {
        if (gesperrt || einrichtungOffen)
            return;
        if (umschalten && befehlsfeldOffen && befehlsfeldAnsicht === "apps") {
            befehlsfeldOffen = false;
            return;
        }
        // Zuerst die Ansicht, dann öffnen: Das Befehlsfeld richtet sich beim Öffnen nach ihr
        befehlsfeldAnsicht = "apps";
        befehlsfeldOffen = true;
    }

    function einstellungenOeffnen(seite: var): void {
        einstellungenSeite = typeof seite === "string" ? seite : "";
        einstellungenOffen = true;
    }

    // Fensterübersicht öffnen (Super+Tab, Drei-Finger-Wischen, Befehlsfeld, IPC). Während der Sperre und der
    // Einrichtung öffnet sie nicht (wie befehlsfeldApps()).
    function uebersichtOeffnen(): void {
        if (gesperrt || einrichtungOffen)
            return;
        befehlsfeldOffen = false;
        modusWahlOffen = false;
        zustandWahlOffen = false;
        zentraleOffen = false;
        uebersichtOffen = true;
    }

    function uebersichtSchliessen(): void {
        uebersichtOffen = false;
    }

    function uebersichtUmschalten(): void {
        if (uebersichtOffen)
            uebersichtSchliessen();
        else
            uebersichtOeffnen();
    }

    // Eine Fläche zur Zeit: Andere Flächen, Sperre und Einrichtung schliessen die Übersicht
    onBefehlsfeldOffenChanged: {
        if (befehlsfeldOffen)
            uebersichtSchliessen();
    }
    onZentraleOffenChanged: {
        if (zentraleOffen)
            uebersichtSchliessen();
    }
    onModusWahlOffenChanged: {
        if (modusWahlOffen)
            uebersichtSchliessen();
    }
    onZustandWahlOffenChanged: {
        if (zustandWahlOffen)
            uebersichtSchliessen();
    }
    onLeisteMenueBildschirmChanged: {
        if (leisteMenueBildschirm !== "")
            uebersichtSchliessen();
    }
    onEinstellungenOffenChanged: {
        if (einstellungenOffen)
            uebersichtSchliessen();
    }
    onEinrichtungOffenChanged: {
        if (einrichtungOffen)
            uebersichtSchliessen();
    }
    onGesperrtChanged: {
        if (gesperrt)
            uebersichtSchliessen();
    }
    onSperrenAngefordert: uebersichtSchliessen()
}
