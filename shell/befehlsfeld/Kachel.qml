import QtQuick
import qs.theme
import qs.komponenten

// Kachel der App-Übersicht im Befehlsfeld: Symbol 40 px, darunter der Name (höchstens zwei Zeilen, sonst
// gekürzt). Die Auswahl ist mit flaeche2 hinterlegt wie eine Zeile im Befehlsfeld; kommt sie von der Tastatur,
// zeigt der Fokusrahmen sie zusätzlich. Füllt ihre Zelle, die Fläche liegt 3 px innerhalb.
Item {
    id: root

    // {name, icon, buchstabe, webApp} aus Befehlsfeld._apps
    property var app: ({})
    property bool gewaehlt: false
    // Auswahl per Tastatur: Fokusrahmen
    property bool fokus: false
    // Ein Wort des Namens passt nicht in eine Zeile (z. B. «Zeichenprogramm»): einzeilig gekürzt statt mitten
    // im Wort umbrochen. Misst AppRaster (eine Schriftmetrik für alle Kacheln).
    property bool einzeilig: false
    // Breite der Namenszeile (für AppRaster)
    readonly property real namenBreite: width - 6 - 16
    // false, solange Karte und Kacheln einblenden: Der Zeiger wählt dann nichts aus (die Szene bewegt sich unter
    // ihm, eine Kachel unter dem ruhenden Zeiger nähme sonst der Tastatur die Auswahl weg)
    property bool zeigerWaehlt: true

    // Maus bewegt sich über der Kachel bzw. Klick
    signal gezeigt
    signal ausgefuehrt

    // Einblenden: 0 → 1 (Deckkraft, Versatz nach oben). Ruhend 1, also sofort sichtbar.
    property real _ein: 1

    // Startet das Einblenden nach verzoegerung ms (dauert Theme.dauerKurz)
    function einblenden(verzoegerung: int): void {
        einblendung.stop();
        pause.duration = Math.max(0, verzoegerung);
        _ein = 0;
        einblendung.start();
    }

    Accessible.role: Accessible.Button
    Accessible.name: app?.name ?? ""
    Accessible.description: app?.webApp === true ? "Web-App" : "App"
    Accessible.onPressAction: ausgefuehrt()

    SequentialAnimation {
        id: einblendung

        PauseAnimation {
            id: pause

            duration: 0
        }

        NumberAnimation {
            target: root
            property: "_ein"
            to: 1
            duration: Theme.dauerKurz
            easing.type: Theme.kurve
        }
    }

    // Nur Deckkraft und Verschiebung animieren (keine Ebene, kein Effekt): flüssig auch auf dem Pi
    Item {
        id: flaeche

        anchors.fill: parent
        anchors.margins: 3
        opacity: root._ein
        transform: Translate {
            y: (1 - root._ein) * Theme.bewegungVersatz
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusFeld
            color: root.gewaehlt ? Theme.flaeche2 : Theme.durchsichtig
        }

        Item {
            id: symbolFeld

            x: Math.round((parent.width - width) / 2)
            y: 12
            width: 40
            height: 40

            // Symbol aus dem Icon-Theme; asynchron, in Zielgrösse dekodiert
            Image {
                id: bild

                anchors.fill: parent
                visible: status === Image.Ready
                source: root.app?.icon ?? ""
                sourceSize: Qt.size(40, 40)
                asynchronous: true
                smooth: true
                fillMode: Image.PreserveAspectFit
            }

            // Ohne Symbol (oder nicht ladbar): Anfangsbuchstabe auf einer ruhigen Fläche
            Rectangle {
                anchors.fill: parent
                visible: bild.status === Image.Null || bild.status === Image.Error
                radius: Theme.radiusFeld
                color: root.gewaehlt ? Theme.flaeche : Theme.flaeche2

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
        }

        Text {
            x: 8
            y: symbolFeld.y + symbolFeld.height + 8
            width: parent.width - 16
            horizontalAlignment: Text.AlignHCenter
            text: root.app?.name ?? ""
            textFormat: Text.PlainText
            color: Theme.text
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
            wrapMode: root.einzeilig ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: root.einzeilig ? 1 : 2
            elide: Text.ElideRight
        }

        Fokusrahmen {
            aktiv: root.fokus
            eckenRadius: Theme.radiusFeld
        }
    }

    MouseArea {
        property point zuletzt: Qt.point(-1, -1)

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Nur echte Mausbewegungen wählen aus (wie Eintrag.qml): Erscheint eine Kachel unter dem ruhenden
        // Zeiger, bleibt die Auswahl der Tastatur. Verglichen wird mit 1 px Spielraum: Während des Aufgleitens
        // liefert Qt die Position bei jedem Bild neu, zurückgerechnet durch die Skalierung mit Rundungsfehlern.
        onPositionChanged: mouse => {
            const p = mapToItem(null, mouse.x, mouse.y);
            if (root.zeigerWaehlt && zuletzt.x >= 0 && (Math.abs(p.x - zuletzt.x) >= 1 || Math.abs(p.y - zuletzt.y) >= 1))
                root.gezeigt();
            zuletzt = p;
        }
        onExited: zuletzt = Qt.point(-1, -1)
        onClicked: root.ausgefuehrt()
    }
}
