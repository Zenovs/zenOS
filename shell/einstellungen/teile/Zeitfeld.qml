import QtQuick
import qs.theme
import qs.komponenten

// Uhrzeit HH:MM (38 px). Übernimmt nur gültige Zeiten (bei Enter oder beim Verlassen).
Eingabe {
    id: root

    property string zeit
    // Nur bei gültiger Eingabe
    signal gesetzt(string zeit)

    implicitWidth: 92
    implicitHeight: 38
    schriftGroesse: Theme.groesseText
    platzhalter: "HH:MM"
    maximaleLaenge: 5
    text: zeit
    fehler: text.length > 0 && !_gueltig(text)

    function _gueltig(t: string): bool {
        return /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(t);
    }

    function _uebernehmen(): void {
        let t = text.trim();
        // «730» oder «7:30» wird zu «07:30»
        const m = /^([0-9]{1,2}):?([0-9]{2})$/.exec(t);
        if (m)
            t = ("0" + m[1]).slice(-2) + ":" + m[2];
        if (_gueltig(t)) {
            text = t;
            if (t !== zeit) {
                zeit = t;
                gesetzt(t);
            }
        }
    }

    onAccepted: _uebernehmen()

    Connections {
        target: root.feld

        function onActiveFocusChanged(): void {
            if (!root.feld.activeFocus)
                root._uebernehmen();
        }
    }
}
