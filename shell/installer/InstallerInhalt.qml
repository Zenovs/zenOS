pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten

// Inhalt des Fensters «zen Installer» (Installer.qml). Zeigt nur, was installer.js bild() beschreibt:
// - Kopf: Symbol des Pakets 64 px (sonst «paket» auf flaeche2), Name in Instrument Serif 36 (lang: bis 24 kleiner, dann
//   gekürzt), darunter die Zusammenfassung (text2) und Paket mit Version in Geist Mono 12 (gedaempft).
// - Lage: Symbol 16 px und Titel wie auf der Updates-Seite, darunter ein ruhiger Satz (gedaempft; bei einer Ablehnung
//   der Grund in text2).
// - Beschreibung (höchstens fünf Zeilen), Werte zweispaltig (Titel 96 px gedaempft, Werte Geist Mono 13), Hinweise
//   unter «Beim Installieren»: Symbol info in gedaempft, Text in text2; nur Entfernungen in warnung.
// - Fuss: ein Primärknopf (rechts, zuerst mit Tab erreichbar) und «Abbrechen», «Schliessen» oder «Fertig». Esc
//   schliesst. Kein Knopf hat von selbst den Fokus: Enter installiert nie aus Versehen.
// Alles aus dem Paket ist reiner Text. Keine Animation: Die Phasen wechseln ohne Übergang.
FocusScope {
    id: root

    property var bild: ({})
    // Zählt jedes neue Ansehen (Installer.qml): Dann hat kein Knopf mehr den Fokus, auch wenn vorher einer ihn hatte
    property int ansehenNummer: 0

    signal ausgefuehrt(string aktion)

    readonly property int rand: Theme.a6
    readonly property var _lage: bild?.lage ?? ({})

    Keys.onEscapePressed: root.ausgefuehrt("schliessen")

    onAnsehenNummerChanged: ruhe.forceActiveFocus()

    // Hält den Fokus, solange kein Knopf ihn hat (Tab führt von hier zum Primärknopf)
    Item {
        id: ruhe

        focus: true
    }

    function _tonFarbe(ton: string): color {
        return ton === "akzent" ? Theme.akzent : ton === "warnung" ? Theme.warnung : Theme.gedaempft;
    }

    Flickable {
        id: flick

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: fuss.top
        contentWidth: width
        contentHeight: spalte.implicitHeight + 2 * Theme.a5 + Theme.a1
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: spalte

            x: root.rand
            y: Theme.a5 + Theme.a1
            width: flick.width - 2 * root.rand
            spacing: Theme.a5

            // --- Kopf ---
            Item {
                width: parent.width
                height: Math.max(symbolFeld.height, kopfText.implicitHeight)

                Item {
                    id: symbolFeld

                    width: 64
                    height: 64
                    anchors.verticalCenter: parent.verticalCenter

                    // Aus dem Paket, nur im Laufzeitordner des Benutzers (zenos-installer); in Zielgrösse dekodiert
                    Image {
                        id: paketSymbol

                        anchors.fill: parent
                        visible: status === Image.Ready
                        source: root.bild?.symbol ? "file://" + root.bild.symbol : ""
                        sourceSize: Qt.size(64, 64)
                        asynchronous: true
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: paketSymbol.status !== Image.Ready
                        radius: Theme.radiusFenster
                        color: Theme.flaeche2

                        Symbol {
                            anchors.centerIn: parent
                            name: "paket"
                            groesse: 30
                            farbe: Theme.gedaempft
                        }
                    }
                }

                Column {
                    id: kopfText

                    anchors.left: symbolFeld.right
                    anchors.leftMargin: Theme.a4 + 2
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.bild?.name ?? ""
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.schriftAnzeige
                        font.pixelSize: Theme.groesseTitel
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 24
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: root.bild?.zusammenfassung ?? ""
                        textFormat: Text.PlainText
                        color: Theme.text2
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: text !== ""
                        width: parent.width
                        topPadding: 2
                        text: root.bild?.kennung ?? ""
                        textFormat: Text.PlainText
                        color: Theme.gedaempft
                        font.family: Theme.schriftMono
                        font.pixelSize: Theme.groesseKlein
                        elide: Text.ElideRight
                    }
                }
            }

            // --- Lage ---
            Column {
                visible: (root._lage.titel ?? "") !== ""
                width: parent.width
                spacing: Theme.a2

                Row {
                    spacing: 10

                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root._lage.symbol ?? "info"
                        groesse: 16
                        farbe: root._tonFarbe(root._lage.ton ?? "")
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._lage.titel ?? ""
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                    }
                }

                Text {
                    visible: text !== ""
                    width: parent.width
                    text: root._lage.satz ?? ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.45)
                    // Bei einer Ablehnung ist der Satz der Grund: lesbar in text2, sonst ruhig
                    color: root._lage.ton === "warnung" ? Theme.text2 : Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }
            }

            // --- Beschreibung aus dem Paket ---
            Text {
                visible: text !== ""
                width: parent.width
                text: root.bild?.beschreibung ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 5
                elide: Text.ElideRight
                lineHeightMode: Text.FixedHeight
                lineHeight: Math.round(font.pixelSize * 1.45)
                color: Theme.text2
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseLabel
            }

            // --- Werte zweispaltig ---
            Column {
                id: werte

                visible: (root.bild?.zeilen ?? []).length > 0
                width: parent.width
                spacing: Theme.a1

                Repeater {
                    model: root.bild?.zeilen ?? []

                    Row {
                        id: zeile

                        required property var modelData

                        spacing: Theme.a3

                        Text {
                            width: 96
                            text: zeile.modelData.titel
                            textFormat: Text.PlainText
                            color: Theme.gedaempft
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                        }

                        Text {
                            width: werte.width - 96 - Theme.a3
                            text: zeile.modelData.wert
                            textFormat: Text.PlainText
                            wrapMode: zeile.modelData.umbruch ? Text.WrapAnywhere : Text.NoWrap
                            elide: zeile.modelData.umbruch ? Text.ElideNone : Text.ElideRight
                            color: Theme.text
                            font.family: Theme.schriftMono
                            font.pixelSize: Theme.groesseLabel
                        }
                    }
                }
            }

            // --- Hinweise ---
            Column {
                visible: (root.bild?.hinweise ?? []).length > 0
                width: parent.width
                spacing: Theme.a2

                Abschnittstitel {
                    width: parent.width
                    text: "Beim Installieren"
                }

                Repeater {
                    model: root.bild?.hinweise ?? []

                    Item {
                        id: hinweis

                        required property var modelData

                        width: parent.width
                        height: hinweisText.implicitHeight

                        Symbol {
                            y: Math.round((hinweisText.lineHeight - groesse) / 2)
                            name: hinweis.modelData.warnung ? "warnung" : "info"
                            groesse: 14
                            farbe: hinweis.modelData.warnung ? Theme.warnung : Theme.gedaempft
                        }

                        Text {
                            id: hinweisText

                            x: 14 + 10
                            width: parent.width - x
                            text: hinweis.modelData.text
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            lineHeightMode: Text.FixedHeight
                            lineHeight: Math.round(font.pixelSize * 1.45)
                            color: hinweis.modelData.warnung ? Theme.warnung : Theme.text2
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                        }
                    }
                }
            }
        }
    }

    // --- Fuss ---
    Item {
        id: fuss

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 44 + 2 * Theme.a5

        Trenner {
            anchors.top: parent.top
            width: parent.width
        }

        // Von rechts: der Primärknopf zuerst (auch in der Tab-Reihenfolge), daneben der zweite
        Row {
            anchors.right: parent.right
            anchors.rightMargin: root.rand
            anchors.verticalCenter: parent.verticalCenter
            layoutDirection: Qt.RightToLeft
            spacing: Theme.a3

            Knopf {
                visible: root.bild?.primaer !== null && root.bild?.primaer !== undefined
                variante: "primaer"
                text: root.bild?.primaer?.text ?? ""
                symbol: root.bild?.primaer?.symbol ?? ""
                enabled: root.bild?.primaer?.aktiv === true
                onClicked: root.ausgefuehrt(root.bild?.primaer?.aktion ?? "")
            }

            Knopf {
                variante: "sekundaer"
                text: root.bild?.sekundaer?.text ?? "Schliessen"
                onClicked: root.ausgefuehrt(root.bild?.sekundaer?.aktion ?? "schliessen")
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: root.rand
            anchors.verticalCenter: parent.verticalCenter
            text: "Esc schliessen"
            textFormat: Text.PlainText
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }
    }
}
