pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.theme
import "symbole.js" as Symbole

// Strich-Symbol aus Entwurf 2 (24er ViewBox, runde Enden).
// groesse in px, strichbreite in Einheiten der 24er ViewBox (wie stroke-width im SVG).
Item {
    id: root

    property string name
    property color farbe: Theme.text
    property real groesse: 16
    property real strichbreite: _daten?.strich ?? 1.8

    readonly property var _daten: Symbole.daten[name] ?? null
    readonly property bool _gefuellt: _daten?.gefuellt === true

    implicitWidth: groesse
    implicitHeight: groesse

    Component.onCompleted: if (name.length > 0 && !_daten) console.warn("Symbol: unbekannter Name", name)

    Shape {
        anchors.fill: parent
        visible: root._daten !== null
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            scale: Qt.size(root.groesse / 24, root.groesse / 24)
            strokeColor: root._gefuellt ? Theme.durchsichtig : root.farbe
            strokeWidth: root._gefuellt ? 0 : root.strichbreite * root.groesse / 24
            fillColor: root._gefuellt ? root.farbe : Theme.durchsichtig
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root._daten?.d ?? ""
            }
        }
    }
}
