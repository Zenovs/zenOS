pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste

// Seite «Bildschirme» der Einstellungen im Stil von Entwurf 2 «Modi & Zustände»: ein Bildschirm-Profil
// (Name, Ausgänge, Raster pro Ausgang) aus ~/.config/zenos/bildschirme.json. kanshi wählt das Profil
// beim Anschliessen; zenos-kanshi schreibt dessen Konfiguration nach jeder Änderung neu (Dienst Raster).
// Änderungen werden kurz nach der Eingabe gespeichert (zenos-konfig prüft sie gegen das Schema).
// unterauswahl: Name des Profils (leer = aktuelles oder erstes)
Item {
    id: root

    property string unterauswahl

    readonly property var profile: Dienste.Raster.profile
    readonly property string aktuell: Dienste.Raster.aktuellesProfil()
    // Index des bearbeiteten Profils in bildschirme.json (-1 = keins)
    readonly property int profilIndex: {
        const alle = Array.isArray(Dienste.Konfig.bildschirme?.profile) ? Dienste.Konfig.bildschirme.profile : [];
        const suche = name => alle.findIndex(p => p && p.name === name);
        let i = unterauswahl !== "" ? suche(unterauswahl) : -1;
        if (i < 0)
            i = suche(aktuell);
        if (i < 0)
            i = alle.findIndex(p => p && typeof p.name === "string");
        return i;
    }
    // Arbeitskopie des Profils
    property var entwurf: ({})
    property string fehlerText: ""

    readonly property var ausgaengeEntwurf: Array.isArray(entwurf.ausgaenge) ? entwurf.ausgaenge : []
    // Ausgang, dessen Raster gilt (wie zenos-labwc: erster mit Eintrag, sonst «*»)
    readonly property string wirksamerAusgang: {
        const r = entwurf.raster && typeof entwurf.raster === "object" ? entwurf.raster : {};
        for (const a of ausgaengeEntwurf) {
            if (typeof r[a] === "string" && r[a] !== "")
                return a;
        }
        return typeof r["*"] === "string" && r["*"] !== "" ? "*" : "";
    }
    readonly property string anzeigename: typeof entwurf.name === "string" && entwurf.name.trim() !== "" ? entwurf.name : "Profil"
    readonly property bool istAktuell: typeof entwurf.name === "string" && entwurf.name === aktuell && aktuell !== ""
    readonly property bool nameDoppelt: {
        const n = (entwurf.name ?? "").trim();
        const alle = Array.isArray(Dienste.Konfig.bildschirme?.profile) ? Dienste.Konfig.bildschirme.profile : [];
        return alle.some((p, i) => i !== _geladenFuer && p && typeof p.name === "string" && p.name.trim() === n);
    }
    readonly property var rasterOptionen: [
        {
            wert: "",
            text: "Nicht festgelegt"
        }
    ].concat(Dienste.Raster.liste.map(r => ({
                wert: r.id,
                text: typeof r.name === "string" && r.name !== "" ? r.name : r.id
            })))

    property int _geladenFuer: -1
    property bool _dirty: false
    // Zählt die Änderungen. Ein Rückruf gibt den Entwurf nur frei, wenn seit seinem Speichern nichts
    // dazukam; _gesendet verhindert, dass derselbe Stand zweimal geschrieben wird.
    property int _stand: 0
    property int _gesendet: -1

    function _kopie(o: var): var {
        return o && typeof o === "object" ? JSON.parse(JSON.stringify(o)) : {};
    }

    function _alle(): var {
        const d = _kopie(Dienste.Konfig.bildschirme);
        return Array.isArray(d.profile) ? d.profile : [];
    }

    function _laden(): void {
        if (_dirty && _geladenFuer === profilIndex)
            return;
        const p = profilIndex >= 0 ? (_alle()[profilIndex] ?? {}) : {};
        entwurf = _kopie(p);
        _geladenFuer = profilIndex;
        if (nameFeld.text !== (p.name ?? ""))
            nameFeld.text = p.name ?? "";
    }

    function aendern(schluessel: string, wert: var): void {
        const d = _kopie(entwurf);
        if (wert === undefined)
            delete d[schluessel];
        else
            d[schluessel] = wert;
        entwurf = d;
        _dirty = true;
        _stand++;
        speicherTimer.restart();
    }

    function speichern(): void {
        speicherTimer.stop();
        const index = _geladenFuer;
        if (!_dirty || index < 0 || _gesendet === _stand)
            return;
        const d = _kopie(entwurf);
        const name = (d.name ?? "").trim();
        if (name === "" || nameDoppelt || !Array.isArray(d.ausgaenge) || d.ausgaenge.length === 0) {
            fehlerText = name === "" ? "Name fehlt" : nameDoppelt ? "Name gibt es schon" : "Mindestens ein Ausgang";
            return;
        }
        d.name = name;
        // Raster nur für Ausgänge des Profils behalten
        if (d.raster && typeof d.raster === "object") {
            const r = {};
            for (const a of d.ausgaenge) {
                if (typeof d.raster[a] === "string" && d.raster[a] !== "")
                    r[a] = d.raster[a];
            }
            if (Object.keys(r).length > 0)
                d.raster = r;
            else
                delete d.raster;
        }
        const daten = _kopie(Dienste.Konfig.bildschirme);
        if (!Array.isArray(daten.profile))
            daten.profile = [];
        const alterName = daten.profile[index]?.name;
        daten.profile[index] = d;
        // Umbenannt: Auswahl in der Navigation gleich mitnehmen (sonst springt die Seite kurz)
        if (alterName !== name && Dienste.Oberflaeche.einstellungenOffen)
            Dienste.Oberflaeche.einstellungenSeite = "bildschirme/" + name;
        const stand = _stand;
        _gesendet = stand;
        Dienste.Raster.bildschirmeSpeichern(daten, (ok, meldung) => {
            // Die Seite kann schon geschlossen sein
            if (!root)
                return;
            // Kam während des Speicherns eine Änderung dazu, bleibt sie offen: Timer oder «Fertig» speichern sie
            if (root._geladenFuer === index && root._stand === stand)
                root._dirty = false;
            root.fehlerText = ok ? "" : meldung;
        });
    }

    function _eindeutig(basis: string): string {
        const alle = _alle().map(p => p?.name);
        if (alle.indexOf(basis) < 0)
            return basis;
        for (let i = 2; i < 100; i++) {
            if (alle.indexOf(basis + " " + i) < 0)
                return basis + " " + i;
        }
        return basis + " " + Date.now();
    }

    // Neues Profil aus den angeschlossenen Bildschirmen
    function neuesProfil(): void {
        speichern();
        const ausg = Dienste.Raster.ausgaenge.length > 0 ? Dienste.Raster.ausgaenge.slice(0, 8) : ["*"];
        const name = _eindeutig(ausg.length > 1 ? ausg.length + " Bildschirme" : "Ein Bildschirm");
        const daten = _kopie(Dienste.Konfig.bildschirme);
        if (!Array.isArray(daten.profile))
            daten.profile = [];
        const raster = {};
        if (Dienste.Raster.aktivId !== "")
            raster[ausg[0]] = Dienste.Raster.aktivId;
        // Vor Profile mit «*», damit kanshi es zuerst prüft (zenos-kanshi ordnet ohnehin so)
        daten.profile.unshift({
            name: name,
            ausgaenge: ausg,
            raster: raster
        });
        _dirty = false;
        Dienste.Raster.bildschirmeSpeichern(daten, ok => {
            if (ok)
                Dienste.Oberflaeche.einstellungenSeite = "bildschirme/" + name;
        });
    }

    function loeschen(): void {
        const index = _geladenFuer;
        if (index < 0)
            return;
        _dirty = false;
        speicherTimer.stop();
        const daten = _kopie(Dienste.Konfig.bildschirme);
        if (!Array.isArray(daten.profile))
            return;
        daten.profile.splice(index, 1);
        Dienste.Raster.bildschirmeSpeichern(daten);
        Dienste.Oberflaeche.einstellungenSeite = "bildschirme";
    }

    function ausgangDazu(name: string): void {
        const n = (name ?? "").trim();
        if (n === "" || !/^(\*|[A-Za-z0-9][A-Za-z0-9 ._:+()-]{0,99})$/.test(n) || ausgaengeEntwurf.indexOf(n) >= 0 || ausgaengeEntwurf.length >= 8)
            return;
        const liste = ausgaengeEntwurf.slice();
        // «*» bleibt am Ende
        const stern = liste.indexOf("*");
        if (n !== "*" && stern >= 0)
            liste.splice(stern, 0, n);
        else
            liste.push(n);
        aendern("ausgaenge", liste);
    }

    function ausgangWeg(name: string): void {
        if (ausgaengeEntwurf.length <= 1)
            return;
        aendern("ausgaenge", ausgaengeEntwurf.filter(a => a !== name));
    }

    function rasterSetzen(ausgang: string, rasterId: string): void {
        const r = _kopie(entwurf.raster);
        if (rasterId === "")
            delete r[ausgang];
        else
            r[ausgang] = rasterId;
        aendern("raster", Object.keys(r).length > 0 ? r : undefined);
    }

    function _wechsel(): void {
        if (_geladenFuer === profilIndex)
            return;
        if (_dirty)
            speichern();
        _dirty = false;
        fehlerText = "";
        _laden();
    }

    onProfilIndexChanged: Qt.callLater(_wechsel)
    Component.onCompleted: _laden()
    Component.onDestruction: speichern()

    Connections {
        target: Dienste.Konfig

        function onGeaendert(art: string): void {
            if (art === "bildschirme")
                Qt.callLater(root._laden);
        }
    }

    Timer {
        id: speicherTimer

        interval: 500
        onTriggered: root.speichern()
    }

    // --- Kein Profil ---
    Seite {
        visible: root.profilIndex < 0
        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Bildschirme"
            titel: "Noch kein Profil"
        }

        Text {
            width: Math.min(parent.width, 600)
            text: "Ein Bildschirm-Profil legt fest, welches Raster gilt, je nachdem, welche Bildschirme angeschlossen sind. Ohne Profil bleibt das Raster, das du zuletzt gewählt hast."
            wrapMode: Text.WordWrap
            lineHeight: 1.4
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseGross
        }

        Knopf {
            text: "Profil für diese Bildschirme"
            symbol: "plus"
            onClicked: root.neuesProfil()
        }
    }

    // --- Editor ---
    Seite {
        id: seite

        visible: root.profilIndex >= 0
        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Bildschirm-Profil"
            titel: root.anzeigename

            Chip {
                text: "Neues Profil"
                symbol: "plus"
                variante: "still"
                onClicked: root.neuesProfil()
            }

            Pille {
                visible: root.istAktuell
                text: "aktiv"
                variante: "aktiv"
            }
        }

        Text {
            width: Math.min(parent.width, 720)
            text: "Das Profil gilt, wenn genau diese Bildschirme angeschlossen sind; «*» steht für beliebige weitere. kanshi prüft Profile mit festen Ausgängen zuerst."
            wrapMode: Text.WordWrap
            lineHeight: 1.4
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
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

            readonly property real spalte: (width - columnSpacing) / 2

            width: parent.width
            columns: 2
            columnSpacing: 40
            rowSpacing: 18

            Feld {
                width: felder.spalte
                beschriftung: "Name"
                hinweis: root.nameDoppelt ? "gibt es schon" : ""
                hinweisBetont: true
                akzent: Theme.fehler

                Eingabe {
                    id: nameFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 60
                    platzhalter: "z. B. Schreibtisch"
                    fehler: text.trim().length === 0 || root.nameDoppelt
                }
            }

            Feld {
                width: felder.spalte
                beschriftung: "Jetzt angeschlossen"

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: Dienste.Raster.ausgaenge

                        Chip {
                            required property string modelData
                            readonly property bool drin: root.ausgaengeEntwurf.indexOf(modelData) >= 0

                            text: modelData
                            mono: true
                            symbol: "monitor"
                            variante: drin ? "gefuellt" : "umrandet"
                            zusatz: drin ? "im Profil" : "+ dazu"
                            onClicked: {
                                if (!drin)
                                    root.ausgangDazu(modelData);
                            }
                        }
                    }

                    Text {
                        visible: Dienste.Raster.ausgaenge.length === 0
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        text: "Kein Bildschirm erkannt"
                        color: Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                    }
                }
            }
        }

        // Ausgänge und Raster pro Ausgang
        Column {
            width: parent.width
            spacing: 0

            Item {
                width: parent.width
                height: 34

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Ausgänge und Raster"
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }
            }

            Repeater {
                model: root.ausgaengeEntwurf

                Item {
                    id: zeile

                    required property string modelData
                    required property int index
                    readonly property string rasterId: root.entwurf.raster?.[modelData] ?? ""
                    readonly property var raster: Dienste.Raster.liste.find(r => r.id === rasterId) ?? null
                    readonly property bool angeschlossen: modelData === "*" || Dienste.Raster.ausgaenge.indexOf(modelData) >= 0

                    width: parent.width
                    height: 58

                    Trenner {
                        width: parent.width
                    }

                    Trenner {
                        visible: zeile.index === root.ausgaengeEntwurf.length - 1
                        anchors.bottom: parent.bottom
                        width: parent.width
                    }

                    Minibild {
                        id: vorschau

                        x: 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 64
                        height: 40
                        raster: zeile.raster
                    }

                    Column {
                        anchors.left: vorschau.right
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 260
                        spacing: 2

                        Text {
                            width: parent.width
                            text: zeile.modelData !== "*" ? zeile.modelData : root.ausgaengeEntwurf.length === 1 ? "Alle Bildschirme" : "Beliebige weitere"
                            color: Theme.text
                            font.family: zeile.modelData === "*" ? Theme.schriftText : Theme.schriftMono
                            font.pixelSize: zeile.modelData === "*" ? 15 : Theme.groesseText
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: zeile.modelData === root.wirksamerAusgang ? "Raster gilt für alle Bildschirme" : zeile.modelData === "*" ? "" : zeile.angeschlossen ? "angeschlossen" : "nicht angeschlossen"
                            color: Theme.gedaempft
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                            elide: Text.ElideRight
                        }
                    }

                    Auswahl {
                        anchors.right: entfernen.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 240
                        optionen: root.rasterOptionen
                        wert: zeile.rasterId
                        onGewaehlt: wert => root.rasterSetzen(zeile.modelData, wert)
                    }

                    Item {
                        id: entfernen

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        opacity: root.ausgaengeEntwurf.length > 1 ? 1 : 0
                        activeFocusOnTab: root.ausgaengeEntwurf.length > 1

                        Accessible.role: Accessible.Button
                        Accessible.name: zeile.modelData + " aus dem Profil entfernen"
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Delete) {
                                root.ausgangWeg(zeile.modelData);
                                event.accepted = true;
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: Theme.text
                            opacity: wegMaus.containsMouse ? 0.07 : 0
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
                            id: wegMaus

                            anchors.fill: parent
                            enabled: root.ausgaengeEntwurf.length > 1
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.ausgangWeg(zeile.modelData)
                        }
                    }
                }
            }

            Item {
                width: 1
                height: 12
            }

            Row {
                spacing: 8

                Hinzufuegen {
                    visible: !ausgangFeld.visible && root.ausgaengeEntwurf.length < 8
                    text: "+ Ausgang"
                    onClicked: {
                        ausgangFeld.visible = true;
                        ausgangFeld.leeren();
                        ausgangFeld.fokussieren();
                    }
                }

                Hinzufuegen {
                    visible: !ausgangFeld.visible && root.ausgaengeEntwurf.indexOf("*") < 0 && root.ausgaengeEntwurf.length < 8
                    text: "+ beliebige weitere (*)"
                    onClicked: root.ausgangDazu("*")
                }

                Eingabe {
                    id: ausgangFeld

                    visible: false
                    width: 300
                    implicitHeight: 30
                    schriftGroesse: Theme.groesseLabel
                    maximaleLaenge: 100
                    platzhalter: "z. B. HDMI-A-1, Enter übernimmt"
                    fehler: text.length > 0 && !/^(\*|[A-Za-z0-9][A-Za-z0-9 ._:+()-]{0,99})$/.test(text.trim())
                    onAccepted: {
                        root.ausgangDazu(text);
                        visible = false;
                    }
                    Keys.onEscapePressed: visible = false
                }
            }
        }

        Text {
            width: Math.min(parent.width, 720)
            text: "labwc kennt ein Raster für alle Bildschirme: Es gilt das Raster des ersten Ausgangs, sonst das von «*». Ein Modus kann pro Profil ein eigenes Raster festlegen (Einstellungen → Modus)."
            wrapMode: Text.WordWrap
            lineHeight: 1.4
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: "~/.config/zenos/bildschirme.json · lokal, nicht im Repo"
            loeschenText: "Profil löschen"
            rueckfrage: "Profil «" + root.anzeigename + "» löschen?"
            onLoeschen: root.loeschen()
            onFertig: {
                root.speichern();
                Dienste.Oberflaeche.einstellungenOffen = false;
            }
        }
    }

    Connections {
        target: nameFeld.feld

        function onTextEdited(): void {
            root.aendern("name", nameFeld.text);
        }
    }

    // Kleine Zeichnung des Rasters (wie in SeiteRaster; gebundene Inline-Komponenten gelten nur in ihrer Datei)
    component Minibild: Rectangle {
        id: bild

        property var raster: null
        readonly property var _bereiche: raster && raster.bereiche && typeof raster.bereiche.length === "number" ? raster.bereiche : []

        radius: Theme.radiusXs
        color: Theme.flaeche2
        border.width: 1
        border.color: Theme.linie

        Item {
            id: flaeche

            x: 2
            y: 5
            width: bild.width - 4
            height: bild.height - 7

            Repeater {
                model: bild._bereiche.length

                Rectangle {
                    required property int index
                    readonly property var b: bild._bereiche[index] ?? ({})

                    x: Math.round(flaeche.width * (b.x ?? 0) / 100 + 1)
                    y: Math.round(flaeche.height * (b.y ?? 0) / 100 + 1)
                    width: Math.max(2, Math.round(flaeche.width * (b.b ?? 0) / 100 - 2))
                    height: Math.max(2, Math.round(flaeche.height * (b.h ?? 0) / 100 - 2))
                    radius: 1.5
                    color: Theme.flaeche
                    border.width: 1
                    border.color: Theme.linie2
                }
            }
        }

        Text {
            visible: bild._bereiche.length === 0
            anchors.centerIn: parent
            text: "–"
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }
    }
}
