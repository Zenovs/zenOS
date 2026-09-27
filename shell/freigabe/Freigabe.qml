// Platzhalter von M3 – wird von M8 ersetzt
import QtQuick
import Quickshell
import Quickshell.Io

// Rahmen und Label bei Bildschirmfreigabe, IPC «freigabe»
Scope {
    IpcHandler {
        target: "freigabe"

        function gestartet(): void {
        }

        function beendet(): void {
        }
    }
}
