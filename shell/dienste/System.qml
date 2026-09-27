// Platzhalter von M3 – wird von M4 ersetzt
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    // °C, -1 wenn unbekannt
    property int temperatur: -1
    // Lüfter in %, -1 wenn unbekannt
    property int luefter: -1
    property bool wlanVerbunden: false
    property bool netzVerbunden: false
    // 0.0–1.0
    property real lautstaerke: 0
    property bool stumm: false
    property bool einsPasswortInstalliert: false
    property bool einsPasswortLaeuft: false
}
