// Platzhalter von M3 – wird von M7 ersetzt
import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste

// WlSessionLock und IPC «sperre». Der Platzhalter sperrt noch nicht.
Scope {
    id: root

    function sperren(): void {
        console.warn("Sperre: noch nicht gebaut (Platzhalter)");
    }

    Connections {
        target: Oberflaeche

        function onSperrenAngefordert(): void {
            root.sperren();
        }
    }

    IpcHandler {
        target: "sperre"

        function sperren(): void {
            console.warn("Sperre: noch nicht gebaut (Platzhalter)");
        }

        function status(): string {
            return "offen";
        }
    }
}
