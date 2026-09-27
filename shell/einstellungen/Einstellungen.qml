pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste

// Einstellungen-Fenster (FloatingWindow mit labwc-Titelzeile) nach Entwurf 2 «Modi & Zustände»:
// Navigation (260 px) mit Modi, Zuständen, Rastern, Bildschirmen (scrollt), darunter fest Web-Apps, Apps,
// Allgemein, System; rechts die Seite Seite<Name>.qml aus diesem Ordner (Seiten anderer Module per Dateiname).
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

    // Raster bzw. Bildschirm-Profil, das die Seite zeigt (wie SeiteRaster/SeiteBildschirme: Unterauswahl,
    // sonst das aktive Raster bzw. aktuelle Profil, sonst das erste)
    readonly property string _rasterShown: {
        const liste = Dienste.Raster.liste;
        if (unterauswahl !== "" && liste.some(r => r.id === unterauswahl))
            return unterauswahl;
        if (liste.some(r => r.id === Dienste.Raster.aktivId))
            return Dienste.Raster.aktivId;
        return liste.length > 0 ? liste[0].id : "";
    }
    readonly property string _profileShown: {
        const profile = Dienste.Raster.profile;
        if (unterauswahl !== "" && profile.some(p => p.name === unterauswahl))
            return unterauswahl;
        const aktuell = Dienste.Raster.aktuellesProfil();
        if (profile.some(p => p.name === aktuell))
            return aktuell;
        return profile.length > 0 ? profile[0].name : "";
    }

    // ID, die gerade über «Neuer Modus» bzw. «Neuer Zustand» entstanden ist (Namensfeld bekommt den Fokus)
    property string neuAngelegt: ""

    function navigieren(pfad: string): void {
        Dienste.Oberflaeche.einstellungenSeite = pfad;
    }

    function schliessen(): void {
        Dienste.Oberflaeche.einstellungenOffen = false;
    }

    // Eigenschaft einer Seite binden, falls die Seite sie hat
    function _bind(seite: var, name: string, wert: var): void {
        if (seite && seite[name] !== undefined)
            seite[name] = Qt.binding(wert);
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

                    // Modi, Zustände, Raster und Bildschirme scrollen; die allgemeinen Seiten bleiben unten sichtbar
                    Flickable {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.rightMargin: 1
                        anchors.bottom: navFuss.top
                        contentHeight: navSpalte.implicitHeight + 16 + 8
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

                            // Vorlagen in fester Reihenfolge, dann eigene nach Name (wie die Seite und das Raster-Menü)
                            Repeater {
                                model: Dienste.Raster.liste

                                NavEintrag {
                                    required property var modelData

                                    width: navSpalte.width
                                    text: typeof modelData.name === "string" && modelData.name.trim() !== "" ? modelData.name : modelData.id
                                    gewaehlt: root.seite === "raster" && root._rasterShown === modelData.id
                                    onClicked: root.navigieren("raster/" + modelData.id)
                                }
                            }

                            NavEintrag {
                                visible: Dienste.Raster.liste.length === 0
                                width: navSpalte.width
                                text: "Alle Raster"
                                gewaehlt: root.seite === "raster"
                                onClicked: root.navigieren("raster")
                            }

                            NavTitel {
                                text: "Bildschirme"
                            }

                            Repeater {
                                model: Dienste.Raster.profile

                                NavEintrag {
                                    required property var modelData

                                    width: navSpalte.width
                                    text: modelData.name
                                    gewaehlt: root.seite === "bildschirme" && root._profileShown === modelData.name
                                    onClicked: root.navigieren("bildschirme/" + modelData.name)
                                }
                            }

                            NavEintrag {
                                visible: Dienste.Raster.profile.length === 0
                                width: navSpalte.width
                                text: "Bildschirm-Profile"
                                gewaehlt: root.seite === "bildschirme"
                                onClicked: root.navigieren("bildschirme")
                            }
                        }
                    }

                    Column {
                        id: navFuss

                        x: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        width: parent.width - 24 - 1
                        spacing: 2

                        Trenner {
                            x: 10
                            width: navFuss.width - 20
                        }

                        Item {
                            width: 1
                            height: 10
                        }

                        NavEintrag {
                            width: navFuss.width
                            text: "Web-Apps"
                            gewaehlt: root.seite === "webapps"
                            onClicked: root.navigieren("webapps")
                        }

                        NavEintrag {
                            width: navFuss.width
                            text: "Apps"
                            gewaehlt: root.seite === "apps"
                            onClicked: root.navigieren("apps")
                        }

                        NavEintrag {
                            width: navFuss.width
                            text: "Allgemein"
                            gewaehlt: root.seite === "allgemein"
                            onClicked: root.navigieren("allgemein")
                        }

                        NavEintrag {
                            width: navFuss.width
                            text: "System"
                            gewaehlt: root.seite === "system"
                            onClicked: root.navigieren("system")
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
                        root._bind(item, "unterauswahl", () => root.unterauswahl);
                        root._bind(item, "frischAngelegt", () => root.neuAngelegt !== "" && root.neuAngelegt === root.unterauswahl.split("@")[0]);
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
