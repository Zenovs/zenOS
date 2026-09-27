pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.dienste
import qs.komponenten
import "zeit.js" as Zeit
import "../komponenten/symbole.js" as Symbole

// Inhalt der Leiste nach Entwurf 2 (Innenabstand 0 10 px):
// links «wo bin ich» (Zeichen, Modus, Zustand, Raster), in der Mitte Datum und Uhrzeit,
// rechts Mitteilungen, Hell/Dunkel und System.
Item {
    id: root

    // aktuelle Zeit (SystemClock, Minutentakt)
    property var jetzt: new Date()
    // offenes Menü dieser Leiste: "" | "system" | "raster"
    property string offenesMenue: ""

    // x in Fensterkoordinaten: Raster-Menü beginnt an der linken Kante des Knopfs,
    // das System-Menü endet an der rechten Kante des System-Knopfs
    signal menueGewuenscht(string name, real x)

    function menueX(name: string): real {
        if (name === "raster")
            return rasterChip.mapToItem(null, 0, 0).x;
        return systemKnopf.mapToItem(null, systemKnopf.width, 0).x;
    }

    // Leiste laut wirksamem Zustand: "normal" | "reduziert" (ohne Raster und Hell/Dunkel) |
    // "aus" (nur Zustand und Uhrzeit; der Platz bleibt reserviert, damit nichts springt)
    readonly property string stufe: {
        const s = Zustaende.wirksam?.leiste;
        return s === "reduziert" || s === "aus" ? s : "normal";
    }

    // --- Modus ---

    readonly property string _modeName: {
        const m = Modi.aktiv;
        if (!m)
            return "";
        const name = typeof m.name === "string" ? m.name.trim() : "";
        return name !== "" ? name : Modi.aktivId;
    }

    // --- Zustand ---

    readonly property bool _sharing: Freigabe.aktiv
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
    readonly property string _stateExtra: {
        if (_sharing)
            return _stateName !== "" ? "Bildschirm wird geteilt" : "";
        return Zustaende.restMinuten >= 0 ? Zeit.duration(Zustaende.restMinuten) : "";
    }

    // --- Raster ---

    readonly property var _raster: {
        const liste = Raster.liste ?? [];
        for (let i = 0; i < liste.length; i++) {
            const r = liste[i];
            if ((typeof r === "string" ? r : r?.id) === Raster.aktivId)
                return typeof r === "string" ? {
                    id: r,
                    name: r
                } : r;
        }
        return Raster.aktivId ? {
            id: Raster.aktivId,
            name: Raster.aktivId
        } : null;
    }
    readonly property string _rasterShort: _shortRasterName(_raster)

    // Kurzname fürs Leistenfeld: «4er» für das 4er-Grid (Entwurf 2), sonst ein kurzes Wort
    function _shortRasterName(r: var): string {
        if (!r)
            return "";
        if (typeof r.kurz === "string" && r.kurz.trim() !== "")
            return r.kurz.trim();
        const known = {
            "voll": "Voll",
            "haelften": "2er",
            "drei-spalten": "3er",
            "4er-grid": "4er",
            "gross-plus-2": "1+2"
        };
        if (r.id in known)
            return known[r.id];
        const name = String(r.name ?? r.id ?? "").trim();
        if (name.length <= 8)
            return name;
        const first = name.split(/[\s-]+/)[0];
        return first.length >= 2 && first.length <= 8 ? first : name.slice(0, 7) + "…";
    }

    // --- Mitteilungen ---

    readonly property int _waiting: Math.max(0, Mitteilungen.anzahlWartend ?? 0)
    readonly property var _nextDelivery: Zeit.validDate(Mitteilungen.naechsteZustellung)
    readonly property bool _paused: _sharing || Mitteilungen.modus === "keine"
    readonly property string _noticeText: {
        // Leitplanke: bei Freigabe nur die Anzahl, nie Inhalte
        if (_sharing)
            return _waiting > 0 ? _waiting + " zurückgehalten" : "";
        if (_waiting === 0)
            return "";
        return _nextDelivery ? _waiting + " · " + Zeit.time(_nextDelivery) : _waiting + " warten";
    }
    readonly property string _noticeDescription: {
        if (_sharing)
            return _waiting > 0 ? "Mitteilungen zurückgehalten, Bildschirm wird geteilt: " + _waiting : "Mitteilungen pausiert, Bildschirm wird geteilt";
        if (_waiting === 0)
            return "Mitteilungen: keine wartet";
        return _nextDelivery ? _waiting + " Mitteilungen gesammelt, Zustellung um " + Zeit.time(_nextDelivery) : _waiting + " Mitteilungen warten";
    }

    // --- System ---

    // Symbole, die es (noch) nicht in qs.komponenten gibt, werden weggelassen statt leer gezeichnet
    function _symbolKnown(name: string): bool {
        return Symbole.daten[name] !== undefined;
    }
    readonly property string _networkSymbol: {
        if (System.netzArt === "wlan")
            return "wlan";
        if (System.netzArt === "kabel")
            return _symbolKnown("kabel") ? "kabel" : "";
        return _symbolKnown("wlan-aus") ? "wlan-aus" : "wlan";
    }
    readonly property string _systemDescription: {
        const parts = [];
        parts.push(System.netzArt === "wlan" ? "WLAN verbunden" : System.netzArt === "kabel" ? "Kabel verbunden" : "nicht verbunden");
        parts.push(!System.tonVerfuegbar ? "kein Tonausgang" : System.stumm ? "Ton stumm" : "Lautstärke " + Math.round(System.lautstaerke * 100) + " %");
        if (System.einsPasswortInstalliert)
            parts.push(System.einsPasswortLaeuft ? "1Password läuft" : "1Password nicht gestartet");
        if (System.temperatur >= 0)
            parts.push(System.temperatur + " Grad");
        return "System: " + parts.join(", ");
    }

    // --- Platz links: lange Namen kürzen, damit nichts in die Uhrzeit ragt ---

    // Breite vom linken Rand bis kurz vor die Uhrzeit
    readonly property real _leftBudget: (width - uhrzeit.implicitWidth) / 2 - Theme.a4 - 10
    // alles ausser den beiden Namen: Zeichen, Innenabstände, Punkt, Pfeil, Zusatz, Raster, Abstände
    readonly property real _leftFixed: (stufe !== "aus" ? 30 + 6 + 10 + 7 + 8 + 8 + 12 + 8 : 0) + (zustandChip.visible ? 6 + 10 + (_sharing ? 7 + 8 : 0) + (_stateExtra !== "" ? 8 + extraMetrics.advanceWidth : 0) + 10 : 0) + (rasterChip.visible ? 6 + rasterChip.implicitWidth : 0)
    readonly property real _namesBudget: Math.max(80, _leftBudget - _leftFixed)
    // Modus höchstens 180 px, Zustand höchstens 160 px; wird es eng, teilen sie sich den Platz
    readonly property real _modeMax: zustandChip.visible ? Math.min(180, Math.max(_namesBudget - Math.min(stateWidth.advanceWidth, 160), _namesBudget / 2)) : Math.min(240, _namesBudget)
    readonly property real _stateMax: Math.min(160, _namesBudget - (modusChip.visible ? Math.min(modeWidth.advanceWidth, _modeMax) : 0))

    // volle Breiten (getrennt vom Kürzen, sonst meldet TextMetrics bei jeder neuen elideWidth eine Änderung)
    TextMetrics {
        id: modeWidth

        font: modeMetrics.font
        text: modeMetrics.text
    }

    TextMetrics {
        id: stateWidth

        font: stateMetrics.font
        text: stateMetrics.text
    }

    TextMetrics {
        id: modeMetrics

        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseLabel
        text: root._modeName !== "" ? root._modeName : "Kein Modus"
        elide: Text.ElideRight
        elideWidth: root._modeMax
    }

    TextMetrics {
        id: stateMetrics

        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseLabel
        text: root._stateName !== "" ? root._stateName : "Bildschirm wird geteilt"
        elide: Text.ElideRight
        elideWidth: root._stateMax
    }

    TextMetrics {
        id: extraMetrics

        font.family: Theme.schriftMono
        font.pixelSize: Theme.groesseKlein
        text: root._stateExtra
    }

    // --- Links ---

    Row {
        id: links

        x: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        move: Transition {
            NumberAnimation {
                properties: "x"
                duration: Theme.dauerMax
                easing.type: Theme.kurve
            }
        }

        // Zeichen (18 px, nur der Bogen) mit 6 px Luft links und rechts
        Item {
            visible: root.stufe !== "aus"
            width: 30
            height: 28

            Zeichen {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                groesse: 18
                farbe: Theme.akzent
            }
        }

        Chip {
            id: modusChip

            visible: root.stufe !== "aus"
            text: modeMetrics.elidedText
            variante: root._modeName !== "" ? "gefuellt" : "still"
            mitPunkt: root._modeName !== ""
            pfeil: true
            Accessible.name: root._modeName !== "" ? "Modus wechseln, aktuell " + root._modeName : "Modus wählen, kein Modus aktiv"
            onClicked: Oberflaeche.modusWahlOffen = !Oberflaeche.modusWahlOffen
        }

        Chip {
            id: zustandChip

            visible: Zustaende.aktivId !== "" || root._sharing
            variante: "umrandet"
            text: stateMetrics.elidedText
            zusatz: root._stateExtra
            mitPunkt: root._sharing
            punktFarbe: Theme.sitzung
            randFarbe: root._sharing ? Theme.sitzung : Theme.eingabeRand
            Accessible.name: "Zustand " + stateMetrics.text + (zusatz !== "" ? ", " + zusatz : "")
            onClicked: Oberflaeche.zustandWahlOffen = !Oberflaeche.zustandWahlOffen
        }

        Chip {
            id: rasterChip

            visible: root.stufe === "normal"
            variante: "still"
            symbol: "raster4"
            text: root._rasterShort
            mono: true
            Accessible.name: root._raster ? "Raster: " + (root._raster.name ?? root._raster.id) : "Raster wählen"
            onClicked: root.menueGewuenscht("raster", root.menueX("raster"))
        }
    }

    // --- Mitte (absolut zentriert) ---

    // Das Datum weicht, bevor sich etwas überschneidet (schmale Bildschirme, lange Namen)
    readonly property bool _dateFits: {
        const full = datum.implicitWidth + mitte.spacing + uhrzeit.implicitWidth;
        const left = (width - full) / 2;
        const right = (width + full) / 2;
        return links.x + links.implicitWidth + Theme.a4 <= left && right + Theme.a4 <= width - 10 - rechts.implicitWidth;
    }

    Row {
        id: mitte

        anchors.centerIn: parent
        spacing: 10

        Text {
            id: datum

            visible: root._dateFits && root.stufe !== "aus"
            text: Zeit.shortDate(root.jetzt)
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseLabel
        }

        Text {
            id: uhrzeit

            text: Zeit.time(root.jetzt)
            color: Theme.text
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseLabel
        }
    }

    // --- Rechts ---

    Row {
        id: rechts

        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        layoutDirection: Qt.LeftToRight

        move: Transition {
            NumberAnimation {
                properties: "x"
                duration: Theme.dauerMax
                easing.type: Theme.kurve
            }
        }

        LeistenKnopf {
            id: mitteilungenKnopf

            visible: root.stufe !== "aus"
            abstand: 6
            aktiv: Oberflaeche.zentraleOffen
            beschreibung: root._noticeDescription
            onClicked: Oberflaeche.zentraleOffen = !Oberflaeche.zentraleOffen

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                name: root._paused ? "glocke-aus" : "glocke"
                groesse: 15
                farbe: Theme.text
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: root._noticeText
                color: Theme.text
                font.family: Theme.schriftMono
                font.pixelSize: Theme.groesseKlein
            }
        }

        LeistenKnopf {
            id: helligkeitKnopf

            visible: root.stufe === "normal"
            width: 32
            beschreibung: Theme.dunkel ? "Hell umschalten" : "Dunkel umschalten"
            onClicked: Erscheinung.umschalten()

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                name: Theme.dunkel ? "sonne" : "mond"
                groesse: 15
                farbe: Theme.text
            }
        }

        LeistenKnopf {
            id: systemKnopf

            visible: root.stufe !== "aus"
            flaeche: Theme.abgesetzt
            abstand: 9
            aktiv: root.offenesMenue === "system"
            beschreibung: root._systemDescription
            onClicked: root.menueGewuenscht("system", root.menueX("system"))

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: root._networkSymbol !== ""
                name: root._networkSymbol
                groesse: 14
                farbe: System.netzVerbunden ? Theme.text : Theme.gedaempft
                opacity: System.netzVerbunden ? 1 : 0.6
            }

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                name: System.tonVerfuegbar && !System.stumm ? "ton" : "ton-aus"
                groesse: 14
                farbe: System.tonVerfuegbar ? Theme.text : Theme.gedaempft
            }

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: System.einsPasswortInstalliert
                name: "schloss"
                groesse: 14
                farbe: System.einsPasswortLaeuft ? Theme.text : Theme.gedaempft
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: System.temperatur >= 0
                text: System.temperatur + "°"
                color: Theme.text
                font.family: Theme.schriftMono
                font.pixelSize: Theme.groesseKlein
            }
        }
    }
}
