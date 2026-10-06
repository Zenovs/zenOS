pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "../appleiste/fenster.mjs" as Fenster
import "../uebersicht/schreibtisch.mjs" as Logik

// Schreibtisch zeigen (Super+H, Befehlsfeld, IPC): umschalten() minimiert alle sichtbaren App-Fenster auf allen
// Bildschirmen, auch Vollbild-Fenster, und merkt sie sich. Ein zweites umschalten() holt genau diese zurück, solange
// der Schreibtisch frei ist; Fenster, die vorher schon von Hand minimiert waren, bleiben unten. Die Fenster der
// Oberfläche (z. B. die Einstellungen) bleiben stehen, ebenso Leiste, Heute und App-Leiste (Layer, keine Fenster).
// «frei» folgt nur aus der Lage der Fenster (schreibtisch.mjs): Holst du ein Fenster anders zurück (App-Leiste,
// Alt+Tab, Übersicht) oder erscheint ein neues, ist es vorbei, der Merker verfällt, und das nächste umschalten()
// minimiert wieder alles Sichtbare (wie ToggleShowDesktop ab labwc 0.20, das es unter 0.9.3 noch nicht gibt).
// Den Stapel gibt labwc nicht heraus; die Reihenfolge nähert ihn über den Verlauf der aktiven Fenster an.
// Kein Hinweis, keine Animation (labwc minimiert ohne Übergang). Nie während Sperre und Einrichtung.
// IPC «schreibtisch»: umschalten, status (frei/normal)
Singleton {
    id: root

    // Schon beim Start gebunden (shell.qml): ToplevelManager füllt sich erst nach dem ersten Zugriff, und der Verlauf
    // der aktiven Fenster gilt ab Sitzungsbeginn
    readonly property var fensterListe: ToplevelManager.toplevels.values
    readonly property var aktivesFenster: ToplevelManager.activeToplevel

    // Beim Zeigen minimierte Fenster, von unten nach oben (das zuletzt aktive als letztes)
    property var merker: []
    // Vor dem Zeigen aktives Fenster, auch eines der Oberfläche; null ohne
    property var vorherAktiv: null
    // Gemerkte Fenster sind minimiert, und kein App-Fenster ist sichtbar. Eine Aktivierung allein ändert nichts:
    // labwc aktiviert beim Minimieren kurz das jeweils nächste Fenster.
    readonly property bool frei: Logik.frei(fensterListe, merker)

    // Verlauf der aktiven Fenster (zuletzt aktiv zuerst), ohne Fenster der Oberfläche
    property var _verlauf: []

    onAktivesFensterChanged: _verlauf = Fenster.verlaufNachfuehren(_verlauf, aktivesFenster, fensterListe)
    onFensterListeChanged: _verlauf = Fenster.verlaufNachfuehren(_verlauf, aktivesFenster, fensterListe)
    // Vorbei (ein Fenster ist wieder sichtbar, oder alle gemerkten sind zu): Der Merker verfällt. Erst nach dem
    // laufenden Ereignis, denn frei hängt am Merker (sonst eine Bindungsschleife). Ein inzwischen neuer Merker bleibt.
    onFreiChanged: {
        if (!frei)
            Qt.callLater(root._verfallen, merker);
    }

    function _verfallen(alt: var): void {
        if (frei || merker !== alt)
            return;
        if (merker.length > 0)
            merker = [];
        vorherAktiv = null;
    }

    function umschalten(): void {
        if (Oberflaeche.gesperrt || Oberflaeche.einrichtungOffen)
            return;
        const liste = fensterListe;
        const was = Logik.entscheiden(liste, merker);
        if (was === "nichts")
            return;
        Oberflaeche.uebersichtSchliessen();
        if (was === "zeigen") {
            // Von unten nach oben, das aktive zuletzt: labwc aktiviert so zwischendurch kein anderes Fenster
            const neu = Logik.merken(liste, Fenster.verlaufNachfuehren(_verlauf, aktivesFenster, liste));
            vorherAktiv = aktivesFenster ?? null;
            merker = neu;
            for (const t of neu)
                t.minimized = true;
            return;
        }
        // Zurück: labwc hebt und aktiviert jedes Fenster, das nicht mehr minimiert ist. Das zuletzt aktive kommt
        // als letztes und liegt oben; danach das vorher aktive holen (z. B. die Einstellungen).
        // activate() wirkt erst, wenn die Oberfläche schon eine Eingabe bekommen hat (Quickshell braucht dafür ein
        // Eingabegerät); Fenster der Apps holt labwc ohnehin nach vorn.
        const zurueck = Logik.zurueckReihenfolge(merker, liste);
        const ziel = vorherAktiv;
        merker = [];
        vorherAktiv = null;
        for (const t of zurueck)
            t.minimized = false;
        if (ziel && Fenster.alsListe(liste).indexOf(ziel) >= 0)
            ziel.activate();
    }

    IpcHandler {
        target: "schreibtisch"

        function umschalten(): void {
            root.umschalten();
        }

        function status(): string {
            return root.frei ? "frei" : "normal";
        }
    }
}
