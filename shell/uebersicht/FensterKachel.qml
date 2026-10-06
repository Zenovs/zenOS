import QtQuick
import qs.theme
import qs.komponenten

// Kachel der Fensterübersicht (Uebersicht.qml): Karte wie die Menüs (flaeche, Rahmen linie2, Radius 12) mit
// App-Symbol 56 px, darunter App-Name (Geist 14, text) und Fenstertitel (Geist 12, gedaempft, höchstens zwei
// Zeilen). Ohne Symbol der Anfangsbuchstabe auf flaeche2. Keine Vorschaubilder: labwc 0.9.3 gibt einzelne Fenster
// nicht heraus. Gewählt: flaeche2 (120 ms), per Tastatur zusätzlich der Fokusrahmen. Das beim Öffnen aktive Fenster
// trägt einen Akzentpunkt wie in der App-Leiste. Oben links in Mono 12: «minimiert» oder «Vollbild», bei mehreren
// Bildschirmen auch der Name eines anderen Bildschirms. Während einer Freigabe steht «Titel verborgen».
Item {
    id: root

    // Eintrag aus liste.mjs: {fenster: Toplevel, app: {name, symbol, buchstabe, appId}}
    property var eintrag: null
    property bool aktiv: false
    property bool gewaehlt: false
    // Auswahl per Tastatur: Fokusrahmen
    property bool fokus: false
    property bool titelVerborgen: false
    // Name des Bildschirms, wenn das Fenster nicht auf dem Bildschirm der Übersicht liegt; sonst leer
    property string bildschirm: ""

    // Maus bewegt sich über der Kachel bzw. Klick
    signal gezeigt
    signal ausgefuehrt

    readonly property bool minimiert: eintrag?.fenster?.minimized === true
    readonly property bool vollbild: eintrag?.fenster?.fullscreen === true
    readonly property string titel: titelVerborgen ? "Titel verborgen" : String(eintrag?.fenster?.title ?? "")
    readonly property string merkmale: [minimiert ? "minimiert" : vollbild ? "Vollbild" : "", bildschirm].filter(m => m !== "").join(" · ")

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
    Accessible.name: String(eintrag?.app?.name ?? "") + (titel !== "" ? " – " + titel : "")
    Accessible.description: merkmale
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
    Rectangle {
        id: karte

        anchors.fill: parent
        opacity: root._ein
        transform: Translate {
            y: (1 - root._ein) * Theme.bewegungVersatz
        }
        radius: Theme.radiusFenster
        color: root.gewaehlt ? Theme.flaeche2 : Theme.flaeche
        border.width: 1
        border.color: Theme.linie2

        Behavior on color {
            ColorAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }

        Text {
            id: merkmalText

            visible: root.merkmale !== ""
            x: Theme.a3
            y: Theme.a2
            width: parent.width - 2 * Theme.a3 - Theme.a3
            text: root.merkmale
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }

        // Aktives Fenster: Akzentpunkt wie in der App-Leiste
        Rectangle {
            visible: root.aktiv
            x: parent.width - Theme.a3 - width
            y: Theme.a3
            width: 5
            height: 5
            radius: width / 2
            color: Theme.akzent
        }

        Item {
            id: symbolFeld

            x: Math.round((parent.width - width) / 2)
            // unter der Zeile mit «minimiert» bzw. «Vollbild»
            y: Theme.a5 + Theme.a1
            width: 56
            height: 56

            // Symbol aus dem Icon-Theme; asynchron, in Zielgrösse dekodiert
            Image {
                id: bild

                anchors.fill: parent
                visible: status === Image.Ready
                source: root.eintrag?.app?.symbol ?? ""
                sourceSize: Qt.size(56, 56)
                asynchronous: true
                smooth: true
                fillMode: Image.PreserveAspectFit
            }

            // Ohne Symbol (oder nicht ladbar): Anfangsbuchstabe auf einer ruhigen Fläche
            Rectangle {
                anchors.fill: parent
                visible: bild.status === Image.Null || bild.status === Image.Error
                radius: Theme.radiusFenster
                color: root.gewaehlt ? Theme.flaeche : Theme.flaeche2

                Text {
                    anchors.centerIn: parent
                    text: root.eintrag?.app?.buchstabe ?? ""
                    textFormat: Text.PlainText
                    color: Theme.text2
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseGross
                    font.weight: Font.Medium
                }
            }
        }

        Text {
            id: name

            x: Theme.a3
            y: symbolFeld.y + symbolFeld.height + Theme.a3
            width: parent.width - 2 * Theme.a3
            horizontalAlignment: Text.AlignHCenter
            text: root.eintrag?.app?.name ?? ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
            font.weight: Font.Medium
        }

        Text {
            x: Theme.a3
            y: name.y + name.height + 2
            width: parent.width - 2 * Theme.a3
            horizontalAlignment: Text.AlignHCenter
            text: root.titel
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseKlein
        }

        Fokusrahmen {
            aktiv: root.fokus
            eckenRadius: Theme.radiusFenster
        }
    }

    MouseArea {
        property point zuletzt: Qt.point(-1, -1)

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Nur echte Mausbewegungen wählen aus (wie im Befehlsfeld): Erscheint eine Kachel unter dem ruhenden
        // Zeiger, bleibt die Auswahl der Tastatur. Rechts- und Mittelklick gehen an die Fläche dahinter (schliessen).
        onPositionChanged: mouse => {
            const p = mapToItem(null, mouse.x, mouse.y);
            if (zuletzt.x >= 0 && (Math.abs(p.x - zuletzt.x) >= 1 || Math.abs(p.y - zuletzt.y) >= 1))
                root.gezeigt();
            zuletzt = p;
        }
        onExited: zuletzt = Qt.point(-1, -1)
        onClicked: root.ausgefuehrt()
    }
}
