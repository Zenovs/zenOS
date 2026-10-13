pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.dienste
import qs.komponenten
import "bluetooth.js" as Bt

// Bluetooth im System-Menü, unter dem Netz. Mit BlueZ (quelle = BluetoothQuelle aus Leiste.qml, im Test eine Attrappe
// mit derselben Schnittstelle): «Bluetooth» mit Schalter, darunter die verbundenen Geräte mit Akku, dann aufklappbar
// «Weitere Geräte» (gekoppelte und gefundene; solange die Liste offen ist, sucht der Adapter). Ein Klick verbindet ein
// gekoppeltes Gerät bzw. koppelt ein neues und verbindet es. Ein Klick auf ein verbundenes Gerät fragt «trennen?», erst
// der zweite trennt (4 s gültig). Das «x» vergisst ein Gerät (fragt ebenfalls einmal nach).
// Ohne Bluetooth im Gerät fehlt der Abschnitt. Läuft BlueZ nicht, steht nur die Zeile mit einem ruhigen Hinweis da.
//
// Während einer Bildschirmfreigabe zeigt der Abschnitt keine Gerätenamen (sie tragen oft Namen von Menschen) und sucht
// nicht. Die Menüs der Leiste sind während der Sperre zu; der Abschnitt entsteht mit dem Menü neu und vergisst dabei
// Liste und Nachfragen.
Column {
    id: root

    // BluetoothQuelle oder null (bluetooth.service läuft nicht, oder BluetoothQuelle liess sich nicht laden)
    property var quelle: null
    // Das Gerät hat Bluetooth (/sys/class/bluetooth, Prüfung in Leiste.qml)
    property bool geraetDa: false
    // Liste aufgeklappt (Startwert: zenos-ipc leiste menue bluetooth)
    property bool offen: false

    readonly property bool _bereit: quelle !== null && quelle.bereit
    readonly property bool _an: _bereit && quelle.an
    readonly property bool _verborgen: Freigabe.aktiv
    readonly property var _alle: _bereit ? quelle.geraete : []
    readonly property var _verbunden: _alle.filter(g => g.verbunden)
    readonly property var _liste: _alle.filter(g => !g.verbunden)
    // Verbundenes Gerät, das nach dem ersten Klick auf die Bestätigung wartet ("" = keins)
    property string _trennen: ""

    visible: _bereit || geraetDa
    width: parent ? parent.width : 0

    function _trennenAusloesen(adresse: string): void {
        if (_trennen !== adresse) {
            _trennen = adresse;
            entschaerfen.restart();
            return;
        }
        _trennen = "";
        entschaerfen.stop();
        quelle.trennen(adresse);
    }

    function _sucheSetzen(): void {
        if (quelle)
            quelle.suchen = offen && _an && !_verborgen;
    }

    function _name(geraet: var): string {
        return _verborgen ? "Gerätename verborgen" : Bt.anzeigeName(geraet.name);
    }

    onOffenChanged: _sucheSetzen()
    on_AnChanged: _sucheSetzen()
    on_VerborgenChanged: {
        // Freigabe beginnt: Liste zu (sie zeigt Gerätenamen in der Nähe)
        if (_verborgen)
            offen = false;
        _trennen = "";
        _sucheSetzen();
    }

    Component.onCompleted: _sucheSetzen()
    Component.onDestruction: {
        if (quelle)
            quelle.aufraeumen();
    }

    // Nachfrage «trennen?» verfällt nach 4 s
    Timer {
        id: entschaerfen

        interval: 4000
        onTriggered: root._trennen = ""
    }

    // --- Bluetooth im Gerät, aber BlueZ antwortet nicht ---

    WlanZeile {
        visible: !root._bereit
        width: root.width
        klickbar: false
        symbol: "bluetooth-aus"
        symbolGedaempft: true
        text: "Bluetooth"
        wert: "nicht bereit"
    }

    Text {
        visible: !root._bereit
        x: 35
        width: root.width - x - 10
        bottomPadding: Theme.a1
        // Geschütztes Leerzeichen ( ): Der Befehl bricht nie über zwei Zeilen
        text: "Bluetooth antwortet nicht. Prüfen mit «zen doctor»."
        textFormat: Text.PlainText
        color: Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseKlein
        wrapMode: Text.Wrap
    }

    // --- mit BlueZ ---

    // Bluetooth ein/aus: nur der Schalter (die Zeile ist eine Beschriftung), wie beim WLAN
    Item {
        id: kopf

        readonly property bool _schaltbar: root._bereit && !root.quelle.gesperrt

        visible: root._bereit
        width: root.width
        height: 36

        WlanZeile {
            anchors.fill: parent
            klickbar: false
            symbol: root._an ? "bluetooth" : "bluetooth-aus"
            symbolGedaempft: !root._an || root._verbunden.length === 0
            text: "Bluetooth"
            wert: kopf._schaltbar ? "" : "gesperrt"
        }

        Schalter {
            id: schalter

            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: kopf._schaltbar
            // Eigener Eintrag für Pfeile und Tab der Menükarte (Leertaste oder Enter schaltet)
            activeFocusOnTab: visible
            an: root._an
            beschriftung: "Bluetooth"
            onUmgeschaltet: an => {
                root.quelle.anSetzen(an);
                // Der Schalter setzt «an» bei Bedienung selbst; danach wieder dem echten Zustand folgen
                schalter.an = Qt.binding(() => root._an);
            }
        }
    }

    // Verbundene Geräte: Symbol nach Typ, Name, Akku, Haken. Klick fragt «trennen?», «x» vergisst.
    Repeater {
        model: root._an ? root._verbunden : []

        delegate: WlanZeile {
            id: verbunden

            required property var modelData
            readonly property bool _gefragt: root._trennen === modelData.adresse

            width: root.width
            symbol: Bt.symbol(modelData.typ)
            text: _gefragt ? "«" + root._name(modelData) + "» trennen?" : root._name(modelData)
            textGedaempft: root._verborgen && !_gefragt
            wert: _gefragt ? "" : Bt.zeilenWert(modelData)
            haken: !_gefragt && !modelData.trennt
            klickbar: !modelData.trennt
            vergessbar: !root._verborgen
            frage: "«" + Bt.anzeigeName(modelData.name) + "» vergessen?"
            onAusgeloest: root._trennenAusloesen(modelData.adresse)
            onVergessen: root.quelle.vergessen(modelData.adresse)
            onHatFokusChanged: if (!hatFokus && _gefragt) root._trennen = ""
        }
    }

    // Aufklappen: gekoppelte und gefundene Geräte
    WlanZeile {
        id: aufklappen

        visible: root._an
        width: root.width
        klickbar: !root._verborgen
        text: "Weitere Geräte"
        textGedaempft: root._verborgen
        wert: root._verborgen ? "verborgen" : ""
        pfeil: root._verborgen ? 0 : root.offen ? 2 : 1
        onAusgeloest: root.offen = !root.offen
    }

    // Liste (höchstens fünfeinhalb Zeilen hoch, dann scrollt sie, wie die Netze)
    Flickable {
        id: flaeche

        function zeigen(zeile: Item): void {
            const p = zeile.mapToItem(inhalt, 0, 0);
            if (p.y < contentY)
                contentY = p.y;
            else if (p.y + zeile.height > contentY + height)
                contentY = p.y + zeile.height - height;
        }

        visible: root._an && root.offen && !root._verborgen
        width: root.width
        height: Math.min(inhalt.implicitHeight, 5.5 * 36)
        contentHeight: inhalt.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // Schmaler Balken rechts, solange die Liste weitergeht
        Rectangle {
            parent: flaeche
            visible: flaeche.contentHeight > flaeche.height + 1
            z: 1
            x: flaeche.width - width
            y: flaeche.contentHeight > 0 ? flaeche.contentY * flaeche.height / flaeche.contentHeight : 0
            width: 3
            height: flaeche.contentHeight > 0 ? flaeche.height * flaeche.height / flaeche.contentHeight : 0
            radius: width / 2
            color: Theme.gedaempft
            opacity: 0.5
        }

        Column {
            id: inhalt

            width: flaeche.width

            Repeater {
                model: root._liste

                delegate: Column {
                    id: eintrag

                    required property var modelData
                    readonly property bool _fehlerHier: root.quelle !== null && root.quelle.fehlerGeraet === modelData.adresse && root.quelle.fehler !== ""

                    width: inhalt.width

                    WlanZeile {
                        width: eintrag.width
                        symbol: Bt.symbol(eintrag.modelData.typ)
                        text: Bt.anzeigeName(eintrag.modelData.name)
                        wert: Bt.zeilenWert(eintrag.modelData)
                        klickbar: !eintrag.modelData.verbindet && !eintrag.modelData.koppelt
                        vergessbar: eintrag.modelData.gekoppelt
                        frage: "«" + Bt.anzeigeName(eintrag.modelData.name) + "» vergessen?"
                        onAusgeloest: root.quelle.verbinden(eintrag.modelData.adresse)
                        onVergessen: root.quelle.vergessen(eintrag.modelData.adresse)
                        onHatFokusChanged: if (hatFokus) flaeche.zeigen(eintrag)
                    }

                    // Fehler ruhig unter dem Gerät
                    Text {
                        visible: eintrag._fehlerHier
                        x: 35
                        width: eintrag.width - x - 10
                        bottomPadding: Theme.a1
                        text: visible ? Bt.fehlerText(root.quelle.fehler) : ""
                        textFormat: Text.PlainText
                        color: Theme.fehler
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseKlein
                        wrapMode: Text.Wrap
                    }
                }
            }

            Text {
                visible: root._liste.length === 0
                x: 35
                width: inhalt.width - x - 10
                height: 36
                verticalAlignment: Text.AlignVCenter
                text: "Suche Geräte …"
                textFormat: Text.PlainText
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
            }
        }
    }

    // Wie ein neues Gerät dazukommt
    Text {
        visible: root._an && root.offen && !root._verborgen
        x: 35
        width: root.width - x - 10
        topPadding: 2
        bottomPadding: Theme.a1
        text: "Neues Gerät: in den Kopplungsmodus bringen, dann hier wählen."
        textFormat: Text.PlainText
        color: Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseKlein
        wrapMode: Text.Wrap
    }
}
