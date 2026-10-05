pragma ComponentBehavior: Bound

import QtQuick
import qs.theme

// Eingabefeld nach Entwurf 2 (44 px, Radius 10, 1-px-Rahmen), auch als Passwortfeld.
// Im Passwortmodus wird der Text nie geloggt; nach dem Weiterreichen mit leeren() löschen.
Item {
    id: root

    property alias text: input.text
    property string platzhalter
    property bool passwort: false
    property bool fehler: false
    property alias nurLesen: input.readOnly
    property alias maximaleLaenge: input.maximumLength
    property alias feld: input
    property int schriftGroesse: 15
    property color flaechenFarbe: Theme.flaeche

    signal accepted
    // Bei jedem Tastendruck, bevor das Feld ihn sieht. Setzt der Empfänger event.accepted = true, ist die Taste
    // verworfen: Nichts wird getippt, auch Return und Rücktaste wirken nicht. Die Sperre verwirft so die Taste, die
    // einen dunklen Bildschirm weckt.
    signal vorTaste(var event)

    // Über text = "": Das leert auch den Rückgängig-Verlauf von TextInput, in dem clear() die getippten Zeichen
    // (auch im Passwortmodus) weiter im Speicher liesse. clear() danach bricht nur noch eine Vorschau (preedit) ab.
    function leeren(): void {
        input.text = "";
        input.clear();
    }

    function fokussieren(): void {
        input.forceActiveFocus();
    }

    implicitHeight: 44
    implicitWidth: 240
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusFeld
        color: root.flaechenFarbe
        border.width: 1
        border.color: root.fehler ? Theme.fehler : input.activeFocus ? Theme.akzent : mouse.containsMouse ? Theme.gedaempft : Theme.eingabeRand

        Behavior on border.color {
            ColorAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Text {
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        visible: input.text.length === 0 && input.preeditText.length === 0
        text: root.platzhalter
        color: Theme.gedaempft
        font: input.font
        elide: Text.ElideRight
    }

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.text
        selectionColor: Qt.alpha(Theme.akzent, 0.35)
        selectedTextColor: Theme.text
        font.family: Theme.schriftText
        font.pixelSize: root.schriftGroesse
        selectByMouse: true
        activeFocusOnTab: true
        echoMode: root.passwort ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        passwordMaskDelay: 0
        inputMethodHints: root.passwort ? (Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase) : Qt.ImhNone
        onAccepted: root.accepted()

        // Ruhig: Der Cursor steht still (ohne Delegate blinkt er im Takt von Qt). Qt blendet einen
        // eigenen Delegate nicht selbst aus, deshalb die Bindung an cursorVisible (ohne Fokus, nurLesen).
        cursorDelegate: Rectangle {
            width: 1
            color: Theme.text
            visible: input.cursorVisible
        }

        // Super-Kombinationen tippen nichts. In der Sperre wertet labwc seine Kürzel nicht aus und reicht
        // die Taste weiter; Qt fügt den Buchstaben von Super+L sonst ein (es filtert nur Ctrl).
        // AltGr (ISO_Level3) ist für Qt kein Meta, Zeichen wie @ und ~ kommen weiter an.
        Keys.onPressed: event => {
            root.vorTaste(event);
            if (event.accepted)
                return;
            if (event.modifiers & Qt.MetaModifier)
                event.accepted = true;
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.IBeamCursor
    }
}
