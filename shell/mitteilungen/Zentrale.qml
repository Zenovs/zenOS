pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.komponenten
import qs.dienste as Dienste
import "format.js" as Format

// Zentrale: Panel rechts unter der Leiste mit allen zugestellten Mitteilungen,
// «Jetzt zustellen», «Alle verwerfen» und der wirksamen Regel. Öffnet über
// Oberflaeche.zentraleOffen (Leiste, IPC). Klick daneben oder Esc schliesst.
// Leitplanke: bei Bildschirmfreigabe nur die Anzahl, keine Liste.
PanelWindow {
    id: fenster

    readonly property bool offen: Dienste.Oberflaeche.zentraleOffen
    readonly property bool verborgen: Dienste.Mitteilungen.inhalteVerborgen
    readonly property var regel: Dienste.Mitteilungen.regel
    readonly property string zustandName: Dienste.Zustaende.aktivId !== "" ? String(Dienste.Zustaende.wirksam?.name ?? "") : ""
    readonly property int breite: 400

    // 0 geschlossen … 1 offen (Ein- und Ausblenden)
    property real anzeige: offen ? 1 : 0
    // für Zeitangaben; läuft nur, solange die Zentrale offen ist
    property var jetzt: new Date()

    function schliessen(): void {
        Dienste.Oberflaeche.zentraleOffen = false;
    }

    function ausfuehren(eintrag: var, kennung: string): void {
        if (Dienste.Mitteilungen.aktionAusfuehren(eintrag.nummer, kennung))
            schliessen();
    }

    visible: offen || anzeige > 0
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    color: Theme.durchsichtig

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: offen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "zenos-zentrale"

    Behavior on anzeige {
        NumberAnimation {
            duration: Theme.dauerKurz
            easing.type: Theme.kurve
        }
    }

    onOffenChanged: {
        if (offen) {
            jetzt = new Date();
            liste.positionViewAtBeginning();
            tasten.forceActiveFocus();
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: fenster.offen
        onTriggered: fenster.jetzt = new Date()
    }

    // Klick neben das Panel schliesst
    MouseArea {
        anchors.fill: parent
        onClicked: fenster.schliessen()
    }

    Item {
        id: tasten

        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: fenster.schliessen()

        Rectangle {
            id: panel

            readonly property real maxHoehe: parent.height - 2 * Theme.a2

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Theme.a2
            anchors.rightMargin: Theme.a2
            width: fenster.breite
            height: Math.min(spalte.implicitHeight, maxHoehe)
            radius: Theme.radiusFenster
            color: Theme.flaeche
            border.width: 1
            border.color: Theme.linie2
            opacity: fenster.anzeige
            clip: true

            transform: Translate {
                x: (1 - fenster.anzeige) * Theme.a3
            }

            // Klicks im Panel nicht zum Schliessen durchreichen
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: spalte

                width: parent.width

                // Kopf: Titel, Regel, Zustand
                ColumnLayout {
                    id: kopf

                    x: Theme.a4
                    width: parent.width - 2 * Theme.a4
                    spacing: 6

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: Theme.a4
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.a2

                        Abschnittstitel {
                            Layout.fillWidth: true
                            text: "Mitteilungen"
                            groesse: 12
                        }

                        Schliessen {
                            beschriftung: "Zentrale schliessen"
                            onClicked: fenster.schliessen()
                        }
                    }

                    // Leitplanke: Hinweis in der Farbe für «Bildschirm wird geteilt»
                    RowLayout {
                        Layout.fillWidth: true
                        visible: fenster.verborgen
                        spacing: Theme.a2

                        Rectangle {
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: 3.5
                            color: Theme.sitzung
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Bildschirm wird geteilt · Inhalte verborgen"
                            color: Theme.text
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                            wrapMode: Text.WordWrap
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !fenster.verborgen
                        text: Format.regel(fenster.regel, Dienste.Mitteilungen.naechsteZustellung, fenster.zustandName !== "")
                        color: Theme.text
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: fenster.zustandName !== ""
                        text: "Zustand «" + fenster.zustandName + "»" + (Dienste.Zustaende.restMinuten >= 0 ? " · noch " + Dienste.Zustaende.restMinuten + " Min." : "")
                        color: Theme.gedaempft
                        font.family: Theme.schriftMono
                        font.pixelSize: Theme.groesseKlein
                        elide: Text.ElideRight
                    }

                    // Wartende: nur die Anzahl, Inhalte erst nach der Zustellung
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: Dienste.Mitteilungen.anzahlWartend > 0
                        implicitHeight: 44
                        radius: Theme.radiusFeld
                        color: Theme.flaeche2

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.a3
                            anchors.rightMargin: 6
                            spacing: Theme.a2

                            Symbol {
                                name: "glocke"
                                groesse: 15
                                farbe: Theme.text2
                            }

                            Text {
                                text: Format.warten(Dienste.Mitteilungen.anzahlWartend)
                                color: Theme.text
                                font.family: Theme.schriftText
                                font.pixelSize: Theme.groesseText
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: fenster.regel?.art === "gebuendelt"
                                text: "bis " + Format.uhrzeit(Dienste.Mitteilungen.naechsteZustellung)
                                color: Theme.gedaempft
                                font.family: Theme.schriftMono
                                font.pixelSize: Theme.groesseKlein
                                elide: Text.ElideRight
                            }

                            Item {
                                Layout.fillWidth: fenster.regel?.art !== "gebuendelt"
                            }

                            Knopf {
                                visible: !fenster.verborgen
                                implicitHeight: 32
                                text: "Jetzt zustellen"
                                variante: "sekundaer"
                                schriftGroesse: Theme.groesseLabel
                                onClicked: Dienste.Mitteilungen.zustellen()
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: Theme.a2
                    }
                }

                Trenner {
                    width: parent.width
                }

                // Leitplanke: nur die Anzahl
                Item {
                    width: parent.width
                    height: visible ? verborgenText.implicitHeight + 2 * Theme.a5 : 0
                    visible: fenster.verborgen

                    Text {
                        id: verborgenText

                        x: Theme.a4
                        width: parent.width - 2 * Theme.a4
                        anchors.verticalCenter: parent.verticalCenter
                        text: Format.mitteilungen(Dienste.Mitteilungen.anzahl) + " · Inhalte verborgen, solange der Bildschirm geteilt wird"
                        color: Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                        wrapMode: Text.WordWrap
                    }
                }

                // Leer
                Item {
                    width: parent.width
                    height: visible ? 72 : 0
                    visible: !fenster.verborgen && Dienste.Mitteilungen.anzahlZugestellt === 0

                    Text {
                        anchors.centerIn: parent
                        text: Dienste.Mitteilungen.anzahlWartend > 0 ? "Noch nichts zugestellt" : "Keine Mitteilungen"
                        color: Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                    }
                }

                ListView {
                    id: liste

                    readonly property real platz: panel.maxHoehe - kopf.implicitHeight - 1 - (fuss.visible ? fuss.height : 0)

                    x: Theme.a2
                    width: parent.width - 2 * Theme.a2
                    height: visible ? Math.max(0, Math.min(contentHeight + topMargin + bottomMargin, platz)) : 0
                    visible: !fenster.verborgen && Dienste.Mitteilungen.anzahlZugestellt > 0
                    topMargin: Theme.a2
                    bottomMargin: Theme.a2
                    spacing: 2
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // Leitplanke: bei Freigabe gar keine Einträge erzeugen
                    model: ScriptModel {
                        values: fenster.verborgen || !fenster.visible ? [] : Dienste.Mitteilungen.zugestellt
                    }

                    delegate: Eintrag {
                        required property var modelData

                        width: ListView.view.width
                        eintrag: modelData
                        polster: 10
                        hoverFlaeche: true
                        textZeilen: 4
                        schliessbar: true
                        schliessenText: "Verwerfen"
                        jetzt: fenster.jetzt
                        onSchliessen: Dienste.Mitteilungen.verwerfen(modelData.nummer)
                        onGeklickt: if (modelData.standardAktion)
                            fenster.ausfuehren(modelData, "default")
                        onAktion: kennung => fenster.ausfuehren(modelData, kennung)
                    }
                }

                // Fuss
                Column {
                    id: fuss

                    width: parent.width
                    visible: !fenster.verborgen && Dienste.Mitteilungen.anzahlZugestellt > 0

                    Trenner {
                        width: parent.width
                    }

                    RowLayout {
                        x: Theme.a2
                        width: parent.width - Theme.a2 - Theme.a4
                        height: 48

                        Knopf {
                            implicitHeight: 32
                            text: "Alle verwerfen"
                            variante: "still"
                            schriftGroesse: Theme.groesseLabel
                            onClicked: Dienste.Mitteilungen.alleVerwerfen()
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "Esc schliessen"
                            color: Theme.gedaempft
                            font.family: Theme.schriftMono
                            font.pixelSize: Theme.groesseKlein
                        }
                    }
                }
            }
        }
    }
}
