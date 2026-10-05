pragma Singleton
pragma ComponentBehavior: Bound

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

    // Sofort sperren und den Bildschirm ausschalten (Energie, über zen energie aus). Eine Eingabe weckt ihn.
    function bildschirmAus(): void {
        Energie.aus();
    }

    function terminal(): void {
        _launchApp(["kitty"], "", "kitty");
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
        _launchApp(entry.runInTerminal ? ["kitty", "--"].concat(command) : command, entry.workingDirectory, entry.id);
    }

    // Ein Programm wie eine App starten (eigene Einheit, siehe _launchApp), z. B. ein Terminal mit einem
    // Befehl. befehl: Argumentliste; name: steht im Namen der Einheit (z. B. "zen-apps")
    function programmStarten(befehl: var, name: var): void {
        _launchApp(befehl, "", name);
    }

    // pfad: absoluter Pfad oder URL. Über zenos-oeffnen (gio open); findet sich keine App oder
    // scheitert das Öffnen, erscheint ein Hinweis statt nichts.
    function dateiOeffnen(pfad: string): void {
        if (!pfad)
            return;
        // Ein Prozess pro Aufruf: zenos-oeffnen endet gleich nach dem Start der App, ein zweites
        // Öffnen kurz danach geht so nicht verloren
        oeffnenVorlage.createObject(root, {
            ziel: pfad
        });
    }

    // ~/Ablage im Dateimanager (Knopf in der Leiste, Aktion «Ablage» im Befehlsfeld). Während der Sperre und
    // der Einrichtung öffnet sich nichts (wie beim Befehlsfeld).
    function ablageOeffnen(): void {
        if (Oberflaeche.gesperrt || Oberflaeche.einrichtungOffen || !Pfade.home)
            return;
        dateiOeffnen(Pfade.ablage);
    }

    function _oeffnenGescheitert(ziel: string, code: int, meldung: string): void {
        console.warn("Aktionen: zenos-oeffnen endete mit", code, meldung.trim());
        let text = "Öffnen hat nicht geklappt";
        if (code === 2)
            text = ziel === Pfade.ablage ? "Ablage nicht gefunden" : "Datei oder Ordner nicht gefunden";
        else if (code === 3)
            text = /^[A-Za-z][A-Za-z0-9+.-]*:/.test(ziel) ? "Keine App für diese Adresse" : "Keine App für diese Datei";
        else if (code === 4)
            text = "Keine App für Ordner";
        Oberflaeche.hinweis(text, "warnung");
    }

    Component {
        id: oeffnenVorlage

        Process {
            id: oeffnen

            property string ziel
            property bool gestartet: false

            // «--»: ein Pfad, der mit «-» beginnt, ist keine Option
            command: [Pfade.bin + "/zenos-oeffnen", "--", oeffnen.ziel]
            workingDirectory: Pfade.home
            running: true
            stderr: StdioCollector {
                id: oeffnenFehler
            }

            onStarted: oeffnen.gestartet = true
            onExited: (code, status) => {
                if (code !== 0 || status !== 0)
                    root._oeffnenGescheitert(oeffnen.ziel, status !== 0 ? -1 : code, oeffnenFehler.text);
            }
            // Nach exited (oder ohne, wenn es sich nicht starten liess) kommt «läuft nicht mehr»
            onRunningChanged: {
                if (oeffnen.running)
                    return;
                if (!oeffnen.gestartet)
                    root._oeffnenGescheitert(oeffnen.ziel, -1, "zenos-oeffnen liess sich nicht starten");
                oeffnen.destroy();
            }
        }
    }

    // Auch die Werkzeuge in eigener Einheit: wl-copy hält danach die Zwischenablage und endet sonst mit
    // einem Neustart der Oberfläche
    function bildschirmfoto(argumente: var): void {
        _launchApp([Pfade.bin + "/zenos-bildschirmfoto"].concat(Array.isArray(argumente) ? argumente : []), "", "bildschirmfoto");
    }

    function pipette(): void {
        _launchApp([Pfade.bin + "/zenos-pipette"], "", "pipette");
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

    // Direkt starten, ohne eigene Einheit: für Befehle, die gleich enden (systemctl, labwc --exit, pkill)
    function _launch(command: var, dir: var): void {
        Quickshell.execDetached({
            command: command,
            workingDirectory: typeof dir === "string" && dir.length > 0 ? dir : Pfade.home
        });
    }

    // Apps in eigener Einheit starten (app-zenos-<name>-<zeit>.scope in app.slice), über
    // zenos-oeffnen --programm: Was die Oberfläche direkt startet, liegt in der cgroup von
    // zenos-shell.service und endet mit jedem Neustart des Dienstes (Absturz, install.sh).
    // zenos-oeffnen kehrt gleich nach dem Start zurück und leitet die Ausgaben der App ins Leere. Der
    // Process hält die App also nicht (Quickshell beendet laufende Process-Objekte beim Neuladen), und sie
    // hängt an keiner Pipe, die niemand mehr liest. Ohne erreichbare Benutzerinstanz oder wenn systemd-run
    // scheitert, startet zenos-oeffnen sie ohne Einheit; lässt es sich selbst nicht starten, startet sie hier
    // direkt.
    // name: Desktop-ID oder Programmname (zenos-oeffnen ersetzt, was im Einheitennamen nicht erlaubt ist)
    function _launchApp(command: var, dir: var, name: var): void {
        if (!Array.isArray(command) || command.length === 0) {
            console.warn("Aktionen: nichts zu starten");
            return;
        }
        starterVorlage.createObject(root, {
            befehl: command.map(a => String(a)),
            name: typeof name === "string" && name.length > 0 ? name : String(command[0]).replace(/^.*\//, ""),
            verzeichnis: typeof dir === "string" && dir.length > 0 ? dir : Pfade.home
        });
    }

    function _startGescheitert(code: int, meldung: string): void {
        console.warn("Aktionen: zenos-oeffnen --programm endete mit", code, meldung.trim());
        Oberflaeche.hinweis(code === 127 ? "Programm nicht gefunden" : "Starten hat nicht geklappt", "warnung");
    }

    Component {
        id: starterVorlage

        Process {
            id: starter

            property var befehl: []
            property string name
            property string verzeichnis
            property bool gestartet: false

            command: [Pfade.bin + "/zenos-oeffnen", "--programm", starter.name, "--"].concat(starter.befehl)
            workingDirectory: starter.verzeichnis
            running: true
            stderr: StdioCollector {
                id: starterFehler
            }

            onStarted: starter.gestartet = true
            onExited: (code, status) => {
                if (code !== 0 || status !== 0)
                    root._startGescheitert(status !== 0 ? -1 : code, starterFehler.text);
            }
            onRunningChanged: {
                if (starter.running)
                    return;
                if (!starter.gestartet) {
                    console.warn("Aktionen: zenos-oeffnen liess sich nicht starten, starte ohne eigene Einheit");
                    root._launch(starter.befehl, starter.verzeichnis);
                }
                starter.destroy();
            }
        }
    }
}
