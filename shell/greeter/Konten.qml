import QtQuick
import Quickshell
import Quickshell.Io

// Konten von Menschen aus /etc/passwd: UID 1000–59999 mit einer Login-Shell (nicht nologin/false).
// Gibt es genau eines, ist es im Greeter vorausgewählt.
Scope {
    id: root

    // [{ name: "login", anzeige: "Anzeigename oder login" }]
    property var liste: []

    function _lesen(text: string): void {
        const result = [];
        for (const line of (text ?? "").split("\n")) {
            const f = line.split(":");
            if (f.length < 7 || f[0].length === 0)
                continue;
            const uid = Number(f[2]);
            if (!Number.isInteger(uid) || uid < 1000 || uid > 59999)
                continue;
            const loginShell = f[6].trim();
            if (loginShell.length === 0 || /(^|\/)(nologin|false)$/.test(loginShell))
                continue;
            let gecos = f[4].split(",")[0].trim();
            // cloud-init gibt dem ersten Benutzer eines Ubuntu-Images den Anzeigenamen «Ubuntu» (default_user),
            // auch wenn der Raspberry Pi Imager einen eigenen Login setzt. Das ist kein Name: dann den Login zeigen.
            if (gecos.toLowerCase() === "ubuntu" && f[0] !== "ubuntu")
                gecos = "";
            result.push({
                name: f[0],
                anzeige: gecos.length > 0 ? gecos : f[0]
            });
        }
        liste = result;
    }

    FileView {
        id: passwd

        path: "/etc/passwd"
        blockLoading: true
        printErrors: false
        onLoaded: root._lesen(text())
        onLoadFailed: console.warn("Greeter: /etc/passwd nicht lesbar")
    }

    Component.onCompleted: _lesen(passwd.text())
}
