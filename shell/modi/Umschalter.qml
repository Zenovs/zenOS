// Platzhalter von M3 – wird von M8 ersetzt
import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste

// Modus- und Zustand-Wahl, IPC «modus» und «zustand»
Scope {
    IpcHandler {
        target: "modus"

        function waehlen(): void {
            Oberflaeche.modusWahlOffen = true;
        }

        function wechseln(id: string): void {
            Modi.wechseln(id);
        }
    }

    IpcHandler {
        target: "zustand"

        function waehlen(): void {
            Oberflaeche.zustandWahlOffen = true;
        }

        function starten(id: string): void {
            Zustaende.starten(id, "manuell");
        }

        function beenden(): void {
            Zustaende.beenden();
        }
    }
}
