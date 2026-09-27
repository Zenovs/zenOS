// Platzhalter von M3 – wird von M8 ersetzt
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    property var liste: []
    property string aktivId: ""
    // Vorlage + Anpassung des Modus + Leitplanken, oder null
    property var wirksam: null
    // Restzeit des Timers in Minuten, -1 ohne Timer
    property int restMinuten: -1

    function starten(id: string, ausloeser: var): void {
    }

    function beenden(): void {
    }

    function speichern(id: string, daten: var): void {
    }

    function anlegen(daten: var): string {
        return "";
    }

    function loeschen(id: string): void {
    }
}
