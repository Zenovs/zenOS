pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste
import "../modi/zustandslogik.js" as Logik

// Seite «Modus» nach Entwurf 2 «Modi & Zustände»: Name, Akzent, Chrome-Profil, Mail-Konten,
// «Heute» (später), Apps beim Wechsel, Raster pro Bildschirm-Profil, Zustände in diesem Modus,
// Leitplanken-Hinweis. Änderungen werden kurz nach der Eingabe gespeichert (zenos-konfig prüft sie).
// unterauswahl: ID des Modus (leer = aktiver oder erster Modus)
Item {
    id: root

    property string unterauswahl
    // Gerade neu angelegt: Namensfeld fokussieren, Text markiert
    property bool frischAngelegt: false

    readonly property string modusId: {
        const liste = Dienste.Modi.liste;
        if (unterauswahl !== "" && liste.some(m => m.id === unterauswahl))
            return unterauswahl;
        if (Dienste.Modi.aktivId !== "" && liste.some(m => m.id === Dienste.Modi.aktivId))
            return Dienste.Modi.aktivId;
        return liste.length > 0 ? liste[0].id : "";
    }
    readonly property var gespeichert: Dienste.Konfig.eintrag("modi", modusId)
    // Arbeitskopie (ohne id)
    property var entwurf: ({})
    property string fehlerText: ""

    readonly property bool istAktiv: modusId !== "" && modusId === Dienste.Modi.aktivId
    readonly property string akzentName: Theme.akzentNamen.indexOf(entwurf.akzent) >= 0 ? entwurf.akzent : Theme.standardAkzent
    readonly property color akzent: Theme.akzentFarbe(akzentName)
    readonly property string anzeigename: typeof entwurf.name === "string" && entwurf.name.trim() !== "" ? entwurf.name : modusId

    property string _geladenFuer: ""
    property bool _dirty: false

    function _kopie(o: var): var {
        return o && typeof o === "object" ? JSON.parse(JSON.stringify(o)) : {};
    }

    function _laden(): void {
        if (_dirty && _geladenFuer === modusId)
            return;
        const d = _kopie(gespeichert);
        delete d.id;
        entwurf = d;
        _geladenFuer = modusId;
        if (nameFeld.text !== (d.name ?? ""))
            nameFeld.text = d.name ?? "";
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
        // Der Entwurf gehört zu dem Modus, für den er geladen wurde
        const id = _geladenFuer;
        if (!_dirty || id === "")
            return;
        const d = _kopie(entwurf);
        if (typeof d.name !== "string" || d.name.trim() === "")
            d.name = Dienste.Konfig.eintrag("modi", id)?.name ?? "Modus";
        Dienste.Modi.speichern(id, d, (ok, meldung) => {
            if (root._geladenFuer === id)
                root._dirty = false;
            root.fehlerText = ok ? "" : meldung;
        });
    }

    // Zustände, die dieser Modus anbietet (fehlt die Liste: alle)
    function _angeboten(zid: string): bool {
        return !Array.isArray(entwurf.zustaende) || entwurf.zustaende.indexOf(zid) >= 0;
    }

    function _anbieten(zid: string, an: bool): void {
        const alle = Dienste.Zustaende.liste.map(z => z.id);
        let liste = Array.isArray(entwurf.zustaende) ? entwurf.zustaende.filter(x => alle.indexOf(x) >= 0) : alle.slice();
        liste = liste.filter(x => x !== zid);
        if (an)
            liste.push(zid);
        aendern("zustaende", alle.filter(x => liste.indexOf(x) >= 0));
    }

    function _listeOhne(schluessel: string, wert: string): void {
        const liste = Array.isArray(entwurf[schluessel]) ? entwurf[schluessel].filter(x => x !== wert) : [];
        aendern(schluessel, liste);
    }

    function _listeMit(schluessel: string, wert: string): void {
        const w = (wert ?? "").trim();
        if (w === "")
            return;
        const liste = Array.isArray(entwurf[schluessel]) ? entwurf[schluessel].slice() : [];
        if (liste.indexOf(w) < 0)
            liste.push(w);
        aendern(schluessel, liste);
    }

    function _rasterSetzen(profil: string, rasterId: string): void {
        const r = _kopie(entwurf.raster);
        if (rasterId === "")
            delete r[profil];
        else
            r[profil] = rasterId;
        aendern("raster", Object.keys(r).length > 0 ? r : undefined);
    }

    function _wechsel(): void {
        if (_geladenFuer === modusId)
            return;
        if (_dirty)
            speichern();
        _dirty = false;
        fehlerText = "";
        _laden();
    }

    // Verzögert, damit kein Schreiben in laufende Bindungen fällt
    onModusIdChanged: Qt.callLater(_wechsel)
    onGespeichertChanged: Qt.callLater(_laden)
    Component.onCompleted: _laden()
    Component.onDestruction: speichern()
    onFrischAngelegtChanged: {
        if (frischAngelegt)
            Qt.callLater(() => {
                nameFeld.fokussieren();
                nameFeld.feld.selectAll();
            });
    }

    Timer {
        id: speicherTimer

        interval: 500
        onTriggered: root.speichern()
    }

    // Chrome-Profile (Anzeigenamen) aus «Local State», nur lesen
    FileView {
        id: chromeStatus

        path: Dienste.Pfade.home + "/.config/google-chrome/Local State"
        printErrors: false
    }

    readonly property var chromeProfile: {
        const text = chromeStatus.text();
        if (!text)
            return [];
        try {
            const info = JSON.parse(text)?.profile?.info_cache ?? {};
            return Object.keys(info).map(k => info[k]?.name).filter(n => typeof n === "string" && n.length > 0).sort((a, b) => a.localeCompare(b));
        } catch (e) {
            return [];
        }
    }

    readonly property var profile: {
        const p = Dienste.Konfig.bildschirme?.profile;
        const namen = Array.isArray(p) ? p.map(x => x?.name).filter(n => typeof n === "string" && n.length > 0) : [];
        return namen.length > 0 ? namen : ["Standard"];
    }

    readonly property var rasterOptionen: [
        {
            wert: "",
            text: "Nicht ändern"
        }
    ].concat(Dienste.Konfig.raster.map(r => ({
                wert: r.id,
                text: typeof r.name === "string" && r.name !== "" ? r.name : r.id
            })))

    // --- Kein Modus ---
    Seite {
        visible: root.modusId === ""
        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Modi"
            titel: "Noch kein Modus"
        }

        Text {
            width: Math.min(parent.width, 560)
            text: "Ein Modus ist ein Kontext wie Arbeit oder privat: Akzentfarbe, Chrome-Profil, Apps beim Wechsel und Raster. Ab Werk gibt es keinen, du legst sie selbst an."
            wrapMode: Text.WordWrap
            lineHeight: 1.4
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseGross
        }

        Knopf {
            text: "Neuer Modus"
            symbol: "plus"
            onClicked: Dienste.Oberflaeche.einstellungenSeite = "modi/neu"
        }
    }

    // --- Editor ---
    Seite {
        id: seite

        visible: root.modusId !== ""
        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Modus"
            titel: root.anzeigename

            Pille {
                visible: root.istAktiv
                text: "aktiv"
                variante: "aktiv"
                akzent: root.akzent
            }

            Chip {
                visible: !root.istAktiv
                text: "Aktivieren"
                variante: "umrandet"
                onClicked: {
                    root.speichern();
                    Dienste.Modi.wechseln(root.modusId);
                }
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
            id: raster

            readonly property real spalte: (width - columnSpacing) / 2

            width: parent.width
            columns: 2
            columnSpacing: 40
            rowSpacing: 18

            Feld {
                width: raster.spalte
                beschriftung: "Name"

                Eingabe {
                    id: nameFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 60
                    platzhalter: "z. B. Arbeit"
                    fehler: text.trim().length === 0
                }
            }

            Feld {
                width: raster.spalte
                beschriftung: "Akzentfarbe"

                Item {
                    width: parent.width
                    height: 38

                    Farbwahl {
                        anchors.verticalCenter: parent.verticalCenter
                        auswahl: root.akzentName
                        hintergrund: Theme.flaeche
                        abstand: 10
                        onAusgewaehlt: name => root.aendern("akzent", name)
                    }
                }
            }

            Feld {
                width: raster.spalte
                beschriftung: "Chrome-Profil"
                hinweis: root.chromeProfile.length === 0 ? "Chrome noch ohne Profile" : ""

                Auswahl {
                    visible: root.chromeProfile.length > 0
                    width: parent.width
                    wert: root.entwurf.chromeProfil ?? ""
                    optionen: {
                        const aktuell = root.entwurf.chromeProfil ?? "";
                        const liste = [
                            {
                                wert: "",
                                text: "Kein bestimmtes Profil"
                            }
                        ].concat(root.chromeProfile.map(n => ({
                                    wert: n,
                                    text: n
                                })));
                        if (aktuell !== "" && root.chromeProfile.indexOf(aktuell) < 0)
                            liste.push({
                                wert: aktuell,
                                text: aktuell + " (nicht gefunden)"
                            });
                        return liste;
                    }
                    onGewaehlt: wert => root.aendern("chromeProfil", wert === "" ? undefined : wert)
                }

                Eingabe {
                    id: chromeFeld

                    visible: root.chromeProfile.length === 0
                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 100
                    platzhalter: "Name des Chrome-Profils"
                    text: root.entwurf.chromeProfil ?? ""
                }
            }

            Feld {
                width: raster.spalte
                beschriftung: "Mail-Konten in coremail"

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: Array.isArray(root.entwurf.mailKonten) ? root.entwurf.mailKonten : []

                        Entfernbar {
                            required property string modelData

                            text: modelData
                            onEntfernen: root._listeOhne("mailKonten", modelData)
                        }
                    }

                    Hinzufuegen {
                        visible: !kontoFeld.visible
                        text: "+ Konto"
                        onClicked: {
                            kontoFeld.visible = true;
                            kontoFeld.leeren();
                            kontoFeld.fokussieren();
                        }
                    }

                    Eingabe {
                        id: kontoFeld

                        visible: false
                        width: 220
                        implicitHeight: 30
                        schriftGroesse: Theme.groesseLabel
                        maximaleLaenge: 200
                        platzhalter: "Konto, Enter übernimmt"
                        onAccepted: {
                            root._listeMit("mailKonten", text);
                            visible = false;
                        }
                        Keys.onEscapePressed: visible = false
                    }
                }
            }

            Feld {
                width: raster.spalte
                beschriftung: "In der «Heute»-Ansicht"

                Row {
                    height: 38
                    spacing: 22

                    Kontrollkaestchen {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Kalender"
                        aktiv: false
                    }

                    Kontrollkaestchen {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Aufgaben"
                        aktiv: false
                    }

                    Kontrollkaestchen {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wetter"
                        aktiv: false
                        an: root.entwurf.heute?.wetter === true
                    }

                    Pille {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "später"
                        variante: "spaeter"
                    }
                }
            }

            Feld {
                width: raster.spalte
                beschriftung: "Beim Wechsel öffnen"

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: Array.isArray(root.entwurf.oeffnen) ? root.entwurf.oeffnen : []

                        Entfernbar {
                            required property string modelData

                            text: DesktopEntries.byId(modelData)?.name ?? modelData
                            onEntfernen: root._listeOhne("oeffnen", modelData)
                        }
                    }

                    Hinzufuegen {
                        id: appKnopf

                        text: "+ App"
                        onClicked: appWahl.open()

                        AppWahl {
                            id: appWahl

                            y: appKnopf.height + 4
                            ausgenommen: Array.isArray(root.entwurf.oeffnen) ? root.entwurf.oeffnen : []
                            onGewaehlt: id => root._listeMit("oeffnen", id)
                        }
                    }
                }
            }
        }

        // Raster pro Bildschirm-Profil (ganze Breite)
        Row {
            width: parent.width
            spacing: 40

            Repeater {
                model: root.profile

                Feld {
                    id: rasterFeld

                    required property string modelData

                    width: (seite.width - 88 - 40 * (root.profile.length - 1)) / root.profile.length
                    beschriftung: modelData === "Standard" ? "Raster · alle Bildschirme" : "Raster · " + modelData
                    hinweis: Dienste.Konfig.raster.length === 0 ? "noch keine Raster" : ""

                    Auswahl {
                        width: parent.width
                        optionen: root.rasterOptionen
                        wert: root.entwurf.raster?.[rasterFeld.modelData] ?? ""
                        onGewaehlt: wert => root._rasterSetzen(rasterFeld.modelData, wert)
                    }
                }
            }
        }

        // Zustände in diesem Modus
        Column {
            width: parent.width
            spacing: 0

            Item {
                width: parent.width
                height: 34

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Zustände in diesem Modus"
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Zustände verwalten"
                    color: root.akzent
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Dienste.Oberflaeche.einstellungenSeite = "zustand"
                    }
                }
            }

            Repeater {
                model: Dienste.Zustaende.liste

                Item {
                    id: zeile

                    required property var modelData
                    required property int index
                    readonly property bool angeboten: root._angeboten(modelData.id)
                    readonly property var anpassung: root.entwurf.anpassungen?.[modelData.id] ?? {}
                    readonly property bool angepasst: (Logik.mischen(modelData, anpassung)?.angepasst ?? []).length > 0

                    width: parent.width
                    height: 46

                    Trenner {
                        width: parent.width
                    }

                    Trenner {
                        visible: zeile.index === Dienste.Zustaende.liste.length - 1
                        anchors.bottom: parent.bottom
                        width: parent.width
                    }

                    Text {
                        id: zName

                        x: 0
                        width: 150
                        anchors.verticalCenter: parent.verticalCenter
                        text: typeof zeile.modelData.name === "string" && zeile.modelData.name !== "" ? zeile.modelData.name : zeile.modelData.id
                        color: zeile.angeboten ? Theme.text : Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    Text {
                        x: 150 + 16
                        width: parent.width - x - 16 - 110 - 16 - 40
                        anchors.verticalCenter: parent.verticalCenter
                        text: Logik.beschreibung(zeile.modelData, zeile.anpassung, zeile.angeboten)
                        color: Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                        elide: Text.ElideRight
                    }

                    // Zeile öffnet den Zustand mit der Anpassung dieses Modus
                    MouseArea {
                        anchors.left: parent.left
                        anchors.right: pille.left
                        height: parent.height
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.speichern();
                            Dienste.Oberflaeche.einstellungenSeite = "zustand/" + zeile.modelData.id + "@" + root.modusId;
                        }
                    }

                    Pille {
                        id: pille

                        x: parent.width - 40 - 16 - 110
                        anchors.verticalCenter: parent.verticalCenter
                        visible: zeile.angeboten
                        text: zeile.angepasst ? "angepasst" : "Vorlage"
                        variante: zeile.angepasst ? "angepasst" : "vorlage"
                        akzent: root.akzent
                    }

                    Kontrollkaestchen {
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        groesse: 18
                        an: zeile.angeboten
                        akzent: root.akzent
                        Accessible.name: zName.text + " in diesem Modus anbieten"
                        onUmgeschaltet: an => root._anbieten(zeile.modelData.id, an)
                    }
                }
            }

            Text {
                visible: Dienste.Zustaende.liste.length === 0
                topPadding: 8
                text: "Noch keine Zustände. «Fokus» und «Sitzung» kommen als Vorlagen mit zen benutzer."
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
            }
        }

        Leitplankenhinweis {
            width: parent.width
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: "~/.config/zenos/modi/" + root.modusId + ".json · lokal, nicht im Repo"
            loeschenText: "Modus löschen"
            rueckfrage: "Modus «" + root.anzeigename + "» löschen?"
            akzent: root.akzent
            onLoeschen: {
                const id = root.modusId;
                root._dirty = false;
                speicherTimer.stop();
                Dienste.Modi.loeschen(id);
                Dienste.Oberflaeche.einstellungenSeite = "modi";
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
        target: chromeFeld.feld

        function onTextEdited(): void {
            const t = chromeFeld.text.trim();
            root.aendern("chromeProfil", t === "" ? undefined : t);
        }
    }
}
