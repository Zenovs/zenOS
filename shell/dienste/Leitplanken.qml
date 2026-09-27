// Platzhalter von M3 – wird von M8 ersetzt
pragma Singleton

import QtQuick
import Quickshell

// Leitplanken sind Code, nicht Konfiguration.
Singleton {
    readonly property bool inhalteBeiFreigabe: false
    readonly property bool sperreZeigtInhalte: false
    readonly property bool sperreAbschaltbar: false

    // Minuten bis zur automatischen Sperre, immer 1–15 (Standard 5)
    function sperreMinuten(wunsch: var): int {
        const n = Number(wunsch);
        if (!isFinite(n))
            return 5;
        return Math.min(15, Math.max(1, Math.round(n)));
    }

    // Erzwingt die Leitplanken in einem wirksamen Zustand
    function anwenden(zustand: var): var {
        return zustand;
    }
}
