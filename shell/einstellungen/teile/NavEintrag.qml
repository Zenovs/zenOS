import QtQuick
import qs.theme
import qs.komponenten

// Eintrag der Navigation (34 px, Radius 8). Mit Punkt (Modi), eingerückt ohne Punkt, oder mit
// Symbol und gedämpft («Neuer Modus»). Gewählt: Fläche flaeche2.
Item {
    id: root

    property string text
    property bool gewaehlt: false
    property bool mitPunkt: false
    property color punktFarbe: Theme.akzent
    property string symbol
    property bool gedaempft: false

    signal clicked

    // In einer scrollbaren Navigation (Flickable) den gewählten oder fokussierten Eintrag ins Bild holen
    function _insBild(): void {
        const f = _flickable(parent);
        if (!f || f.height <= 0 || !visible)
            return;
        const y = mapToItem(f.contentItem, 0, 0).y;
        const rand = 8;
        // nach oben mit Platz für einen Abschnittstitel darüber
        if (y - rand < f.contentY)
            f.contentY = Math.max(0, y - 44);
        else if (y + height + rand > f.contentY + f.height)
            f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, y + height + rand - f.height));
    }

    function _flickable(item: var): var {
        let f = item;
        while (f && (f.contentY === undefined || f.flickableDirection === undefined))
            f = f.parent;
        return f ?? null;
    }

    implicitHeight: 34
    implicitWidth: 236
    activeFocusOnTab: true

    onGewaehltChanged: {
        if (gewaehlt)
            Qt.callLater(_insBild);
    }
    onActiveFocusChanged: {
        if (activeFocus)
            _insBild();
    }
    Component.onCompleted: {
        if (gewaehlt)
            Qt.callLater(_insBild);
    }

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: clicked()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: Theme.flaeche2
        opacity: root.gewaehlt ? 1 : maus.containsMouse ? 0.5 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Row {
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Item {
            visible: root.mitPunkt || root.symbol.length > 0
            width: root.mitPunkt ? 8 : 12
            height: 12
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                visible: root.mitPunkt
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: root.punktFarbe
            }

            Symbol {
                visible: !root.mitPunkt
                anchors.centerIn: parent
                name: root.symbol
                groesse: 12
                strichbreite: 2
                farbe: root.gedaempft ? Theme.gedaempft : Theme.text
            }
        }

        Text {
            // ohne Punkt und Symbol eingerückt (wie Entwurf 2: 28 px)
            leftPadding: root.mitPunkt || root.symbol.length > 0 ? 0 : 18
            width: root.width - 20 - (root.mitPunkt || root.symbol.length > 0 ? 22 : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.gedaempft ? Theme.gedaempft : Theme.text
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
            elide: Text.ElideRight
        }
    }

    Fokusrahmen {
        eckenRadius: Theme.radiusChip
    }

    MouseArea {
        id: maus

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
