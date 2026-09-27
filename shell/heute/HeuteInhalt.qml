pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.dienste
import qs.komponenten
import "../leiste/zeit.js" as Zeit

// Inhalt von «Heute» nach Entwurf 2: Raster 1120 px (zwei Spalten, Lücke 128), linke Spalte
// senkrecht mittig unter der Leiste; Fusszeile mit Tastenkürzeln 30 px über dem unteren Rand.
// Ausgeblendet, solange der wirksame Zustand «heute: false» hat oder der Bildschirm geteilt wird.
Item {
    id: root

    // aktuelle Zeit (SystemClock, Minutentakt)
    property var jetzt: new Date()

    readonly property bool inhaltSichtbar: Zustaende.wirksam?.heute !== false && !Freigabe.aktiv

    // Masse aus Entwurf 2
    readonly property int _gridWidth: Math.min(1120, width - 2 * Theme.a7)
    readonly property int _gap: 128
    readonly property int _columnWidth: Math.max(0, Math.floor((_gridWidth - _gap) / 2))
    // Hauptfläche: unter der Leiste, unten 70 px frei für die Fusszeile
    readonly property real _centerY: Theme.leisteHoehe + (height - Theme.leisteHoehe - 70) / 2

    readonly property var _now: Zeit.validDate(jetzt) ?? new Date()

    readonly property string gruss: {
        const name = (Einstellungen.name ?? "").trim();
        return Zeit.greeting(_now.getHours()) + (name !== "" ? ", " + name : "") + ".";
    }

    readonly property string _stateName: {
        const id = Zustaende.aktivId;
        if (!id)
            return "";
        const w = Zustaende.wirksam;
        if (typeof w?.name === "string" && w.name.trim() !== "")
            return w.name.trim();
        const liste = Zustaende.liste ?? [];
        for (let i = 0; i < liste.length; i++) {
            if (liste[i]?.id === id && typeof liste[i].name === "string" && liste[i].name.trim() !== "")
                return liste[i].name.trim();
        }
        return id.charAt(0).toUpperCase() + id.slice(1);
    }

    // Ein bis zwei ruhige Sätze zu Zustand und Mitteilungen
    readonly property string zusammenfassung: {
        const parts = [];
        if (_stateName !== "") {
            const end = Zeit.validDate(Zustaende.ende) ?? _stateEnd;
            parts.push(end ? _stateName + " bis " + Zeit.time(end) + "." : _stateName + " ist aktiv.");
        }
        const n = Math.max(0, Mitteilungen.anzahlWartend ?? 0);
        const modus = Mitteilungen.modus ?? "";
        const bundled = /^gebuendelt-(\d+)$/.exec(modus);
        const next = Zeit.validDate(Mitteilungen.naechsteZustellung) ?? (bundled ? Zeit.nextSlot(_now, Number(bundled[1])) : null);
        if (next) {
            const um = " gesammelt um " + Zeit.time(next) + ".";
            parts.push(n === 0 ? "Mitteilungen kommen" + um : n === 1 ? "Eine Mitteilung kommt" + um : n + " Mitteilungen kommen" + um);
        } else if (modus === "nur-dringend") {
            parts.push(n === 0 ? "Nur Dringendes kommt sofort." : (n === 1 ? "Eine Mitteilung wartet" : n + " Mitteilungen warten") + ", nur Dringendes kommt sofort.");
        } else if (modus === "keine") {
            const bis = _stateName !== "" ? " bis zum Ende von «" + _stateName + "»." : ".";
            parts.push(n === 0 ? "Mitteilungen warten" + bis : n === 1 ? "Eine Mitteilung wartet" + bis : n + " Mitteilungen warten" + bis);
        } else if (n > 0) {
            parts.push(n === 1 ? "Eine Mitteilung wartet." : n + " Mitteilungen warten.");
        } else {
            parts.push("Mitteilungen kommen sofort.");
        }
        return parts.join(" ");
    }

    // Ende des Zustands aus restMinuten, falls Zustaende kein «ende» liefert. Nur neu berechnet,
    // wenn es mehr als 90 s abweicht: sonst könnte «bis 11:40» je nach Takt auf 11:41 springen.
    property var _stateEnd: null

    function _updateStateEnd(): void {
        const rest = Zustaende.restMinuten;
        if (!Zustaende.aktivId || !(rest >= 0)) {
            _stateEnd = null;
            return;
        }
        const expected = Date.now() + rest * 60000;
        if (!_stateEnd || Math.abs(expected - _stateEnd.getTime()) > 90000)
            _stateEnd = new Date(expected);
    }

    Connections {
        target: Zustaende

        function onRestMinutenChanged(): void {
            root._updateStateEnd();
        }
        function onAktivIdChanged(): void {
            root._updateStateEnd();
        }
    }

    Component.onCompleted: _updateStateEnd()

    readonly property string _modeName: {
        const m = Modi.aktiv;
        if (!m)
            return "";
        const name = typeof m.name === "string" ? m.name.trim() : "";
        return name !== "" ? name : Modi.aktivId;
    }

    // Text mit fester Zeilenhöhe wie im Entwurf (CSS line-height): Qt setzt die Glyphen oben in die
    // Zeile, der Browser mittig. Der Versatz gleicht das aus, die Höhe zählt nur die Zeilen.
    component Zeilentext: Item {
        id: zeilentext

        property alias text: textItem.text
        property alias color: textItem.color
        property alias font: textItem.font
        property alias maximumLineCount: textItem.maximumLineCount
        // Vielfaches der Schriftgrösse
        property real zeilenhoehe: 1.2

        implicitHeight: Math.max(1, textItem.lineCount) * textItem.lineHeight

        Text {
            id: textItem

            width: parent.width
            y: Math.round((lineHeight - metrics.height) / 2)
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            lineHeightMode: Text.FixedHeight
            lineHeight: font.pixelSize * zeilentext.zeilenhoehe
        }

        FontMetrics {
            id: metrics

            font: textItem.font
        }
    }

    // --- linke Spalte ---

    Column {
        id: spalte

        x: Math.round((root.width - root._gridWidth) / 2)
        y: Math.round(root._centerY - height / 2)
        width: root._columnWidth
        spacing: 22
        opacity: root.inhaltSichtbar ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dauerMax
                easing.type: Theme.kurve
            }
        }

        // «MONTAG · SEPTEMBER»
        Text {
            width: parent.width
            text: Zeit.dayMonth(root._now)
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseLabel
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Theme.groesseLabel * 0.1
            elide: Text.ElideRight
        }

        // Tageszahl, 300 px, Zeilenhöhe 0.8 (wie im Entwurf: Glyphen mittig in der engeren Zeile)
        Item {
            width: tag.implicitWidth
            height: Math.round(tag.font.pixelSize * 0.8)

            Text {
                id: tag

                y: Math.round((parent.height - implicitHeight) / 2)
                text: String(root._now.getDate())
                color: Theme.text
                font.family: Theme.schriftAnzeige
                font.pixelSize: 300
                font.letterSpacing: -6
            }
        }

        // «Guten Morgen, Name.» – Instrument Serif kursiv 38 px, Zeilenhöhe 1.2
        Zeilentext {
            width: parent.width
            text: root.gruss
            color: Theme.text
            font.family: Theme.schriftAnzeige
            font.pixelSize: 38
            font.italic: true
            zeilenhoehe: 1.2
            maximumLineCount: 2
        }

        // Zusammenfassung, 16 px, Zeilenhöhe 1.6, höchstens 420 px breit
        Zeilentext {
            width: Math.min(420, parent.width)
            text: root.zusammenfassung
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseGross
            zeilenhoehe: 1.6
        }

        // Moduszeile mit Akzentpunkt
        Row {
            spacing: 8

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: root._modeName !== "" ? Theme.akzent : Theme.durchsichtig
                border.width: root._modeName !== "" ? 0 : 1
                border.color: Theme.gedaempft
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, root._columnWidth - 14)
                elide: Text.ElideRight
                text: root._modeName !== "" ? "Modus " + root._modeName : "Kein Modus"
                color: Theme.gedaempft
                font.family: Theme.schriftMono
                font.pixelSize: Theme.groesseKlein
            }
        }
    }

    // --- Fusszeile: Tastenkürzel ---

    component Kuerzel: Row {
        id: kuerzel

        property list<string> tasten
        property string was

        spacing: 6

        Repeater {
            model: kuerzel.tasten

            Kbd {
                required property string modelData

                anchors.verticalCenter: parent.verticalCenter
                text: modelData
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: kuerzel.was
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        spacing: 28
        opacity: spalte.opacity
        visible: opacity > 0

        Kuerzel {
            tasten: ["Super", "Leertaste"]
            was: "Befehlsfeld"
        }

        Kuerzel {
            tasten: ["Super", "M"]
            was: "Modus"
        }

        Kuerzel {
            tasten: ["Super", "Z"]
            was: "Zustand"
        }
    }
}
