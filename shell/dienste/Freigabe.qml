pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

// Bildschirmfreigabe. Das Portal (xdg-desktop-portal-wlr) ruft vor und nach jeder Freigabe
// zenos-freigabe auf; das pflegt den Marker $XDG_RUNTIME_DIR/zenos/freigabe (eine Zeile je geteiltem
// Ausgang oder «*») und meldet es per IPC «freigabe» (gewaehlt, gestartet, beendet).
// Der Marker hält den Zustand auch über einen Neustart der Oberfläche. «gewaehlt» kommt schon aus der
// Bildschirmwahl, bevor das Portal den Stream anlegt (es wartet nicht auf exec_before).
Singleton {
    id: root

    // true, solange etwas geteilt wird (ab der Wahl des Bildschirms)
    readonly property bool aktiv: _outputs.length > 0 || _ipcActive || _chosen !== ""
    // Beginn der Freigabe; ungültig, solange nichts geteilt wird
    property date seit: new Date(NaN)
    // Geteilte Ausgänge, z. B. ["HDMI-A-1"]; «*» = unbekannt
    readonly property var ausgaenge: _shown
    // Unbekannt, welcher Bildschirm geteilt wird: dann gelten alle als geteilt
    readonly property bool alleBildschirme: aktiv && (_shown.length === 0 || _shown.indexOf("*") >= 0)

    // IPC «freigabe gewaehlt <ausgang>»: Bildschirm gewählt, die Freigabe beginnt gleich. Gilt, bis
    // exec_before den Marker setzt; kommt der nicht (das Portal brach nach der Wahl ab), verfällt sie.
    function gewaehlt(ausgang: string): void {
        if (!/^[A-Za-z0-9._-]{1,64}$/.test(ausgang ?? ""))
            return;
        _chosen = ausgang;
        chosenExpiry.restart();
    }

    // IPC «freigabe gestartet»
    function gestartet(): void {
        _ipcActive = true;
        marker.reload();
    }

    // IPC «freigabe beendet»
    function beendet(): void {
        _ipcActive = false;
        _chosen = "";
        chosenExpiry.stop();
        marker.reload();
    }

    // Wird dieser Bildschirm (Name des Ausgangs) gerade geteilt? (ab der Wahl, vor dem Marker)
    function betrifft(ausgang: string): bool {
        return aktiv && (alleBildschirme || _shown.indexOf(ausgang) >= 0);
    }

    property bool _ipcActive: false
    property var _outputs: []
    // Gewählter Ausgang, bevor der Marker da ist
    property string _chosen: ""
    readonly property var _shown: _outputs.length > 0 ? _outputs : (_chosen !== "" ? [_chosen] : [])

    function _read(text: string): void {
        const list = (text ?? "").split("\n").map(s => s.trim()).filter(s => /^(\*|[A-Za-z0-9._-]{1,64})$/.test(s));
        const ended = _outputs.length > 0 && list.length === 0;
        if (JSON.stringify(list) !== JSON.stringify(_outputs))
            _outputs = list;
        // Der Marker übernimmt die Wahl
        if (list.length > 0 && _chosen !== "") {
            _chosen = "";
            chosenExpiry.stop();
        }
        // Leer wird der Marker nur durch «zenos-freigabe ende»: vorbei, auch wenn die IPC-Meldung
        // danach nicht ankommt (z. B. Portal gerade neu gestartet)
        if (ended) {
            _ipcActive = false;
            _chosen = "";
            chosenExpiry.stop();
        }
    }

    onAktivChanged: seit = aktiv ? new Date() : new Date(NaN)

    // exec_before folgt der Wahl sofort (im Container nach rund 10 ms); 10 s reichen auch unter Last
    Timer {
        id: chosenExpiry

        interval: 10000
        onTriggered: root._chosen = ""
    }

    FileView {
        id: marker

        path: Pfade.laufzeit + "/freigabe"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._read(text())
        onLoadFailed: root._read("")
    }

    // Entsteht $XDG_RUNTIME_DIR/zenos erst später, meldet das der Ordner selbst (eine Ansicht auf
    // einen Ordner lädt nie Inhalt, beobachtet aber ihn und seinen Elternordner).
    FileView {
        path: Pfade.laufzeit
        watchChanges: true
        printErrors: false
        onFileChanged: marker.reload()
    }

    Component.onCompleted: _read(marker.text())
}
