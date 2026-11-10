pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.dienste
import qs.komponenten

// System-Menü unter dem System-Knopf der Leiste: Netz mit WLAN (WlanAbschnitt: Netz wählen, verbinden,
// vergessen, WLAN ein/aus über NetworkManager), Bluetooth (BluetoothAbschnitt, nur wenn BlueZ läuft), Lautstärke mit
// Regler und Stumm, dann das Gerät (Akku und CPU-Temperatur als Anzeige), dann Sperren, Bildschirm aus, Abmelden,
// Neustart und Ausschalten. Läuft gerade ein Update (zen update, Update.laeuft), steht bei Neustart und Ausschalten
// «Update läuft»: Beides wartet, bis es fertig ist, statt das Schreiben der neuen Hälfte abzubrechen. Ist ein neuer
// Stand installiert (Update.neustartNoetig), steht bei Neustart «nötig».
Menuekarte {
    id: root

    // WlanQuelle aus Leiste.qml (null, solange NetworkManager nicht läuft)
    property var wlanQuelle: null
    property bool wlanNmLaeuft: false
    // Liste der WLANs gleich aufgeklappt (zenos-ipc leiste menue wlan)
    property bool wlanOffen: false
    // BluetoothQuelle aus Leiste.qml (null, solange bluetooth.service nicht läuft) und ob das Gerät Bluetooth hat
    property var bluetoothQuelle: null
    property bool bluetoothGeraet: false
    // Liste der Bluetooth-Geräte gleich aufgeklappt (zenos-ipc leiste menue bluetooth)
    property bool bluetoothOffen: false

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

    // --- Bluetooth ---

    Abschnitt {
        visible: bluetooth.visible
    }

    BluetoothAbschnitt {
        id: bluetooth

        quelle: root.bluetoothQuelle
        geraetDa: root.bluetoothGeraet
        offen: root.bluetoothOffen
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

    // --- Gerät: Akku und CPU-Temperatur (Werte von /run/zenos/geraet.json bzw. aus /sys) ---

    Abschnitt {
        visible: akkuZeile.visible || temperaturZeile.visible
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

    // Während eines Updates hält zenos-update.service einen Block-Inhibitor: systemctl lehnte ab. Darum hier ehrlich
    // sagen, dass es wartet, statt still nichts zu tun. Sonst steht hier «nötig», wenn ein neuer Stand installiert ist.
    MenueEintrag {
        width: parent.width
        symbol: "neustart"
        text: "Neustart"
        wert: Update.laeuft ? "Update läuft" : Update.neustartNoetig ? "nötig" : ""
        // Während des Updates ohne Rückfrage: Der Klick sagt nur, warum es wartet
        bestaetigen: !Update.laeuft
        frage: "Wirklich neu starten?"
        onAusgeloest: {
            root.schliessen();
            if (Update.laeuft)
                Oberflaeche.hinweis("Update läuft: Neustart geht erst danach", "warnung");
            else
                Aktionen.neustarten();
        }
    }

    MenueEintrag {
        width: parent.width
        symbol: "ausschalten"
        text: "Ausschalten"
        wert: Update.laeuft ? "Update läuft" : ""
        // Während des Updates ohne Rückfrage: Der Klick sagt nur, warum es wartet
        bestaetigen: !Update.laeuft
        frage: "Wirklich ausschalten?"
        onAusgeloest: {
            root.schliessen();
            if (Update.laeuft)
                Oberflaeche.hinweis("Update läuft: Ausschalten geht erst danach", "warnung");
            else
                Aktionen.ausschalten();
        }
    }
}
