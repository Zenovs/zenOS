pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste

// Seite «Energie»: was ohne Eingabe geschieht (Zeitleiste), «Bildschirm aus» 1–10 Min. nach der Sperre, Ausschalten
// nach langer Sperre (Nie · Im Akkubetrieb · Immer, 30–240 Min.) mit dem, was gerade im Weg ist, die Ein/Aus-Taste,
// Zuklappen und Bereitschaft als Anzeige, dazu die Leitplanke: Nichts hier verzögert die automatische Sperre (die
// bleibt auf «Allgemein», sie ist Sicherheit).
// Gespeichert wird wie auf «Allgemein» 500 ms nach der letzten Änderung in ~/.config/zenos/einstellungen.json;
// zenos-idle, die Sperre und Dienste.Energie übernehmen die Werte von selbst.
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

    // Was das Ausschalten gerade aufhält (zenos-energie status: «nein: Grund»), leer: nichts oder unbekannt
    property string _blockiert: ""

    readonly property var _ausschaltenOptionen: [
        {
            wert: "nie",
            text: "Nie"
        },
        {
            wert: "akku",
            text: "Im Akkubetrieb"
        },
        {
            wert: "immer",
            text: "Immer"
        }
    ]
    readonly property var _tastenOptionen: [
        {
            wert: "sperren",
            text: "Sperren"
        },
        {
            wert: "menue",
            text: "System-Menü"
        },
        {
            wert: "ausschalten",
            text: "Ausschalten"
        }
    ]

    // Deckel (Argon ONE UP, zenos-argon liest GPIO27): Zuklappen sperrt immer (Leitplanke). Liest zenos-argon ihn nicht,
    // beim Laptop ehrlich sagen, sonst gibt es keinen.
    readonly property string zuklappenText: Dienste.Geraet.deckelVorhanden ? "Sperrt sofort und schaltet den Bildschirm aus. Aufklappen schaltet ihn wieder an." : Dienste.Geraet.modell === "argon-one-up" ? "Deckel nicht erkannt. Bis dahin vor dem Zuklappen mit Super+L sperren." : "Kein Deckel erkannt."

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

    // Was gerade im Weg ist: beim Öffnen und alle 15 s, solange die Seite offen ist (nur lesen, ohne Journal)
    Process {
        id: statusProzess

        command: [Dienste.Pfade.bin + "/zenos-energie", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const zeile = text.trim().split("\n").pop() ?? "";
                root._blockiert = zeile.startsWith("nein:") ? zeile.slice(5).trim() : "";
            }
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: {
            if (!statusProzess.running)
                statusProzess.running = true;
        }
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
                    text: "Dunkel heisst gesperrt: Der Bildschirm geht nur aus, wenn zenOS gesperrt ist. Eine Taste weckt ihn, sie landet nicht im Passwortfeld. Am Login-Bildschirm geht er nach " + Dienste.Leitplanken.loginBildschirmAusMinuten + " Min. ohne Eingabe aus."
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

        Feld {
            width: parent.width
            beschriftung: "Ausschalten, wenn gesperrt"

            Column {
                width: parent.width
                spacing: 12

                Segmente {
                    id: ausschaltenSegmente

                    optionen: root._ausschaltenOptionen
                    onGewaehlt: wert => root.setzen("ausschalten", wert)
                }

                // Segmente setzt «wert» bei einer Wahl selbst; das Binding folgt trotzdem weiter der Datei
                Binding {
                    target: ausschaltenSegmente
                    property: "wert"
                    value: Dienste.Energie.ausschaltenArt
                }

                Row {
                    visible: Dienste.Energie.ausschaltenArt !== "nie"
                    spacing: 16

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Nach"
                        color: Theme.text
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                    }

                    Stufenwahl {
                        id: ausschaltenWahl

                        min: Dienste.Leitplanken.ausschaltenMinutenMin
                        max: Dienste.Leitplanken.ausschaltenMinutenMax
                        schritt: 30
                        einheit: "Min."
                        onGeaendert: wert => root.setzen("ausschaltenNachMinuten", Dienste.Leitplanken.ausschaltenMinuten(wert))
                    }

                    Binding {
                        target: ausschaltenWahl
                        property: "wert"
                        value: Dienste.Energie.ausschaltenMinuten
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "gesperrt ohne Eingabe"
                        color: Theme.text
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                    }
                }

                Hinweistext {
                    text: "Vorher steht " + Dienste.Leitplanken.vorwarnungSekunden + " s lang die Uhrzeit auf dem Sperrbildschirm, eine Taste bricht ab. Nie während einer SSH-Sitzung, mit tmux oder während eines Updates."
                }

                Hinweistext {
                    visible: Dienste.Energie.ausschaltenArt === "akku" && !Dienste.Geraet.akkuVorhanden
                    text: "Kein Akku erkannt: «Im Akkubetrieb» schaltet auf diesem Gerät nie aus."
                }

                // Leitplanke unabhängig von der Wahl oben (zenos-argon, auch am Login-Bildschirm)
                Hinweistext {
                    visible: Dienste.Geraet.akkuVorhanden
                    text: "Bei " + Dienste.Leitplanken.akkuAusschaltenProzent + " % Akku schaltet zenOS immer kontrolliert aus, nach " + Dienste.Leitplanken.vorwarnungSekunden + " s Vorwarnung. Nur das Netzteil bricht ab."
                }

                // Zenos Entscheid, fest: am Login-Bildschirm im Akkubetrieb (ohne Akku gilt es nie)
                Hinweistext {
                    visible: Dienste.Geraet.akkuVorhanden
                    text: "Am Login-Bildschirm schaltet zenOS im Akkubetrieb nach " + Dienste.Leitplanken.loginAusschaltenMinuten + " Min. ohne Eingabe aus, ebenfalls mit Vorwarnung."
                }

                // Ohne Akku sagt «Kein Akku erkannt» oben schon, warum «Im Akkubetrieb» nicht greift
                Hinweistext {
                    visible: Dienste.Energie.ausschaltenArt !== "nie" && root._blockiert.length > 0 && !(Dienste.Energie.ausschaltenArt === "akku" && !Dienste.Geraet.akkuVorhanden)
                    text: "Zurzeit nicht: " + root._blockiert
                    color: Theme.text2
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Ein/Aus-Taste"

            Column {
                width: parent.width
                spacing: 12

                Segmente {
                    id: tastenSegmente

                    optionen: root._tastenOptionen
                    onGewaehlt: wert => root.setzen("einAusTaste", wert)
                }

                Binding {
                    target: tastenSegmente
                    property: "wert"
                    value: Dienste.Energie.einAusTaste
                }

                Hinweistext {
                    text: Dienste.Energie.einAusTaste === "ausschalten" ? "Kurz drücken schaltet sofort aus, am Login-Bildschirm weckt es nur. Gedrückt halten schaltet immer hart aus." : "Kurz drücken, gesperrt: Bildschirm an oder aus. Am Login-Bildschirm weckt es nur, in den ersten Sekunden nach dem Anmelden schaltet es sofort aus. Gedrückt halten schaltet immer hart aus."
                }
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

    // Ruhiger Text unter einer Beschriftung (Anzeige ohne Bedienung). Nur reiner Text: «Zurzeit nicht» zeigt den Namen
    // eines fremden logind-Hemmers.
    component Hinweistext: Text {
        width: parent ? parent.width : 0
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        lineHeightMode: Text.FixedHeight
        lineHeight: Math.round(font.pixelSize * 1.45)
        color: Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseText
    }
}
