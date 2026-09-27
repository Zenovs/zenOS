pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten
import qs.dienste

// Schritt 1 des ersten Starts nach Entwurf 2: Name, Ort, Erscheinungsbild, erster Modus.
// «Einrichten» speichert (Einstellungen, Modus über den Modi-Dienst), «Überspringen» nur
// eingerichtet = true. Enter richtet ein, Tab geht die Felder in Leserichtung durch.
FocusScope {
    id: root

    // Breite einer Spalte (Entwurf: 500 px bei 1120 px Gesamtbreite)
    property real spalte: 500
    readonly property int luecke: 120

    // Schritt abgeschlossen (weiter zu den Apps)
    signal fertig

    property string fehlerText: ""
    property bool _laeuft: false
    // Modus, der angelegt wird, sobald die Konfiguration bereit und gelesen ist
    property var _modusWartet: null

    implicitWidth: 2 * spalte + luecke
    implicitHeight: Math.max(einleitung.implicitHeight, formular.implicitHeight)

    // Beim Erscheinen: bisherige Angaben übernehmen (erneut geöffnet) und gleich bedienbar sein
    Component.onCompleted: {
        nameFeld.text = Einstellungen.name;
        ortFeld.text = Einstellungen.ort;
        Qt.callLater(fokussieren);
    }

    function fokussieren(): void {
        nameFeld.fokussieren();
    }

    function einrichten(): void {
        if (_laeuft)
            return;
        _laeuft = true;
        fehlerText = "";
        Einstellungen.name = nameFeld.text.trim().slice(0, 60);
        Einstellungen.ort = ortFeld.text.trim().slice(0, 100);
        Einstellungen.erscheinungsbild = erscheinung.wert;
        Einstellungen.eingerichtet = true;
        Einstellungen.speichern();

        const modusName = modusFeld.text.trim().slice(0, 60);
        if (modusName.length === 0) {
            _abschliessen();
            return;
        }
        _modusWartet = {
            name: modusName,
            akzent: farbwahl.auswahl
        };
        if (_konfigBereit())
            _modusAnlegen();
        else
            konfigWarten.start();
    }

    // Modi und Zustände sind gelesen: Der neue Modus bekommt die ID, die noch frei ist, und alle
    // Zustände (Fokus, Sitzung), die schon bereitliegen
    function _konfigBereit(): bool {
        return Konfig.verfuegbar && Konfig.geladen;
    }

    function ueberspringen(): void {
        if (_laeuft)
            return;
        _laeuft = true;
        Einstellungen.eingerichtet = true;
        Einstellungen.speichern();
        _abschliessen();
    }

    function _modusAnlegen(): void {
        konfigWarten.stop();
        const daten = _modusWartet;
        _modusWartet = null;
        if (!daten)
            return;
        // Gibt es den Modus schon (Einrichtung erneut geöffnet), wird er nur aktiviert
        const vorhanden = Modi.liste.find(m => String(m.name ?? "").toLowerCase() === daten.name.toLowerCase());
        if (vorhanden) {
            Modi.wechseln(vorhanden.id);
            _abschliessen();
            return;
        }
        const neu = {
            name: daten.name,
            akzent: Theme.akzentNamen.indexOf(daten.akzent) >= 0 ? daten.akzent : Theme.standardAkzent
        };
        // Ohne Liste bietet ein Modus alle Zustände an; eine leere Liste hiesse «keinen»
        const zustaende = Zustaende.liste.map(z => z.id);
        if (zustaende.length > 0)
            neu.zustaende = zustaende;
        // anlegen gibt die ID sofort zurück und trägt den Modus gleich in die Liste ein; die Rückmeldung
        // von zenos-konfig kommt danach. Schlägt das Schreiben fehl, gilt wieder der Modus von vorher.
        const vorher = Modi.aktivId;
        let id = "";
        let abgelehnt = false;
        id = Modi.anlegen(neu, (ok, meldung) => {
            if (ok) {
                root._abschliessen();
                return;
            }
            abgelehnt = true;
            if (id !== "" && Modi.aktivId === id)
                Modi.wechseln(Modi.liste.some(m => m.id === vorher) ? vorher : "");
            root._modusFehler(meldung);
        });
        if (id === "") {
            _modusFehler("");
            return;
        }
        if (!abgelehnt)
            Modi.wechseln(id);
    }

    function _modusFehler(meldung: string): void {
        fehlerText = "Der Modus liess sich nicht anlegen" + (meldung ? " (" + meldung + ")" : "") + ". Du kannst ihn später in den Einstellungen anlegen.";
        _laeuft = false;
    }

    function _abschliessen(): void {
        _laeuft = false;
        fertig();
    }

    Keys.onReturnPressed: einrichten()
    Keys.onEnterPressed: einrichten()

    // ~/.config/zenos entsteht spätestens mit dem ersten Speichern, gelesen wird danach: kurz warten
    Connections {
        target: Konfig

        function onVerfuegbarChanged(): void {
            if (root._konfigBereit() && root._modusWartet)
                root._modusAnlegen();
        }

        function onGeladenChanged(): void {
            if (root._konfigBereit() && root._modusWartet)
                root._modusAnlegen();
        }
    }

    Timer {
        id: konfigWarten

        interval: 4000
        onTriggered: {
            root._modusWartet = null;
            root.fehlerText = "Der Modus liess sich noch nicht anlegen. Du kannst ihn später in den Einstellungen anlegen.";
            root._laeuft = false;
        }
    }

    Einleitung {
        id: einleitung

        width: root.spalte
        anchors.verticalCenter: parent.verticalCenter
        titel: "Willkommen\nbei zenOS."
        text: "Hier ist noch nichts von dir gespeichert. Was du jetzt einträgst, bleibt lokal auf diesem Gerät: nicht im Repo, nicht in einer Cloud."
        fuss: ["keine Konten", "keine Telemetrie", "keine Vorgaben"]
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
                nummer: "01"
                text: "Wie soll dich zenOS nennen?"
            }

            Eingabe {
                id: nameFeld

                width: parent.width
                platzhalter: "Name"
                maximaleLaenge: 60
            }
        }

        Column {
            width: parent.width
            spacing: 8

            Frage {
                nummer: "02"
                text: "Ort fürs Wetter"
                zusatz: "(optional)"
            }

            Eingabe {
                id: ortFeld

                width: parent.width
                platzhalter: "Ort"
                maximaleLaenge: 100
            }
        }

        Column {
            width: parent.width
            spacing: 10

            Frage {
                nummer: "03"
                text: "Erscheinungsbild"
            }

            // Wirkt sofort, damit du siehst, was du wählst
            Erscheinungswahl {
                id: erscheinung

                wert: Erscheinung.gewaehlt
                onGewaehlt: wert => Erscheinung.setzen(wert)
            }
        }

        Column {
            width: parent.width
            spacing: 8

            Frage {
                nummer: "04"
                text: "Erster Modus"
            }

            Row {
                width: parent.width
                spacing: 14

                Eingabe {
                    id: modusFeld

                    width: parent.width - farbwahl.width - parent.spacing
                    platzhalter: "z. B. Arbeit"
                    maximaleLaenge: 60
                }

                Farbwahl {
                    id: farbwahl

                    anchors.verticalCenter: modusFeld.verticalCenter
                    hintergrund: Theme.grund
                }
            }

            Text {
                width: parent.width
                text: "Weitere Modi, Zustände und Raster legst du später an. «Fokus» und «Sitzung» liegen als Vorlagen bereit."
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
                text: "Einrichten"
                variante: "primaer"
                schriftGroesse: 15
                enabled: !root._laeuft
                onClicked: root.einrichten()
            }

            Knopf {
                text: "Überspringen"
                variante: "still"
                schriftGroesse: 15
                enabled: !root._laeuft
                onClicked: root.ueberspringen()
            }
        }
    }

    // Unter dem Formular, ausserhalb der Spalte: Eine Meldung verschiebt nichts
    Text {
        visible: root.fehlerText.length > 0
        x: formular.x
        y: formular.y + formular.height + 18
        width: root.spalte
        text: root.fehlerText
        color: Theme.fehler
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseLabel
        lineHeightMode: Text.FixedHeight
        lineHeight: 20
        wrapMode: Text.WordWrap
    }
}
