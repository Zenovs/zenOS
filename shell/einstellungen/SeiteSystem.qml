pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste

// Seite «System»: Schalter «Firewall» (Dienst Firewall: Einschalten ohne, Ausschalten nur mit Passwort über
// polkit), «Updates · zenOS» (Dienst Kanal: Lage des signierten Kanals, «Jetzt prüfen», «Jetzt installieren», bei
// Firewall, Netz oder Boot «Zustimmen …» mit Passwort), «Updates · Ubuntu-Basis» (Dienst Basis: Pakete von Ubuntu und
// den Herstellerquellen, «Jetzt prüfen», «Jetzt installieren», bei Kernel, Firmware, Bootloader oder Entfernungen «Mit
// Passwort installieren», Neustart nötig) und «Automatisch installieren» (Zeitpunkt: Bei Sperre · Zeitfenster ·
// Jederzeit · Von Hand, gilt für das ganze Gerät und beide), Ausgabe von «zen version», Kurzprüfung mit «zen doctor
// --kurz» auf Knopfdruck und Hinweise aufs Terminal. unterauswahl «updates» scrollt zu den Updates.
Item {
    id: root

    property string unterauswahl

    // Lage eines Updates-Abschnitts: Symbol (16 px) und Titel
    component Lagezeile: Row {
        id: lagezeile

        property var symbol: ({
                symbol: "info",
                ton: "gedaempft"
            })
        property string titel

        spacing: 10

        Symbol {
            anchors.verticalCenter: parent.verticalCenter
            name: lagezeile.symbol.symbol
            groesse: 16
            farbe: lagezeile.symbol.ton === "akzent" ? Theme.akzent : lagezeile.symbol.ton === "warnung" ? Theme.warnung : Theme.gedaempft
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: lagezeile.titel
            textFormat: Text.PlainText
            color: Theme.text
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
        }
    }

    // Ruhiger Satz in gedaempft (13 px, Zeilenhöhe 1,45), reiner Text
    component Satz: Text {
        visible: text !== ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        lineHeightMode: Text.FixedHeight
        lineHeight: Math.round(font.pixelSize * 1.45)
        color: Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseLabel
    }

    // Werte zweispaltig: Titel 96 px in gedaempft, Werte in Geist Mono 13 (zu lang: am Ende gekürzt)
    component Wertezeilen: Column {
        id: werte

        property var zeilen: []

        spacing: 4
        visible: zeilen.length > 0

        Repeater {
            model: werte.zeilen

            Row {
                id: zeile

                required property var modelData

                spacing: 12

                Text {
                    width: 96
                    text: zeile.modelData.titel
                    textFormat: Text.PlainText
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }

                Text {
                    width: werte.width - 108
                    text: zeile.modelData.wert
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.schriftMono
                    font.pixelSize: Theme.groesseLabel
                }
            }
        }
    }

    // Zeitpunkt, wie ihn die Segmente zeigen: während des Setzens die neue Wahl, sonst die Datei
    readonly property string _zeitpunktArt: Dienste.Kanal.zeitpunktZiel !== "" ? Dienste.Kanal.zeitpunktZiel : Dienste.Kanal.zeitpunkt.art
    // Formularfehler unter dem Zeitfenster (nicht als Hinweis)
    property string _fensterFehler: ""

    readonly property var _zeitpunktOptionen: [
        {
            wert: "sperre",
            text: "Bei Sperre"
        },
        {
            wert: "fenster",
            text: "Zeitfenster"
        },
        {
            wert: "jederzeit",
            text: "Jederzeit"
        },
        {
            wert: "hand",
            text: "Von Hand"
        }
    ]

    function _zeitpunktWaehlen(art: string): void {
        _fensterFehler = "";
        const z = Dienste.Kanal.zeitpunkt;
        Dienste.Kanal.zeitpunktSetzen(art, z.von, z.bis);
    }

    function _fensterSetzen(von: string, bis: string): void {
        const problem = Dienste.Kanal.fensterProblem(von, bis);
        _fensterFehler = problem !== "" ? problem + "." : "";
        if (problem === "")
            Dienste.Kanal.zeitpunktSetzen("fenster", von, bis);
    }

    // «einstellungen oeffnen system/updates»: die Updates oben im sichtbaren Bereich
    function _zuUpdates(): void {
        if (root.unterauswahl !== "updates")
            return;
        const p = updatesFeld.mapToItem(seite.flick.contentItem, 0, 0);
        seite.flick.contentY = Math.max(0, Math.min(seite.flick.contentHeight - seite.flick.height, p.y - 12));
    }

    onUnterauswahlChanged: scrollen.restart()

    // Knöpfe der Updates: eine Bedienung zur Zeit (Kanal oder Basis), nicht während ein Update läuft
    readonly property bool _bedienbar: Dienste.Kanal.laeuft === "" && Dienste.Basis.laeuft === "" && !Dienste.Kanal.updateLaeuft

    readonly property string _zen: Dienste.Pfade.code + "/scripts/zen"
    property string versionText: ""
    property string pruefText: ""
    property bool pruefFehler: false

    // Während eines Wechsels zeigt der Schalter das Ziel; bricht die Passwortabfrage ab, springt er zurück
    function _firewallAn(): bool {
        return Dienste.Firewall.laeuft ? Dienste.Firewall.ziel : Dienste.Firewall.aktiv;
    }

    readonly property string _firewallStatus: {
        const f = Dienste.Firewall;
        if (!f.bekannt)
            return "ufw fehlt";
        if (f.laeuft)
            return f.ziel ? "Wird eingeschaltet …" : "Wartet auf dein Passwort …";
        return f.aktiv ? "An" : "Aus";
    }

    readonly property string _firewallText: {
        const f = Dienste.Firewall;
        if (!f.bekannt)
            return "ufw ist nicht installiert. install.sh richtet die Firewall ein.";
        if (f.aktiv)
            return "Eingehende Verbindungen sind gesperrt. Erlaubt bleibt nur SSH aus lokalen Netzen, höchstens fünf neue Verbindungen in 30 Sekunden. Ausschalten verlangt jedes Mal dein Passwort.";
        if (f.bewusstAus) {
            const seit = f.seit !== "" ? new Date(f.seit) : null;
            const wann = seit && !isNaN(seit.getTime()) ? " am " + seit.toLocaleString(Qt.locale("de_CH"), "d. MMMM 'um' HH:mm") : "";
            return "Eingehende Verbindungen sind nicht gesperrt. Du hast die Firewall" + wann + " ausgeschaltet; zen update lässt sie aus. Einschalten geht ohne Passwort.";
        }
        return "Eingehende Verbindungen sind nicht gesperrt. Einschalten geht ohne Passwort; sonst schaltet zen update sie ein.";
    }

    Component.onCompleted: {
        Dienste.Firewall.aktualisieren();
        Dienste.Kanal.aktualisieren();
        Dienste.Basis.aktualisieren();
    }

    // Erst nach dem Aufbau der Seite (die Spalte setzt die Positionen verzögert)
    Timer {
        id: scrollen

        interval: 100
        running: true
        onTriggered: root._zuUpdates()
    }

    Process {
        id: version

        command: [root._zen, "version"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.versionText = text.trim()
        }
        onExited: code => {
            if (code !== 0 && root.versionText === "")
                root.versionText = "zen version ist nicht verfügbar.";
        }
        onRunningChanged: {
            if (!running && root.versionText === "")
                root.versionText = "zen version ist nicht verfügbar.";
        }
    }

    Process {
        id: pruefung

        command: [root._zen, "doctor", "--kurz"]
        stdout: StdioCollector {
            onStreamFinished: {
                const zeilen = text.trim().split("\n");
                root.pruefText = zeilen[zeilen.length - 1] ?? "";
            }
        }
        onExited: code => {
            root.pruefFehler = code !== 0;
            if (root.pruefText === "")
                root.pruefText = "Keine Ausgabe von zen doctor.";
        }
    }

    Seite {
        id: seite

        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Einstellungen"
            titel: "System"
        }

        Feld {
            width: parent.width
            beschriftung: "Firewall"

            Column {
                width: parent.width
                spacing: 10

                Row {
                    spacing: 14

                    Schalter {
                        id: firewallSchalter

                        anchors.verticalCenter: parent.verticalCenter
                        enabled: Dienste.Firewall.bekannt && !Dienste.Firewall.laeuft
                        an: root._firewallAn()
                        beschriftung: "Firewall"
                        onUmgeschaltet: an => {
                            if (an)
                                Dienste.Firewall.einschalten();
                            else
                                Dienste.Firewall.ausschalten();
                            // Der Schalter folgt wieder dem Zustand (Bedienung hat die Bindung ersetzt)
                            firewallSchalter.an = Qt.binding(() => root._firewallAn());
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._firewallStatus
                        color: Theme.text
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                    }
                }

                Text {
                    width: parent.width
                    text: root._firewallText
                    wrapMode: Text.WordWrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.45)
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }
            }
        }

        Feld {
            id: updatesFeld

            width: parent.width
            beschriftung: "Updates · zenOS"

            Column {
                width: parent.width
                spacing: 12

                Lagezeile {
                    symbol: Dienste.Kanal.zustandSymbol
                    titel: Dienste.Kanal.zustandTitel
                }

                Satz {
                    width: parent.width
                    text: Dienste.Kanal.grundText
                }

                // Kanal, installierte und bereite Version, letzte Prüfung, Kontakt, Anker mit kurzen Fingerabdrücken
                Wertezeilen {
                    width: parent.width
                    zeilen: Dienste.Kanal.zeilen
                }

                Row {
                    spacing: 12

                    Knopf {
                        implicitHeight: 38
                        variante: "sekundaer"
                        text: Dienste.Kanal.laeuft === "pruefen" ? "Prüft …" : "Jetzt prüfen"
                        enabled: root._bedienbar
                        onClicked: Dienste.Kanal.pruefen()
                    }

                    Knopf {
                        visible: Dienste.Kanal.kannInstallieren || Dienste.Kanal.laeuft === "installieren"
                        implicitHeight: 38
                        variante: "primaer"
                        text: Dienste.Kanal.laeuft === "installieren" ? "Wird installiert …" : "Jetzt installieren"
                        enabled: root._bedienbar
                        onClicked: Dienste.Kanal.installieren()
                    }

                    Knopf {
                        visible: Dienste.Kanal.zustimmungObjekt !== "" || Dienste.Kanal.laeuft === "zustimmen"
                        implicitHeight: 38
                        variante: "sekundaer"
                        symbol: "schloss"
                        text: Dienste.Kanal.laeuft === "zustimmen" ? "Läuft …" : "Zustimmen …"
                        enabled: root._bedienbar
                        onClicked: Dienste.Kanal.zustimmen(Dienste.Kanal.zustimmungObjekt)
                    }
                }

                Satz {
                    width: parent.width
                    // Läuft ein Update, sagen es Titel und Erklärung oben schon
                    text: Dienste.Kanal.updateLaeuft ? "" : Dienste.Kanal.zustimmungText !== "" ? Dienste.Kanal.zustimmungText : Dienste.Kanal.installierenHinweis
                }
            }
        }

        // Pakete der Ubuntu-Basis (zenos-basis): getrennt vom Kanal, dieselben Bausteine
        Feld {
            width: parent.width
            beschriftung: "Updates · Ubuntu-Basis"

            Column {
                width: parent.width
                spacing: 12

                Lagezeile {
                    symbol: Dienste.Basis.zustandSymbol
                    titel: Dienste.Basis.zustandTitel
                }

                Satz {
                    width: parent.width
                    text: Dienste.Basis.grundText
                }

                // Ausstehend, Kernel/Boot, Entfernen, Hersteller, Neustart, letztes Update, Automatik, Geprüft, Liste
                Wertezeilen {
                    width: parent.width
                    zeilen: Dienste.Basis.zeilen
                }

                Row {
                    spacing: 12

                    Knopf {
                        implicitHeight: 38
                        variante: "sekundaer"
                        text: Dienste.Basis.laeuft === "pruefen" ? "Prüft …" : "Jetzt prüfen"
                        enabled: root._bedienbar
                        onClicked: Dienste.Basis.pruefen()
                    }

                    Knopf {
                        visible: Dienste.Basis.installierenListe !== "" || Dienste.Basis.laeuft === "installieren"
                        implicitHeight: 38
                        variante: "primaer"
                        text: Dienste.Basis.laeuft === "installieren" ? "Wird installiert …" : "Jetzt installieren"
                        enabled: root._bedienbar
                        onClicked: Dienste.Basis.installieren(Dienste.Basis.installierenListe)
                    }

                    // Kernel, Firmware, Bootloader oder Entfernungen: polkit fragt jedes Mal nach dem Passwort
                    Knopf {
                        visible: Dienste.Basis.zustimmungListe !== "" || Dienste.Basis.laeuft === "zustimmen"
                        implicitHeight: 38
                        variante: "sekundaer"
                        symbol: "schloss"
                        text: Dienste.Basis.laeuft === "zustimmen" ? "Läuft …" : "Mit Passwort installieren"
                        enabled: root._bedienbar
                        onClicked: Dienste.Basis.zustimmen(Dienste.Basis.zustimmungListe)
                    }
                }

                Satz {
                    width: parent.width
                    text: Dienste.Kanal.updateLaeuft ? "" : Dienste.Basis.knopfHinweis
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Automatisch installieren"
            hinweis: Dienste.Kanal.zeitpunkt.problem !== "" ? "Datei ungültig · es gilt «Bei Sperre»" : ""
            // Ein Problem, nichts Angepasstes: in der Warnfarbe, nicht im Akzent
            hinweisBetont: true
            akzent: Theme.warnung

            Column {
                width: parent.width
                spacing: 10

                Segmente {
                    id: zeitpunktSegmente

                    optionen: root._zeitpunktOptionen
                    aktiv: Dienste.Kanal.laeuft === ""
                    onGewaehlt: wert => root._zeitpunktWaehlen(wert)
                }

                // Segmente setzen «wert» bei einer Wahl selbst; das Binding folgt trotzdem weiter der Datei (und springt
                // zurück, wenn das Setzen scheitert)
                Binding {
                    target: zeitpunktSegmente
                    property: "wert"
                    value: root._zeitpunktArt
                }

                Row {
                    visible: root._zeitpunktArt === "fenster"
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Von"
                        color: Theme.text2
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                    }

                    Zeitfeld {
                        id: vonFeld

                        onGesetzt: zeit => root._fensterSetzen(zeit, bisFeld.zeit)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "bis"
                        color: Theme.text2
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                    }

                    Zeitfeld {
                        id: bisFeld

                        onGesetzt: zeit => root._fensterSetzen(vonFeld.zeit, zeit)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Uhr"
                        color: Theme.text2
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                    }
                }

                Binding {
                    target: vonFeld
                    property: "zeit"
                    value: Dienste.Kanal.zeitpunkt.von
                }

                Binding {
                    target: bisFeld
                    property: "zeit"
                    value: Dienste.Kanal.zeitpunkt.bis
                }

                Text {
                    visible: root._zeitpunktArt === "fenster" && root._fensterFehler !== ""
                    width: parent.width
                    text: root._fensterFehler
                    wrapMode: Text.Wrap
                    color: Theme.fehler
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }

                Text {
                    width: parent.width
                    text: Dienste.Kanal.zeitpunktErklaerung(root._zeitpunktArt, Dienste.Kanal.zeitpunkt.von, Dienste.Kanal.zeitpunkt.bis) + " " + Dienste.Kanal.zeitpunktImmer + " " + Dienste.Basis.automatikImmer
                    wrapMode: Text.Wrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.45)
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "zen version"

            Rectangle {
                width: parent.width
                height: Math.max(1, versionAusgabe.lineCount) * versionAusgabe.lineHeight + 28
                radius: Theme.radiusFeld
                color: Qt.alpha(Theme.flaeche2, 0.55)

                Text {
                    id: versionAusgabe

                    x: 16
                    y: 14
                    width: parent.width - 32
                    text: root.versionText !== "" ? root.versionText : "…"
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    // Feste Zeilenhöhe wie CSS line-height (proportional vervielfacht Qt die Schrifthöhe)
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.5)
                    color: Theme.text
                    font.family: Theme.schriftMono
                    font.pixelSize: Theme.groesseLabel
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Prüfbericht"

            Column {
                width: parent.width
                spacing: 10

                Row {
                    spacing: 16

                    Knopf {
                        implicitHeight: 38
                        variante: "sekundaer"
                        text: pruefung.running ? "Prüft …" : "Kurz prüfen"
                        enabled: !pruefung.running
                        onClicked: {
                            root.pruefText = "";
                            pruefung.running = true;
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.pruefText !== ""
                        text: root.pruefText
                        color: root.pruefFehler ? Theme.fehler : Theme.text
                        font.family: Theme.schriftMono
                        font.pixelSize: Theme.groesseLabel
                    }
                }

                Text {
                    width: parent.width
                    text: "Den ausführlichen Bericht zeigt «zen doctor» im Terminal. Er enthält keine Geheimnisse und keine Inhalte aus deiner Konfiguration."
                    wrapMode: Text.WordWrap
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Im Terminal"

            Column {
                width: parent.width
                spacing: 10

                Text {
                    width: parent.width
                    text: "«zen kanal» zeigt den ganzen Stand mit allen Fingerabdrücken. «zen update» bringt zuerst zenOS, dann die Pakete der Ubuntu-Basis, auch was dein «ja» braucht (etwa auf dev oder ein neuer Kernel); «zen rollback <tag>» geht zu einem früheren Stand von zenOS zurück."
                    wrapMode: Text.WordWrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.4)
                    color: Theme.text
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }

                Row {
                    spacing: 8

                    Kbd {
                        text: "zen kanal"
                    }

                    Kbd {
                        text: "zen update"
                    }

                    Kbd {
                        text: "zen doctor"
                    }
                }

                Knopf {
                    implicitHeight: 38
                    variante: "sekundaer"
                    symbol: "terminal"
                    text: "Terminal öffnen"
                    onClicked: Dienste.Aktionen.terminal()
                }
            }
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: "/opt/zenos · Code aus dem Git-Repo, persönliche Daten nur unter ~/.config/zenos"
            onFertig: Dienste.Oberflaeche.einstellungenOffen = false
        }
    }
}
