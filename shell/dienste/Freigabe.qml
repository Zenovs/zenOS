pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

// Bildschirmfreigabe. Das Portal (xdg-desktop-portal-wlr) ruft vor und nach jeder Freigabe
// zenos-freigabe auf; das pflegt den Marker $XDG_RUNTIME_DIR/zenos/freigabe (eine Zeile pro
// Freigabe mit dem geteilten Ausgang oder «*») und meldet es per IPC «freigabe» (gestartet, beendet).
// Der Marker hält den Zustand auch über einen Neustart der Oberfläche.
Singleton {
    id: root

    // true, solange etwas geteilt wird
    readonly property bool aktiv: _outputs.length > 0 || _ipcActive
    // Beginn der Freigabe; ungültig, solange nichts geteilt wird
    property date seit: new Date(NaN)
    // Geteilte Ausgänge, z. B. ["HDMI-A-1"]; «*» = unbekannt
    readonly property var ausgaenge: _outputs
    // Unbekannt, welcher Bildschirm geteilt wird: dann gelten alle als geteilt
    readonly property bool alleBildschirme: aktiv && (_outputs.length === 0 || _outputs.indexOf("*") >= 0)

    // IPC «freigabe gestartet»
    function gestartet(): void {
        _ipcActive = true;
        marker.reload();
    }

    // IPC «freigabe beendet»
    function beendet(): void {
        _ipcActive = false;
        marker.reload();
    }

    // Wird dieser Bildschirm (Name des Ausgangs) gerade geteilt?
    function betrifft(ausgang: string): bool {
        return aktiv && (alleBildschirme || _outputs.indexOf(ausgang) >= 0);
    }

    property bool _ipcActive: false
    property var _outputs: []

    function _read(text: string): void {
        const list = (text ?? "").split("\n").map(s => s.trim()).filter(s => /^(\*|[A-Za-z0-9._-]{1,64})$/.test(s));
        if (JSON.stringify(list) !== JSON.stringify(_outputs))
            _outputs = list;
    }

    onAktivChanged: seit = aktiv ? new Date() : new Date(NaN)

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
