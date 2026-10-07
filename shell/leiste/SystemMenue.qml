pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.dienste
import qs.komponenten

// System-Menü unter dem System-Knopf der Leiste: Netz mit WLAN (WlanAbschnitt: Netz wählen, verbinden,
// vergessen, WLAN ein/aus über NetworkManager), Lautstärke mit Regler und Stumm, 1Password, dann das Gerät
// (Akku und CPU-Temperatur als Anzeige; Lüfter mit aufklappbarer Wahl «Auto · 1 · 2 · 3 · 4», LuefterAbschnitt),
// dann Sperren, Bildschirm aus, Einstellungen, Abmelden, Neustart und Ausschalten. Läuft gerade ein Update aus dem
// Kanal (install.sh mit Block-Inhibitor), steht bei Neustart und Ausschalten «Update läuft»: Beides wartet dann,
// bis es fertig ist (meist wenige Minuten), statt dpkg mittendrin abzubrechen.
Menuekarte {
    id: root

    // WlanQuelle aus Leiste.qml (null, solange NetworkManager nicht läuft)
    property var wlanQuelle: null
    property bool wlanNmLaeuft: false
    // Liste der WLANs gleich aufgeklappt (zenos-ipc leiste menue wlan)
    property bool wlanOffen: false
    // Wahl des Lüfters gleich aufgeklappt (zenos-ipc leiste menue luefter)
    property bool luefterOffen: false

    breite: 300

    // Anzeigezeile ohne Bedienung: Symbol, Titel, rechts ein Wert in Mono
    component Statuszeile: Item {
        id: zeile

        property string symbol
        property string titel
        property string wert
        property bool gedaempft: false
        // Symbol in der Warnfarbe (niedriger Akku)
        property bool warnend: false

        width: parent ? parent.width : 0
        height: 36

        Row {
            id: titelZeile

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
                    farbe: zeile.warnend ? Theme.warnung : zeile.gedaempft ? Theme.gedaempft : Theme.text2
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

        // Höchstens bis kurz vor den Titel; ist der Wert länger (z. B. fünfstellige U/min), wird er in der Mitte gekürzt
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, zeile.width - titelZeile.x - titelZeile.width - Theme.a2 - 10))
            horizontalAlignment: Text.AlignRight
            text: zeile.wert
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
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

    WlanAbschnitt {
        quelle: root.wlanQuelle
        nmLaeuft: root.wlanNmLaeuft
        offen: root.wlanOffen
    }

    Abschnitt {}

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

    // --- 1Password ---

    Statuszeile {
        symbol: "schloss"
        gedaempft: !System.einsPasswortLaeuft
        titel: "1Password"
        wert: System.einsPasswortLaeuft ? "läuft" : System.einsPasswortInstalliert ? "nicht gestartet" : "nicht installiert"
    }

    // --- Gerät: Akku, Lüfter, CPU-Temperatur (Werte von zenos-argon bzw. aus /sys; nur der Lüfter ist einstellbar) ---

    Abschnitt {
        visible: akkuZeile.visible || luefterZeile.visible || temperaturZeile.visible
    }

    Statuszeile {
        id: akkuZeile

        visible: Geraet.akkuVorhanden
        symbol: Geraet.akkuSymbol
        gedaempft: !Geraet.akkuBekannt
        warnend: Geraet.akkuNiedrig
        titel: "Akku"
        wert: Geraet.akkuWert
    }

    LuefterAbschnitt {
        id: luefterZeile

        offen: root.luefterOffen
    }

    Statuszeile {
        id: temperaturZeile

        visible: System.temperatur >= 0
        symbol: "thermometer"
        titel: "CPU-Temperatur"
        wert: System.temperatur + " °C"
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

    // Sperrt zuerst (dunkel heisst gesperrt), ohne Rückfrage: Eine Taste weckt den Bildschirm wieder
    MenueEintrag {
        width: parent.width
        symbol: "monitor"
        text: "Bildschirm aus"
        onAusgeloest: {
            root.schliessen();
            Aktionen.bildschirmAus();
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

    // Nur solange die Firewall aus ist, ruhig und ohne Farbe: führt zum Schalter in den Einstellungen
    MenueEintrag {
        visible: Firewall.bekannt && !Firewall.aktiv
        width: parent.width
        symbol: "schloss-offen"
        text: "Firewall"
        wert: "aus"
        Accessible.name: "Firewall ist aus – Einstellungen öffnen"
        onAusgeloest: {
            root.schliessen();
            Aktionen.einstellungen("system");
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

    // Während eines Updates aus dem Kanal oder der Ubuntu-Basis hält zenos-kanal bzw. zenos-basis einen Block-Inhibitor:
    // systemctl lehnte ab. Darum hier ehrlich sagen, dass es wartet, statt still nichts zu tun.
    MenueEintrag {
        width: parent.width
        symbol: "neustart"
        text: "Neustart"
        wert: Kanal.updateLaeuft ? "Update läuft" : ""
        // Während des Updates ohne Rückfrage: Der Klick sagt nur, warum es wartet
        bestaetigen: !Kanal.updateLaeuft
        frage: "Wirklich neu starten?"
        onAusgeloest: {
            root.schliessen();
            if (Kanal.updateLaeuft)
                Oberflaeche.hinweis("Update läuft: Neustart geht erst danach (meist wenige Minuten)", "warnung");
            else
                Aktionen.neustarten();
        }
    }

    MenueEintrag {
        width: parent.width
        symbol: "ausschalten"
        text: "Ausschalten"
        wert: Kanal.updateLaeuft ? "Update läuft" : ""
        // Während des Updates ohne Rückfrage: Der Klick sagt nur, warum es wartet
        bestaetigen: !Kanal.updateLaeuft
        frage: "Wirklich ausschalten?"
        onAusgeloest: {
            root.schliessen();
            if (Kanal.updateLaeuft)
                Oberflaeche.hinweis("Update läuft: Ausschalten geht erst danach (meist wenige Minuten)", "warnung");
            else
                Aktionen.ausschalten();
        }
    }
}
