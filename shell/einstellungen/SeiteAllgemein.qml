pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste
import "../modi/zustandslogik.js" as Logik

// Seite «Allgemein»: Name, Ort, Erscheinungsbild (hell, dunkel, nach Tageszeit mit Zeiten),
// automatische Sperre (1–15 Minuten, nicht abschaltbar, mit Verweis auf die Seite «Energie»), Mitteilungen ohne
// Zustand und Scroll-Tempo für Touchpad und Maus (wirkt nach dem Speichern sofort, siehe Dienst Raster).
// Gespeichert wird in ~/.config/zenos/einstellungen.json (Einstellungen-Dienst).
Item {
    id: root

    property string unterauswahl

    readonly property string standardArt: Logik.gebuendeltMinuten(Dienste.Einstellungen.mitteilungenStandard) > 0 ? "gebuendelt" : Dienste.Einstellungen.mitteilungenStandard
    readonly property int standardMinuten: Math.max(5, Logik.gebuendeltMinuten(Dienste.Einstellungen.mitteilungenStandard) > 0 ? Logik.gebuendeltMinuten(Dienste.Einstellungen.mitteilungenStandard) : 60)

    // Stufen des Scroll-Tempos (Faktor für labwc, docs/module/m9.md): halb, wie bisher, anderthalb, doppelt
    readonly property var scrollStufen: [
        {
            wert: "0.5",
            text: "Langsam"
        },
        {
            wert: "1",
            text: "Normal"
        },
        {
            wert: "1.5",
            text: "Schnell"
        },
        {
            wert: "2",
            text: "Sehr schnell"
        }
    ]
    // Gewähltes Tempo als Text wie in scrollStufen ("1", "1.5"); ungültig in der Datei: Normal
    readonly property string scrollWert: String(Dienste.Einstellungen.scrollTempoPruefen(Dienste.Einstellungen.scrollTempo))
    readonly property bool scrollEigen: !scrollStufen.some(s => s.wert === scrollWert)

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

    Seite {
        id: seite

        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Einstellungen"
            titel: "Allgemein"
        }

        Grid {
            id: raster

            readonly property real spalte: (width - columnSpacing) / 2

            width: parent.width
            columns: 2
            columnSpacing: 40
            rowSpacing: 18

            Feld {
                width: raster.spalte
                beschriftung: "Wie soll dich zenOS nennen?"

                Eingabe {
                    id: nameFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 60
                    platzhalter: "Name"
                    text: Dienste.Einstellungen.name
                }
            }

            Feld {
                width: raster.spalte
                beschriftung: "Ort fürs Wetter"
                hinweis: "optional · später"

                Eingabe {
                    id: ortFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 100
                    platzhalter: "Ort"
                    text: Dienste.Einstellungen.ort
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Erscheinungsbild"

            Column {
                spacing: 12

                Segmente {
                    optionen: [
                        {
                            wert: "hell",
                            text: "Hell"
                        },
                        {
                            wert: "dunkel",
                            text: "Dunkel"
                        },
                        {
                            wert: "tageszeit",
                            text: "Nach Tageszeit"
                        }
                    ]
                    wert: Dienste.Erscheinung.gewaehlt
                    onGewaehlt: wert => Dienste.Erscheinung.setzen(wert)
                }

                Row {
                    visible: Dienste.Erscheinung.gewaehlt === "tageszeit"
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Hell ab"
                        color: Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                    }

                    Zeitfeld {
                        zeit: Dienste.Einstellungen.tagAb
                        onGesetzt: zeit => root.setzen("tagAb", zeit)
                    }

                    Item {
                        width: 14
                        height: 1
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Dunkel ab"
                        color: Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                    }

                    Zeitfeld {
                        zeit: Dienste.Einstellungen.nachtAb
                        onGesetzt: zeit => root.setzen("nachtAb", zeit)
                    }
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Automatische Sperre nach"

            Column {
                spacing: 6

                Row {
                    spacing: 16

                    Stufenwahl {
                        wert: Dienste.Leitplanken.sperreMinuten(Dienste.Einstellungen.sperreNachMinuten)
                        min: Dienste.Leitplanken.sperreMinutenMin
                        max: Dienste.Leitplanken.sperreMinutenMax
                        schritt: 1
                        einheit: "Min."
                        onGeaendert: wert => root.setzen("sperreNachMinuten", Dienste.Leitplanken.sperreMinuten(wert))
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Symbol {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "schloss"
                            groesse: 14
                            farbe: Theme.gedaempft
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Leitplanke: 1 bis 15 Minuten, lässt sich nicht abschalten."
                            color: Theme.gedaempft
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                        }
                    }
                }

                // Bildschirm aus nach der Sperre und was sonst ohne Eingabe geschieht: Seite «Energie»
                Knopf {
                    x: -16
                    implicitHeight: 32
                    variante: "still"
                    symbol: "monitor"
                    schriftGroesse: Theme.groesseLabel
                    text: "Bildschirm aus nach der Sperre: Energie"
                    onClicked: Dienste.Aktionen.einstellungen("energie")
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Mitteilungen, wenn kein Zustand aktiv ist"

            Row {
                spacing: 12

                Segmente {
                    optionen: [
                        {
                            wert: "alle",
                            text: "Sofort"
                        },
                        {
                            wert: "gebuendelt",
                            text: "Gebündelt"
                        },
                        {
                            wert: "nur-dringend",
                            text: "Nur Dringendes"
                        },
                        {
                            wert: "keine",
                            text: "Keine"
                        }
                    ]
                    wert: root.standardArt
                    onGewaehlt: wert => root.setzen("mitteilungenStandard", wert === "gebuendelt" ? "gebuendelt-" + root.standardMinuten : wert)
                }

                Stufenwahl {
                    visible: root.standardArt === "gebuendelt"
                    wert: root.standardMinuten
                    min: 5
                    max: 240
                    schritt: 5
                    einheit: "Min."
                    onGeaendert: wert => root.setzen("mitteilungenStandard", "gebuendelt-" + wert)
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Scroll-Tempo für Touchpad und Maus"

            Row {
                spacing: 16

                Segmente {
                    id: scrollSegmente

                    optionen: root.scrollStufen
                    onGewaehlt: wert => root.setzen("scrollTempo", Number(wert))
                }

                // Segmente setzt «wert» bei einer Wahl selbst und löst damit eine einfache Bindung; das
                // Binding-Element folgt dem Wert trotzdem weiter (z. B. nach einer Änderung von Hand)
                Binding {
                    target: scrollSegmente
                    property: "wert"
                    value: root.scrollWert
                }

                // Wert von Hand zwischen den Stufen (einstellungen.json): zeigen, keine Stufe ist gewählt
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.scrollEigen
                    text: "Eigener Wert: " + root.scrollWert.replace(".", ",") + "-fach"
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }
            }
        }

        Leitplankenhinweis {
            width: parent.width
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

    Connections {
        target: nameFeld.feld

        function onTextEdited(): void {
            root.setzen("name", nameFeld.text.trim());
        }
    }

    Connections {
        target: ortFeld.feld

        function onTextEdited(): void {
            root.setzen("ort", ortFeld.text.trim());
        }
    }
}
