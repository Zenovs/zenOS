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
// vorher genau zeigt, was passiert, und einmal nachfragt. Dazu der SSH-Agent von 1Password und, was über
// den zen Installer kam (Dienst InstallerListe), mit «Entfernen …» (jedes Mal mit Passwort). unterauswahl
// «installer» scrollt dorthin.
Item {
    id: root

    property string unterauswahl

    // Ein Programm, das über den zen Installer kam (Zeile aus InstallerListe.zeilen): Symbol, Name, darunter Paket,
    // Version und seit wann, rechts «Entfernen …» (sekundär mit Schloss). Alles aus dem Paket als reiner Text.
    component InstallerZeile: Item {
        id: zeile

        required property var modelData

        implicitHeight: 60

        Trenner {
            anchors.top: parent.top
            width: parent.width
        }

        Symbol {
            id: zeichen

            x: 16
            anchors.verticalCenter: parent.verticalCenter
            name: "paket"
            groesse: 18
            farbe: Theme.gedaempft
        }

        Column {
            x: zeichen.x + 18 + 14
            width: knopf.x - x - 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                width: parent.width
                text: zeile.modelData.name
                color: Theme.text
                font.family: Theme.schriftText
                font.pixelSize: 15
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            Text {
                width: parent.width
                text: zeile.modelData.unter
                color: Theme.gedaempft
                font.family: Theme.schriftMono
                font.pixelSize: Theme.groesseKlein
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }

        Knopf {
            id: knopf

            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: 38
            variante: "sekundaer"
            text: zeile.modelData.knopf.text
            symbol: zeile.modelData.knopf.symbol
            enabled: zeile.modelData.knopf.aktiv
            Accessible.name: zeile.modelData.knopf.text + " " + zeile.modelData.name
            onClicked: Dienste.InstallerListe.entfernen(zeile.modelData.paket)
        }
    }

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
        onTriggered: {
            katalog.nachladen();
            Dienste.InstallerListe.aktualisieren();
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.visible
        onTriggered: {
            katalog.nachladen();
            Dienste.InstallerListe.aktualisieren();
        }
    }

    Component.onCompleted: {
        Dienste.InstallerListe.aktualisieren();
        _scrollen();
    }

    // «einstellungen oeffnen apps/installer»: der Abschnitt des zen Installers oben im sichtbaren Bereich. Die Liste der
    // Apps darüber kommt erst nach und nach; solange (höchstens 3 s) folgt die Lage jeder neuen Höhe des Inhalts.
    property bool _scrollFolgt: false

    function _zuInstaller(): void {
        if (root.unterauswahl !== "installer")
            return;
        const p = installerFeld.mapToItem(seite.flick.contentItem, 0, 0);
        seite.flick.contentY = Math.max(0, Math.min(seite.flick.contentHeight - seite.flick.height, p.y - 12));
    }

    function _scrollen(): void {
        _scrollFolgt = root.unterauswahl === "installer";
        scrollen.restart();
        scrollEnde.restart();
    }

    onUnterauswahlChanged: _scrollen()

    Connections {
        target: seite.flick

        function onContentHeightChanged(): void {
            if (root._scrollFolgt)
                scrollen.restart();
        }
    }

    Timer {
        id: scrollen

        interval: 100
        running: true
        onTriggered: root._zuInstaller()
    }

    Timer {
        id: scrollEnde

        interval: 3000
        onTriggered: root._scrollFolgt = false
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
                        Dienste.Oberflaeche.hinweis("Installation läuft im Terminal", "terminal");
                }
            }

            Knopf {
                visible: katalog.aktualisierbar.length > 0
                implicitHeight: 40
                text: "Aktualisieren …"
                variante: "sekundaer"
                onClicked: {
                    if (katalog.imTerminal("aktualisieren", katalog.aktualisierbar))
                        Dienste.Oberflaeche.hinweis("Aktualisierung läuft im Terminal", "terminal");
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

        // Was über den zen Installer kam (heruntergeladene .deb): je Zeile «Entfernen …» mit Passwort
        Feld {
            id: installerFeld

            width: parent.width
            beschriftung: "Über den zen Installer"

            Column {
                width: parent.width
                spacing: 10

                Column {
                    visible: Dienste.InstallerListe.zeilen.length > 0
                    width: parent.width

                    Repeater {
                        model: Dienste.InstallerListe.zeilen

                        InstallerZeile {
                            width: parent.width
                        }
                    }

                    Trenner {
                        width: parent.width
                    }
                }

                Text {
                    width: Math.min(parent.width, 720)
                    text: {
                        const l = Dienste.InstallerListe;
                        if (l.zeilen.length > 0)
                            return "«Entfernen …» verlangt jedes Mal dein Passwort und entfernt nur das Programm; seine Einstellungen bleiben. Nähme apt dabei weitere Pakete mit, lässt der zen Installer es stehen.";
                        if (!l.gelesen)
                            return "Einen Moment …";
                        if (l.fehlgeschlagen)
                            return "Die Liste liess sich nicht lesen. «zen install --liste» im Terminal zeigt mehr.";
                        return "Noch nichts. Ein Doppelklick auf eine heruntergeladene .deb öffnet den zen Installer; was du damit installierst, steht dann hier.";
                    }
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.45)
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }
            }
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: "zen apps · zen install --liste · Quellen in /etc/apt/sources.list.d/zenos-*.sources"
            onFertig: Dienste.Oberflaeche.einstellungenOffen = false
        }
    }
}
