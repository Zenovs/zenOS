pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste
import qs.komponenten

// Modus- und Zustandswahl: kleine Menüs unter den Chips der Leiste (Klick, Oberflaeche.wahlAnker) oder
// mittig (Super+M / Super+Z über zenos-ipc modus waehlen bzw. zustand waehlen). Tastatur: Pfeile, Enter, Esc.
// Während der Einrichtung öffnen die Menüs nicht.
// IPC «modus»: waehlen(), wechseln(id), aktiv() · «zustand»: waehlen(), starten(id), beenden(), aktiv()
Scope {
    id: root

    // "modus" | "zustand" | ""
    readonly property string offen: Oberflaeche.modusWahlOffen ? "modus" : Oberflaeche.zustandWahlOffen ? "zustand" : ""
    // Ohne Anker (Tastenkürzel, Befehlsfeld): mittig statt unter dem Chip
    property bool zentriert: false

    // Über IPC (Super+M / Super+Z): immer mittig, auch wenn vorher ein Chip geklickt wurde
    function umschalten(art: string): void {
        if (Oberflaeche.einrichtungOffen)
            return;
        if (offen === art) {
            schliessen();
            return;
        }
        Oberflaeche.wahlAnker = null;
        Oberflaeche.modusWahlOffen = art === "modus";
        Oberflaeche.zustandWahlOffen = art === "zustand";
    }

    function schliessen(): void {
        Oberflaeche.modusWahlOffen = false;
        Oberflaeche.zustandWahlOffen = false;
    }

    // Ort der Karte, beim Öffnen festgehalten. Die Leiste setzt Oberflaeche.wahlAnker = { bildschirm, x }
    // vor dem Klick auf einen Chip (x in Fensterkoordinaten der Leiste = des Bildschirms); wer ohne Chip
    // öffnet, setzt ihn auf null. Ohne gültigen Anker erscheint die Karte mittig auf dem Bildschirm des
    // aktiven Fensters, sonst auf dem ersten.
    // Festhalten statt binden: Sobald die Karte den Tastaturfokus hat, ist kein Fenster mehr aktiv.
    property string _screenName: ""
    property real _anchorX: -1
    // Hier gebunden, damit ToplevelManager schon beim Start die Fenster kennt (er füllt sich erst nach dem
    // ersten Zugriff, asynchron)
    readonly property var _activeToplevel: ToplevelManager.activeToplevel

    readonly property var _screen: {
        const screens = Quickshell.screens;
        const s = _screenName !== "" ? screens.find(x => x.name === _screenName) : null;
        return s ?? (screens.length > 0 ? screens[0] : null);
    }

    function _remember(): void {
        const anchor = Oberflaeche.wahlAnker;
        const name = anchor && typeof anchor.bildschirm === "string" ? anchor.bildschirm : "";
        const x = anchor && typeof anchor.x === "number" && isFinite(anchor.x) ? Math.max(0, anchor.x) : -1;
        // Ein Anker auf einem inzwischen abgezogenen Bildschirm gilt nicht
        if (name !== "" && x >= 0 && Quickshell.screens.some(s => s.name === name)) {
            zentriert = false;
            _anchorX = x;
            _screenName = name;
        } else {
            zentriert = true;
            _anchorX = -1;
            _screenName = _screenOf(_activeToplevel) || (Quickshell.screens[0]?.name ?? "");
        }
    }

    // Name des (ersten) Bildschirms eines Fensters (Toplevel) oder ""
    function _screenOf(toplevel: var): string {
        const screens = toplevel ? toplevel.screens : null;
        const s = screens && screens.length > 0 ? screens[0] : null;
        return s && typeof s.name === "string" ? s.name : "";
    }

    readonly property string _modeName: {
        const m = Modi.aktiv;
        const name = m && typeof m.name === "string" ? m.name.trim() : "";
        return name !== "" ? name : (m ? Modi.aktivId : "");
    }

    function _duration(z: var): string {
        const w = Zustaende.wirksamFuer(z.id);
        return w?.ende?.art === "timer" ? w.ende.minuten + " Min." : "";
    }

    // Andere Oberflächen gehen vor. Während der Einrichtung bleibt die Wahl zu (wie das Befehlsfeld): Die
    // Karte läge über ihr, und «… bearbeiten» bzw. «Neuer Modus» öffneten die Einstellungen unsichtbar
    // hinter ihrer Vollfläche.
    Connections {
        target: Oberflaeche

        function onModusWahlOffenChanged(): void {
            if (Oberflaeche.modusWahlOffen && Oberflaeche.einrichtungOffen) {
                Oberflaeche.modusWahlOffen = false;
            } else if (Oberflaeche.modusWahlOffen) {
                Oberflaeche.zustandWahlOffen = false;
                root._remember();
            } else if (!Oberflaeche.zustandWahlOffen) {
                root.zentriert = false;
            }
        }
        function onZustandWahlOffenChanged(): void {
            if (Oberflaeche.zustandWahlOffen && Oberflaeche.einrichtungOffen) {
                Oberflaeche.zustandWahlOffen = false;
            } else if (Oberflaeche.zustandWahlOffen) {
                Oberflaeche.modusWahlOffen = false;
                root._remember();
            } else if (!Oberflaeche.modusWahlOffen) {
                root.zentriert = false;
            }
        }
        function onEinrichtungOffenChanged(): void {
            if (Oberflaeche.einrichtungOffen)
                root.schliessen();
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
            root.umschalten("modus");
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
            root.umschalten("zustand");
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

        screen: root._screen
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

            // Breite des Bildschirms statt des Fensters: das Fenster kennt seine Breite erst nach dem Einblenden
            readonly property real _spanWidth: root._screen?.width ?? fenster.width

            active: fenster.visible
            focus: true
            sourceComponent: root.offen === "zustand" ? zustandKarte : modusKarte
            x: Math.round(root.zentriert ? (_spanWidth - width) / 2 : Math.max(Theme.a2, Math.min(_spanWidth - width - Theme.a2, root._anchorX)))
            y: root.zentriert ? Math.max(Theme.a1, Theme.befehlsfeldOben - Theme.leisteHoehe) : Theme.a1
        }
    }

    Component {
        id: modusKarte

        WahlKarte {
            id: modusKarteInhalt

            titel: "Modus"
            focus: true
            onSchliessen: root.schliessen()

            Repeater {
                model: Modi.liste

                WahlEintrag {
                    required property var modelData
                    required property int index

                    width: modusKarteInhalt.width - 2 * Theme.a2
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
                width: modusKarteInhalt.width - 2 * Theme.a2
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
                width: modusKarteInhalt.width - 2 * Theme.a2
                height: 1
            }

            Item {
                width: 1
                height: Theme.a1
            }

            WahlEintrag {
                width: modusKarteInhalt.width - 2 * Theme.a2
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
                width: modusKarteInhalt.width - 2 * Theme.a2
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
            id: zustandKarteInhalt

            titel: Modi.aktiv ? "Zustand · " + root._modeName : "Zustand"
            focus: true
            onSchliessen: root.schliessen()

            // Aktiver Zustand zuerst: beenden
            WahlEintrag {
                visible: Zustaende.aktivId !== ""
                width: zustandKarteInhalt.width - 2 * Theme.a2
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
                width: zustandKarteInhalt.width - 2 * Theme.a2
                height: 1
            }

            Repeater {
                model: Zustaende.startbar

                WahlEintrag {
                    required property var modelData
                    required property int index

                    width: zustandKarteInhalt.width - 2 * Theme.a2
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
                width: zustandKarteInhalt.width - 2 * Theme.a2
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
                width: zustandKarteInhalt.width - 2 * Theme.a2
                height: 1
            }

            Item {
                width: 1
                height: Theme.a1
            }

            WahlEintrag {
                width: zustandKarteInhalt.width - 2 * Theme.a2
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
