//@ pragma IconTheme Adwaita
// Quickshell selbst braucht weder das Qt-Plattform-Theme noch die Portal-Dienste von Qt (Farben aus Theme,
// Symbole über IconTheme). Ohne sie wartet der Start nicht auf das Desktop-Portal, und dessen Warnungen
// entfallen. Nur für diesen Prozess: gestartete Apps erben die Umgebung der Sitzung unverändert.
//@ pragma Env QT_QPA_PLATFORMTHEME=
//@ pragma Env QT_NO_XDG_DESKTOP_PORTAL=1

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
import qs.polkit as PolkitModul
import qs.appleiste as AppleisteModul
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
        source: "appleiste/AppLeiste.qml"
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

    // polkit-Agent der Sitzung (Passwortdialog, z. B. für «Firewall ausschalten»)
    LazyLoader {
        source: "polkit/Polkit.qml"
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
    // (Übertragung des Erscheinungsbilds, Mitteilungsdienst, Auslöser, IPC, Höchstdauer der Sperre trotz Video).
    Component.onCompleted: {
        const dienste = [() => Erscheinung.dunkel, () => Mitteilungen.anzahlWartend, () => Modi.aktivId, () => Zustaende.aktivId, () => Freigabe.aktiv, () => Raster.aktivId, () => Energie.sperreTrotzHemmerMinuten];
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
