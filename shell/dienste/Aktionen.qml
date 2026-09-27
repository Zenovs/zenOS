pragma Singleton

import QtQuick
import Quickshell
// Process; dazu der Werttyp für execDetached({ command, workingDirectory })
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

// Prozessstarts der Oberfläche. Immer mit Argumentlisten, nie über eine Shell.
Singleton {
    id: root

    function sperren(): void {
        Oberflaeche.sperren();
    }

    function terminal(): void {
        _launch(["kitty"]);
    }

    // eintrag: DesktopEntry (aus DesktopEntries) oder dessen ID ("org.example.App")
    function appStarten(eintrag: var): void {
        const entry = typeof eintrag === "string" ? DesktopEntries.byId(eintrag) : eintrag;
        if (!entry || !entry.command || entry.command.length === 0) {
            console.warn("Aktionen: App nicht gefunden", typeof eintrag === "string" ? eintrag : "");
            return;
        }
        // Exec schreibt ein «%» als «%%». Quickshell v0.3.1 lässt «%%» in Anführungszeichen stehen, GLib nicht
        // (z. B. "--app=https://…%%25…" einer Web-App). Eine gültige Adresse enthält nie «%%».
        const command = Array.from(entry.command).map(a => String(a).replace(/%%/g, "%"));
        _launch(entry.runInTerminal ? ["kitty", "--"].concat(command) : command, entry.workingDirectory);
    }

    // pfad: absoluter Pfad oder URL
    function dateiOeffnen(pfad: string): void {
        if (!pfad)
            return;
        // Ein führendes «-» wäre für xdg-open eine Option
        _launch(["xdg-open", pfad.startsWith("-") ? "./" + pfad : pfad]);
    }

    function bildschirmfoto(argumente: var): void {
        _launch([Pfade.bin + "/zenos-bildschirmfoto"].concat(Array.isArray(argumente) ? argumente : []));
    }

    function pipette(): void {
        _launch([Pfade.bin + "/zenos-pipette"]);
    }

    // Über zenos-abmelden: stoppt erst die Sitzungsdienste, dann labwc (sonst enden sie als «failed»).
    // Nur wenn es sich nicht starten lässt, wird labwc direkt beendet.
    function abmelden(): void {
        if (abmeldenProzess.running)
            return;
        abmeldenProzess.gestartet = false;
        abmeldenProzess.command = [Pfade.bin + "/zenos-abmelden"];
        abmeldenProzess.running = true;
    }

    function _labwcBeenden(): void {
        // labwc --exit braucht LABWC_PID; fehlt sie in der Umgebung des Dienstes,
        // wird labwc des eigenen Benutzers direkt beendet.
        if (Quickshell.env("LABWC_PID"))
            _launch(["labwc", "--exit"]);
        else
            _launch(["pkill", "-TERM", "-x", "-u", Quickshell.env("USER") ?? "", "labwc"]);
    }

    function neustarten(): void {
        _launch(["systemctl", "reboot"]);
    }

    function ausschalten(): void {
        _launch(["systemctl", "poweroff"]);
    }

    // seite: z. B. "modi", "allgemein"; leer = Startseite der Einstellungen
    function einstellungen(seite: var): void {
        Oberflaeche.einstellungenOeffnen(typeof seite === "string" ? seite : "");
    }

    Process {
        id: abmeldenProzess

        property bool gestartet: false

        workingDirectory: Pfade.home
        stderr: StdioCollector {
            id: abmeldenFehler
        }

        onStarted: gestartet = true
        // Lässt sich das Programm nicht starten (fehlt, nicht ausführbar), meldet Process nur «läuft nicht mehr»
        onRunningChanged: {
            if (!running && !gestartet)
                root._labwcBeenden();
        }
        // 0: Abmelden läuft (die Sitzung endet gleich). Endet es mit einem Fehler, bleibt die Sitzung offen.
        // Ein Signal (Status 1) kommt nur vom Ende der Sitzung selbst.
        onExited: (code, status) => {
            if (code === 0 || status !== 0)
                return;
            console.warn("Aktionen: zenos-abmelden endete mit", code, abmeldenFehler.text.trim());
            Oberflaeche.hinweis("Abmelden hat nicht geklappt", "warnung");
        }
    }

    function _launch(command: var, dir: var): void {
        Quickshell.execDetached({
            command: command,
            workingDirectory: typeof dir === "string" && dir.length > 0 ? dir : Pfade.home
        });
    }
}
