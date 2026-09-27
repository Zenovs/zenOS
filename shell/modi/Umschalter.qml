pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste
import qs.komponenten

// Modus- und Zustandswahl: kleine Menüs unter den Chips der Leiste (Klick) oder mittig
// (Super+M / Super+Z über zenos-ipc modus waehlen bzw. zustand waehlen). Tastatur: Pfeile, Enter, Esc.
// IPC «modus»: waehlen(), wechseln(id), aktiv() · «zustand»: waehlen(), starten(id), beenden(), aktiv()
Scope {
    id: root

    // "modus" | "zustand" | ""
    readonly property string offen: Oberflaeche.modusWahlOffen ? "modus" : Oberflaeche.zustandWahlOffen ? "zustand" : ""
    // Über ein Tastenkürzel geöffnet: mittig statt unter dem Chip
    property bool zentriert: false

    function umschalten(art: string, mittig: bool): void {
        if (offen === art) {
            schliessen();
            return;
        }
        zentriert = mittig;
        Oberflaeche.modusWahlOffen = art === "modus";
        Oberflaeche.zustandWahlOffen = art === "zustand";
    }

    function schliessen(): void {
        Oberflaeche.modusWahlOffen = false;
        Oberflaeche.zustandWahlOffen = false;
    }

    // Anker unter dem Chip. Die Leiste darf Oberflaeche.wahlAnker = { bildschirm, x } setzen;
    // sonst wird die Lage der Chips aus ihrem Aufbau berechnet (Leiste: Rand 10, Zeichen 30, Abstand 6).
    readonly property var _anchor: Oberflaeche["wahlAnker"] ?? null
    readonly property string _stufe: Zustaende.wirksam?.leiste === "aus" ? "aus" : "sichtbar"
    readonly property string _modeName: {
        const m = Modi.aktiv;
        const name = m && typeof m.name === "string" ? m.name.trim() : "";
        return name !== "" ? name : (m ? Modi.aktivId : "");
    }
    readonly property real _modeChipX: 10 + 30 + 6
    readonly property real _modeChipWidth: Math.ceil(modeMetrics.advanceWidth) + (_modeName !== "" ? 53 : 38)
    readonly property real _stateChipX: _stufe === "aus" ? 10 : _modeChipX + _modeChipWidth + 6

    function _anchorX(): real {
        if (_anchor && typeof _anchor.x === "number")
            return _anchor.x;
        return offen === "zustand" ? _stateChipX : _modeChipX;
    }

    function _screen(): var {
        const screens = Quickshell.screens;
        if (_anchor && typeof _anchor.bildschirm === "string") {
            const s = screens.find(s => s.name === _anchor.bildschirm);
            if (s)
                return s;
        }
        return screens.length > 0 ? screens[0] : null;
    }

    function _duration(z: var): string {
        const w = Zustaende.wirksamFuer(z.id);
        return w?.ende?.art === "timer" ? w.ende.minuten + " Min." : "";
    }

    TextMetrics {
        id: modeMetrics

        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseLabel
        text: root._modeName !== "" ? root._modeName : "Kein Modus"
    }

    // Andere Oberflächen gehen vor
    Connections {
        target: Oberflaeche

        function onModusWahlOffenChanged(): void {
            if (Oberflaeche.modusWahlOffen)
                Oberflaeche.zustandWahlOffen = false;
            else if (!Oberflaeche.zustandWahlOffen)
                root.zentriert = false;
        }
        function onZustandWahlOffenChanged(): void {
            if (Oberflaeche.zustandWahlOffen)
                Oberflaeche.modusWahlOffen = false;
            else if (!Oberflaeche.modusWahlOffen)
                root.zentriert = false;
        }
        function onBefehlsfeldOffenChanged(): void {
            if (Oberflaeche.befehlsfeldOffen)
                root.schliessen();
        }
        function onEinstellungenOffenChanged(): void {
            if (Oberflaeche.einstellungenOffen)
                root.schliessen();
        }
        function onSperrenAngefordert(): void {
            root.schliessen();
        }
    }

    IpcHandler {
        target: "modus"

        function waehlen(): void {
            root.umschalten("modus", true);
        }

        function wechseln(id: string): void {
            Modi.wechseln(id);
        }

        // ID des aktiven Modus ("" = keiner)
        function aktiv(): string {
            return Modi.aktivId;
        }
    }

    IpcHandler {
        target: "zustand"

        function waehlen(): void {
            root.umschalten("zustand", true);
        }

        function starten(id: string): void {
            Zustaende.starten(id, "manuell");
        }

        function beenden(): void {
            Zustaende.beenden();
        }

        // ID des aktiven Zustands ("" = keiner)
        function aktiv(): string {
            return Zustaende.aktivId;
        }
    }

    PanelWindow {
        id: fenster

        screen: root._screen()
        visible: root.offen !== ""
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        // Die Leiste bleibt bedienbar (ein zweiter Klick auf den Chip schliesst)
        margins.top: Theme.leisteHoehe
        exclusionMode: ExclusionMode.Ignore
        color: Theme.durchsichtig

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "zenos-wahl"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        MouseArea {
            anchors.fill: parent
            onClicked: root.schliessen()
        }

        Loader {
            id: lader

            active: fenster.visible
            focus: true
            sourceComponent: root.offen === "zustand" ? zustandKarte : modusKarte
            x: Math.round(root.zentriert ? (fenster.width - width) / 2 : Math.max(Theme.a2, Math.min(fenster.width - width - Theme.a2, root._anchorX())))
            y: root.zentriert ? Math.max(Theme.a1, Theme.befehlsfeldOben - Theme.leisteHoehe) : Theme.a1
        }
    }

    Component {
        id: modusKarte

        WahlKarte {
            id: karte

            titel: "Modus"
            focus: true
            onSchliessen: root.schliessen()

            Repeater {
                model: Modi.liste

                WahlEintrag {
                    required property var modelData
                    required property int index

                    width: karte.width - 2 * Theme.a2
                    text: typeof modelData.name === "string" && modelData.name.trim() !== "" ? modelData.name : modelData.id
                    mitPunkt: true
                    punktFarbe: Theme.akzentFarbe(Theme.akzentNamen.indexOf(modelData.akzent) >= 0 ? modelData.akzent : Theme.standardAkzent)
                    gewaehlt: modelData.id === Modi.aktivId
                    focus: modelData.id === Modi.aktivId || (Modi.aktivId === "" && index === 0)
                    onAusgeloest: {
                        root.schliessen();
                        Modi.wechseln(modelData.id);
                    }
                }
            }

            Item {
                visible: Modi.liste.length === 0
                width: karte.width - 2 * Theme.a2
                height: 36

                Text {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Noch kein Modus angelegt"
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }
            }

            Trenner {
                width: karte.width - 2 * Theme.a2
                height: 1
            }

            Item {
                width: 1
                height: Theme.a1
            }

            WahlEintrag {
                width: karte.width - 2 * Theme.a2
                text: "Neuer Modus …"
                symbol: "plus"
                gedaempft: true
                focus: Modi.liste.length === 0
                onAusgeloest: {
                    root.schliessen();
                    Oberflaeche.einstellungenOeffnen("modi/neu");
                }
            }

            WahlEintrag {
                visible: Modi.liste.length > 0
                width: karte.width - 2 * Theme.a2
                text: "Modi bearbeiten"
                symbol: "zahnrad"
                gedaempft: true
                onAusgeloest: {
                    root.schliessen();
                    Oberflaeche.einstellungenOeffnen(Modi.aktivId !== "" ? "modi/" + Modi.aktivId : "modi");
                }
            }
        }
    }

    Component {
        id: zustandKarte

        WahlKarte {
            id: karte

            titel: Modi.aktiv ? "Zustand · " + root._modeName : "Zustand"
            focus: true
            onSchliessen: root.schliessen()

            // Aktiver Zustand zuerst: beenden
            WahlEintrag {
                visible: Zustaende.aktivId !== ""
                width: karte.width - 2 * Theme.a2
                text: (Zustaende.aktiv?.name ?? Zustaende.aktivId) + " beenden"
                symbol: "x"
                wert: Zustaende.restMinuten >= 0 ? "noch " + Zustaende.restMinuten + " Min." : (Freigabe.aktiv && Zustaende.ausloeser === "bildschirmfreigabe" ? "geteilt" : "")
                focus: Zustaende.aktivId !== ""
                onAusgeloest: {
                    root.schliessen();
                    Zustaende.beenden();
                }
            }

            Trenner {
                visible: Zustaende.aktivId !== ""
                width: karte.width - 2 * Theme.a2
                height: 1
            }

            Repeater {
                model: Zustaende.startbar

                WahlEintrag {
                    required property var modelData
                    required property int index

                    width: karte.width - 2 * Theme.a2
                    text: typeof modelData.name === "string" && modelData.name.trim() !== "" ? modelData.name : modelData.id
                    wert: root._duration(modelData)
                    gewaehlt: modelData.id === Zustaende.aktivId
                    focus: Zustaende.aktivId === "" && index === 0
                    onAusgeloest: {
                        root.schliessen();
                        Zustaende.starten(modelData.id, "manuell");
                    }
                }
            }

            Item {
                visible: Zustaende.startbar.length === 0
                width: karte.width - 2 * Theme.a2
                height: 36

                Text {
                    x: 10
                    width: parent.width - 20
                    anchors.verticalCenter: parent.verticalCenter
                    text: Zustaende.liste.length === 0 ? "Noch kein Zustand angelegt" : "Keine Zustände zum Starten in diesem Modus"
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                    elide: Text.ElideRight
                }
            }

            Trenner {
                width: karte.width - 2 * Theme.a2
                height: 1
            }

            Item {
                width: 1
                height: Theme.a1
            }

            WahlEintrag {
                width: karte.width - 2 * Theme.a2
                text: "Zustände bearbeiten"
                symbol: "zahnrad"
                gedaempft: true
                focus: Zustaende.aktivId === "" && Zustaende.startbar.length === 0
                onAusgeloest: {
                    root.schliessen();
                    const erster = Zustaende.aktivId !== "" ? Zustaende.aktivId : (Zustaende.liste.length > 0 ? Zustaende.liste[0].id : "");
                    Oberflaeche.einstellungenOeffnen(erster !== "" ? "zustand/" + erster : "zustand/neu");
                }
            }
        }
    }
}
