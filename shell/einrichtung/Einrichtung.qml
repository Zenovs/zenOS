pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste

// Erster Start nach Entwurf 2: erscheint beim Sitzungsstart, solange die Einrichtung nicht
// abgeschlossen ist (Einstellungen.eingerichtet). Schritt 1: Name, Ort, Erscheinungsbild, erster
// Modus. Schritt 2: Zustimmung zu den proprietären Apps (zen apps installieren im Terminal).
// Vollfläche auf der Overlay-Ebene mit exklusivem Tastaturfokus; kein Weichzeichnen.
// IPC «einrichtung»: oeffnen(), apps() (direkt Schritt 2), schliessen(), status()
Scope {
    id: root

    readonly property bool offen: Oberflaeche.einrichtungOffen
    // 1 = Start, 2 = Apps
    property int schritt: 1
    property bool _geprueft: false

    function oeffnen(zuSchritt: int): void {
        weiter.stop();
        inhalt.opacity = 1;
        schritt = zuSchritt === 2 ? 2 : 1;
        Oberflaeche.einrichtungOffen = true;
    }

    function schliessen(): void {
        Oberflaeche.einrichtungOffen = false;
    }

    // Einmal pro Sitzung: noch nicht eingerichtet → Einrichtung zeigen
    function _pruefen(): void {
        if (_geprueft || !Einstellungen.geladen)
            return;
        _geprueft = true;
        if (Einstellungen.eingerichtet !== true)
            oeffnen(1);
    }

    Component.onCompleted: _pruefen()

    Connections {
        target: Einstellungen

        function onGeladenChanged(): void {
            root._pruefen();
        }
    }

    IpcHandler {
        target: "einrichtung"

        function oeffnen(): void {
            root.oeffnen(1);
        }

        function apps(): void {
            root.oeffnen(2);
        }

        function schliessen(): void {
            root.schliessen();
        }

        function status(): string {
            return root.offen ? "offen " + root.schritt : "zu";
        }
    }

    PanelWindow {
        id: fenster

        visible: root.offen || flaeche.opacity > 0
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.durchsichtig

        WlrLayershell.layer: WlrLayer.Overlay
        // Während der Sperre None: labwc gibt einer exklusiven Fläche den Fokus nach dem Entsperren nicht
        // zurück, beim Wechsel zurück auf Exclusive fokussiert es sie neu.
        WlrLayershell.keyboardFocus: root.offen && !Oberflaeche.gesperrt ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "zenos-einrichtung"

        Rectangle {
            id: flaeche

            anchors.fill: parent
            color: Theme.grund
            clip: true
            opacity: root.offen ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.dauerMax
                    easing.type: Theme.kurve
                }
            }

            // Klicks gehen nie an das, was darunter liegt
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Loader {
                id: inhalt

                readonly property real breite: Math.min(1120, flaeche.width - 2 * Theme.a7)

                anchors.centerIn: parent
                active: fenster.visible
                focus: true
                sourceComponent: root.schritt === 2 ? schrittApps : schrittStart

                // Schrittwechsel: kurz aus- und wieder einblenden, nichts springt
                SequentialAnimation {
                    id: weiter

                    NumberAnimation {
                        target: inhalt
                        property: "opacity"
                        to: 0
                        duration: Theme.dauerKurz
                        easing.type: Theme.kurve
                    }
                    ScriptAction {
                        script: root.schritt = 2
                    }
                    NumberAnimation {
                        target: inhalt
                        property: "opacity"
                        to: 1
                        duration: Theme.dauerMax
                        easing.type: Theme.kurve
                    }
                }
            }
        }
    }

    Component {
        id: schrittStart

        SchrittStart {
            spalte: (inhalt.breite - luecke) / 2
            focus: true
            onFertig: weiter.start()
        }
    }

    Component {
        id: schrittApps

        SchrittApps {
            spalte: (inhalt.breite - luecke) / 2
            focus: true
            onFertig: root.schliessen()
        }
    }
}
