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
// Nachlauf: zenos-freigabe löscht den Marker erst 3 s nach dem Ende (Chrome öffnet beim Klick auf
// «Teilen» gleich eine zweite Sitzung). Endet die Freigabe hier trotzdem (leerer Marker, «beendet»),
// bleibt «aktiv» noch 2 s stehen; beginnt in der Zeit eine neue, geht es nahtlos weiter. So enden
// Sitzung und Zurückhalten nie zwischen zwei Streams.
Singleton {
    id: root

    // true, solange etwas geteilt wird (ab der Wahl des Bildschirms) und noch 2 s danach. Wird nur in
    // _update gesetzt und vom Nachlauf gelöscht, nie kurz zwischendurch.
    readonly property bool aktiv: _active
    // Beginn der Freigabe; ungültig, solange nichts geteilt wird
    property date seit: new Date(NaN)
    // Geteilte Ausgänge, z. B. ["HDMI-A-1"]; «*» = unbekannt. Im Nachlauf die zuletzt geteilten.
    readonly property var ausgaenge: _shown.length > 0 ? _shown : (_active ? _lastShown : [])
    // Unbekannt, welcher Bildschirm geteilt wird: dann gelten alle als geteilt
    readonly property bool alleBildschirme: aktiv && (ausgaenge.length === 0 || ausgaenge.indexOf("*") >= 0)

    // IPC «freigabe gewaehlt <ausgang>»: Bildschirm gewählt, die Freigabe beginnt gleich. Gilt, bis
    // exec_before den Marker setzt; kommt der nicht (das Portal brach nach der Wahl ab), verfällt sie.
    function gewaehlt(ausgang: string): void {
        if (!/^[A-Za-z0-9._-]{1,64}$/.test(ausgang ?? ""))
            return;
        _chosen = ausgang;
        chosenExpiry.restart();
        _update();
    }

    // IPC «freigabe gestartet»
    function gestartet(): void {
        _ipcActive = true;
        marker.reload();
        _update();
    }

    // IPC «freigabe beendet». Eine Wahl bleibt: Sie gehört zu einer Freigabe, die gleich beginnt
    // (sie verfällt von selbst oder geht im Marker auf).
    function beendet(): void {
        _ipcActive = false;
        marker.reload();
        _update();
    }

    // Wird dieser Bildschirm (Name des Ausgangs) gerade geteilt? (ab der Wahl, vor dem Marker)
    function betrifft(ausgang: string): bool {
        return aktiv && (alleBildschirme || ausgaenge.indexOf(ausgang) >= 0);
    }

    property bool _active: false
    property bool _ipcActive: false
    property var _outputs: []
    // Gewählter Ausgang, bevor der Marker da ist
    property string _chosen: ""
    readonly property var _shown: _outputs.length > 0 ? _outputs : (_chosen !== "" ? [_chosen] : [])
    // Zuletzt geteilte Ausgänge (für den Rahmen im Nachlauf)
    property var _lastShown: []

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
        // Leer wird der Marker nur durch zenos-freigabe (Ende nach dem Nachlauf, Zurücksetzen): die
        // gemeldete Freigabe ist vorbei, auch wenn die IPC-Meldung danach nicht ankommt
        if (ended)
            _ipcActive = false;
        _update();
    }

    // «aktiv» sofort an; aus erst, wenn der Nachlauf abläuft, ohne dass etwas Neues kam
    function _update(): void {
        if (_shown.length > 0 && JSON.stringify(_shown) !== JSON.stringify(_lastShown))
            _lastShown = _shown;
        if (_outputs.length > 0 || _ipcActive || _chosen !== "") {
            afterglow.stop();
            if (!_active)
                _active = true;
        } else if (_active && !afterglow.running) {
            afterglow.restart();
        }
    }

    onAktivChanged: seit = aktiv ? new Date() : new Date(NaN)

    // Nachlauf der Oberfläche (zusätzlich zu den 3 s von zenos-freigabe)
    Timer {
        id: afterglow

        interval: 2000
        onTriggered: {
            if (root._outputs.length > 0 || root._ipcActive || root._chosen !== "")
                return;
            root._active = false;
            root._lastShown = [];
        }
    }

    // exec_before folgt der Wahl sofort (im Container nach rund 10 ms); 10 s reichen auch unter Last
    Timer {
        id: chosenExpiry

        interval: 10000
        onTriggered: {
            root._chosen = "";
            root._update();
        }
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
