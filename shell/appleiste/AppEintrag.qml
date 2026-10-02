import QtQuick
import qs.theme

// Eintrag der App-Leiste: Symbol 40 px in einer Zelle von 48 px (Zeigen hinterlegt mit flaeche2, Radius 10),
// rechts daneben der Akzentpunkt der aktiven App, unten rechts am Symbol die Anzahl der Fenster ab zwei. Ohne
// Symbol der Anfangsbuchstabe auf flaeche2 wie in der App-Übersicht. Keine Bewegung pro Eintrag.
Item {
    id: root

    // {schluessel, appId, name, symbol, buchstabe, fenster} aus AppLeiste.gruppen
    property var app: null
    property bool aktiv: false
    // Breite des Streifens rechts neben der Zelle (Innenabstand der Karte); der Punkt steht darin mittig
    property int punktStreifen: Theme.a3
    // false, solange die Karte hereingleitet: Einträge, die unter dem ruhenden Zeiger durchgleiten, gelten nicht
    // als gezeigt (sonst blitzt ihre Beschriftung auf)
    property bool zeigbar: true

    signal gewaehlt
    signal gezeigt(bool ja)

    readonly property int anzahl: app?.fenster?.length ?? 0
    readonly property bool zeigt: maus.containsMouse && zeigbar

    implicitWidth: 48
    implicitHeight: 48

    Accessible.role: Accessible.Button
    Accessible.name: app?.name ?? ""
    Accessible.description: anzahl > 1 ? anzahl + " Fenster" : "App"
    Accessible.onPressAction: gewaehlt()

    onZeigtChanged: gezeigt(zeigt)

    // Zeigen und Drücken (120 ms wie überall)
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusFeld
        color: root.zeigt ? Theme.flaeche2 : Theme.durchsichtig

        Behavior on color {
            ColorAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Item {
        id: symbolFeld

        anchors.centerIn: parent
        width: 40
        height: 40
        // Drücken rückt das Symbol nicht, es dunkelt nur leicht ab (keine Bewegung pro Symbol)
        opacity: maus.pressed ? 0.8 : 1

        // Symbol aus dem Icon-Theme; asynchron, in Zielgrösse dekodiert
        Image {
            id: bild

            anchors.fill: parent
            visible: status === Image.Ready
            source: root.app?.symbol ?? ""
            sourceSize: Qt.size(40, 40)
            asynchronous: true
            smooth: true
            fillMode: Image.PreserveAspectFit
        }

        // Ohne Symbol (oder nicht ladbar): Anfangsbuchstabe auf einer ruhigen Fläche. Beim Zeigen geht sie in der
        // Hinterlegung auf (gleiche Farbe), statt als Rahmen darin zu stehen.
        Rectangle {
            anchors.fill: parent
            visible: bild.status === Image.Null || bild.status === Image.Error
            radius: Theme.radiusFeld
            color: Theme.flaeche2

            Text {
                anchors.centerIn: parent
                text: root.app?.buchstabe ?? ""
                color: Theme.text2
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseGross
                font.weight: Font.Medium
                textFormat: Text.PlainText
            }
        }

        // Mehrere Fenster: kleine Zahl unten rechts am Symbol (Fläche der Karte, Rahmen wie Chips)
        Rectangle {
            visible: root.anzahl > 1
            x: parent.width - width + 6
            y: parent.height - height + 6
            width: Math.max(height, zahl.implicitWidth + 8)
            height: 18
            radius: Theme.radiusPille
            color: Theme.flaeche
            border.width: 1
            border.color: Theme.linie2

            Text {
                id: zahl

                anchors.centerIn: parent
                text: root.anzahl > 9 ? "9+" : String(root.anzahl)
                color: Theme.text2
                font.family: Theme.schriftMono
                font.pixelSize: Theme.groesseKlein
                textFormat: Text.PlainText
            }
        }
    }

    // Aktive App: Akzentpunkt rechts neben der Zelle, zum Bildschirmrand hin
    Rectangle {
        visible: root.aktiv
        width: 5
        height: 5
        radius: width / 2
        x: root.width + Math.round((root.punktStreifen - width) / 2)
        y: Math.round((root.height - height) / 2)
        color: Theme.akzent
    }

    MouseArea {
        id: maus

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.gewaehlt()
    }
}
