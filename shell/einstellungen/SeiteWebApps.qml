pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste

// Seite «Web-Apps»: eine Website in einem eigenen Chrome-Fenster. Name, https-Adresse und optional
// ein Chrome-Profil; zenos-webapp prüft die Adresse, pflegt ~/.config/zenos/webapps.json und legt den
// Starter ~/.local/share/applications/zenos-webapp-<id>.desktop an. Liste mit Löschen.
Item {
    id: root

    property string unterauswahl

    // [{ id, name, url, chromeProfil? }]
    property var webapps: []
    property bool geladen: false
    property string fehlerText: ""
    // Chrome installiert? (DesktopEntries meldet neue und entfernte Starter von selbst)
    readonly property bool chromeDa: DesktopEntries.applications.values.some(e => e.id === "google-chrome" || e.id === "com.google.Chrome")
    // ID der Web-App, die auf «Wirklich entfernen?» wartet
    property string entfernenFrage: ""

    readonly property string zenosWebapp: Dienste.Pfade.bin + "/zenos-webapp"
    // Grobe Prüfung beim Tippen; die genaue macht zenos-webapp (nur https, keine Sonderzeichen)
    readonly property string _adresse: adresseFeld.text.trim()
    readonly property bool adresseOk: _adresse.length > 0 && /^(https:\/\/)?[^\s"'<>\\`]+$/i.test(_adresse) && !/^[a-z][a-z0-9+.-]*:\/\//i.test(_adresse.replace(/^https:\/\//i, ""))
    readonly property bool eingabeOk: nameFeld.text.trim().length > 0 && adresseOk

    function laden(): void {
        if (!listeAufruf.running)
            listeAufruf.exec({
                command: [root.zenosWebapp, "liste", "--json"]
            });
    }

    function hinzufuegen(): void {
        if (aenderung.running)
            return;
        const name = nameFeld.text.trim();
        const url = adresseFeld.text.trim();
        if (!name || !url) {
            fehlerText = !name ? "Name fehlt" : "Adresse fehlt";
            return;
        }
        if (/^http:\/\//i.test(url)) {
            fehlerText = "Nur https-Adressen sind erlaubt";
            return;
        }
        const befehl = [root.zenosWebapp, "anlegen", "--name", name, "--url", url];
        const profil = profilFeld.text.trim();
        if (profil)
            befehl.push("--profil", profil);
        fehlerText = "";
        aenderung.neu = true;
        aenderung.exec({
            command: befehl
        });
    }

    function entfernen(id: string): void {
        if (aenderung.running || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(id))
            return;
        entfernenFrage = "";
        aenderung.neu = false;
        aenderung.exec({
            command: [root.zenosWebapp, "loeschen", id]
        });
    }

    Component.onCompleted: {
        laden();
        // Das Formular ist der Zweck der Seite: gleich tippen können
        nameFeld.fokussieren();
    }

    // Änderungen von aussen (z. B. von Hand in webapps.json) übernehmen
    Connections {
        target: Dienste.Konfig

        function onGeaendert(art: string): void {
            if (art === "webapps")
                root.laden();
        }
    }

    Process {
        id: listeAufruf

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const liste = JSON.parse(text);
                    if (Array.isArray(liste))
                        root.webapps = liste.filter(w => w && typeof w.id === "string");
                } catch (e) {
                    // bleibt beim letzten Stand
                }
                root.geladen = true;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim().replace(/^zenos-webapp: /gm, "");
                if (t.length > 0)
                    root.fehlerText = t;
            }
        }
    }

    Process {
        id: aenderung

        property bool neu: false

        stderr: StdioCollector {
            id: aenderungFehler
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                if (neu) {
                    nameFeld.leeren();
                    adresseFeld.leeren();
                    profilFeld.leeren();
                    nameFeld.fokussieren();
                }
                root.fehlerText = "";
            } else {
                root.fehlerText = aenderungFehler.text.trim().replace(/^zenos-webapp: /gm, "") || "Nicht gespeichert";
            }
            root.laden();
        }
    }

    Seite {
        id: seite

        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Einstellungen"
            titel: "Web-Apps"
        }

        Text {
            width: Math.min(parent.width, 720)
            text: "Eine Web-App öffnet eine Website in einem eigenen Chrome-Fenster ohne Adressleiste. Sie erscheint im Befehlsfeld mit dem Hinweis «Web-App». Ohne Profil öffnet sie im Chrome-Profil des aktiven Modus."
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
            lineHeightMode: Text.FixedHeight
            lineHeight: 21
            wrapMode: Text.WordWrap
        }

        Row {
            visible: !root.chromeDa
            spacing: 8

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                name: "info"
                groesse: 14
                farbe: Theme.gedaempft
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Google Chrome ist noch nicht installiert. Web-Apps starten erst danach."
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseLabel
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Apps installieren"
                color: Theme.akzent
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseLabel

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Dienste.Oberflaeche.einstellungenSeite = "apps"
                }
            }
        }

        // Neue Web-App
        Grid {
            id: formular

            readonly property real spalte: (width - columnSpacing) / 2

            width: parent.width
            columns: 2
            columnSpacing: 40
            rowSpacing: 18

            Feld {
                width: formular.spalte
                beschriftung: "Name"

                Eingabe {
                    id: nameFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 60
                    platzhalter: "z. B. Kalender"
                    onAccepted: adresseFeld.fokussieren()
                }
            }

            Feld {
                width: formular.spalte
                beschriftung: "Adresse"
                hinweis: "nur https"

                Eingabe {
                    id: adresseFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 2048
                    platzhalter: "https://…"
                    fehler: root._adresse.length > 0 && !root.adresseOk
                    onAccepted: root.hinzufuegen()
                }
            }

            Feld {
                width: formular.spalte
                beschriftung: "Chrome-Profil"
                hinweis: "optional"

                Eingabe {
                    id: profilFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 100
                    platzhalter: "Profil des aktiven Modus"
                    onAccepted: root.hinzufuegen()
                }
            }

            Item {
                width: formular.spalte
                height: hinzufuegenKnopf.height + 21

                Knopf {
                    id: hinzufuegenKnopf

                    anchors.bottom: parent.bottom
                    implicitHeight: 38
                    text: "Hinzufügen"
                    symbol: "plus"
                    variante: "primaer"
                    enabled: root.eingabeOk && !aenderung.running
                    onClicked: root.hinzufuegen()
                }
            }
        }

        Text {
            visible: root.fehlerText.length > 0
            width: parent.width
            text: root.fehlerText
            color: Theme.fehler
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
            wrapMode: Text.WordWrap
        }

        // Liste
        Column {
            width: parent.width
            spacing: 0

            Item {
                width: parent.width
                height: 34

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Deine Web-Apps"
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }
            }

            Repeater {
                model: root.webapps

                Item {
                    id: zeile

                    required property var modelData
                    required property int index
                    readonly property bool fragt: root.entfernenFrage === modelData.id

                    width: parent.width
                    height: 52

                    Trenner {
                        width: parent.width
                    }

                    Trenner {
                        visible: zeile.index === root.webapps.length - 1
                        anchors.bottom: parent.bottom
                        width: parent.width
                    }

                    Text {
                        id: wName

                        width: 200
                        anchors.verticalCenter: parent.verticalCenter
                        text: zeile.modelData.name ?? zeile.modelData.id
                        color: Theme.text
                        font.family: Theme.schriftText
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }

                    Text {
                        x: wName.width + 16
                        width: knoepfe.x - x - 16 - (profil.visible ? profil.width + 16 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        text: zeile.modelData.url ?? ""
                        color: Theme.gedaempft
                        font.family: Theme.schriftMono
                        font.pixelSize: Theme.groesseKlein
                        elide: Text.ElideMiddle
                        textFormat: Text.PlainText
                    }

                    Pille {
                        id: profil

                        visible: typeof zeile.modelData.chromeProfil === "string" && zeile.modelData.chromeProfil.length > 0
                        x: knoepfe.x - 16 - width
                        anchors.verticalCenter: parent.verticalCenter
                        text: zeile.modelData.chromeProfil ?? ""
                        variante: "vorlage"
                    }

                    Row {
                        id: knoepfe

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            visible: zeile.fragt
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Wirklich entfernen?"
                            color: Theme.fehler
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                        }

                        Knopf {
                            visible: zeile.fragt
                            implicitHeight: 32
                            text: "Abbrechen"
                            variante: "still"
                            onClicked: root.entfernenFrage = ""
                        }

                        Knopf {
                            implicitHeight: 32
                            text: "Entfernen"
                            variante: zeile.fragt ? "gefahr" : "still"
                            onClicked: {
                                if (zeile.fragt)
                                    root.entfernen(zeile.modelData.id);
                                else
                                    root.entfernenFrage = zeile.modelData.id;
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.geladen && root.webapps.length === 0
                topPadding: 8
                text: "Noch keine Web-Apps."
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
            }
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: "~/.config/zenos/webapps.json · lokal, nicht im Repo"
            onFertig: Dienste.Oberflaeche.einstellungenOffen = false
        }
    }
}
