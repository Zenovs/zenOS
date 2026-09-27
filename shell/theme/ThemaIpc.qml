import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste

// IPC-Ziel «thema»: zenos-ipc thema wechseln | setzen hell|dunkel|tageszeit | status
Scope {
    IpcHandler {
        target: "thema"

        function wechseln(): void {
            Erscheinung.umschalten();
        }

        function setzen(modus: string): void {
            Erscheinung.setzen(modus);
        }

        // wirksames Erscheinungsbild: "hell" oder "dunkel"
        function status(): string {
            return Erscheinung.dunkel ? "dunkel" : "hell";
        }
    }
}
