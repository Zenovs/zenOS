pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.einrichtung
import qs.dienste as Dienste

// Seite «Apps»: Stand der proprietären Apps (installiert, Version, Herkunft) und der gleiche Ablauf
// wie beim ersten Start: «Installieren …» öffnet ein Terminal mit «zen apps installieren …», das
// vorher genau zeigt, was passiert, und einmal nachfragt. Dazu der SSH-Agent von 1Password.
Item {
    id: root

    property string unterauswahl

    readonly property var einsPasswort: katalog.apps.find(a => a.id === "1password") ?? null

    AppKatalog {
        id: katalog

        Component.onCompleted: laden()
    }

    // Nach einer Installation im Terminal den Stand neu lesen: dpkg meldet Paketänderungen,
    // 1Password (Archiv) sieht nur der regelmässige Blick, solange die Seite offen ist.
    FileView {
        path: "/var/lib/dpkg/status"
        watchChanges: true
        printErrors: false
        onFileChanged: nachladen.restart()
    }

    Timer {
        id: nachladen

        interval: 1500
        onTriggered: katalog.nachladen()
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.visible
        onTriggered: katalog.nachladen()
    }

    Seite {
        id: seite

        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Einstellungen"
            titel: "Apps"
        }

        Text {
            width: Math.min(parent.width, 720)
            text: "Proprietäre Apps gehören nicht zu zenOS und kommen nie ins Image. Auf deinen Wunsch installiert zenOS sie direkt aus den offiziellen Quellen der Hersteller; Updates kommen danach von dort. «Installieren …» öffnet ein Terminal und zeigt vorher genau, was passiert."
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
            lineHeightMode: Text.FixedHeight
            lineHeight: 21
            wrapMode: Text.WordWrap
        }

        Column {
            width: parent.width

            Repeater {
                model: katalog.apps

                AppZeile {
                    required property var modelData
                    required property int index

                    width: parent.width
                    app: modelData
                    gewaehlt: katalog.auswahl[modelData.id] !== false
                    onUmgeschaltet: an => katalog.waehlen(modelData.id, an)
                }
            }

            Trenner {
                visible: katalog.apps.length > 0
                width: parent.width
            }

            Text {
                visible: katalog.apps.length === 0
                topPadding: 8
                text: katalog.fehlgeschlagen ? "Der Stand der Apps liess sich nicht lesen. «zen apps status» im Terminal zeigt mehr." : "Einen Moment …"
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
            }
        }

        Row {
            spacing: 12

            Knopf {
                visible: katalog.installierbar.length > 0
                implicitHeight: 40
                text: "Installieren …"
                variante: "primaer"
                enabled: katalog.gewaehlt.length > 0
                onClicked: {
                    if (katalog.imTerminal("installieren", katalog.gewaehlt))
                        Dienste.Oberflaeche.hinweis("Installation läuft im Terminal");
                }
            }

            Knopf {
                visible: katalog.aktualisierbar.length > 0
                implicitHeight: 40
                text: "Aktualisieren …"
                variante: "sekundaer"
                onClicked: {
                    if (katalog.imTerminal("aktualisieren", katalog.aktualisierbar))
                        Dienste.Oberflaeche.hinweis("Aktualisierung läuft im Terminal");
                }
            }
        }

        Text {
            visible: katalog.apps.some(a => a.installiert)
            width: Math.min(parent.width, 720)
            text: "Chrome, VS Code und die 1Password-CLI aktualisiert apt mit den Systemupdates. «Aktualisieren …» holt neue Versionen von 1Password, coremail und Nubix."
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
            wrapMode: Text.WordWrap
        }

        // SSH-Agent von 1Password
        Feld {
            visible: root.einsPasswort?.installiert === true
            width: parent.width
            beschriftung: "SSH-Agent von 1Password"

            Column {
                width: parent.width
                spacing: 10

                Row {
                    spacing: 10

                    Pille {
                        anchors.verticalCenter: parent.verticalCenter
                        text: katalog.agent.socket ? "läuft" : "aus"
                        variante: katalog.agent.socket ? "aktiv" : "vorlage"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "~/.1password/agent.sock" + (katalog.agent.konfiguriert ? " · SSH_AUTH_SOCK gesetzt" : " · SSH_AUTH_SOCK noch nicht gesetzt (zen benutzer)")
                        color: Theme.gedaempft
                        font.family: Theme.schriftMono
                        font.pixelSize: Theme.groesseKlein
                    }
                }

                Text {
                    width: Math.min(parent.width, 720)
                    text: "Einschalten in 1Password: Einstellungen → Entwickler → SSH-Agent. Apps der Sitzung nutzen ihn ab der nächsten Anmeldung, neue Terminals sofort. ~/.ssh und der SSH-Server bleiben unverändert."
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                    wrapMode: Text.WordWrap
                }
            }
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: "zen apps · Quellen in /etc/apt/sources.list.d/zenos-*.sources"
            onFertig: Dienste.Oberflaeche.einstellungenOffen = false
        }
    }
}
