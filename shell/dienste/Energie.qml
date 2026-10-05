pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "energie.js" as EnergieLogik

// Energie der Sitzung: Bildschirm aus und an, die Sofort-Aktion «Bildschirm aus» und die Höchstdauer, die ein
// Idle-Hemmer die automatische Sperre aufhalten darf. Die Logik steht in energie.js und ist dort getestet.
//
// - aus(): Sofort-Aktion (System-Menü, Befehlsfeld, IPC «energie aus»; Super+Shift+L ruft «zen energie aus»
//   direkt auf). Über «zen energie aus», das immer zuerst sperrt: Läuft zenos-idle, löst SIGUSR1 Sperre und
//   Bildschirm aus sofort aus, und die nächste Eingabe weckt ihn (resume von swayidle). Sonst sperrt und schaltet
//   zenos-bildschirm direkt, geweckt wird dann über die Sperre (sperre/Sperre.qml).
// - bildschirm("aus" | "an"): zenos-bildschirm mit Argumentliste. «aus» sperrt dort immer zuerst (dunkel heisst
//   gesperrt). Es läuft immer nur ein Aufruf, der letzte Wunsch gilt. Gelingt er, kommt bildschirmGeschaltet.
//   Die Sperre nutzt das für «Bildschirm aus nach der Sperre» und zum Wecken.
// - Leitplanke (Code, nicht abschaltbar): Ein Idle-Hemmer (z. B. ein Video im Browser) hält die automatische
//   Sperre höchstens Leitplanken.sperreTrotzHemmerMinuten (60) ohne Eingabe auf, dann sperrt zenOS trotzdem
//   (IdleMonitor ohne Rücksicht auf Hemmer). Ohne Hemmer sperrt zenos-idle wie bisher nach 1–15 Min.
// IPC «energie»: aus(), status()
Singleton {
    id: root

    // Wirksame Werte aus einstellungen.json, begrenzt durch die Leitplanken (genauso liest sie zenos-idle)
    readonly property var wirksam: EnergieLogik.wirksam({
        sperreNachMinuten: Einstellungen.sperreNachMinuten,
        bildschirmAusNachSperre: Einstellungen.bildschirmAusNachSperre,
        ausschalten: Einstellungen.ausschalten,
        ausschaltenNachMinuten: Einstellungen.ausschaltenNachMinuten,
        einAusTaste: Einstellungen.einAusTaste
    })
    readonly property int sperreMinuten: wirksam.sperreMinuten
    // Minuten nach der Sperre, bis der Bildschirm ausgeht (1–10)
    readonly property int bildschirmMinuten: wirksam.bildschirmMinuten
    // So lange hält ein Idle-Hemmer die Sperre höchstens auf (Leitplanke)
    readonly property int sperreTrotzHemmerMinuten: Leitplanken.sperreTrotzHemmerMinuten
    // «Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min.». Das Ausschalten nach langer Sperre kommt erst mit
    // seinem Helfer dazu; bis dahin steht es hier nicht (es geschieht ja noch nicht).
    readonly property string zeitleisteText: EnergieLogik.zeitleisteText({
        sperreNachMinuten: Einstellungen.sperreNachMinuten,
        bildschirmAusNachSperre: Einstellungen.bildschirmAusNachSperre,
        ausschalten: "nie"
    }, null)

    // zenos-bildschirm hat den Bildschirm aus- bzw. eingeschaltet ("aus" | "an")
    signal bildschirmGeschaltet(string was)

    // Sofort sperren und den Bildschirm ausschalten
    function aus(): void {
        if (ausProzess.running)
            return;
        ausProzess.gestartet = false;
        ausProzess.running = true;
    }

    // was: "aus" | "an"
    function bildschirm(was: string): void {
        if (was !== "aus" && was !== "an")
            return;
        // Läuft genau dieser Wunsch schon, genügt das (z. B. zwei Monitore wecken zugleich)
        root._wunsch = bildschirmProzess.running && bildschirmProzess.was === was ? "" : was;
        root._naechster();
    }

    // --- intern ---

    readonly property string _zen: Pfade.code + "/scripts/zen"
    // Nächster Aufruf von zenos-bildschirm ("aus", "an" oder "": keiner)
    property string _wunsch: ""

    function _naechster(): void {
        if (bildschirmProzess.running || root._wunsch === "")
            return;
        bildschirmProzess.was = root._wunsch;
        bildschirmProzess.gestartet = false;
        root._wunsch = "";
        bildschirmProzess.running = true;
    }

    // Leitplanke: trotz Idle-Hemmer spätestens jetzt sperren. Über zen lock (mit Notfall-Sperre, falls die
    // Oberfläche nicht sperren kann), mit Argumentliste.
    function _sperrenTrotzHemmer(): void {
        console.info("Energie:", root.sperreTrotzHemmerMinuten, "Min. ohne Eingabe, sperre trotz Idle-Hemmer (Leitplanke)");
        Quickshell.execDetached({
            command: [root._zen, "lock"],
            workingDirectory: Pfade.home
        });
    }

    Process {
        id: ausProzess

        property bool gestartet: false

        command: [root._zen, "energie", "aus"]
        workingDirectory: Pfade.home
        stderr: StdioCollector {
            id: ausFehler
        }

        onStarted: gestartet = true
        onExited: (code, status) => {
            if (code !== 0 || status !== 0)
                console.warn("Energie: zen energie aus endete mit", code, ausFehler.text.trim());
        }
        onRunningChanged: {
            if (!running && !gestartet)
                console.warn("Energie: zen liess sich nicht starten:", root._zen);
        }
    }

    Process {
        id: bildschirmProzess

        property string was: ""
        property bool gestartet: false

        command: [Pfade.bin + "/zenos-bildschirm", bildschirmProzess.was]
        workingDirectory: Pfade.home
        stderr: StdioCollector {
            id: bildschirmFehler
        }

        onStarted: gestartet = true
        onExited: (code, status) => {
            if (code === 0 && status === 0)
                root.bildschirmGeschaltet(bildschirmProzess.was);
            else
                console.warn("Energie: zenos-bildschirm", bildschirmProzess.was, "endete mit", code, bildschirmFehler.text.trim());
        }
        onRunningChanged: {
            if (running)
                return;
            if (!gestartet)
                console.warn("Energie: zenos-bildschirm liess sich nicht starten");
            Qt.callLater(root._naechster);
        }
    }

    // Höchstdauer trotz Idle-Hemmer (Leitplanke): zählt ohne Rücksicht auf Hemmer, nur ungesperrt
    IdleMonitor {
        enabled: !Oberflaeche.gesperrt
        respectInhibitors: false
        timeout: root.sperreTrotzHemmerMinuten * 60
        onIsIdleChanged: {
            if (isIdle && !Oberflaeche.gesperrt)
                root._sperrenTrotzHemmer();
        }
    }

    IpcHandler {
        target: "energie"

        // Sperren und Bildschirm aus (wie Super+Shift+L)
        function aus(): void {
            root.aus();
        }

        // Wirksame Zeitleiste, z. B. «Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min.»
        function status(): string {
            return root.zeitleisteText;
        }
    }
}
