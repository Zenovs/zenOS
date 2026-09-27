pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten
import qs.dienste

// Schritt 2 des ersten Starts: Zustimmung zu den proprietären Apps. Nichts wird ohne Klick
// installiert: «Installieren» öffnet ein Terminal mit «zen apps installieren …», das vorher zeigt,
// was passiert, und nachfragt. «Später» führt zu Einstellungen → Apps.
FocusScope {
    id: root

    property real spalte: 500
    readonly property int luecke: 120

    // Schritt abgeschlossen (Einrichtung schliessen)
    signal fertig

    implicitWidth: 2 * spalte + luecke
    implicitHeight: Math.max(einleitung.implicitHeight, formular.implicitHeight)

    // Beim Erscheinen gleich bedienbar
    Component.onCompleted: Qt.callLater(fokussieren)

    function fokussieren(): void {
        root.forceActiveFocus();
    }

    function installieren(): void {
        if (katalog.allesInstalliert) {
            fertig();
            return;
        }
        if (katalog.imTerminal("installieren", katalog.gewaehlt)) {
            Oberflaeche.hinweis("Installation läuft im Terminal");
            fertig();
        }
    }

    function spaeter(): void {
        if (!katalog.allesInstalliert)
            Oberflaeche.hinweis("Apps installierst du später unter Einstellungen → Apps");
        fertig();
    }

    Keys.onEscapePressed: spaeter()

    AppKatalog {
        id: katalog

        Component.onCompleted: laden()
    }

    Einleitung {
        id: einleitung

        width: root.spalte
        anchors.verticalCenter: parent.verticalCenter
        titel: "Apps von den\nHerstellern."
        text: "Chrome, VS Code, 1Password und coremail gehören nicht zu zenOS und kommen deshalb nicht mit dem Image. Mit deiner Zustimmung installiert zenOS sie direkt aus den offiziellen Quellen. Updates kommen danach von dort."
        fuss: ["nur mit Zustimmung", "alles im Terminal sichtbar", "jederzeit später"]
    }

    Column {
        id: formular

        x: root.spalte + root.luecke
        width: root.spalte
        anchors.verticalCenter: parent.verticalCenter
        spacing: 26

        Column {
            width: parent.width
            spacing: 8

            Frage {
                nummer: "05"
                text: "Was soll zenOS installieren?"
            }

            Rectangle {
                width: parent.width
                height: Math.max(60, liste.implicitHeight)
                radius: Theme.radiusFeld
                color: Theme.flaeche
                border.width: 1
                border.color: Theme.eingabeRand

                Column {
                    id: liste

                    width: parent.width

                    Repeater {
                        model: katalog.apps

                        AppZeile {
                            required property var modelData
                            required property int index

                            width: liste.width
                            app: modelData
                            gewaehlt: katalog.auswahl[modelData.id] !== false
                            trennlinie: index > 0
                            onUmgeschaltet: an => katalog.waehlen(modelData.id, an)
                        }
                    }
                }

                Text {
                    visible: katalog.apps.length === 0
                    anchors.centerIn: parent
                    text: katalog.fehlgeschlagen ? "Der Stand der Apps liess sich nicht lesen (zen apps status)." : "Einen Moment …"
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }
            }

            Text {
                width: parent.width
                text: katalog.allesInstalliert ? "Alles ist schon installiert. Updates kommen von den Herstellern." : "«Installieren» öffnet ein Terminal. Dort steht vorher genau, was passiert: Quellen, Schlüssel, Dateien. Du bestätigst einmal und gibst dort dein Passwort ein."
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseLabel
                lineHeightMode: Text.FixedHeight
                lineHeight: 20
                wrapMode: Text.WordWrap
            }
        }

        Row {
            topPadding: 4
            spacing: 12

            Knopf {
                text: katalog.allesInstalliert ? "Fertig" : "Installieren"
                variante: "primaer"
                schriftGroesse: 15
                enabled: katalog.allesInstalliert || katalog.gewaehlt.length > 0
                onClicked: root.installieren()
            }

            Knopf {
                visible: !katalog.allesInstalliert
                text: "Später"
                variante: "still"
                schriftGroesse: 15
                onClicked: root.spaeter()
            }
        }
    }
}
