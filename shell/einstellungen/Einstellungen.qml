// Platzhalter von M3 – wird von M8 ersetzt
import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste as Dienste

// Einstellungen-Fenster (FloatingWindow) und IPC «einstellungen».
// Lädt die Seiten Seite<Name>.qml aus diesem Ordner.
Scope {
    IpcHandler {
        target: "einstellungen"

        function oeffnen(seite: string): void {
            Dienste.Aktionen.einstellungen(seite);
        }
    }
}
