pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.dienste
import qs.komponenten
import "../dienste/geraet.js" as Logik

// Lüfter im System-Menü: Zeile «Lüfter» (36 px, wie MenueEintrag) mit Stufe, Drehzahl und Wunsch in Mono rechts
// («aus · Auto», «Stufe 2 · 3120 U/min · mind. 2»; der längste Text, der passt, sonst in der Mitte gekürzt).
// Kann zenos-argon den Wunsch umsetzen (Geraet.luefterSteuerbar), klappt ein Klick, Enter oder die Leertaste darunter
// die Wahl «Auto · 1 · 2 · 3 · 4» auf: Segmente wie in den Einstellungen (Fläche flaeche2, die gewählte hebt sich
// mit flaeche ab), ohne Animation, die Karte wächst einfach. Pfeile links/rechts (Pos1/Ende) wandern, der
// Fokusrahmen zeigt wohin; Enter oder Leertaste wählt, ein Klick ebenso. Gewählt wird über Luefter (pkexec mit
// zenos-luefter); bis zenos-argon den Wunsch bestätigt, gilt die neue Wahl. Darunter eine Zeile in gedaempft.
// Ohne Steuerung (älterer Dienst, Zone nicht einstellbar) ist die Zeile reine Anzeige.
Column {
    id: root

    // Wahl aufgeklappt (Startwert: zenos-ipc leiste menue luefter)
    property bool offen: false

    readonly property bool _steuerbar: Geraet.luefterSteuerbar
    // Wahl, die gerade gilt: die eben gewählte, bis zenos-argon sie bestätigt, sonst die gemeldete
    readonly property string _gewaehlt: Luefter.ziel !== "" ? Luefter.ziel : Geraet.luefterWahl

    function _umschalten(tastatur: bool): void {
        if (!_steuerbar)
            return;
        offen = !offen;
        if (offen && tastatur)
            Qt.callLater(() => wahl.forceActiveFocus(Qt.TabFocusReason));
    }

    width: parent ? parent.width : 0
    visible: Geraet.luefterWert !== ""

    // --- Zeile «Lüfter» ---

    Item {
        id: zeile

        width: root.width
        height: 36
        activeFocusOnTab: root._steuerbar

        Accessible.role: root._steuerbar ? Accessible.MenuItem : Accessible.StaticText
        Accessible.name: "Lüfter, " + wertText.text
        Accessible.onPressAction: root._umschalten(false)

        Keys.onPressed: event => {
            if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
                root._umschalten(true);
                event.accepted = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusChip
            color: Theme.flaeche2
            opacity: root._steuerbar && (maus.containsMouse || zeile.activeFocus) ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.dauerKurz
                    easing.type: Theme.kurve
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusChip
            color: Theme.text
            opacity: maus.pressed && root._steuerbar ? 0.05 : 0
        }

        Row {
            id: links

            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                name: "luefter"
                groesse: 15
                farbe: Theme.text2
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Lüfter"
                color: Theme.text
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
            }
        }

        FontMetrics {
            id: masse

            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }

        Row {
            id: rechts

            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                id: wertText

                // Platz bis kurz vor den Titel
                readonly property real platz: Math.max(0, zeile.width - links.x - links.width - Theme.a2 - 10 - (pfeil.visible ? pfeil.width + rechts.spacing : 0))

                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, platz)
                text: {
                    const werte = Geraet.luefterWerte;
                    for (const w of werte) {
                        if (masse.advanceWidth(w) <= platz)
                            return w;
                    }
                    return werte.length > 0 ? werte[werte.length - 1] : "";
                }
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignRight
                color: Theme.gedaempft
                font.family: Theme.schriftMono
                font.pixelSize: Theme.groesseKlein
            }

            Symbol {
                id: pfeil

                anchors.verticalCenter: parent.verticalCenter
                visible: root._steuerbar
                rotation: root.offen ? 180 : 0
                name: "pfeil-runter"
                groesse: 14
                farbe: Theme.text2
            }
        }

        MouseArea {
            id: maus

            anchors.fill: parent
            hoverEnabled: true
            enabled: root._steuerbar
            cursorShape: Qt.PointingHandCursor
            onClicked: root._umschalten(false)
        }
    }

    // --- Wahl «Auto · 1 · 2 · 3 · 4» ---

    Item {
        visible: root.offen && root._steuerbar
        width: root.width
        height: wahl.height + hinweis.implicitHeight + Theme.a1 * 3

        Item {
            id: wahl

            readonly property var optionen: [
                {
                    wert: "auto",
                    text: "Auto"
                },
                {
                    wert: "1",
                    text: "1"
                },
                {
                    wert: "2",
                    text: "2"
                },
                {
                    wert: "3",
                    text: "3"
                },
                {
                    wert: "4",
                    text: "4"
                }
            ]
            // Segment unter dem Tastaturfokus
            property int cursor: 0

            function waehlen(i: int): void {
                if (i < 0 || i >= optionen.length || Luefter.laeuft)
                    return;
                cursor = i;
                Luefter.setzen(optionen[i].wert);
            }

            function wandern(i: int): void {
                cursor = Math.max(0, Math.min(optionen.length - 1, i));
            }

            x: 35
            y: Theme.a1
            width: parent.width - x - 10
            height: 32
            activeFocusOnTab: true

            Accessible.role: Accessible.PageTabList
            Accessible.name: "Lüfter einstellen"

            onActiveFocusChanged: {
                if (activeFocus)
                    cursor = Math.max(0, optionen.findIndex(o => o.wert === root._gewaehlt));
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left) {
                    wandern(cursor - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    wandern(cursor + 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Home) {
                    wandern(0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_End) {
                    wandern(optionen.length - 1);
                    event.accepted = true;
                } else if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
                    waehlen(cursor);
                    event.accepted = true;
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFeld
                color: Theme.flaeche2
            }

            Row {
                x: 3
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Repeater {
                    model: wahl.optionen

                    Item {
                        id: segment

                        required property var modelData
                        required property int index
                        readonly property bool gewaehlt: root._gewaehlt === modelData.wert

                        width: (wahl.width - 6 - 4 * 2) / 5
                        height: wahl.height - 6

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusFeld - 3
                            color: Theme.flaeche
                            opacity: segment.gewaehlt ? 1 : segmentMaus.containsMouse && !Luefter.laeuft ? 0.45 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.dauerKurz
                                    easing.type: Theme.kurve
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: segment.modelData.text
                            color: segment.gewaehlt ? Theme.text : Theme.gedaempft
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                        }

                        Fokusrahmen {
                            aktiv: wahl.activeFocus && wahl.cursor === segment.index
                            eckenRadius: Theme.radiusFeld - 3
                        }

                        MouseArea {
                            id: segmentMaus

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Luefter.laeuft ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: wahl.waehlen(segment.index)
                        }

                        Accessible.role: Accessible.PageTab
                        Accessible.name: segment.index === 0 ? "Automatisch" : "Mindeststufe " + modelData.text
                        Accessible.checked: gewaehlt
                        Accessible.onPressAction: wahl.waehlen(segment.index)
                    }
                }
            }
        }

        Text {
            id: hinweis

            x: wahl.x
            y: wahl.y + wahl.height + Theme.a1
            width: wahl.width
            text: Luefter.laeuft || Luefter.ziel !== "" ? "Wird eingestellt …" : Logik.luefterHinweis(root._gewaehlt)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseKlein
        }
    }
}
