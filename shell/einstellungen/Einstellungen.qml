pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste

// Einstellungen-Fenster (FloatingWindow mit labwc-Titelzeile) nach Entwurf 2 «Modi & Zustände»:
// Navigation (260 px) mit Modi, Zuständen, Rastern, Bildschirmen, dann Web-Apps, Apps, Allgemein,
// System; rechts die Seite Seite<Name>.qml aus diesem Ordner (Seiten anderer Module per Dateiname).
// Seite als "name" oder "name/unterauswahl", z. B. "modi/arbeit", "zustand/fokus", "zustand/fokus@arbeit",
// "modi/neu", "zustand/neu", "allgemein".
// IPC «einstellungen»: oeffnen(seite), schliessen()
Scope {
    id: root

    readonly property var _dateien: ({
            "modi": "SeiteModi.qml",
            "modus": "SeiteModi.qml",
            "zustand": "SeiteZustand.qml",
            "zustaende": "SeiteZustand.qml",
            "raster": "SeiteRaster.qml",
            "bildschirme": "SeiteBildschirme.qml",
            "webapps": "SeiteWebApps.qml",
            "web-apps": "SeiteWebApps.qml",
            "apps": "SeiteApps.qml",
            "allgemein": "SeiteAllgemein.qml",
            "system": "SeiteSystem.qml"
        })

    readonly property string angefragt: Dienste.Oberflaeche.einstellungenSeite
    readonly property string seite: {
        const name = angefragt.split("/")[0].toLowerCase();
        return _dateien[name] ? (name === "modus" ? "modi" : name === "zustaende" ? "zustand" : name === "web-apps" ? "webapps" : name) : "modi";
    }
    readonly property string unterauswahl: angefragt.indexOf("/") >= 0 ? angefragt.slice(angefragt.indexOf("/") + 1) : ""

    // ID, die gerade über «Neuer Modus» bzw. «Neuer Zustand» entstanden ist (Namensfeld bekommt den Fokus)
    property string neuAngelegt: ""

    function navigieren(pfad: string): void {
        Dienste.Oberflaeche.einstellungenSeite = pfad;
    }

    function schliessen(): void {
        Dienste.Oberflaeche.einstellungenOffen = false;
    }

    // «Neuer Modus» / «Neuer Zustand»: sofort anlegen und öffnen
    function _neuAnlegen(): void {
        if (unterauswahl !== "neu" || !Dienste.Oberflaeche.einstellungenOffen)
            return;
        if (seite === "modi") {
            const benutzt = Dienste.Modi.liste.map(m => m.akzent);
            const akzent = Theme.akzentNamen.find(a => benutzt.indexOf(a) < 0) ?? Theme.standardAkzent;
            const id = Dienste.Modi.anlegen({
                name: "Neuer Modus",
                akzent: akzent,
                zustaende: Dienste.Zustaende.liste.map(z => z.id)
            });
            neuAngelegt = id;
            navigieren(id !== "" ? "modi/" + id : "modi");
        } else if (seite === "zustand") {
            const id = Dienste.Zustaende.anlegen({
                name: "Neuer Zustand",
                mitteilungen: "nur-dringend",
                leiste: "normal",
                fenster: "normal",
                heute: true,
                widgets: true,
                ausloeser: ["manuell"],
                ende: {
                    art: "timer",
                    minuten: 30
                }
            });
            neuAngelegt = id;
            navigieren(id !== "" ? "zustand/" + id : "zustand");
        }
    }

    onAngefragtChanged: Qt.callLater(_neuAnlegen)

    Connections {
        target: Dienste.Oberflaeche

        function onEinstellungenOffenChanged(): void {
            Qt.callLater(root._neuAnlegen);
        }
    }

    IpcHandler {
        target: "einstellungen"

        function oeffnen(seite: string): void {
            Dienste.Aktionen.einstellungen(seite);
        }

        function schliessen(): void {
            root.schliessen();
        }
    }

    LazyLoader {
        active: Dienste.Oberflaeche.einstellungenOffen

        FloatingWindow {
            id: fenster

            readonly property var _bildschirm: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

            title: "Einstellungen"
            color: Theme.flaeche
            implicitWidth: Math.min(1240, (_bildschirm?.width ?? 1440) - 2 * Theme.a6)
            implicitHeight: Math.min(820, (_bildschirm?.height ?? 900) - Theme.leisteHoehe - Theme.titelzeile - 2 * Theme.a5)
            minimumSize: Qt.size(Math.min(960, implicitWidth), Math.min(600, implicitHeight))
            visible: true

            onClosed: root.schliessen()

            FocusScope {
                id: inhalt

                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: root.schliessen()

                // --- Navigation ---
                Rectangle {
                    id: navigation

                    width: 260
                    height: parent.height
                    color: Qt.alpha(Theme.grund, Theme.dunkel ? 0.7 : 0.6)

                    Rectangle {
                        anchors.right: parent.right
                        width: 1
                        height: parent.height
                        color: Theme.trennlinie
                    }

                    Flickable {
                        anchors.fill: parent
                        anchors.rightMargin: 1
                        contentHeight: navSpalte.implicitHeight + 32
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: navSpalte

                            x: 12
                            y: 16
                            width: parent.width - 24
                            spacing: 2

                            NavTitel {
                                text: "Modi"
                                erster: true
                            }

                            Repeater {
                                model: Dienste.Modi.liste

                                NavEintrag {
                                    required property var modelData

                                    width: navSpalte.width
                                    text: typeof modelData.name === "string" && modelData.name.trim() !== "" ? modelData.name : modelData.id
                                    mitPunkt: true
                                    punktFarbe: Theme.akzentFarbe(Theme.akzentNamen.indexOf(modelData.akzent) >= 0 ? modelData.akzent : Theme.standardAkzent)
                                    gewaehlt: root.seite === "modi" && (root.unterauswahl === modelData.id || (root.unterauswahl === "" && modelData.id === (Dienste.Modi.aktivId || Dienste.Modi.liste[0].id)))
                                    onClicked: root.navigieren("modi/" + modelData.id)
                                }
                            }

                            NavEintrag {
                                width: navSpalte.width
                                text: "Neuer Modus"
                                symbol: "plus"
                                gedaempft: true
                                onClicked: root.navigieren("modi/neu")
                            }

                            NavTitel {
                                text: "Zustände"
                            }

                            Repeater {
                                model: Dienste.Zustaende.liste

                                NavEintrag {
                                    required property var modelData

                                    width: navSpalte.width
                                    text: typeof modelData.name === "string" && modelData.name.trim() !== "" ? modelData.name : modelData.id
                                    gewaehlt: root.seite === "zustand" && (root.unterauswahl.split("@")[0] === modelData.id || (root.unterauswahl === "" && Dienste.Zustaende.liste[0].id === modelData.id))
                                    onClicked: root.navigieren("zustand/" + modelData.id)
                                }
                            }

                            NavEintrag {
                                width: navSpalte.width
                                text: "Neuer Zustand"
                                symbol: "plus"
                                gedaempft: true
                                onClicked: root.navigieren("zustand/neu")
                            }

                            NavTitel {
                                text: "Raster"
                            }

                            Repeater {
                                model: Dienste.Konfig.raster

                                NavEintrag {
                                    required property var modelData

                                    width: navSpalte.width
                                    text: typeof modelData.name === "string" && modelData.name.trim() !== "" ? modelData.name : modelData.id
                                    gewaehlt: root.seite === "raster" && root.unterauswahl === modelData.id
                                    onClicked: root.navigieren("raster/" + modelData.id)
                                }
                            }

                            NavEintrag {
                                visible: Dienste.Konfig.raster.length === 0
                                width: navSpalte.width
                                text: "Alle Raster"
                                gewaehlt: root.seite === "raster"
                                onClicked: root.navigieren("raster")
                            }

                            NavTitel {
                                text: "Bildschirme"
                            }

                            Repeater {
                                model: Array.isArray(Dienste.Konfig.bildschirme?.profile) ? Dienste.Konfig.bildschirme.profile.filter(p => p && typeof p.name === "string") : []

                                NavEintrag {
                                    required property var modelData

                                    width: navSpalte.width
                                    text: modelData.name
                                    gewaehlt: root.seite === "bildschirme" && root.unterauswahl === modelData.name
                                    onClicked: root.navigieren("bildschirme/" + modelData.name)
                                }
                            }

                            NavEintrag {
                                visible: !(Array.isArray(Dienste.Konfig.bildschirme?.profile) && Dienste.Konfig.bildschirme.profile.length > 0)
                                width: navSpalte.width
                                text: "Bildschirm-Profile"
                                gewaehlt: root.seite === "bildschirme"
                                onClicked: root.navigieren("bildschirme")
                            }

                            Item {
                                width: 1
                                height: 14
                            }

                            Trenner {
                                x: 10
                                width: navSpalte.width - 20
                            }

                            Item {
                                width: 1
                                height: 12
                            }

                            NavEintrag {
                                width: navSpalte.width
                                text: "Web-Apps"
                                gewaehlt: root.seite === "webapps"
                                onClicked: root.navigieren("webapps")
                            }

                            NavEintrag {
                                width: navSpalte.width
                                text: "Apps"
                                gewaehlt: root.seite === "apps"
                                onClicked: root.navigieren("apps")
                            }

                            NavEintrag {
                                width: navSpalte.width
                                text: "Allgemein"
                                gewaehlt: root.seite === "allgemein"
                                onClicked: root.navigieren("allgemein")
                            }

                            NavEintrag {
                                width: navSpalte.width
                                text: "System"
                                gewaehlt: root.seite === "system"
                                onClicked: root.navigieren("system")
                            }
                        }
                    }
                }

                // --- Seite ---
                Loader {
                    id: seitenLader

                    anchors.left: navigation.right
                    anchors.right: parent.right
                    height: parent.height
                    focus: true
                    source: root._dateien[root.seite] ?? "SeiteModi.qml"

                    // Seiten haben «unterauswahl» (alle) und «frischAngelegt» (Modi, Zustand)
                    onLoaded: {
                        const seite = item;
                        if (seite && seite["unterauswahl"] !== undefined)
                            seite["unterauswahl"] = Qt.binding(() => root.unterauswahl);
                        if (seite && seite["frischAngelegt"] !== undefined)
                            seite["frischAngelegt"] = Qt.binding(() => root.neuAngelegt !== "" && root.neuAngelegt === root.unterauswahl.split("@")[0]);
                    }
                    onStatusChanged: {
                        if (status === Loader.Error)
                            console.warn("Einstellungen: Seite lässt sich nicht laden:", source);
                    }
                }

                // Eine Seite, die nicht lädt (Fehler in der Datei eines anderen Moduls), bleibt ruhig leer
                Text {
                    visible: seitenLader.status === Loader.Error
                    anchors.centerIn: seitenLader
                    text: "Diese Seite lässt sich gerade nicht öffnen."
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }
            }
        }
    }

    component NavTitel: Item {
        property alias text: titel.text
        property bool erster: false

        width: 236
        height: (erster ? 0 : 18) + 6 + titel.implicitHeight

        Abschnittstitel {
            id: titel

            x: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
        }
    }
}
