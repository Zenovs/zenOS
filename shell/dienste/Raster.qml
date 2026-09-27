// Platzhalter von M3 – wird von M9 ersetzt
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var liste: []
    property string aktivId: ""

    function setzen(id: string): void {
    }

    IpcHandler {
        target: "raster"

        function setzen(id: string): void {
            root.setzen(id);
        }
    }
}
