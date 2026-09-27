pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.dienste
import qs.komponenten

// System-Menü unter dem System-Knopf der Leiste: Netz (nur Anzeige – zenOS hat kein eigenes
// WLAN-Menü), Lautstärke mit Regler und Stumm, 1Password, Temperatur und Lüfter,
// dann Sperren, Einstellungen, Abmelden, Neustart und Ausschalten.
Menuekarte {
    id: root

    breite: 300

    // Anzeigezeile ohne Bedienung: Symbol, Titel, rechts ein Wert in Mono
    component Statuszeile: Item {
        id: zeile

        property string symbol
        property string titel
        property string wert
        property bool gedaempft: false

        width: parent ? parent.width : 0
        height: 36

        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 15
                height: 15

                Symbol {
                    visible: zeile.symbol !== ""
                    anchors.fill: parent
                    name: zeile.symbol
                    groesse: 15
                    farbe: zeile.gedaempft ? Theme.gedaempft : Theme.text2
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: zeile.titel
                color: Theme.text
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: zeile.wert
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }
    }

    component Abschnitt: Item {
        width: parent ? parent.width : 0
        height: Theme.a2 + 1

        Trenner {
            y: Theme.a1
            width: parent.width
        }
    }

    // --- Netz ---

    // Symbole wie in der Leiste
    Statuszeile {
        symbol: System.netzArt === "kabel" ? "kabel" : System.netzArt === "wlan" || System.wlanVerbunden ? "wlan" : "wlan-aus"
        gedaempft: !System.netzVerbunden
        titel: System.netzArt === "kabel" ? "Kabel" : System.netzArt === "wlan" || System.wlanVerbunden ? "WLAN" : "Netzwerk"
        wert: {
            if (!System.netzVerbunden)
                return System.wlanVerbunden ? "WLAN ohne Internet" : "nicht verbunden";
            if (System.netzArt === "wlan" && System.wlanSignal >= 0)
                return "verbunden · " + System.wlanSignal + " %";
            return "verbunden";
        }
    }

    // --- Ton ---

    MenueEintrag {
        width: parent.width
        enabled: System.tonVerfuegbar
        symbol: System.tonVerfuegbar && !System.stumm ? "ton" : "ton-aus"
        text: "Lautstärke"
        wert: !System.tonVerfuegbar ? "kein Ausgang" : System.stumm ? "stumm" : Math.round(System.lautstaerke * 100) + " %"
        Accessible.name: System.stumm ? "Ton einschalten" : "Stumm schalten"
        onAusgeloest: System.stummUmschalten()
    }

    Item {
        visible: System.tonVerfuegbar
        width: parent.width
        height: 28

        Regler {
            x: 35 - 7
            width: parent.width - x - 10 + 7
            anchors.verticalCenter: parent.verticalCenter
            wert: System.lautstaerke
            leise: System.stumm
            beschreibung: "Lautstärke"
            onVerschoben: wert => System.lautstaerkeSetzen(wert)
        }
    }

    // --- 1Password, Temperatur ---

    Statuszeile {
        symbol: "schloss"
        gedaempft: !System.einsPasswortLaeuft
        titel: "1Password"
        wert: System.einsPasswortLaeuft ? "läuft" : System.einsPasswortInstalliert ? "nicht gestartet" : "nicht installiert"
    }

    Statuszeile {
        visible: System.temperatur >= 0 || System.luefter >= 0
        symbol: "thermometer"
        titel: "Temperatur"
        wert: {
            const parts = [];
            if (System.temperatur >= 0)
                parts.push(System.temperatur + " °C");
            if (System.luefter >= 0)
                parts.push("Lüfter " + System.luefter + " %");
            return parts.join(" · ");
        }
    }

    Abschnitt {}

    MenueEintrag {
        width: parent.width
        symbol: "schloss"
        text: "Sperren"
        onAusgeloest: {
            root.schliessen();
            Aktionen.sperren();
        }
    }

    MenueEintrag {
        width: parent.width
        symbol: "zahnrad"
        text: "Einstellungen"
        onAusgeloest: {
            root.schliessen();
            Aktionen.einstellungen("");
        }
    }

    Abschnitt {}

    // Beenden erst nach Rückfrage (zweiter Klick)
    MenueEintrag {
        width: parent.width
        symbol: "abmelden"
        text: "Abmelden"
        bestaetigen: true
        frage: "Wirklich abmelden?"
        onAusgeloest: {
            root.schliessen();
            Aktionen.abmelden();
        }
    }

    MenueEintrag {
        width: parent.width
        symbol: "neustart"
        text: "Neustart"
        bestaetigen: true
        frage: "Wirklich neu starten?"
        onAusgeloest: {
            root.schliessen();
            Aktionen.neustarten();
        }
    }

    MenueEintrag {
        width: parent.width
        symbol: "ausschalten"
        text: "Ausschalten"
        bestaetigen: true
        frage: "Wirklich ausschalten?"
        onAusgeloest: {
            root.schliessen();
            Aktionen.ausschalten();
        }
    }
}
