pragma Singleton

import QtQuick
import Quickshell

// Feste Orte von zenOS. Der Code liegt unter /opt/zenos; für Tests aus einem
// anderen Checkout lässt er sich mit der Umgebungsvariable ZENOS_CODE umlenken.
Singleton {
    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string konfig: home + "/.config/zenos"
    readonly property string zustand: home + "/.local/state/zenos"
    // Der eine Ordner für eigene Dateien (legt install.sh an, Modul 48-ablage)
    readonly property string ablage: home + "/Ablage"
    readonly property string laufzeit: (Quickshell.env("XDG_RUNTIME_DIR") ?? ("/tmp/zenos-" + (Quickshell.env("USER") ?? "benutzer"))) + "/zenos"
    readonly property string code: _stripSlash(Quickshell.env("ZENOS_CODE") || "/opt/zenos")
    readonly property string bin: code + "/scripts/bin"

    function _stripSlash(path: string): string {
        return path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;
    }
}
