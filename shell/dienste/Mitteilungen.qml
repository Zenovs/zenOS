// Platzhalter von M3 – wird von M6 ersetzt
pragma Singleton

import QtQuick
import Quickshell
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

Singleton {
    property var wartend: []
    property var zugestellt: []
    readonly property int anzahlWartend: wartend.length
    // Zeitpunkt der nächsten Zustellung (date) oder null
    property var naechsteZustellung: null
    // wirksame Bündelung: "alle" | "gebuendelt-<N>" | "nur-dringend" | "keine"
    readonly property string modus: Einstellungen.mitteilungenStandard

    function zustellen(): void {
    }

    function verwerfen(id: var): void {
    }

    function alleVerwerfen(): void {
    }
}
