pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste

// Seite «Raster» der Einstellungen im Stil von Entwurf 2 «Modi & Zustände»: alle Raster als kleine
// Zeichnungen, darunter das gewählte zum Bearbeiten (Name, Kurzname, Abstand, Bereiche in Prozent).
// «Aktivieren» setzt das Raster sofort, «Als Standard» legt es für das aktuelle Bildschirm-Profil fest.
// Änderungen werden kurz nach der Eingabe gespeichert (zenos-konfig prüft sie gegen das Schema).
// unterauswahl: ID des Rasters (leer = aktives oder erstes)
Item {
    id: root

    property string unterauswahl

    readonly property var liste: Dienste.Raster.liste
    readonly property string rasterId: {
        if (unterauswahl !== "" && liste.some(r => r.id === unterauswahl))
            return unterauswahl;
        if (liste.some(r => r.id === Dienste.Raster.aktivId))
            return Dienste.Raster.aktivId;
        return liste.length > 0 ? liste[0].id : "";
    }
    readonly property var gespeichert: liste.find(r => r.id === rasterId) ?? null
    // Arbeitskopie (ohne id)
    property var entwurf: ({})
    property string fehlerText: ""
    // Bereich, der in der Zeichnung hervorgehoben ist
    property int markiert: -1

    readonly property bool istAktiv: rasterId !== "" && rasterId === Dienste.Raster.aktivId
    readonly property string profilName: Dienste.Raster.aktuellesProfil()
    readonly property bool istStandard: rasterId !== "" && Dienste.Raster.standardFuerProfil(profilName) === rasterId
    readonly property var bereiche: Array.isArray(entwurf.bereiche) ? entwurf.bereiche : []
    readonly property string anzeigename: typeof entwurf.name === "string" && entwurf.name.trim() !== "" ? entwurf.name : rasterId

    property string _geladenFuer: ""
    property bool _dirty: false

    function _kopie(o: var): var {
        return o && typeof o === "object" ? JSON.parse(JSON.stringify(o)) : {};
    }

    function _laden(): void {
        if (_dirty && _geladenFuer === rasterId)
            return;
        const d = _kopie(gespeichert);
        delete d.id;
        entwurf = d;
        _geladenFuer = rasterId;
        if (nameFeld.text !== (d.name ?? ""))
            nameFeld.text = d.name ?? "";
        if (kurzFeld.text !== (d.kurz ?? ""))
            kurzFeld.text = d.kurz ?? "";
        if (markiert >= bereiche.length)
            markiert = -1;
    }

    // Einen Schlüssel ändern (undefined entfernt ihn) und bald speichern
    function aendern(schluessel: string, wert: var): void {
        const d = _kopie(entwurf);
        if (wert === undefined)
            delete d[schluessel];
        else
            d[schluessel] = wert;
        entwurf = d;
        _dirty = true;
        speicherTimer.restart();
    }

    function speichern(): void {
        speicherTimer.stop();
        const id = _geladenFuer;
        if (!_dirty || id === "")
            return;
        const d = _kopie(entwurf);
        if (typeof d.name !== "string" || d.name.trim() === "")
            d.name = gespeichert?.name ?? "Raster";
        Dienste.Raster.speichern(id, d, (ok, meldung) => {
            if (root._geladenFuer === id)
                root._dirty = false;
            root.fehlerText = ok ? "" : meldung;
        });
    }

    // Wert eines Bereichs setzen; hält den Bereich innerhalb des Bildschirms
    function bereichSetzen(index: int, schluessel: string, wert: int): void {
        const liste = _kopie(bereiche);
        const b = liste[index];
        if (!b)
            return;
        const gegenueber = {
            "x": "b",
            "b": "x",
            "y": "h",
            "h": "y"
        }[schluessel];
        const min = schluessel === "b" || schluessel === "h" ? 1 : 0;
        b[schluessel] = Math.max(min, Math.min(100 - (b[gegenueber] ?? 0), wert));
        aendern("bereiche", liste);
    }

    function bereichNeu(): void {
        const liste = _kopie(bereiche);
        if (liste.length >= 12)
            return;
        const ids = liste.map(b => b.id);
        let n = liste.length + 1;
        while (ids.indexOf("bereich-" + n) >= 0)
            n++;
        liste.push({
            id: "bereich-" + n,
            x: 25,
            y: 25,
            b: 50,
            h: 50
        });
        aendern("bereiche", liste);
        markiert = liste.length - 1;
    }

    function bereichEntfernen(index: int): void {
        if (bereiche.length <= 1)
            return;
        const liste = _kopie(bereiche);
        liste.splice(index, 1);
        aendern("bereiche", liste);
        markiert = -1;
    }

    function neuesRaster(): void {
        speichern();
        const vorlage = bereiche.length > 0 ? _kopie(bereiche) : [
            {
                id: "links",
                x: 0,
                y: 0,
                b: 50,
                h: 100
            },
            {
                id: "rechts",
                x: 50,
                y: 0,
                b: 50,
                h: 100
            }
        ];
        const id = Dienste.Raster.anlegen({
            name: "Neues Raster",
            abstand: typeof entwurf.abstand === "number" ? entwurf.abstand : Theme.rasterAbstand,
            bereiche: vorlage
        });
        if (id !== "")
            Dienste.Oberflaeche.einstellungenSeite = "raster/" + id;
    }

    function _wechsel(): void {
        if (_geladenFuer === rasterId)
            return;
        if (_dirty)
            speichern();
        _dirty = false;
        fehlerText = "";
        markiert = -1;
        _laden();
    }

    onRasterIdChanged: Qt.callLater(_wechsel)
    onGespeichertChanged: Qt.callLater(_laden)
    Component.onCompleted: _laden()
    Component.onDestruction: speichern()

    Timer {
        id: speicherTimer

        interval: 500
        onTriggered: root.speichern()
    }

    // --- Noch kein Raster ---
    Seite {
        visible: root.rasterId === ""
        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Raster"
            titel: "Noch kein Raster"
        }

        Text {
            width: Math.min(parent.width, 560)
            text: "Ein Raster teilt den Bildschirm in Bereiche, in die Fenster einrasten. Die Vorlagen Voll, Hälften, 3 Spalten, 4er-Grid und Gross + 2 kommen mit zen benutzer."
            wrapMode: Text.WordWrap
            lineHeight: 1.4
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseGross
        }

        Knopf {
            text: "Neues Raster"
            symbol: "plus"
            onClicked: root.neuesRaster()
        }
    }

    // --- Editor ---
    Seite {
        id: seite

        visible: root.rasterId !== ""
        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Raster"
            titel: root.anzeigename

            Pille {
                visible: root.istStandard
                text: "Standard"
                variante: "vorlage"
            }

            Chip {
                visible: !root.istStandard
                text: "Als Standard"
                variante: "still"
                onClicked: {
                    root.speichern();
                    Dienste.Raster.alsStandard(root.rasterId);
                }
            }

            Pille {
                visible: root.istAktiv
                text: "aktiv"
                variante: "aktiv"
            }

            Chip {
                visible: !root.istAktiv
                text: "Aktivieren"
                variante: "umrandet"
                onClicked: {
                    root.speichern();
                    Dienste.Raster.setzen(root.rasterId);
                }
            }
        }

        // Alle Raster als kleine Zeichnungen
        Flow {
            width: parent.width
            spacing: 12

            Repeater {
                model: root.liste

                Item {
                    id: karte

                    required property var modelData
                    readonly property bool gewaehlt: modelData.id === root.rasterId

                    width: 112
                    height: 70 + 8 + 18
                    activeFocusOnTab: true

                    Accessible.role: Accessible.Button
                    Accessible.name: (modelData.name ?? modelData.id) + (modelData.id === Dienste.Raster.aktivId ? ", aktiv" : "")
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            Dienste.Oberflaeche.einstellungenSeite = "raster/" + karte.modelData.id;
                            event.accepted = true;
                        }
                    }

                    Rasterbild {
                        id: kleinBild

                        width: parent.width
                        height: 70
                        raster: karte.modelData
                        rahmen: karte.gewaehlt ? Theme.akzent : kartenMaus.containsMouse ? Theme.gedaempft : Theme.linie

                        Fokusrahmen {
                            aktiv: karte.activeFocus
                            eckenRadius: Theme.radiusChip
                        }
                    }

                    Row {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            visible: karte.modelData.id === Dienste.Raster.aktivId
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.akzent
                        }

                        Text {
                            width: parent.width - (karte.modelData.id === Dienste.Raster.aktivId ? 12 : 0)
                            text: typeof karte.modelData.name === "string" && karte.modelData.name !== "" ? karte.modelData.name : karte.modelData.id
                            color: karte.gewaehlt ? Theme.text : Theme.gedaempft
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: kartenMaus

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Dienste.Oberflaeche.einstellungenSeite = "raster/" + karte.modelData.id
                        onDoubleClicked: Dienste.Raster.setzen(karte.modelData.id)
                    }
                }
            }

            Hinzufuegen {
                width: 112
                height: 70
                text: "+ Raster"
                onClicked: root.neuesRaster()
            }
        }

        Text {
            visible: root.fehlerText !== ""
            width: parent.width
            text: "Nicht gespeichert – bitte die Eingaben prüfen. (" + root.fehlerText + ")"
            wrapMode: Text.WordWrap
            color: Theme.fehler
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
        }

        Grid {
            id: felder

            readonly property real spalte: (width - columnSpacing * 2) / 3

            width: parent.width
            columns: 3
            columnSpacing: 40
            rowSpacing: 18

            Feld {
                width: felder.spalte
                beschriftung: "Name"

                Eingabe {
                    id: nameFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 60
                    platzhalter: "z. B. Schreiben"
                    fehler: text.trim().length === 0
                }
            }

            Feld {
                width: felder.spalte
                beschriftung: "Kurzname in der Leiste"
                hinweis: "höchstens 6 Zeichen"

                Eingabe {
                    id: kurzFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 6
                    platzhalter: "z. B. 4er"
                }
            }

            Feld {
                width: felder.spalte
                beschriftung: "Abstand zwischen Fenstern"

                Stufenwahl {
                    wert: typeof root.entwurf.abstand === "number" ? root.entwurf.abstand : Theme.rasterAbstand
                    min: 0
                    max: 32
                    schritt: 2
                    einheit: "px"
                    onGeaendert: wert => root.aendern("abstand", wert)
                }
            }
        }

        // Bereiche: Zeichnung links, Werte rechts
        Column {
            width: parent.width
            spacing: 10

            Text {
                text: "Bereiche"
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseLabel
            }

            Row {
                width: parent.width
                spacing: 32

                Rasterbild {
                    id: grossBild

                    width: 320
                    height: 200
                    raster: root.entwurf
                    nummern: true
                    markiert: root.markiert
                    onBereichGewaehlt: index => root.markiert = index
                }

                Column {
                    width: parent.width - grossBild.width - parent.spacing
                    spacing: 6

                    // Spaltenköpfe über den Werten
                    Row {
                        spacing: 10

                        Item {
                            width: 58
                            height: 1
                        }

                        Repeater {
                            model: ["links", "oben", "breit", "hoch"]

                            Text {
                                required property string modelData

                                width: 52 + 4 + 8
                                text: modelData
                                color: Theme.gedaempft
                                font.family: Theme.schriftMono
                                font.pixelSize: 11
                            }
                        }
                    }

                    Repeater {
                        model: root.bereiche.length

                        Item {
                            id: zeile

                            required property int index
                            readonly property var bereich: root.bereiche[index] ?? ({})

                            width: parent.width
                            height: 36

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: -8
                                anchors.rightMargin: -8
                                radius: Theme.radiusChip
                                color: Theme.flaeche2
                                opacity: root.markiert === zeile.index ? 0.7 : 0
                            }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Item {
                                    width: 58
                                    height: 24
                                    anchors.verticalCenter: parent.verticalCenter

                                    Kbd {
                                        visible: zeile.index < 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Super " + (zeile.index + 1)
                                        leise: root.markiert !== zeile.index
                                    }

                                    Text {
                                        visible: zeile.index >= 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(zeile.index + 1)
                                        color: Theme.gedaempft
                                        font.family: Theme.schriftMono
                                        font.pixelSize: Theme.groesseKlein
                                    }
                                }

                                Repeater {
                                    model: [
                                        {
                                            k: "x",
                                            t: "links"
                                        },
                                        {
                                            k: "y",
                                            t: "oben"
                                        },
                                        {
                                            k: "b",
                                            t: "breit"
                                        },
                                        {
                                            k: "h",
                                            t: "hoch"
                                        }
                                    ]

                                    Prozentfeld {
                                        required property var modelData

                                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                        beschriftung: modelData.t
                                        wert: zeile.bereich[modelData.k] ?? 0
                                        onGesetzt: wert => {
                                            root.markiert = zeile.index;
                                            root.bereichSetzen(zeile.index, modelData.k, wert);
                                        }
                                        onFokussiert: root.markiert = zeile.index
                                    }
                                }
                            }

                            // Entfernen (nicht beim letzten Bereich)
                            Item {
                                visible: root.bereiche.length > 1
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 26
                                activeFocusOnTab: visible

                                Accessible.role: Accessible.Button
                                Accessible.name: "Bereich " + (zeile.index + 1) + " entfernen"
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Delete) {
                                        root.bereichEntfernen(zeile.index);
                                        event.accepted = true;
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: Theme.text
                                    opacity: entfernenMaus.containsMouse ? 0.07 : 0
                                }

                                Symbol {
                                    anchors.centerIn: parent
                                    name: "x"
                                    groesse: 11
                                    strichbreite: 2.4
                                    farbe: Theme.gedaempft
                                }

                                Fokusrahmen {
                                    eckenRadius: 6
                                }

                                MouseArea {
                                    id: entfernenMaus

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.bereichEntfernen(zeile.index)
                                }
                            }
                        }
                    }

                    Item {
                        width: 1
                        height: 4
                    }

                    Hinzufuegen {
                        visible: root.bereiche.length < 12
                        text: "+ Bereich"
                        onClicked: root.bereichNeu()
                    }
                }
            }

            Text {
                width: Math.min(parent.width, 720)
                topPadding: 6
                text: "Super+1 bis Super+4 rasten in die ersten vier Bereiche. Beim Ziehen an der Titelzeile eine Taste halten (Super, Ctrl, Alt oder Shift), dann zeigt zenOS die Bereiche. Super+Links und Super+Rechts sind immer die Hälften. Werte in Prozent der Fläche unter der Leiste."
                wrapMode: Text.WordWrap
                lineHeight: 1.4
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseLabel
            }
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: "~/.config/zenos/raster/" + root.rasterId + ".json · lokal, nicht im Repo"
            loeschenText: root.liste.length > 1 ? "Raster löschen" : ""
            rueckfrage: "Raster «" + root.anzeigename + "» löschen?"
            onLoeschen: {
                const id = root.rasterId;
                root._dirty = false;
                speicherTimer.stop();
                Dienste.Raster.loeschen(id);
                Dienste.Oberflaeche.einstellungenSeite = "raster";
            }
            onFertig: {
                root.speichern();
                Dienste.Oberflaeche.einstellungenOffen = false;
            }
        }
    }

    Connections {
        target: nameFeld.feld

        function onTextEdited(): void {
            if (nameFeld.text.trim().length > 0)
                root.aendern("name", nameFeld.text);
        }
    }

    Connections {
        target: kurzFeld.feld

        function onTextEdited(): void {
            const t = kurzFeld.text.trim();
            root.aendern("kurz", t === "" ? undefined : t);
        }
    }

    // Zeichnung eines Rasters: Bildschirm mit Leiste, Bereiche mit massstäblicher Lücke
    component Rasterbild: Item {
        id: bild

        property var raster: null
        property int markiert: -1
        property bool nummern: false
        property color rahmen: Theme.linie
        // Aus einem Repeater-Modell kommen Listen als Sequenz, nicht als JS-Array: nur Länge und Index nutzen
        readonly property var _bereiche: raster && raster.bereiche && typeof raster.bereiche.length === "number" ? raster.bereiche : []
        // 1440 px breiter Bildschirm als Massstab
        readonly property real _massstab: width / 1440
        readonly property real _luecke: Math.max(1.5, (typeof raster?.abstand === "number" ? raster.abstand : Theme.rasterAbstand) * _massstab)
        readonly property real _leiste: Math.max(4, Theme.leisteHoehe * _massstab)

        signal bereichGewaehlt(int index)

        Rectangle {
            anchors.fill: parent
            radius: Math.min(Theme.radiusChip, bild.height / 8)
            color: Theme.flaeche2
            border.width: 1
            border.color: bild.rahmen

            Behavior on border.color {
                ColorAnimation {
                    duration: Theme.dauerKurz
                    easing.type: Theme.kurve
                }
            }
        }

        // Arbeitsfläche unter der Leiste
        Item {
            id: flaeche

            x: bild._luecke + 1
            y: bild._leiste + bild._luecke
            width: bild.width - 2 * bild._luecke - 2
            height: bild.height - bild._leiste - 2 * bild._luecke - 1

            Repeater {
                model: bild._bereiche.length

                Rectangle {
                    id: bereichBild

                    required property int index
                    readonly property var b: bild._bereiche[index] ?? ({})
                    readonly property bool hervor: bild.markiert === index

                    x: Math.round(flaeche.width * (b.x ?? 0) / 100 + bild._luecke / 2)
                    y: Math.round(flaeche.height * (b.y ?? 0) / 100 + bild._luecke / 2)
                    width: Math.max(2, Math.round(flaeche.width * (b.b ?? 0) / 100 - bild._luecke))
                    height: Math.max(2, Math.round(flaeche.height * (b.h ?? 0) / 100 - bild._luecke))
                    radius: Math.max(1.5, Math.min(Theme.radiusFenster * bild._massstab * 2, Math.min(width, height) / 4))
                    color: hervor ? Qt.alpha(Theme.akzent, Theme.dunkel ? 0.3 : 0.2) : Theme.flaeche
                    border.width: 1
                    border.color: hervor ? Theme.akzent : Theme.linie2

                    Text {
                        visible: bild.nummern
                        anchors.centerIn: parent
                        text: String(bereichBild.index + 1)
                        color: bereichBild.hervor ? Theme.akzent : Theme.gedaempft
                        font.family: Theme.schriftMono
                        font.pixelSize: Theme.groesseLabel
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: bild.nummern
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: bild.bereichGewaehlt(bereichBild.index)
                    }
                }
            }
        }
    }

    // Ganze Prozent (0–100); Enter oder Verlassen übernimmt, Pfeil hoch/runter ändert um 1 (mit Shift um 5)
    component Prozentfeld: Row {
        id: pf

        property int wert: 0
        property string beschriftung

        signal gesetzt(int wert)
        signal fokussiert

        function _uebernehmen(): void {
            const n = parseInt(eingabe.text, 10);
            if (isNaN(n)) {
                eingabe.text = String(wert);
                return;
            }
            if (n !== wert)
                gesetzt(n);
            else
                eingabe.text = String(wert);
        }

        spacing: 4
        onWertChanged: {
            if (!eingabe.feld.activeFocus)
                eingabe.text = String(wert);
        }

        Eingabe {
            id: eingabe

            width: 52
            implicitHeight: 28
            schriftGroesse: Theme.groesseLabel
            maximaleLaenge: 3
            text: String(pf.wert)
            feld.Accessible.name: pf.beschriftung
            onAccepted: pf._uebernehmen()

            Keys.onUpPressed: event => pf.gesetzt(pf.wert + ((event.modifiers & Qt.ShiftModifier) ? 5 : 1))
            Keys.onDownPressed: event => pf.gesetzt(pf.wert - ((event.modifiers & Qt.ShiftModifier) ? 5 : 1))
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "%"
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }

        Connections {
            target: eingabe.feld

            function onActiveFocusChanged(): void {
                if (eingabe.feld.activeFocus)
                    pf.fokussiert();
                else
                    pf._uebernehmen();
            }
        }
    }
}
