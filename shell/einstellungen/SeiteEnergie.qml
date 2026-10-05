pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste

// Seite «Energie»: was ohne Eingabe geschieht (Zeitleiste), «Bildschirm aus» 1–10 Min. nach der Sperre, Ausschalten
// nach langer Sperre und Ein/Aus-Taste (noch nicht verfügbar), Zuklappen und Bereitschaft als Anzeige, dazu die
// Leitplanke: Nichts hier verzögert die automatische Sperre (die bleibt auf «Allgemein», sie ist Sicherheit).
// Gespeichert wird wie auf «Allgemein» 500 ms nach der letzten Änderung in ~/.config/zenos/einstellungen.json;
// zenos-idle und die Sperre übernehmen den Wert von selbst.
Item {
    id: root

    property string unterauswahl

    // Wirksam (Leitplanke 1–10) und wie es in der Datei steht
    readonly property int bildschirmMinuten: Dienste.Energie.bildschirmMinuten
    readonly property var _bildschirmRoh: Dienste.Einstellungen.bildschirmAusNachSperre
    // Wert von Hand, der so nicht wirkt (ausserhalb 1–10, keine ganze Zahl, keine Zahl): zeigen, was gilt
    readonly property bool bildschirmEigen: {
        const roh = root._bildschirmRoh;
        const zahl = typeof roh === "number" ? roh : typeof roh === "string" && roh.trim() !== "" ? Number(roh.trim().replace(",", ".")) : NaN;
        return zahl !== root.bildschirmMinuten;
    }

    // Schlafzustände des Kernels aus /sys/power/state (leer: keine; null: noch nicht gelesen)
    property var _schlafzustaende: null
    readonly property bool bereitschaftAngeboten: _schlafzustaende !== null && /(^|\s)(mem|freeze)(\s|$)/.test(_schlafzustaende)

    readonly property string bereitschaftText: {
        if (root._schlafzustaende === null)
            return "…";
        if (root.bereitschaftAngeboten)
            return "Der Kernel bietet einen Schlafzustand an (" + root._schlafzustaende + "), zenOS nutzt ihn noch nicht. Es schaltet stattdessen den Bildschirm aus.";
        return "Auf diesem Gerät nicht verfügbar: Der Kernel bietet keinen Schlafzustand an. zenOS schaltet stattdessen den Bildschirm aus.";
    }

    // Den Deckel wertet zenOS noch nicht aus. Beim Argon ONE UP (Laptop) ehrlich sagen, sonst gibt es keinen.
    readonly property string zuklappenText: Dienste.Geraet.modell === "argon-one-up" ? "Sperrt noch nicht. Bis dahin vor dem Zuklappen mit Super+L sperren." : "Kein Deckel erkannt."

    function _speichernBald(): void {
        speicherTimer.restart();
    }

    function speichern(): void {
        if (!speicherTimer.running && !_offen)
            return;
        speicherTimer.stop();
        _offen = false;
        Dienste.Einstellungen.speichern();
    }

    property bool _offen: false

    function setzen(schluessel: string, wert: var): void {
        if (Dienste.Einstellungen[schluessel] === wert)
            return;
        Dienste.Einstellungen[schluessel] = wert;
        _offen = true;
        _speichernBald();
    }

    Component.onDestruction: speichern()

    Timer {
        id: speicherTimer

        interval: 500
        onTriggered: root.speichern()
    }

    // /sys/power/state: nur lesen, einmal beim Öffnen der Seite
    FileView {
        path: "/sys/power/state"
        printErrors: false

        onLoaded: root._schlafzustaende = text().trim()
        onLoadFailed: root._schlafzustaende = ""
    }

    Seite {
        id: seite

        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Einstellungen"
            titel: "Energie"
        }

        Feld {
            width: parent.width
            beschriftung: "Ohne Eingabe"

            Text {
                width: parent.width
                text: Dienste.Energie.zeitleisteText
                wrapMode: Text.WordWrap
                color: Theme.text
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Bildschirm aus"

            Column {
                width: parent.width
                spacing: 12

                Row {
                    spacing: 16

                    Stufenwahl {
                        id: bildschirmWahl

                        min: Dienste.Leitplanken.bildschirmAusNachSperreMin
                        max: Dienste.Leitplanken.bildschirmAusNachSperreMax
                        schritt: 1
                        einheit: "Min."
                        onGeaendert: wert => root.setzen("bildschirmAusNachSperre", Dienste.Leitplanken.bildschirmMinuten(wert))
                    }

                    // Stufenwahl setzt «wert» bei Bedienung selbst; das Binding folgt trotzdem weiter der Datei
                    Binding {
                        target: bildschirmWahl
                        property: "wert"
                        value: root.bildschirmMinuten
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "nach der Sperre"
                        color: Theme.text
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                    }

                    // Wert von Hand in einstellungen.json, der so nicht gilt
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.bildschirmEigen
                        text: "Eigener Wert: " + String(root._bildschirmRoh) + " · es gelten " + root.bildschirmMinuten + " Min."
                        color: Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                    }
                }

                Text {
                    width: parent.width
                    text: "Dunkel heisst gesperrt: Der Bildschirm geht nur aus, wenn zenOS gesperrt ist. Eine Taste weckt ihn, sie landet nicht im Passwortfeld."
                    wrapMode: Text.WordWrap
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }

                Row {
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Sofort sperren und Bildschirm aus"
                        color: Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                    }

                    Kbd {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Super Shift L"
                    }
                }
            }
        }

        // Folgt: Ausschalten nach langer Sperre (30–240 Min., mit Vorwarnung) und die Wahl für die Ein/Aus-Taste
        Feld {
            width: parent.width
            beschriftung: "Ausschalten, wenn gesperrt"

            Hinweistext {
                text: "Noch nicht verfügbar. zenOS schaltet heute nie selbst aus."
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Ein/Aus-Taste"

            Hinweistext {
                text: "Noch nicht einstellbar. Kurz drücken schaltet heute aus, gedrückt halten schaltet immer hart aus."
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Zuklappen"

            Hinweistext {
                text: root.zuklappenText
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Bereitschaft"

            Hinweistext {
                text: root.bereitschaftText
            }
        }

        Leitplankenhinweis {
            width: parent.width
            text: Dienste.Leitplanken.energieHinweis
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: "~/.config/zenos/einstellungen.json · lokal, nicht im Repo"
            onFertig: {
                root.speichern();
                Dienste.Oberflaeche.einstellungenOffen = false;
            }
        }
    }

    // Ruhiger Text unter einer Beschriftung (Anzeige ohne Bedienung)
    component Hinweistext: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        lineHeightMode: Text.FixedHeight
        lineHeight: Math.round(font.pixelSize * 1.45)
        color: Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseText
    }
}
