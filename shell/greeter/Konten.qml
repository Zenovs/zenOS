import QtQuick
import Quickshell
import Quickshell.Io

// Konten von Menschen: In zenOS 1.0 verwaltet systemd-homed die Konten (UID 60001–60513); sie stehen nicht in
// /etc/passwd, sondern kommen über NSS (libnss-systemd). Gelesen wird deshalb «getent passwd» (Argumentliste), dazu
// klassische Konten mit UID 1000–59999. Nur mit einer Login-Shell (nicht nologin/false). Gibt es genau eines, ist es
// im Greeter vorausgewählt; ist die Liste leer, fragt das Formular nach dem Namen.
Scope {
    id: root

    // [{ name: "login", anzeige: "Anzeigename oder login" }]
    property var liste: []

    function _mensch(uid: int): bool {
        return (uid >= 1000 && uid <= 59999) || (uid >= 60001 && uid <= 60513);
    }

    function _lesen(text: string): void {
        const result = [];
        const gesehen = {};
        for (const line of (text ?? "").split("\n")) {
            const f = line.split(":");
            if (f.length < 7 || f[0].length === 0 || gesehen[f[0]])
                continue;
            const uid = Number(f[2]);
            if (!Number.isInteger(uid) || !root._mensch(uid))
                continue;
            const loginShell = f[6].trim();
            if (loginShell.length === 0 || /(^|\/)(nologin|false)$/.test(loginShell))
                continue;
            const gecos = f[4].split(",")[0].trim();
            gesehen[f[0]] = true;
            result.push({
                name: f[0],
                anzeige: gecos.length > 0 ? gecos : f[0]
            });
        }
        liste = result;
    }

    Process {
        id: konten

        command: ["getent", "passwd"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root._lesen(text)
        }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0)
                console.warn("Greeter: getent passwd endete mit", code);
        }
    }
}
