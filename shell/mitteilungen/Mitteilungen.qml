// Platzhalter von M3 – wird von M6 ersetzt
import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste as Dienste

// Popups, Zentrale und IPC «mitteilungen»
Scope {
    IpcHandler {
        target: "mitteilungen"

        function zentrale(): void {
            Dienste.Oberflaeche.zentraleOffen = !Dienste.Oberflaeche.zentraleOffen;
        }

        function zustellen(): void {
            Dienste.Mitteilungen.zustellen();
        }
    }
}
