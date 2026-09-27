pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste

// Kurze Hinweise (Toast) unten in der Mitte, z. B. «Farbe kopiert».
// Auslöser: Oberflaeche.hinweis(text) oder zenos-ipc hinweis zeigen "<text>".
// Das Fenster ist klickdurchlässig und nimmt nie den Tastaturfokus.
Scope {
    id: root

    function zeigen(text: string): void {
        const t = (text ?? "").trim();
        if (t.length === 0)
            return;
        toast.zeigen(t.length > 120 ? t.slice(0, 119) + "…" : t);
    }

    Connections {
        target: Oberflaeche

        function onHinweisGezeigt(text: string): void {
            root.zeigen(text);
        }
    }

    IpcHandler {
        target: "hinweis"

        function zeigen(text: string): void {
            root.zeigen(text);
        }
    }

    PanelWindow {
        id: fenster

        visible: toast.sichtbar
        anchors.bottom: true
        margins.bottom: Theme.a7
        implicitWidth: toast.implicitWidth
        implicitHeight: toast.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        color: Theme.durchsichtig
        mask: Region {}

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "zenos-hinweis"

        Toast {
            id: toast

            anchors.centerIn: parent
        }
    }
}
