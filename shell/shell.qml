//@ pragma IconTheme Adwaita

import QtQuick
import Quickshell
import qs.dienste
// Die Oberflächen-Ordner werden importiert, damit Quickshell sie kennt (eigene Module,
// Live-Reload). Geladen werden die Dateien einzeln über LazyLoader mit source: Ein Fehler
// in einer Datei reisst so die anderen nicht mit.
// qmllint disable unused-imports
import qs.theme as ThemeModul
import qs.komponenten as KomponentenModul
import qs.sperre as SperreModul
import qs.leiste as LeisteModul
import qs.heute as HeuteModul
import qs.befehlsfeld as BefehlsfeldModul
import qs.mitteilungen as MitteilungenModul
import qs.freigabe as FreigabeModul
import qs.modi as ModiModul
import qs.einstellungen as EinstellungenModul
import qs.einrichtung as EinrichtungModul
// qmllint enable unused-imports

// Einstieg der zenOS-Sitzung.
ShellRoot {
    id: root

    // Die Sperre zuerst und synchron
    LazyLoader {
        source: "sperre/Sperre.qml"
        active: true
    }

    LazyLoader {
        source: "leiste/Leiste.qml"
        loading: true
    }

    LazyLoader {
        source: "heute/Heute.qml"
        loading: true
    }

    LazyLoader {
        source: "befehlsfeld/Befehlsfeld.qml"
        loading: true
    }

    LazyLoader {
        source: "mitteilungen/Mitteilungen.qml"
        loading: true
    }

    LazyLoader {
        source: "freigabe/Freigabe.qml"
        loading: true
    }

    LazyLoader {
        source: "modi/Umschalter.qml"
        loading: true
    }

    LazyLoader {
        source: "einstellungen/Einstellungen.qml"
        loading: true
    }

    LazyLoader {
        source: "einrichtung/Einrichtung.qml"
        loading: true
    }

    LazyLoader {
        source: "komponenten/Hinweise.qml"
        loading: true
    }

    LazyLoader {
        source: "theme/ThemaIpc.qml"
        loading: true
    }

    // Dienste, die unabhängig von einer Oberfläche von Anfang an laufen müssen
    // (Übertragung des Erscheinungsbilds, Mitteilungsdienst, Auslöser, IPC).
    Component.onCompleted: {
        const dienste = [() => Erscheinung.dunkel, () => Mitteilungen.anzahlWartend, () => Modi.aktivId, () => Zustaende.aktivId, () => Freigabe.aktiv, () => Raster.aktivId];
        for (const starten of dienste) {
            try {
                starten();
            } catch (e) {
                console.error("zenOS: Dienst konnte nicht starten:", e);
            }
        }
    }

    // Ruhe: kein Hinweis nach erfolgreichem Neuladen (Fehler zeigt Quickshell weiterhin an)
    Connections {
        target: Quickshell

        function onReloadCompleted(): void {
            Quickshell.inhibitReloadPopup();
        }
    }
}
