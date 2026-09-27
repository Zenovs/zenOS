pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.theme

// Bildmarke «Offene Stelle»: ein Bogen, optional mit Punkt.
// Ohne Punkt: der Bogen aus der Leiste (24er ViewBox), auch als Wasserzeichen.
// Mit Punkt: die Bildmarke aus assets/zeichen-platzhalter.svg (64er ViewBox).
// strichbreite gilt in Einheiten der 24er ViewBox.
Item {
    id: root

    property real groesse: 18
    property color farbe: Theme.akzent
    property color punktFarbe: farbe
    property bool mitPunkt: false
    property real strichbreite: mitPunkt ? 2.625 : 2.2

    implicitWidth: groesse
    implicitHeight: groesse

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            readonly property real einheit: root.groesse / (root.mitPunkt ? 64 : 24)

            scale: Qt.size(einheit, einheit)
            strokeColor: root.farbe
            strokeWidth: root.strichbreite * root.groesse / 24
            fillColor: Theme.durchsichtig
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: root.mitPunkt ? "M53.25 26.31A22 22 0 1 1 37.69 10.75" : "M20.6 9.2A9 9 0 1 1 14.8 3.4"
            }
        }

        ShapePath {
            readonly property real einheit: root.groesse / 64

            scale: Qt.size(einheit, einheit)
            strokeColor: Theme.durchsichtig
            strokeWidth: 0
            fillColor: root.mitPunkt ? root.punktFarbe : Theme.durchsichtig

            PathSvg {
                path: "M42.96 16.44a4.6 4.6 0 1 0 9.2 0a4.6 4.6 0 1 0 -9.2 0z"
            }
        }
    }
}
