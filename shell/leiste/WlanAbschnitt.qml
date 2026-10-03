pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.dienste
import qs.komponenten
import "wlan.js" as Wlan

// Netz im System-Menü. Mit NetworkManager (quelle = WlanQuelle aus Leiste.qml, im Test eine Attrappe mit
// derselben Schnittstelle): WLAN mit Schalter, das verbundene Netz mit Signal, darunter aufklappbar die Netze in
// Reichweite. Ein Klick verbindet ein bekanntes oder offenes Netz direkt; bei einem neuen Netz mit Passwort
// erscheint ein Passwortfeld (Enter verbindet, Esc bricht ab). Gespeicherte Netze lassen sich vergessen.
// Ohne NetworkManager (quelle null) wie bisher nur die Anzeige aus System, dazu ein ruhiger Hinweis.
//
// Während einer Bildschirmfreigabe zeigt der Abschnitt keine Netznamen (sie verraten Orte). Die Menüs der Leiste
// sind während der Sperre zu; der Abschnitt entsteht mit dem Menü neu und vergisst dabei Liste und Passwortfeld.
Column {
    id: root

    // WlanQuelle oder null (NetworkManager läuft nicht, oder WlanQuelle liess sich nicht laden)
    property var quelle: null
    // NetworkManager läuft (Prüfung in Leiste.qml)
    property bool nmLaeuft: false
    // Liste der Netze aufgeklappt (Startwert: zenos-ipc leiste menue wlan)
    property bool offen: false

    readonly property bool _nm: quelle !== null && quelle.bereit
    readonly property bool _wlan: _nm && quelle.geraetDa
    readonly property bool _an: _wlan && quelle.wlanAn
    readonly property bool _verborgen: Freigabe.aktiv
    // Netz, für das gerade das Passwortfeld offen ist
    property string _passwortNetz: ""
    property string _hinweis: ""
    // Netze ohne das verbundene (das steht immer oben)
    property var _liste: []

    width: parent ? parent.width : 0

    function _netz(name: string): var {
        const alle = quelle ? quelle.netze : [];
        for (let i = 0; i < alle.length; i++) {
            if (alle[i].name === name)
                return alle[i];
        }
        return null;
    }

    function _waehlen(netz: var): void {
        if (!Wlan.verbindbar(netz) || netz.verbindet)
            return;
        if (Wlan.brauchtPasswort(netz)) {
            _passwortOeffnen(netz.name);
            return;
        }
        _passwortSchliessen(false);
        quelle.verbinden(netz.name);
    }

    function _passwortOeffnen(name: string): void {
        _passwortNetz = name;
        _hinweis = "";
        Qt.callLater(() => {
            if (passwortLader.item)
                passwortLader.item.fokussieren();
        });
    }

    // abbrechen: Zeno bricht ab (Esc) – ein eben angelegtes, gescheitertes Profil wieder vergessen
    function _passwortSchliessen(abbrechen: bool): void {
        if (_passwortNetz === "")
            return;
        const name = _passwortNetz;
        _passwortNetz = "";
        _hinweis = "";
        if (abbrechen && quelle)
            quelle.abbrechen(name);
        if (abbrechen)
            Qt.callLater(() => aufklappen.fokussieren());
    }

    function _senden(passwort: string): bool {
        const pruefung = Wlan.passwortPruefen(passwort);
        if (pruefung !== "") {
            _hinweis = pruefung;
            return false;
        }
        _hinweis = "";
        quelle.verbindenMitPasswort(_passwortNetz, passwort);
        return true;
    }

    function _scannenSetzen(): void {
        if (quelle)
            quelle.scannen = offen && _an && !_verborgen;
    }

    // Liste neu, Fokus beim selben Netz halten (die Zeilen entstehen neu)
    function _listeAktualisieren(): void {
        let fokus = "";
        for (let i = 0; i < zeilen.count; i++) {
            const z = zeilen.itemAt(i);
            if (z && z.hatFokus)
                fokus = z.netzName;
        }
        const alle = quelle ? quelle.netze : [];
        _liste = alle.filter(n => !n.verbunden);
        if (fokus === "")
            return;
        Qt.callLater(() => {
            for (let i = 0; i < zeilen.count; i++) {
                const z = zeilen.itemAt(i);
                if (z && z.netzName === fokus) {
                    z.fokussieren();
                    return;
                }
            }
        });
    }

    onOffenChanged: {
        if (!offen)
            _passwortSchliessen(true);
        _scannenSetzen();
    }
    on_AnChanged: _scannenSetzen()
    on_VerborgenChanged: {
        // Freigabe beginnt: Liste und Passwortfeld zu (sie zeigen Netznamen)
        if (_verborgen) {
            _passwortSchliessen(true);
            offen = false;
        }
        _scannenSetzen();
    }

    Component.onCompleted: {
        if (quelle)
            quelle.menueOffen = true;
        _listeAktualisieren();
        _scannenSetzen();
    }
    Component.onDestruction: {
        if (!quelle)
            return;
        quelle.scannen = false;
        quelle.menueOffen = false;
        quelle.aufraeumen();
    }

    Connections {
        target: root.quelle

        function onNetzeChanged(): void {
            root._listeAktualisieren();
        }

        // Ergebnis eines Versuchs: verbunden → Passwortfeld zu; Passwort falsch → Feld (wieder) öffnen
        function onFehlerChanged(): void {
            const q = root.quelle;
            if (q.fehler === "passwort" && q.fehlerNetz !== "" && !root._verborgen)
                root._passwortOeffnen(q.fehlerNetz);
        }

        function onVerbundenChanged(): void {
            const v = root.quelle.verbunden;
            if (v && v.name === root._passwortNetz)
                root._passwortSchliessen(false);
        }
    }

    // --- ohne NetworkManager oder ohne WLAN-Gerät: Anzeige wie bisher (System) ---

    WlanZeile {
        visible: !root._wlan
        width: root.width
        klickbar: false
        stufe: System.netzArt === "kabel" ? -1 : System.netzArt === "wlan" || System.wlanVerbunden ? Wlan.stufe(System.wlanSignal) : 0
        symbol: "kabel"
        symbolGedaempft: !System.netzVerbunden
        text: System.netzArt === "kabel" ? "Kabel" : System.netzArt === "wlan" || System.wlanVerbunden ? "WLAN" : "Netzwerk"
        wert: {
            if (!System.netzVerbunden)
                return System.wlanVerbunden ? "WLAN ohne Internet" : "nicht verbunden";
            if (System.netzArt === "wlan" && System.wlanSignal >= 0)
                return "verbunden · " + System.wlanSignal + " %";
            return "verbunden";
        }
    }

    // Hinweis: WLAN wählen geht erst mit NetworkManager (zen netzwerk umstellen, docs/module/netzwerk.md)
    Text {
        visible: !root._nm && System.wlanGeraet
        x: 35
        width: root.width - x - 10
        bottomPadding: Theme.a1
        // Geschützte Leerzeichen (\u00a0): Der Befehl bricht nie über zwei Zeilen
        text: root.quelle !== null || root.nmLaeuft ? "NetworkManager antwortet nicht. Prüfen mit «zen\u00a0netzwerk\u00a0status»." : "WLAN wählen: im Terminal «zen\u00a0netzwerk\u00a0umstellen», dann neu starten."
        textFormat: Text.PlainText
        color: Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseKlein
        wrapMode: Text.Wrap
    }

    // --- mit NetworkManager und WLAN-Gerät ---

    // Kabel zusätzlich zum WLAN (Standardverbindung über ein Kabelgerät)
    WlanZeile {
        visible: root._wlan && System.netzArt === "kabel"
        width: root.width
        klickbar: false
        symbol: "kabel"
        text: "Kabel"
        wert: "verbunden"
    }

    // WLAN ein/aus: nur der Schalter (die Zeile selbst ist eine Beschriftung). Ein versehentlicher Klick auf «WLAN»
    // oder Pfeil runter und Enter trennt so nicht die Verbindung (auch nicht SSH).
    Item {
        id: kopf

        visible: root._wlan
        width: root.width
        height: 36

        readonly property bool _schaltbar: root._wlan && root.quelle.hardwareAn

        WlanZeile {
            anchors.fill: parent
            klickbar: false
            stufe: root._an && root.quelle.verbunden ? root.quelle.verbundenStufe : root._an ? 3 : 0
            symbolGedaempft: !root._an || !root.quelle.verbunden
            text: "WLAN"
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
            beschriftung: "WLAN"
            onUmgeschaltet: an => {
                root.quelle.wlanSetzen(an);
                // Der Schalter setzt «an» bei Bedienung selbst; danach wieder dem echten Zustand folgen
                schalter.an = Qt.binding(() => root._an);
            }
        }
    }

    // Verbundenes Netz: Signal, Name, Haken; vergessen trennt und löscht das Profil
    WlanZeile {
        readonly property var netz: root._an ? root.quelle.verbunden : null

        visible: netz !== null
        width: root.width
        klickbar: false
        stufe: netz ? netz.stufe : 0
        text: !netz ? "" : root._verborgen ? "Netzname verborgen" : Wlan.anzeigeName(netz.name)
        textGedaempft: root._verborgen
        gesichert: netz !== null && netz.sicherheit !== "offen"
        haken: true
        vergessbar: netz !== null && netz.bekannt && !root._verborgen
        frage: netz ? "«" + Wlan.anzeigeName(netz.name) + "» vergessen?" : ""
        onVergessen: root.quelle.vergessen(netz.name)
    }

    // Aufklappen: Netze in Reichweite
    WlanZeile {
        id: aufklappen

        visible: root._an
        width: root.width
        klickbar: !root._verborgen
        text: "Netze in Reichweite"
        textGedaempft: root._verborgen
        wert: root._verborgen ? "verborgen" : ""
        pfeil: root._verborgen ? 0 : root.offen ? 2 : 1
        onAusgeloest: root.offen = !root.offen
    }

    // Liste (höchstens fünfeinhalb Zeilen hoch, dann scrollt sie: Die angeschnittene Zeile und ein schmaler Balken
    // rechts zeigen, dass es weitergeht).
    // Während das Passwortfeld offen ist, steht dort nur das gewählte Netz mit dem Feld.
    Flickable {
        id: flaeche

        function zeigen(zeile: Item): void {
            const p = zeile.mapToItem(inhalt, 0, 0);
            if (p.y < contentY)
                contentY = p.y;
            else if (p.y + zeile.height > contentY + height)
                contentY = p.y + zeile.height - height;
        }

        visible: root._an && root.offen && root._passwortNetz === "" && !root._verborgen
        width: root.width
        height: Math.min(inhalt.implicitHeight, 5.5 * 36)
        contentHeight: inhalt.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // Schmaler Balken rechts, solange die Liste weitergeht (auch wenn eine Zeile genau am Rand endet)
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
                id: zeilen

                model: root._liste

                delegate: Column {
                    id: eintrag

                    required property var modelData
                    readonly property string netzName: modelData.name
                    readonly property bool hatFokus: zeile.hatFokus
                    readonly property bool _fehlerHier: root.quelle !== null && root.quelle.fehlerNetz === modelData.name && root.quelle.fehler !== "" && root.quelle.fehler !== "passwort"

                    function fokussieren(): void {
                        zeile.fokussieren();
                    }

                    width: inhalt.width

                    WlanZeile {
                        id: zeile

                        width: eintrag.width
                        stufe: eintrag.modelData.stufe
                        text: Wlan.anzeigeName(eintrag.modelData.name)
                        gesichert: eintrag.modelData.sicherheit !== "offen"
                        wert: Wlan.zeilenWert(eintrag.modelData)
                        blass: !Wlan.verbindbar(eintrag.modelData)
                        klickbar: Wlan.verbindbar(eintrag.modelData) && !eintrag.modelData.verbindet
                        vergessbar: eintrag.modelData.bekannt
                        frage: "«" + Wlan.anzeigeName(eintrag.modelData.name) + "» vergessen?"
                        onAusgeloest: root._waehlen(eintrag.modelData)
                        onVergessen: root.quelle.vergessen(eintrag.modelData.name)
                        onHatFokusChanged: if (hatFokus) flaeche.zeigen(eintrag)
                    }

                    // Fehler ruhig unter dem Netz (ein falsches Passwort zeigt das Passwortfeld)
                    Text {
                        visible: eintrag._fehlerHier
                        x: 35
                        width: eintrag.width - x - 10
                        bottomPadding: Theme.a1
                        text: visible ? Wlan.fehlerText(root.quelle.fehler, eintrag.modelData.wpa3) : ""
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
                text: "Suche Netze …"
                textFormat: Text.PlainText
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
            }
        }
    }

    // Passwortfeld für ein neues Netz (oder ein bekanntes, dessen Passwort nicht mehr stimmt)
    Loader {
        id: passwortLader

        active: root._an && root._passwortNetz !== "" && !root._verborgen
        visible: active
        width: root.width

        sourceComponent: Column {
            id: passwort

            readonly property var netz: root._netz(root._passwortNetz)
            readonly property bool verbindet: root.quelle.versuch === root._passwortNetz
            readonly property bool gescheitert: root.quelle.fehlerNetz === root._passwortNetz && root.quelle.fehler !== ""

            function fokussieren(): void {
                feld.fokussieren();
            }

            width: root.width

            // Esc bricht ab (statt das Menü zu schliessen), solange nicht gerade verbunden wird
            Keys.onEscapePressed: event => {
                if (passwort.verbindet) {
                    event.accepted = false;
                    return;
                }
                root._passwortSchliessen(true);
                event.accepted = true;
            }

            WlanZeile {
                width: passwort.width
                klickbar: false
                stufe: passwort.netz ? passwort.netz.stufe : 3
                text: Wlan.anzeigeName(root._passwortNetz)
                gesichert: true
            }

            Item {
                width: passwort.width
                height: 40

                Eingabe {
                    id: feld

                    x: 35 - 14
                    width: parent.width - x - 10
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    passwort: true
                    platzhalter: "Passwort"
                    schriftGroesse: Theme.groesseText
                    enabled: !passwort.verbindet
                    fehler: passwort.gescheitert || root._hinweis !== ""
                    onAccepted: {
                        // Das Passwort geht nur an NetworkManager und bleibt nicht im Feld stehen
                        const text = feld.text;
                        if (root._senden(text))
                            feld.leeren();
                    }
                }
            }

            Text {
                x: 35
                width: passwort.width - x - 10
                topPadding: 2
                bottomPadding: Theme.a1
                text: {
                    if (passwort.verbindet)
                        return "Verbinde …";
                    if (root._hinweis !== "")
                        return root._hinweis;
                    if (passwort.gescheitert)
                        return Wlan.fehlerText(root.quelle.fehler, passwort.netz ? passwort.netz.wpa3 : false);
                    return "Enter verbindet · Esc bricht ab";
                }
                textFormat: Text.PlainText
                color: !passwort.verbindet && (root._hinweis !== "" || passwort.gescheitert) ? Theme.fehler : Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseKlein
                wrapMode: Text.Wrap
            }

            // Nach einem gescheiterten Versuch wieder ins Feld
            onGescheitertChanged: if (gescheitert) feld.fokussieren()
        }
    }
}
