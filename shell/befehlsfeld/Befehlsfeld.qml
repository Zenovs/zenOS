// Platzhalter von M3 – wird von M5 ersetzt
import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste

Scope {
    IpcHandler {
        target: "befehlsfeld"

        function umschalten(): void {
            Oberflaeche.befehlsfeldOffen = !Oberflaeche.befehlsfeldOffen;
        }

        function oeffnen(): void {
            Oberflaeche.befehlsfeldOffen = true;
        }

        function schliessen(): void {
            Oberflaeche.befehlsfeldOffen = false;
        }

        function werkzeuge(): void {
            Oberflaeche.befehlsfeldOffen = true;
        }
    }
}
