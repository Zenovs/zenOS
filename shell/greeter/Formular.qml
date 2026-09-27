pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten

// Anmeldeformular (380 px) nach dem Sperrbildschirm von Entwurf 2: Konto (nur ohne eindeutiges Konto),
// Passwort, «Anmelden» und eine Zeile für Meldungen. Die Meldungszeile hat immer ihre Höhe,
// damit beim Einblenden nichts springt.
Item {
    id: root

    required property Konten konten
    required property Ablauf ablauf

    // Login-Name des gewählten Kontos (bei genau einem Konto vorausgewählt)
    property string gewaehlt: konten.liste.length === 1 ? konten.liste[0].name : ""
    readonly property bool mitAuswahl: konten.liste.length > 1
    readonly property bool mitNamensfeld: konten.liste.length === 0

    function fokussieren(): void {
        if (mitNamensfeld && namensfeld.text.length === 0)
            namensfeld.fokussieren();
        else
            passwortfeld.fokussieren();
    }

    function absenden(): void {
        if (ablauf.wartetAufEingabe) {
            ablauf.antworten(passwortfeld.text);
            passwortfeld.leeren();
            return;
        }
        if (ablauf.beschaeftigt)
            return;
        const benutzer = mitNamensfeld ? namensfeld.text.trim() : gewaehlt;
        if (benutzer.length === 0) {
            if (mitAuswahl)
                ablauf.melden("Bitte zuerst ein Konto wählen.", false);
            fokussieren();
            return;
        }
        if (passwortfeld.text.length === 0) {
            passwortfeld.fokussieren();
            return;
        }
        ablauf.anmelden(benutzer, !mitNamensfeld);
    }

    implicitWidth: 380
    implicitHeight: spalte.implicitHeight

    Connections {
        target: root.ablauf

        function onAntwortGebraucht(): void {
            root.ablauf.antworten(passwortfeld.text);
            passwortfeld.leeren();
        }

        function onFehlgeschlagen(): void {
            passwortfeld.leeren();
            root.fokussieren();
        }
    }

    Column {
        id: spalte

        width: parent.width
        spacing: 10

        // Mehrere Konten: wählen
        Text {
            visible: root.mitAuswahl
            text: "Konto"
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
        }

        Flow {
            visible: root.mitAuswahl
            width: parent.width
            spacing: 8

            Repeater {
                model: root.mitAuswahl ? root.konten.liste : []

                Chip {
                    required property var modelData

                    text: modelData.anzeige
                    variante: root.gewaehlt === modelData.name ? "gefuellt" : "umrandet"
                    mitPunkt: root.gewaehlt === modelData.name
                    onClicked: {
                        root.gewaehlt = modelData.name;
                        passwortfeld.fokussieren();
                    }
                }
            }
        }

        // Kein Konto gefunden: Namen eintippen
        Text {
            visible: root.mitNamensfeld
            text: "Benutzername"
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
        }

        Eingabe {
            id: namensfeld

            visible: root.mitNamensfeld
            width: parent.width
            platzhalter: "Benutzername"
            nurLesen: root.ablauf.beschaeftigt || root.ablauf.wartetAufEingabe
            onAccepted: passwortfeld.fokussieren()
        }

        Text {
            width: parent.width
            text: root.ablauf.wartetAufEingabe && root.ablauf.frage.length > 0 ? root.ablauf.frage : "Passwort"
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
            elide: Text.ElideRight
        }

        Row {
            width: parent.width
            spacing: 8

            Eingabe {
                id: passwortfeld

                width: parent.width - knopf.width - parent.spacing
                passwort: !(root.ablauf.wartetAufEingabe && root.ablauf.frageSichtbar)
                platzhalter: root.ablauf.wartetAufEingabe ? "" : "Passwort"
                nurLesen: root.ablauf.beschaeftigt
                fehler: root.ablauf.meldungFehler && root.ablauf.meldung.length > 0 && text.length === 0
                onAccepted: root.absenden()
                onTextChanged: {
                    if (root.ablauf.meldungFehler && text.length > 0)
                        root.ablauf.meldung = "";
                }
                Keys.onEscapePressed: {
                    passwortfeld.leeren();
                    root.ablauf.abbrechen();
                }
            }

            // Gleich breit für «Anmelden» und «Weiter», damit das Feld nicht springt
            TextMetrics {
                id: knopfText

                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
                font.weight: Font.Medium
                text: "Anmelden"
            }

            Knopf {
                id: knopf

                width: Math.max(implicitWidth, Math.ceil(knopfText.width) + 40)
                text: root.ablauf.wartetAufEingabe ? "Weiter" : "Anmelden"
                variante: "primaer"
                enabled: root.ablauf.verfuegbar && !root.ablauf.beschaeftigt
                onClicked: root.absenden()
            }
        }

        // Meldung: Fehler in fehler, Hinweise gedämpft; die Zeile bleibt immer gleich hoch
        Text {
            width: parent.width
            height: Math.max(implicitHeight, 20)
            text: root.ablauf.meldung
            color: root.ablauf.meldungFehler ? Theme.fehler : Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
}
