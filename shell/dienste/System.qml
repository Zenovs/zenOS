pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Systemzustand für die Leiste: Temperatur, Netz, Ton, 1Password (Akku und Lüfter: Geraet).
// Sparsam für den Pi: ein Timer (5 s) liest ein paar kleine Dateien aus /sys und /proc,
// der Ton kommt direkt von PipeWire. Prozesse startet der Dienst nur für die 1Password-Prüfung
// (selten und nur, wenn 1Password installiert ist).
Singleton {
    id: root

    // °C aus /sys/class/thermal/thermal_zone0/temp, -1 wenn unbekannt
    readonly property int temperatur: _temperature

    // Netz: Standardverbindung über ein Gerät, das oben ist (nur Anzeige, zenOS verwaltet kein Netz)
    readonly property bool netzVerbunden: _network.best !== ""
    readonly property bool wlanVerbunden: _network.wlan !== ""
    // "wlan" | "kabel" | "" – Art der Standardverbindung
    readonly property string netzArt: _network.best === "" ? "" : (_isWireless(_network.best) ? "wlan" : "kabel")
    // Signal des verbundenen WLANs in %, -1 wenn unbekannt
    readonly property int wlanSignal: _network.wlan !== "" ? (_wireless[_network.wlan] ?? -1) : -1
    // Es gibt ein WLAN-Gerät (/proc/net/wireless oder ein Gerät «wl…» in /proc/net/dev; für den Hinweis im
    // System-Menü, solange NetworkManager das Netz nicht verwaltet)
    readonly property bool wlanGeraet: Object.keys(_wireless).length > 0 || _wlanNamen

    // Ton über PipeWire (Standardausgang)
    readonly property bool tonVerfuegbar: (_sink?.audio ?? null) !== null
    // 0.0–1.0; PipeWire erlaubt auch mehr als 1.0
    readonly property real lautstaerke: tonVerfuegbar ? Math.max(0, _sink.audio.volume) : 0
    readonly property bool stumm: tonVerfuegbar ? _sink.audio.muted : false

    // 1Password (/opt/1Password, siehe zen apps)
    readonly property bool einsPasswortInstalliert: _opDesktopEntry || _opBinary
    readonly property bool einsPasswortLaeuft: einsPasswortInstalliert && _opRunning

    // Lautstärke setzen (0.0–1.0); hebt Stumm auf, sobald etwas zu hören sein soll
    function lautstaerkeSetzen(wert: real): void {
        if (!tonVerfuegbar || !isFinite(wert))
            return;
        const v = Math.max(0, Math.min(1, wert));
        _sink.audio.volume = v;
        if (v > 0 && _sink.audio.muted)
            _sink.audio.muted = false;
    }

    function stummSetzen(an: bool): void {
        if (tonVerfuegbar)
            _sink.audio.muted = an;
    }

    function stummUmschalten(): void {
        stummSetzen(!stumm);
    }

    // Sofort neu einlesen, z. B. beim Öffnen des System-Menüs
    function aktualisieren(): void {
        _poll(true);
    }

    // --- Temperatur ---

    property int _temperature: -1

    // Plausible Werte, sonst -1
    function _celsius(value: var): int {
        const n = Number(value);
        return isFinite(n) && n > -40 && n < 150 ? Math.round(n) : -1;
    }

    FileView {
        id: thermalFile

        path: "/sys/class/thermal/thermal_zone0/temp"
        printErrors: false
        // Milligrad, z. B. «46123»
        onLoaded: root._temperature = root._celsius(parseInt(text().trim(), 10) / 1000)
        onLoadFailed: root._temperature = -1
    }

    // --- Netz ---

    // Standardrouten: Gerät → kleinste Metrik (IPv4 und IPv6)
    property var _routes: ({})
    // WLAN-Geräte aus /proc/net/wireless: Gerät → Signal in %
    property var _wireless: ({})
    // operstate der beobachteten Geräte: Gerät → "up" | "down" | "dormant" | "unknown" | …
    property var _operstate: ({})
    // Geräte, deren operstate gelesen wird
    property list<string> _devices: []
    // ein Gerät «wl…» in /proc/net/dev (nur beim Start und beim Öffnen des System-Menüs gelesen)
    property bool _wlanNamen: false

    readonly property var _network: {
        const up = name => _operstate[name] === "up" || _operstate[name] === "unknown";
        let best = "";
        let metric = Infinity;
        for (const name of Object.keys(_routes)) {
            if (up(name) && _routes[name] < metric) {
                best = name;
                metric = _routes[name];
            }
        }
        let wlan = best !== "" && _isWireless(best) ? best : "";
        if (wlan === "") {
            for (const name of Object.keys(_wireless)) {
                if (_operstate[name] === "up") {
                    wlan = name;
                    break;
                }
            }
        }
        return {
            best: best,
            wlan: wlan
        };
    }

    function _isWireless(name: string): bool {
        return name in _wireless || name.startsWith("wl");
    }

    function _parseRoutes(v4: string, v6: string): var {
        const result = {};
        const add = (name, metric) => {
            if (name && name !== "lo" && (!(name in result) || metric < result[name]))
                result[name] = metric;
        };
        // Iface Destination Gateway Flags RefCnt Use Metric Mask …
        for (const line of v4.split("\n").slice(1)) {
            const f = line.trim().split(/\s+/);
            if (f.length >= 8 && f[1] === "00000000" && f[7] === "00000000" && (parseInt(f[3], 16) & 0x1))
                add(f[0], Number(f[6]));
        }
        // Ziel Präfix Quelle Präfix Nächster Metrik Ref Use Flags Gerät; Standardroute ::/0, ohne «reject»
        for (const line of v6.split("\n")) {
            const f = line.trim().split(/\s+/);
            if (f.length >= 10 && /^0{32}$/.test(f[0]) && f[1] === "00") {
                const flags = parseInt(f[8], 16);
                if ((flags & 0x1) && !(flags & 0x200))
                    add(f[9], parseInt(f[5], 16));
            }
        }
        return result;
    }

    function _parseWireless(content: string): var {
        const result = {};
        // Zwei Kopfzeilen, dann «wlan0: 0000   70.  -40.  -256 …» (Qualität meist von 70)
        for (const line of content.split("\n").slice(2)) {
            const m = /^\s*([^\s:]+):\s+\S+\s+([\d.]+)/.exec(line);
            if (m)
                result[m[1]] = Math.max(0, Math.min(100, Math.round(parseFloat(m[2]) / 70 * 100)));
        }
        return result;
    }

    function _updateNetwork(): void {
        const routes = _parseRoutes(routeFile.text(), route6File.text());
        const wireless = _parseWireless(wirelessFile.text());
        if (JSON.stringify(routes) !== JSON.stringify(_routes))
            _routes = routes;
        if (JSON.stringify(wireless) !== JSON.stringify(_wireless))
            _wireless = wireless;
        const devices = Object.keys(routes).concat(Object.keys(wireless).filter(n => !(n in routes))).sort();
        if (JSON.stringify(devices) !== JSON.stringify(Array.from(_devices)))
            _devices = devices;
    }

    function _setOperstate(name: string, state: string): void {
        if (_operstate[name] === state)
            return;
        const next = Object.assign({}, _operstate);
        next[name] = state;
        _operstate = next;
    }

    FileView {
        id: routeFile

        path: "/proc/net/route"
        printErrors: false
        onLoaded: root._updateNetwork()
        onLoadFailed: root._updateNetwork()
    }

    FileView {
        id: route6File

        path: "/proc/net/ipv6_route"
        printErrors: false
        onLoaded: root._updateNetwork()
        onLoadFailed: root._updateNetwork()
    }

    FileView {
        id: wirelessFile

        path: "/proc/net/wireless"
        printErrors: false
        onLoaded: root._updateNetwork()
        onLoadFailed: root._updateNetwork()
    }

    // «Inter-|   Receive …», dann je Gerät «  wlan0: 1234 …»
    FileView {
        id: devFile

        path: "/proc/net/dev"
        printErrors: false
        onLoaded: root._wlanNamen = /^\s*wl[^\s:]*:/m.test(text())
        onLoadFailed: root._wlanNamen = false
    }

    Instantiator {
        id: operstateFiles

        model: root._devices

        delegate: FileView {
            required property string modelData

            path: "/sys/class/net/" + modelData + "/operstate"
            printErrors: false
            onLoaded: root._setOperstate(modelData, text().trim())
            onLoadFailed: root._setOperstate(modelData, "")
        }
    }

    // --- Ton ---

    readonly property var _sink: Pipewire.defaultAudioSink

    // Lautstärke und Stumm sind nur an gebundenen Knoten gültig
    PwObjectTracker {
        objects: [root._sink]
    }

    // --- 1Password ---

    // Starter von 1Password (DesktopEntries beobachtet die Ordner): after-install.sh legt seit 8.12
    // com.onepassword.OnePassword.desktop an, ältere Versionen 1password.desktop
    readonly property list<string> _opDesktopIds: ["com.onepassword.onepassword", "1password"]
    readonly property bool _opDesktopEntry: {
        const apps = DesktopEntries.applications.values;
        for (let i = 0; i < apps.length; i++) {
            const id = String(apps[i]?.id ?? "").toLowerCase();
            if (_opDesktopIds.includes(id))
                return true;
        }
        return false;
    }
    property bool _opBinary: false
    property bool _opRunning: false

    Process {
        id: opInstalledCheck

        command: ["test", "-x", "/opt/1Password/1password"]
    }

    Process {
        id: opRunningCheck

        // nur Prozesse des eigenen Benutzers
        command: {
            const user = Quickshell.env("USER");
            return user ? ["pgrep", "-x", "-u", user, "1password"] : ["pgrep", "-x", "1password"];
        }
    }

    // --- Takt ---

    property int _tick: 0

    function _poll(full: bool): void {
        thermalFile.reload();
        routeFile.reload();
        route6File.reload();
        wirelessFile.reload();
        for (let i = 0; i < operstateFiles.count; i++)
            (operstateFiles.objectAt(i) as FileView)?.reload();
        if (full)
            devFile.reload();
        // 1Password: installiert alle 5 Minuten, läuft alle 30 s (nur wenn installiert)
        if ((full || _tick % 60 === 0) && !opInstalledCheck.running)
            opInstalledCheck.running = true;
        if ((full || _tick % 6 === 0) && einsPasswortInstalliert && !opRunningCheck.running)
            opRunningCheck.running = true;
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            root._tick = (root._tick + 1) % 3600;
            root._poll(false);
        }
    }

    Component.onCompleted: {
        // exited(code, status) hier verbunden: qmllint kennt QProcess::ExitStatus nicht
        opInstalledCheck.exited.connect(code => root._opBinary = code === 0);
        opRunningCheck.exited.connect(code => root._opRunning = code === 0);
        opInstalledCheck.running = true;
        opRunningCheck.running = true;
    }
}
