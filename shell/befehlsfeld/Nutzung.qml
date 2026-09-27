import QtQuick
import Quickshell.Io
import "suche.mjs" as Suche

// Lokale Nutzungsstatistik des Befehlsfelds für Vorschläge: nur App-IDs und Zähler, dazu die
// Reihenfolge der zuletzt genutzten. Keine Zeiten, keine Fenstertitel. Verlässt den Rechner nie.
// Wer die Datei löscht, löscht damit auch die Vorschläge (auch bei laufender Oberfläche).
QtObject {
    id: root

    // ~/.local/share/zenos/befehlsfeld.json; leer = nichts lesen oder schreiben
    property string pfad
    property var daten: Suche.nutzungLeer()

    function merken(id: string): void {
        daten = Suche.nutzungMerken(daten, id);
        if (pfad.length > 0)
            datei.setText(JSON.stringify(daten) + "\n");
    }

    function _lesen(): void {
        try {
            daten = Suche.nutzungPruefen(JSON.parse(datei.text()));
        } catch (e) {
            console.warn("Befehlsfeld: Nutzungsstatistik nicht lesbar, beginne neu");
            daten = Suche.nutzungLeer();
        }
    }

    property FileView datei: FileView {
        path: root.pfad
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._lesen()
        onLoadFailed: fehler => {
            if (fehler === FileViewError.FileNotFound)
                root.daten = Suche.nutzungLeer();
        }
    }
}
