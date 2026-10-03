pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking
import "wlan.js" as Wlan

// Brücke zwischen dem WLAN-Abschnitt des System-Menüs und NetworkManager (Quickshell.Networking, über D-Bus).
// Leiste.qml lädt sie erst, wenn NetworkManager läuft: Quickshell wählt sein Netz-Backend einmal beim ersten
// Zugriff und behält es bis zum Neustart von Quickshell (ohne NetworkManager bliebe es «None», mit einer
// Fehlerzeile im Protokoll). Deshalb steht Quickshell.Networking nur hier und nie unter dienste/.
//
// Nach aussen nur einfache Werte (gleiche Schnittstelle wie die Attrappe im Container-Test):
//   bereit, geraetDa, wlanAn, hardwareAn, netze (Objekte wie in wlan.js), verbunden (Objekt oder null),
//   verbundenStufe, versuch, fehlerNetz, fehler; scannen und menueOffen (schreibbar);
//   verbinden(name), verbindenMitPasswort(name, passwort), vergessen(name), abbrechen(name), aufraeumen(),
//   wlanSetzen(an).
//
// Passwörter gehen nur über D-Bus an NetworkManager (connectWithPsk), nie in eine Kommandozeile, ein Protokoll
// oder eine zenOS-Datei. NetworkManager speichert sie wie jedes Profil (docs/sicherheit.md).
// Offene Netze (auch OWE) verbinden nur auf Klick: Ihr neues Profil bekommt gleich «autoconnect: nein», sonst
// verbände sich NetworkManager später überall von selbst mit jedem Zugangspunkt gleichen Namens.
Scope {
    id: root

    readonly property bool bereit: Networking.backend === NetworkBackendType.NetworkManager
    // erstes WLAN-Gerät (WifiDevice) oder null
    readonly property var geraet: {
        const liste = Networking.devices.values;
        for (let i = 0; i < liste.length; i++) {
            if (liste[i].type === DeviceType.Wifi)
                return liste[i];
        }
        return null;
    }
    readonly property bool geraetDa: geraet !== null
    readonly property bool wlanAn: Networking.wifiEnabled
    // Hardware-Sperre (rfkill) – dann lässt sich WLAN nicht per Schalter einschalten
    readonly property bool hardwareAn: Networking.wifiHardwareEnabled

    // Netze in Reichweite (sortiert, siehe wlan.js). Wird nur ersetzt, wenn sich etwas Sichtbares ändert, damit
    // die Zeilen im Menü (und ihr Tastaturfokus) nach einem Suchlauf stehen bleiben.
    property var netze: []
    readonly property var verbunden: {
        for (let i = 0; i < netze.length; i++) {
            if (netze[i].verbunden)
                return netze[i];
        }
        return null;
    }
    // Signalstufe des verbundenen Netzes (1–3), 0 ohne Verbindung
    readonly property int verbundenStufe: _verbundenStufe

    // Suchlauf: nur solange die Liste im Menü offen ist (Quickshell fragt dann höchstens alle 10 s neu)
    property bool scannen: false
    // Das System-Menü mit dem WLAN-Abschnitt ist offen. Scheitert ein neues Netz, während es zu ist, räumt die
    // Quelle das angelegte Profil sofort weg (niemand kann das Passwort mehr korrigieren).
    property bool menueOffen: false

    // Netz, mit dem gerade verbunden wird ("" = keins), und der letzte Fehler dazu
    property string versuch: ""
    property string fehlerNetz: ""
    // "passwort" | "abgelehnt" | "zeit" | "weg" | "keine-antwort" | ""
    property string fehler: ""

    function verbinden(name: string): void {
        const netz = _netz(name);
        if (!netz)
            return;
        if (!netz.known) {
            _neu[name] = true;
            if (_sicherheit(netz.security) === "offen")
                _offen[name] = true;
        }
        _start(name);
        netz.connect();
    }

    // Neues Netz: NetworkManager legt ein dauerhaftes Profil an (auch wenn das Passwort falsch ist; abbrechen()
    // räumt es dann wieder weg). Bekanntes Netz: Quickshell ersetzt nur das Passwort im Profil.
    function verbindenMitPasswort(name: string, passwort: string): void {
        const netz = _netz(name);
        if (!netz || Wlan.passwortPruefen(passwort) !== "")
            return;
        if (!netz.known)
            _neu[name] = true;
        _start(name);
        netz.connectWithPsk(passwort);
    }

    function vergessen(name: string): void {
        const netz = _netz(name);
        if (!netz)
            return;
        delete _neu[name];
        delete _offen[name];
        if (fehlerNetz === name)
            _fehlerLoeschen();
        netz.forget();
    }

    // Zeno bricht ab (Esc, Menü zu): Ein Profil, das erst dieser Versuch angelegt hat und das nicht verbunden ist,
    // wieder vergessen. Sonst bliebe ein Profil mit falschem Passwort, und NetworkManager versuchte es weiter.
    function abbrechen(name: string): void {
        const netz = _netz(name);
        if (name in _neu && netz && !netz.connected && !(netz.stateChanging && versuch === name)) {
            delete _neu[name];
            netz.forget();
        }
        if (fehlerNetz === name)
            _fehlerLoeschen();
    }

    // Menü geht zu: alle Profile, die ein Versuch aus dem Menü angelegt hat und die weder verbunden sind noch
    // gerade verbinden, wieder vergessen
    function aufraeumen(): void {
        for (const name of Object.keys(_neu)) {
            const netz = _netz(name);
            if (!netz) {
                delete _neu[name];
                continue;
            }
            if (netz.connected || netz.state === ConnectionState.Connecting)
                continue;
            delete _neu[name];
            netz.forget();
        }
        _fehlerLoeschen();
    }

    function wlanSetzen(an: bool): void {
        Networking.wifiEnabled = an;
    }

    // --- intern ---

    // Namen der Netze, deren Profil ein Versuch aus dem Menü angelegt hat und die noch nie verbunden waren
    property var _neu: ({})
    // Offene Netze, deren neues Profil noch «autoconnect: nein» bekommen muss
    property var _offen: ({})
    property string _json: ""
    property int _verbundenStufe: 0

    function _netz(name: string): var {
        if (!geraet)
            return null;
        const liste = geraet.networks.values;
        for (let i = 0; i < liste.length; i++) {
            if (liste[i].name === name)
                return liste[i];
        }
        return null;
    }

    // Neues Profil eines offenen Netzes: nur auf Klick verbinden (NMSettings.write schreibt nur dieses Feld um)
    function _offenSichern(netz: var): void {
        if (!netz || !(netz.name in _offen) || !netz.known)
            return;
        const profile = netz.nmSettings ?? [];
        // known kommt manchmal vor der Liste der Profile; dann beim nächsten nmSettingsChanged
        if (profile.length === 0)
            return;
        delete _offen[netz.name];
        for (let i = 0; i < profile.length; i++)
            profile[i].write({
                connection: {
                    autoconnect: false
                }
            });
    }

    function _start(name: string): void {
        _fehlerLoeschen();
        versuch = name;
        zeitlimit.restart();
    }

    function _fehlerLoeschen(): void {
        fehlerNetz = "";
        fehler = "";
    }

    function _sicherheit(art: int): string {
        switch (art) {
        case WifiSecurityType.Open:
        case WifiSecurityType.Owe:
            return "offen";
        case WifiSecurityType.WpaPsk:
        case WifiSecurityType.Wpa2Psk:
        case WifiSecurityType.Sae:
            return "passwort";
        case WifiSecurityType.StaticWep:
            return "wep";
        case WifiSecurityType.Wpa2Eap:
        case WifiSecurityType.WpaEap:
        case WifiSecurityType.Wpa3SuiteB192:
        case WifiSecurityType.Leap:
        case WifiSecurityType.DynamicWep:
            return "unternehmen";
        default:
            return "unbekannt";
        }
    }

    function _grund(grund: int): string {
        switch (grund) {
        case ConnectionFailReason.NoSecrets:
            return "passwort";
        case ConnectionFailReason.WifiClientDisconnected:
        case ConnectionFailReason.WifiClientFailed:
            return "abgelehnt";
        case ConnectionFailReason.WifiAuthTimeout:
            return "zeit";
        case ConnectionFailReason.WifiNetworkLost:
            return "weg";
        default:
            return "keine-antwort";
        }
    }

    // Alle Netze als einfache Objekte; liest jede Eigenschaft, damit die Bindung bei Änderungen neu rechnet
    readonly property var _roh: {
        if (!geraet || !wlanAn)
            return [];
        const liste = [];
        const werte = geraet.networks.values;
        for (let i = 0; i < werte.length; i++) {
            const n = werte[i];
            liste.push({
                name: n.name,
                stufe: n.signalStrength > 0 ? Wlan.stufe(Math.round(n.signalStrength * 100)) : 0,
                sicherheit: _sicherheit(n.security),
                wpa3: n.security === WifiSecurityType.Sae,
                bekannt: n.known,
                verbunden: n.connected,
                verbindet: n.state === ConnectionState.Connecting
            });
        }
        return Wlan.sortieren(liste);
    }

    on_RohChanged: {
        const json = JSON.stringify(_roh);
        if (json !== _json) {
            _json = json;
            netze = _roh;
        }
    }

    // Signal des verbundenen Netzes für die Leiste (genau, nicht nur aus der Liste)
    Binding {
        target: root
        property: "_verbundenStufe"
        value: {
            if (!root.geraet || !root.wlanAn)
                return 0;
            const werte = root.geraet.networks.values;
            for (let i = 0; i < werte.length; i++) {
                if (werte[i].connected)
                    return Wlan.stufe(Math.round(werte[i].signalStrength * 100));
            }
            return 0;
        }
    }

    // Suchlauf an das Gerät weitergeben
    Binding {
        when: root.geraet !== null
        target: root.geraet
        property: "scannerEnabled"
        value: root.scannen && root.wlanAn
    }

    // Ergebnis eines Versuchs: verbunden oder gescheitert (connectionFailed kommt je Netz)
    Instantiator {
        model: root.geraet ? root.geraet.networks : null

        delegate: Connections {
            required property var modelData

            target: modelData

            function onConnectionFailed(grund: int): void {
                const name = modelData.name;
                if (root.versuch !== name && !(name in root._neu))
                    return;
                zeitlimit.stop();
                root.versuch = "";
                if (!root.menueOffen && name in root._neu) {
                    delete root._neu[name];
                    modelData.forget();
                    return;
                }
                root.fehlerNetz = name;
                root.fehler = root._grund(grund);
            }

            function onKnownChanged(): void {
                root._offenSichern(modelData);
            }

            function onNmSettingsChanged(): void {
                root._offenSichern(modelData);
            }

            function onConnectedChanged(): void {
                if (!modelData.connected)
                    return;
                const name = modelData.name;
                delete root._neu[name];
                if (root.versuch === name) {
                    zeitlimit.stop();
                    root.versuch = "";
                }
                if (root.fehlerNetz === name)
                    root._fehlerLoeschen();
            }
        }
    }

    // Ohne Antwort (z. B. polkit lehnt ab, Quickshell meldet das nicht weiter) nach 40 s aufgeben
    Timer {
        id: zeitlimit

        interval: 40000
        onTriggered: {
            if (root.versuch === "")
                return;
            const name = root.versuch;
            root.versuch = "";
            root.fehlerNetz = name;
            root.fehler = "keine-antwort";
        }
    }
}
