pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.theme

// Bildmarke «Zwei Steine» (docs/bildmarke.md): ein Kiesel, diagonal geteilt, gezeichnet aus den Pfaden in
// Theme (tokens.json → zeichen). Unter Theme.zeichenPixelUnter px gilt die Pixel-Variante. Nur der untere
// Stein trägt Farbe; bei einem neuen Akzent blendet er über, sonst bewegt sich nichts.
Item {
    id: root

    property real groesse: 32
    property color obenFarbe: Theme.text
    // Akzent des unteren Steins (Name aus tokens.json), Standard: aktiver Modus
    property string akzent: Theme.akzentName
    // Farbe des unteren Steins. Wer sie selbst setzt, verzichtet auf das Überblenden.
    property color fokusFarbe: Qt.tint(Theme.akzentFarbe(_von), Qt.alpha(Theme.akzentFarbe(_ziel), _anteil))
    // Beide Steine in obenFarbe, z. B. mit obenFarbe: Theme.gedaempft
    property bool einfarbig: false

    readonly property bool pixel: groesse < Theme.zeichenPixelUnter
    readonly property real _einheit: groesse / (pixel ? Theme.zeichenPixelRaster : Theme.zeichenRaster)

    // Überblendet wird zwischen zwei Akzentnamen, nicht zwischen Farben: So stellt hell/dunkel beide Enden
    // sofort um, und nur ein neuer Akzent bewegt etwas. Qt.tint legt den neuen Akzent mit _anteil über den alten.
    property string _von
    property string _ziel
    property real _anteil: 1

    onAkzentChanged: {
        _von = _ziel;
        _ziel = akzent;
        if (_von !== _ziel) {
            _anteil = 0;
            blende.restart();
        }
    }

    Component.onCompleted: {
        _von = akzent;
        _ziel = akzent;
    }

    implicitWidth: groesse
    implicitHeight: groesse

    NumberAnimation {
        id: blende

        target: root
        property: "_anteil"
        from: 0
        to: 1
        duration: Theme.dauerMax
        easing.type: Theme.kurve
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            scale: Qt.size(root._einheit, root._einheit)
            strokeWidth: -1
            strokeColor: Theme.durchsichtig
            fillColor: root.obenFarbe

            PathSvg {
                path: root.pixel ? Theme.zeichenPixelOben : Theme.zeichenOben
            }
        }

        ShapePath {
            scale: Qt.size(root._einheit, root._einheit)
            strokeWidth: -1
            strokeColor: Theme.durchsichtig
            fillColor: root.einfarbig ? root.obenFarbe : root.fokusFarbe

            PathSvg {
                path: root.pixel ? Theme.zeichenPixelUnten : Theme.zeichenUnten
            }
        }
    }
}
