// Platzhalter von M3 – wird von M12 ersetzt
import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste

// Erster Start, IPC «einrichtung»
Scope {
    IpcHandler {
        target: "einrichtung"

        function oeffnen(): void {
            Oberflaeche.einrichtungOffen = true;
        }
    }
}
