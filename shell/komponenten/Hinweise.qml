pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste
import "symbole.js" as Symbole

// Kurze Hinweise (Toast) unten in der Mitte, z. B. «Farbe kopiert».
// Auslöser: Oberflaeche.hinweis(text[, symbol]) oder zenos-ipc hinweis zeigen|warnen "<text>".
// Das Fenster ist klickdurchlässig und nimmt nie den Tastaturfokus.
Scope {
    id: root

    readonly property string standardSymbol: "haken"

    // symbol: Name aus Symbol (z. B. "warnung", "info"); leer = Haken. Warnungen bleiben etwas länger stehen.
    function zeigen(text: string, symbol: string): void {
        const t = (text ?? "").trim();
        if (t.length === 0)
            return;
        let s = (symbol ?? "").trim();
        if (s.length > 0 && !Symbole.daten[s]) {
            console.warn("Hinweise: unbekanntes Symbol", s);
            s = "";
        }
        toast.symbol = s.length > 0 ? s : standardSymbol;
        toast.dauer = s === "warnung" ? 4000 : 2500;
        toast.zeigen(t.length > 120 ? t.slice(0, 119) + "…" : t);
    }

    Connections {
        target: Oberflaeche

        function onHinweisGezeigt(text: string, symbol: string): void {
            root.zeigen(text, symbol);
        }
    }

    IpcHandler {
        target: "hinweis"

        function zeigen(text: string): void {
            root.zeigen(text, "");
        }

        // Fehlermeldungen, z. B. aus zenos-bildschirmfoto: Symbol «warnung»
        function warnen(text: string): void {
            root.zeigen(text, "warnung");
        }
    }

    PanelWindow {
        id: fenster

        visible: toast.sichtbar
        anchors.bottom: true
        // über der Fusszeile von «Heute» (30 px vom Rand, eine Tastenkappe hoch) mit etwas Luft
        margins.bottom: 30 + kappe.implicitHeight + Theme.a4
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

        // nur zum Messen der Höhe einer Tastenkappe
        Kbd {
            id: kappe

            visible: false
            text: "Z"
        }
    }
}
