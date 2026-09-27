pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.dienste
import qs.komponenten

// Raster-Menü unter dem Raster-Knopf der Leiste: alle Raster, das aktive mit Haken.
Menuekarte {
    id: root

    breite: 240

    readonly property var _liste: Array.isArray(Raster.liste) ? Raster.liste : Array.from(Raster.liste ?? [])

    Item {
        width: parent.width
        height: 30

        Abschnittstitel {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Raster"
        }
    }

    Repeater {
        model: root._liste

        MenueEintrag {
            required property var modelData
            readonly property string rasterId: typeof modelData === "string" ? modelData : String(modelData?.id ?? "")

            width: parent ? parent.width : 0
            symbolPlatz: false
            text: typeof modelData === "string" ? modelData : String(modelData?.name ?? rasterId)
            gewaehlt: rasterId === Raster.aktivId
            onAusgeloest: {
                root.schliessen();
                if (rasterId !== "" && rasterId !== Raster.aktivId)
                    Raster.setzen(rasterId);
            }
        }
    }

    Item {
        visible: root._liste.length === 0
        width: parent.width
        height: 36

        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Noch keine Raster"
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
        }
    }

    Item {
        width: parent.width
        height: Theme.a2 + 1

        Trenner {
            y: Theme.a1
            width: parent.width
        }
    }

    MenueEintrag {
        width: parent.width
        symbolPlatz: false
        text: "Raster bearbeiten"
        onAusgeloest: {
            root.schliessen();
            Aktionen.einstellungen("raster");
        }
    }
}
