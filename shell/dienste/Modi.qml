// Platzhalter von M3 – wird von M8 ersetzt
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    // Array von Objekten inkl. id
    property var liste: []
    // Objekt des aktiven Modus oder null
    property var aktiv: null
    property string aktivId: ""

    function wechseln(id: string): void {
    }

    function speichern(id: string, daten: var): void {
    }

    function anlegen(daten: var): string {
        return "";
    }

    function loeschen(id: string): void {
    }
}
