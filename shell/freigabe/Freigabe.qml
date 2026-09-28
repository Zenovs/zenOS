pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.komponenten
import qs.dienste as Dienste

// Bildschirmfreigabe: 2-px-Rahmen in «sitzung» um die Arbeitsfläche und oben mittig das Label
// «Dieser Bildschirm wird geteilt» (Entwurf 2 «Sitzung»). Klickdurchlässig, nimmt nie den Fokus.
// Geteilt wird immer ein ganzer Bildschirm (xdg-desktop-portal-wlr); ist bekannt, welcher, bekommt
// nur er den Rahmen, sonst alle.
// IPC «freigabe»: gewaehlt(ausgang), gestartet(), beendet() (zenos-freigabe über das Portal), status()
Scope {
    id: root

    IpcHandler {
        target: "freigabe"

        // Aus der Bildschirmwahl (zenos-freigabe waehlen), bevor das Portal den Stream anlegt
        function gewaehlt(ausgang: string): void {
            Dienste.Freigabe.gewaehlt(ausgang);
        }

        function gestartet(): void {
            Dienste.Freigabe.gestartet();
        }

        function beendet(): void {
            Dienste.Freigabe.beendet();
        }

        // "aktiv" oder "inaktiv"
        function status(): string {
            return Dienste.Freigabe.aktiv ? "aktiv" : "inaktiv";
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: fenster

            required property ShellScreen modelData
            // Beim Abziehen des Bildschirms wird modelData kurz null, bevor das Fenster verschwindet
            readonly property bool geteilt: Dienste.Freigabe.betrifft(modelData?.name ?? "")

            screen: modelData
            visible: geteilt || rahmen.opacity > 0
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.durchsichtig
            // Keine Eingaben: alles geht an die Fenster darunter
            mask: Region {}

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "zenos-freigabe"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                id: rahmen

                anchors.fill: parent
                opacity: fenster.geteilt ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.dauerMax
                        easing.type: Theme.kurve
                    }
                }

                // Arbeitsfläche unter der Leiste, mit der Rasterlücke als Rand
                Rectangle {
                    id: linie

                    x: Theme.rasterAbstand
                    y: Theme.leisteHoehe + 10
                    width: parent.width - 2 * Theme.rasterAbstand
                    height: parent.height - y - Theme.rasterAbstand
                    radius: Theme.radiusFenster
                    color: Theme.durchsichtig
                    border.width: 2
                    border.color: Theme.sitzung
                }

                // Label mittig auf der oberen Kante
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: linie.y - height / 2
                    width: label.implicitWidth + 24
                    height: 24
                    radius: Theme.radiusPille
                    color: Theme.sitzung

                    Row {
                        id: label

                        anchors.centerIn: parent
                        spacing: 8

                        Symbol {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "monitor"
                            groesse: 13
                            strichbreite: 2
                            farbe: Theme.grund
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Dieser Bildschirm wird geteilt"
                            color: Theme.grund
                            font.family: Theme.schriftMono
                            font.pixelSize: Theme.groesseKlein
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }
}
