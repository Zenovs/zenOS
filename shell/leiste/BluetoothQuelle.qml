pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "bluetooth.js" as Bt

// Brücke zwischen dem Bluetooth-Abschnitt des System-Menüs und BlueZ (Quickshell.Bluetooth, über D-Bus).
// Leiste.qml lädt sie erst, wenn bluetooth.service läuft (wie WlanQuelle erst mit NetworkManager). Deshalb steht
// Quickshell.Bluetooth nur hier und nie unter dienste/.
//
// Nach aussen nur einfache Werte (gleiche Schnittstelle wie eine Attrappe im Test):
//   bereit, an, gesperrt, geraete (Objekte wie in bluetooth.js, sortiert), versuch, fehlerGeraet, fehler;
//   suchen (schreibbar); anSetzen(an), verbinden(adresse), trennen(adresse), vergessen(adresse), aufraeumen().
//
// Koppeln ohne eigenen Agenten: BlueZ koppelt dann mit «NoInputNoOutput» (Just Works). Mäuse, Kopfhörer und die
// meisten Tastaturen gehen so, Geräte mit PIN-Eingabe nicht. Nach dem Koppeln wird das Gerät vertraut (trusted), damit
// es sich später von selbst wieder verbindet. Sichtbar für andere (discoverable) macht zenOS den Rechner nie.
// Die Adresse dient nur als Schlüssel und erscheint nie in der Oberfläche.
Scope {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool bereit: adapter !== null
    readonly property bool an: bereit && adapter.enabled
    // rfkill-Sperre: Dann lässt sich Bluetooth nicht per Schalter einschalten
    readonly property bool gesperrt: bereit && adapter.state === BluetoothAdapterState.Blocked

    // Suche nach Geräten: nur solange die Liste im Menü offen ist
    property bool suchen: false

    // Geräte (sortiert, siehe bluetooth.js). Wird nur ersetzt, wenn sich etwas Sichtbares ändert, damit die Zeilen im
    // Menü (und ihr Tastaturfokus) stehen bleiben.
    property var geraete: []

    // Gerät, mit dem gerade verbunden bzw. gekoppelt wird ("" = keins), und der letzte Fehler dazu
    property string versuch: ""
    property string fehlerGeraet: ""
    // "koppeln" | "verbinden" | "zeit" | ""
    property string fehler: ""

    // Wir haben die Suche gestartet (nur dann beenden wir sie auch), und der Start ist noch unterwegs
    property bool _wirSuchen: false
    property bool _startOffen: false
    // Geräte, die gerade gekoppelt werden (danach vertrauen und verbinden), und ob die Kopplung schon lief
    property var _koppeln: ({})
    property var _koppelnLief: ({})
    // Der Versuch war schon sichtbar im Gang (verbindet oder koppelt)
    property bool _imGang: false

    function anSetzen(ein: bool): void {
        if (!bereit || gesperrt)
            return;
        adapter.enabled = ein;
    }

    function verbinden(adresse: string): void {
        const d = _geraet(adresse);
        if (!d)
            return;
        versuch = adresse;
        fehlerGeraet = "";
        fehler = "";
        _imGang = false;
        frist.restart();
        if (d.paired || d.bonded) {
            d.connect();
            return;
        }
        _koppeln[adresse] = true;
        delete _koppelnLief[adresse];
        d.pair();
    }

    function trennen(adresse: string): void {
        const d = _geraet(adresse);
        if (d)
            d.disconnect();
    }

    function vergessen(adresse: string): void {
        const d = _geraet(adresse);
        if (!d)
            return;
        if (versuch === adresse)
            _abbrechen();
        delete _koppeln[adresse];
        delete _koppelnLief[adresse];
        d.forget();
    }

    // Menü zu: Suche beenden, eine laufende Kopplung abbrechen, Fehler vergessen
    function aufraeumen(): void {
        suchen = false;
        _sucheSetzen();
        _abbrechen();
        fehlerGeraet = "";
        fehler = "";
    }

    function _geraet(adresse: string): var {
        if (!adapter)
            return null;
        const liste = adapter.devices.values;
        for (let i = 0; i < liste.length; i++) {
            if (liste[i].address === adresse)
                return liste[i];
        }
        return null;
    }

    function _abbrechen(): void {
        if (versuch === "")
            return;
        const d = _geraet(versuch);
        if (d && d.pairing)
            d.cancelPair();
        versuch = "";
        frist.stop();
    }

    function _scheitern(art: string): void {
        fehlerGeraet = versuch;
        fehler = art;
        versuch = "";
        frist.stop();
    }

    // Start und Stopp der Suche gehen über D-Bus; «discovering» folgt erst, wenn BlueZ es meldet. Solange ein Start
    // unterwegs ist, wird nicht beendet (das ginge ins Leere, und die Suche liefe weiter): Erst wenn BlueZ den Start
    // meldet (onDiscoveringChanged) oder nach 5 s ohne Meldung, kommt der Stopp.
    function _sucheSetzen(): void {
        if (!adapter)
            return;
        const soll = suchen && an;
        if (soll) {
            _wirSuchen = true;
            if (!adapter.discovering && !_startOffen) {
                _startOffen = true;
                startFrist.restart();
                adapter.discovering = true;
            }
        } else if (_wirSuchen && !_startOffen) {
            _wirSuchen = false;
            if (adapter.discovering)
                adapter.discovering = false;
        }
    }

    // Kopplungen weiterführen und den laufenden Versuch auswerten
    function _pruefen(): void {
        for (const adresse in _koppeln) {
            const d = _geraet(adresse);
            if (!d) {
                delete _koppeln[adresse];
                continue;
            }
            if (d.paired || d.bonded) {
                delete _koppeln[adresse];
                delete _koppelnLief[adresse];
                d.trusted = true;
                if (!d.connected) {
                    _imGang = false;
                    d.connect();
                }
            } else if (d.pairing) {
                _koppelnLief[adresse] = true;
            } else if (_koppelnLief[adresse]) {
                delete _koppeln[adresse];
                delete _koppelnLief[adresse];
                if (versuch === adresse)
                    _scheitern("koppeln");
            }
        }
        if (versuch === "")
            return;
        const d = _geraet(versuch);
        if (!d) {
            _scheitern("verbinden");
            return;
        }
        if (d.connected) {
            versuch = "";
            frist.stop();
            return;
        }
        if (d.pairing || d.state === BluetoothDeviceState.Connecting) {
            _imGang = true;
            return;
        }
        if (_imGang && !(versuch in _koppeln))
            _scheitern("verbinden");
    }

    // Rohliste aus Quickshell. Die Bindung liest jede Eigenschaft und rechnet bei jeder Änderung neu.
    readonly property var _roh: {
        if (!adapter)
            return [];
        const liste = adapter.devices.values;
        const aus = [];
        for (let i = 0; i < liste.length; i++) {
            const d = liste[i];
            aus.push({
                adresse: d.address,
                name: d.name,
                typ: d.icon,
                verbunden: d.connected,
                gekoppelt: d.paired || d.bonded,
                verbindet: d.state === BluetoothDeviceState.Connecting,
                trennt: d.state === BluetoothDeviceState.Disconnecting,
                koppelt: d.pairing,
                akku: Bt.akku(d.batteryAvailable, d.battery)
            });
        }
        return aus;
    }

    on_RohChanged: {
        const neu = Bt.sortieren(_roh);
        if (JSON.stringify(neu) !== JSON.stringify(geraete))
            geraete = neu;
        _pruefen();
    }
    onSuchenChanged: _sucheSetzen()
    onAnChanged: _sucheSetzen()

    Connections {
        target: root.adapter

        function onDiscoveringChanged(): void {
            root._startOffen = false;
            startFrist.stop();
            root._sucheSetzen();
        }
    }

    // Meldet BlueZ den Start nicht (abgelehnt, Adapter weg), nach 5 s neu entscheiden
    Timer {
        id: startFrist

        interval: 5000
        onTriggered: {
            root._startOffen = false;
            root._sucheSetzen();
        }
    }

    // Antwortet ein Gerät nicht (aus, zu weit weg, nicht im Kopplungsmodus), bricht der Versuch nach 30 s ab
    Timer {
        id: frist

        interval: 30000
        onTriggered: {
            if (root.versuch === "")
                return;
            const adresse = root.versuch;
            root._abbrechen();
            // Kommt die Kopplung später doch noch durch, nicht mehr von selbst verbinden
            delete root._koppeln[adresse];
            delete root._koppelnLief[adresse];
            root.fehlerGeraet = adresse;
            root.fehler = "zeit";
        }
    }
}
