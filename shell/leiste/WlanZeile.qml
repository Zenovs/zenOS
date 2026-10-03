pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten

// Zeile im WLAN-Abschnitt des System-Menüs (36 px, Radius 8, wie MenueEintrag): links Signal oder Symbol, Name,
// rechts ein Wert in Mono, Schloss, Haken bzw. Pfeil und bei gespeicherten Netzen ein kleines «x» zum Vergessen.
// Vergessen fragt einmal nach («Heimnetz vergessen?» in fehler), erst der zweite Klick löst aus (4 s gültig).
// Hauptfläche und «x» sind je ein Eintrag für Pfeile und Tab der Menükarte.
// Alle Texte als reiner Text: Netznamen kommen ungeprüft aus der Luft (wlan.js, anzeigeName).
Item {
    id: root

    property string text
    // Signalstufe 0–3 (WlanSymbol); -1 = stattdessen das Symbol «symbol»
    property int stufe: -1
    property string symbol
    property string wert
    property bool gesichert: false
    property bool haken: false
    // 0 ohne, 1 nach unten (aufklappen), 2 nach oben (zuklappen)
    property int pfeil: 0
    property bool klickbar: true
    // gedämpfter Text (z. B. verborgene Namen) bzw. die ganze Zeile blass (nicht verbindbar)
    property bool textGedaempft: false
    // Symbol gedämpft (z. B. keine Verbindung)
    property bool symbolGedaempft: false
    property bool blass: false
    property bool vergessbar: false
    property string frage: "Vergessen?"
    readonly property bool hatFokus: haupt.activeFocus || vergessenKnopf.activeFocus

    signal ausgeloest
    signal vergessen

    // Tastaturfokus auf die Hauptfläche (z. B. nach dem Neuaufbau der Liste)
    function fokussieren(): void {
        if (haupt.activeFocusOnTab)
            haupt.forceActiveFocus(Qt.TabFocusReason);
        else if (vergessenKnopf.activeFocusOnTab)
            vergessenKnopf.forceActiveFocus(Qt.TabFocusReason);
    }

    property bool _armed: false

    function _vergessenAusloesen(): void {
        if (!_armed) {
            _armed = true;
            entschaerfen.restart();
            return;
        }
        _armed = false;
        entschaerfen.stop();
        vergessen();
    }

    implicitWidth: 260
    implicitHeight: 36
    opacity: blass ? 0.45 : 1

    Item {
        id: haupt

        anchors.fill: parent
        activeFocusOnTab: root.klickbar && root.enabled

        Accessible.role: Accessible.MenuItem
        Accessible.name: root.text + (root.wert !== "" ? ", " + root.wert : "")
        Accessible.onPressAction: if (root.klickbar) root.ausgeloest()

        Keys.onPressed: event => {
            if (!event.isAutoRepeat && root.klickbar && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
                root.ausgeloest();
                event.accepted = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusChip
            color: Theme.flaeche2
            opacity: (maus.containsMouse && root.klickbar) || haupt.activeFocus || vergessenKnopf.activeFocus ? 1 : 0

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
            opacity: maus.pressed && root.klickbar ? 0.05 : 0
        }

        MouseArea {
            id: maus

            anchors.fill: parent
            hoverEnabled: true
            enabled: root.enabled
            cursorShape: root.klickbar ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.klickbar) root.ausgeloest()
        }
    }

    Row {
        id: links

        x: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 15
            height: 15

            WlanSymbol {
                visible: root.stufe >= 0
                anchors.fill: parent
                stufe: root.stufe
                groesse: 15
                farbe: root._armed ? Theme.fehler : root.symbolGedaempft ? Theme.gedaempft : Theme.text2
            }

            Symbol {
                visible: root.stufe < 0 && root.symbol !== ""
                anchors.fill: parent
                name: root.symbol
                groesse: 15
                farbe: root._armed ? Theme.fehler : root.symbolGedaempft ? Theme.gedaempft : Theme.text2
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, rechts.x - links.x - 25 - 8))
            text: root._armed ? root.frage : root.text
            textFormat: Text.PlainText
            color: root._armed ? Theme.fehler : root.textGedaempft ? Theme.gedaempft : Theme.text
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
            elide: Text.ElideRight
        }
    }

    Row {
        id: rechts

        anchors.right: parent.right
        anchors.rightMargin: root.vergessbar ? 4 : 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== "" && !root._armed
            text: root.wert
            textFormat: Text.PlainText
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }

        Symbol {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.gesichert
            name: "schloss"
            groesse: 12
            farbe: Theme.gedaempft
        }

        Symbol {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.haken
            name: "haken"
            groesse: 14
            farbe: Theme.akzent
        }

        Symbol {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.pfeil > 0
            rotation: root.pfeil === 2 ? 180 : 0
            name: "pfeil-runter"
            groesse: 14
            farbe: Theme.text2
        }

        // Vergessen: 24 px, eigener Eintrag für die Tastatur
        Item {
            id: vergessenKnopf

            anchors.verticalCenter: parent.verticalCenter
            visible: root.vergessbar
            width: 24
            height: 24
            activeFocusOnTab: visible && root.enabled

            Accessible.role: Accessible.Button
            Accessible.name: root._armed ? root.frage : root.text + " vergessen"
            Accessible.onPressAction: root._vergessenAusloesen()

            Keys.onPressed: event => {
                if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
                    root._vergessenAusloesen();
                    event.accepted = true;
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusXs
                color: Theme.text
                opacity: xMaus.pressed ? 0.09 : xMaus.containsMouse ? 0.05 : 0
            }

            Symbol {
                anchors.centerIn: parent
                name: "x"
                groesse: 12
                farbe: root._armed ? Theme.fehler : Theme.gedaempft
            }

            Fokusrahmen {
                eckenRadius: Theme.radiusXs
            }

            MouseArea {
                id: xMaus

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root._vergessenAusloesen()
            }

            onActiveFocusChanged: if (!activeFocus && !xMaus.containsMouse) root._armed = false
        }
    }

    // Nachfrage verfällt nach 4 s
    Timer {
        id: entschaerfen

        interval: 4000
        onTriggered: root._armed = false
    }
}
