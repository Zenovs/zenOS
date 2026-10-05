pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste

// Leiste oben auf jedem Bildschirm (40 px, reserviert ihren Platz), dazu das System- und das
// Raster-Menü. Modus- und Zustandswahl (Oberflaeche.modusWahlOffen/zustandWahlOffen) zeigt
// modi/Umschalter.qml, die Zentrale (Oberflaeche.zentraleOffen) mitteilungen/Mitteilungen.qml.
// WLAN: WlanQuelle (NetworkManager über Quickshell.Networking) entsteht erst, wenn NetworkManager läuft.
Scope {
    id: root

    // Offenes Menü: "" | "system" | "raster", auf dem Bildschirm menueBildschirm
    property string menue: ""
    property string menueBildschirm: ""
    // Anker in Fensterkoordinaten (siehe LeistenInhalt.menueGewuenscht)
    property real menueX: 0
    // System-Menü mit aufgeklappter WLAN-Liste öffnen (zenos-ipc leiste menue wlan)
    property bool menueWlanOffen: false
    // System-Menü mit aufgeklappter Wahl des Lüfters öffnen (zenos-ipc leiste menue luefter)
    property bool menueLuefterOffen: false

    // NetworkManager läuft (geprüft beim Start und beim Öffnen des System-Menüs, bis er einmal lief). Erst dann
    // entsteht WlanQuelle: Quickshell wählt sein Netz-Backend beim ersten Zugriff und behält es bis zum Neustart.
    property bool nmLaeuft: false
    // WlanQuelle oder null
    readonly property var wlan: wlanLader.item ?? null

    function _nmPruefen(): void {
        if (!nmLaeuft && !nmPruefung.running)
            nmPruefung.running = true;
    }

    // umschalten: ein zweiter Klick auf denselben Knopf schliesst das Menü wieder
    function menueOeffnen(name: string, bildschirm: string, x: real, umschalten: bool): void {
        // Während der Sperre bleiben die Menüs zu (auch per IPC, z. B. aus einer SSH-Sitzung): Ihre Fläche
        // nimmt die Tastatur exklusiv, nach dem Entsperren hätte dann nichts die Tastatur.
        if (Oberflaeche.gesperrt) {
            menueSchliessen();
            return;
        }
        if (umschalten && menue === name && menueBildschirm === bildschirm) {
            menueSchliessen();
            return;
        }
        // Wahl und Zentrale liegen auf der Ebene Overlay über dem Menü: vorher schliessen. Die
        // Mitteilungskarten (ebenfalls Overlay) treten über Oberflaeche.leisteMenueBildschirm zurück.
        Oberflaeche.modusWahlOffen = false;
        Oberflaeche.zustandWahlOffen = false;
        Oberflaeche.zentraleOffen = false;
        menueX = x;
        menueBildschirm = bildschirm;
        menue = name;
        if (name === "system") {
            System.aktualisieren();
            Geraet.aktualisieren();
            Kanal.aktualisieren();
            _nmPruefen();
        }
    }

    function menueSchliessen(): void {
        menue = "";
        menueWlanOffen = false;
        menueLuefterOffen = false;
    }

    // Nur der Zustand des Dienstes (Argumentliste, keine Shell); Exit 0 = läuft
    Process {
        id: nmPruefung

        command: ["systemctl", "is-active", "--quiet", "NetworkManager.service"]
    }

    // Über «source» geladen: Fehlt Quickshell.Networking oder hat WlanQuelle einen Fehler, bleibt die Leiste stehen
    // (das Menü zeigt dann die Netzzeile wie ohne NetworkManager)
    LazyLoader {
        id: wlanLader

        active: root.nmLaeuft
        source: "WlanQuelle.qml"
    }

    Component.onCompleted: {
        // exited(code, status) hier verbunden: qmllint kennt QProcess::ExitStatus nicht
        nmPruefung.exited.connect(code => {
            if (code === 0)
                root.nmLaeuft = true;
        });
        root._nmPruefen();
    }

    // Bildschirm mit offenem Menü für die anderen Oberflächen (leer = keins)
    Binding {
        target: Oberflaeche
        property: "leisteMenueBildschirm"
        value: root.menue !== "" ? root.menueBildschirm : ""
    }

    SystemClock {
        id: uhr

        precision: SystemClock.Minutes
    }

    Variants {
        id: leisten

        model: Quickshell.screens

        delegate: Scope {
            id: proBildschirm

            required property ShellScreen modelData
            // beim Abziehen des Bildschirms wird modelData null, der Name bleibt
            property string bildschirmName: ""
            readonly property bool menueHier: root.menue !== "" && root.menueBildschirm === bildschirmName

            function menueOeffnen(name: string): void {
                root.menueOeffnen(name, bildschirmName, inhalt.menueX(name), false);
            }

            Component.onCompleted: bildschirmName = modelData?.name ?? ""
            // Bildschirm weg: sein Menü schliessen (kommt beim Wiedereinstecken nicht zurück)
            Component.onDestruction: {
                if (root.menueBildschirm === bildschirmName)
                    root.menueSchliessen();
            }

            PanelWindow {
                screen: proBildschirm.modelData
                anchors {
                    top: true
                    left: true
                    right: true
                }
                implicitHeight: Theme.leisteHoehe
                exclusiveZone: Theme.leisteHoehe
                color: Theme.grund

                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "zenos-leiste"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                LeistenInhalt {
                    id: inhalt

                    anchors.fill: parent
                    jetzt: uhr.date
                    wlan: root.wlan
                    bildschirm: proBildschirm.bildschirmName
                    offenesMenue: proBildschirm.menueHier ? root.menue : ""
                    onMenueGewuenscht: (name, x) => root.menueOeffnen(name, proBildschirm.bildschirmName, x, true)
                }
            }

            // Menüfläche unter der Leiste: fängt Klicks daneben ab (schliesst), Esc schliesst.
            // Die Leiste selbst bleibt bedienbar.
            PanelWindow {
                id: menueFenster

                screen: proBildschirm.modelData
                visible: proBildschirm.menueHier
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                margins.top: Theme.leisteHoehe
                exclusionMode: ExclusionMode.Ignore
                color: Theme.durchsichtig

                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "zenos-leiste-menue"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.menueSchliessen()
                }

                Loader {
                    id: menueLader

                    active: menueFenster.visible
                    focus: true
                    sourceComponent: root.menue === "raster" ? rasterMenue : systemMenue
                    // System-Menü rechtsbündig unter dem Knopf, Raster-Menü linksbündig.
                    // Begrenzt mit der Bildschirmbreite: das Fenster kennt seine Breite erst nach dem Einblenden.
                    x: Math.round(Math.max(Theme.a2, Math.min((proBildschirm.modelData?.width ?? 0) - width - Theme.a2, root.menue === "raster" ? root.menueX : root.menueX - width)))
                    y: Theme.a1
                }

                Component {
                    id: systemMenue

                    SystemMenue {
                        wlanQuelle: root.wlan
                        wlanNmLaeuft: root.nmLaeuft
                        wlanOffen: root.menueWlanOffen
                        luefterOffen: root.menueLuefterOffen
                        onSchliessen: root.menueSchliessen()
                    }
                }

                Component {
                    id: rasterMenue

                    RasterMenue {
                        onSchliessen: root.menueSchliessen()
                    }
                }
            }
        }
    }

    // Andere Oberflächen gehen vor: Menüs der Leiste schliessen
    Connections {
        target: Oberflaeche

        function onBefehlsfeldOffenChanged(): void {
            if (Oberflaeche.befehlsfeldOffen)
                root.menueSchliessen();
        }
        function onZentraleOffenChanged(): void {
            if (Oberflaeche.zentraleOffen)
                root.menueSchliessen();
        }
        function onModusWahlOffenChanged(): void {
            if (Oberflaeche.modusWahlOffen)
                root.menueSchliessen();
        }
        function onZustandWahlOffenChanged(): void {
            if (Oberflaeche.zustandWahlOffen)
                root.menueSchliessen();
        }
        function onEinstellungenOffenChanged(): void {
            if (Oberflaeche.einstellungenOffen)
                root.menueSchliessen();
        }
        function onSperrenAngefordert(): void {
            root.menueSchliessen();
        }
        function onGesperrtChanged(): void {
            if (Oberflaeche.gesperrt)
                root.menueSchliessen();
        }
    }

    // zenos-ipc leiste menue system|raster|wlan|luefter · zenos-ipc leiste schliessen
    // (für Tests und eigene Tastenkürzel; öffnet auf dem ersten Bildschirm; «wlan» bzw. «luefter» ist das System-Menü
    // mit aufgeklappter WLAN-Liste bzw. Wahl des Lüfters)
    IpcHandler {
        target: "leiste"

        function menue(name: string): void {
            if (["system", "raster", "wlan", "luefter"].indexOf(name) < 0)
                return;
            const instanz = leisten.instances.length > 0 ? leisten.instances[0] : null;
            if (!instanz)
                return;
            if (name === "wlan" || name === "luefter") {
                // neu aufbauen, damit die Liste bzw. Wahl aufgeklappt beginnt
                root.menueSchliessen();
                root.menueWlanOffen = name === "wlan";
                root.menueLuefterOffen = name === "luefter";
                name = "system";
            }
            instanz.menueOeffnen(name);
        }

        function schliessen(): void {
            root.menueSchliessen();
        }
    }
}
