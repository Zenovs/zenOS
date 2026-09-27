pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme

// Hintergrund «Heute» auf jedem Bildschirm (Ebene Background, Farbe grund) nach Entwurf 2:
// Datum, Gruss, kurze Zusammenfassung, aktiver Modus; unten die wichtigsten Tastenkürzel.
// Termine, Aufgaben und Wetter (rechte Spalte) kommen erst «Danach».
Scope {
    id: root

    SystemClock {
        id: uhr

        precision: SystemClock.Minutes
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: fenster

            required property ShellScreen modelData

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.grund
            // klickdurchlässig: der Hintergrund hat nichts zu bedienen
            mask: Region {}

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "zenos-heute"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            HeuteInhalt {
                anchors.fill: parent
                jetzt: uhr.date
            }
        }
    }
}
