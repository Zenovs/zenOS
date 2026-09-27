//@ pragma IconTheme Adwaita
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

// Notfall-Login. zenos-greeter startet ihn, wenn greeter.qml nicht lädt (z. B. ein Fehler in einem Dienst
// unter shell/dienste). Absichtlich ohne qs.*-Module: nur Quickshell selbst. Farben kommen aus
// theme/tokens.json (dunkel), ist die Datei unlesbar, aus der Systempalette.
ShellRoot {
    id: root

    property var _farben: ({})
    property string _akzent: ""
    property string schrift: "sans-serif"
    readonly property color grund: _farben.grund ?? system.window
    readonly property color flaeche: _farben.flaeche ?? system.base
    readonly property color text: _farben.text ?? system.windowText
    readonly property color gedaempft: _farben.gedaempft ?? system.placeholderText
    readonly property color rand: _farben.eingabeRand ?? system.mid
    readonly property color akzent: _akzent.length > 0 ? _akzent : system.highlight
    readonly property color fehler: _farben.fehler ?? system.highlight

    readonly property string code: Quickshell.env("ZENOS_CODE") || "/opt/zenos"
    property string konto: ""
    property string meldung: Greetd.available ? "" : "Kein Anmeldedienst (greetd) erreichbar."
    property bool meldungFehler: false
    property string frage: ""
    property bool frageSichtbar: false
    property bool _antwortBereit: false
    readonly property bool beschaeftigt: Greetd.state !== GreetdState.Inactive && frage.length === 0

    SystemPalette {
        id: system
    }

    FileView {
        id: tokens

        // Pfad über den Code-Ordner: ausserhalb des eigenen Ordners löst Quickshell relative URLs nicht auf
        path: root.code + "/shell/theme/tokens.json"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: passwd

        path: "/etc/passwd"
        blockLoading: true
        printErrors: false
    }

    function _laden(): void {
        try {
            const t = JSON.parse(tokens.text());
            const d = t?.farben?.dunkel ?? {};
            const s = t?.farben?.signal?.fehler?.dunkel;
            _farben = Object.assign({}, d, s ? {
                fehler: s
            } : {});
            const name = t?.farben?.standardAkzent ?? "";
            _akzent = t?.farben?.akzente?.[name]?.dunkel ?? "";
            schrift = t?.schrift?.text ?? schrift;
        } catch (e) {
            console.warn("Notfall-Login: tokens.json nicht lesbar, Systemfarben");
        }
        const menschen = [];
        for (const line of (passwd.text() ?? "").split("\n")) {
            const f = line.split(":");
            if (f.length < 7 || f[0].length === 0)
                continue;
            const uid = Number(f[2]);
            if (Number.isInteger(uid) && uid >= 1000 && uid <= 59999 && f[6].trim().length > 0 && !/(^|\/)(nologin|false)$/.test(f[6].trim()))
                menschen.push(f[0]);
        }
        if (menschen.length === 1)
            konto = menschen[0];
    }

    function absenden(): void {
        if (frage.length > 0) {
            frage = "";
            Greetd.respond(passwort.text);
            passwort.clear();
            return;
        }
        if (beschaeftigt)
            return;
        if (!Greetd.available) {
            meldung = "Kein Anmeldedienst (greetd) erreichbar.";
            meldungFehler = true;
            return;
        }
        const benutzer = name.text.trim();
        if (benutzer.length === 0) {
            name.forceActiveFocus();
            return;
        }
        meldung = "";
        _antwortBereit = true;
        Greetd.createSession(benutzer);
    }

    Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (responseRequired) {
                if (root._antwortBereit && !echoResponse) {
                    root._antwortBereit = false;
                    Greetd.respond(passwort.text);
                    passwort.clear();
                    return;
                }
                root._antwortBereit = false;
                root.frage = message.trim().length > 0 ? message.trim() : "Antwort";
                root.frageSichtbar = echoResponse;
                passwort.forceActiveFocus();
            } else if (message.trim().length > 0) {
                root.meldung = message.trim();
                root.meldungFehler = error;
            }
        }

        function onAuthFailure(message: string): void {
            console.warn("Notfall-Login: Anmeldung abgelehnt:", message);
            root._antwortBereit = false;
            root.frage = "";
            root.meldung = "Benutzername oder Passwort stimmt nicht.";
            root.meldungFehler = true;
            passwort.clear();
            passwort.forceActiveFocus();
        }

        function onError(message: string): void {
            root._antwortBereit = false;
            root.frage = "";
            root.meldung = "Die Anmeldung ist fehlgeschlagen (greetd: " + message + ").";
            root.meldungFehler = true;
            passwort.clear();
        }

        function onReadyToLaunch(): void {
            root.meldung = "Sitzung startet …";
            root.meldungFehler = false;
            Greetd.launch([root.code + "/scripts/bin/zenos-sitzung"], ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=zenos", "XDG_CURRENT_DESKTOP=labwc:wlroots"]);
        }
    }

    PanelWindow {
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusionMode: ExclusionMode.Ignore
        color: root.grund

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "zenos-greeter"

        Column {
            anchors.centerIn: parent
            width: 380
            spacing: 10

            Text {
                text: "zenOS"
                color: root.text
                font.family: root.schrift
                font.pixelSize: 28
            }

            Text {
                width: parent.width
                text: "Der Login konnte nicht vollständig geladen werden. Anmelden geht trotzdem; danach zeigt «zen doctor» den Grund."
                color: root.gedaempft
                font.family: root.schrift
                font.pixelSize: 13
                wrapMode: Text.Wrap
                bottomPadding: 14
            }

            Text {
                text: "Benutzername"
                color: root.gedaempft
                font.family: root.schrift
                font.pixelSize: 13
            }

            Rectangle {
                width: parent.width
                height: 44
                radius: 10
                color: root.flaeche
                border.width: 1
                border.color: name.activeFocus ? root.akzent : root.rand

                TextInput {
                    id: name

                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.konto
                    color: root.text
                    font.family: root.schrift
                    font.pixelSize: 15
                    clip: true
                    readOnly: root.beschaeftigt
                    onAccepted: passwort.forceActiveFocus()
                }
            }

            Text {
                text: root.frage.length > 0 ? root.frage : "Passwort"
                color: root.gedaempft
                font.family: root.schrift
                font.pixelSize: 13
            }

            Rectangle {
                width: parent.width
                height: 44
                radius: 10
                color: root.flaeche
                border.width: 1
                border.color: root.meldungFehler && root.meldung.length > 0 ? root.fehler : passwort.activeFocus ? root.akzent : root.rand

                TextInput {
                    id: passwort

                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.text
                    font.family: root.schrift
                    font.pixelSize: 15
                    clip: true
                    echoMode: root.frage.length > 0 && root.frageSichtbar ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    passwordMaskDelay: 0
                    readOnly: root.beschaeftigt
                    focus: true
                    onAccepted: root.absenden()
                }
            }

            Text {
                width: parent.width
                height: Math.max(implicitHeight, 20)
                text: root.meldung
                color: root.meldungFehler ? root.fehler : root.gedaempft
                font.family: root.schrift
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
        }
    }

    Component.onCompleted: {
        _laden();
        if (konto.length === 0)
            name.forceActiveFocus();
        else
            passwort.forceActiveFocus();
    }
}
