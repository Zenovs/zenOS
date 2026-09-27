// Platzhalter von M3 – wird von M8 ersetzt
pragma Singleton

import QtQuick
import Quickshell

// Liste, Schreiben und Löschen von JSON-Dateien unter ~/.config/zenos über zenos-konfig
Singleton {
    function liste(art: string): var {
        return [];
    }

    function schreiben(art: string, id: string, daten: var): void {
    }

    function loeschen(art: string, id: string): void {
    }
}
