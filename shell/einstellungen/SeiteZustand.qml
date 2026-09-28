pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste
import "../modi/zustandslogik.js" as Logik

// Seite «Zustand»: alle Schlüssel aus docs/konfiguration.md, wahlweise für die Vorlage oder als
// Anpassung eines Modus («Werte für»). Die Leitplanken stehen sichtbar, aber nicht änderbar dabei.
// unterauswahl: "<zustand>" oder "<zustand>@<modus>" (leer = erster Zustand)
Item {
    id: root

    property string unterauswahl
    // Gerade neu angelegt: Namensfeld fokussieren, Text markiert
    property bool frischAngelegt: false

    readonly property string zustandId: {
        const wunsch = unterauswahl.split("@")[0];
        const liste = Dienste.Zustaende.liste;
        if (wunsch !== "" && liste.some(z => z.id === wunsch))
            return wunsch;
        return liste.length > 0 ? liste[0].id : "";
    }
    // Modus, dessen Anpassung bearbeitet wird ("" = Vorlage)
    readonly property string modusId: {
        const m = unterauswahl.indexOf("@") >= 0 ? unterauswahl.split("@")[1] : "";
        return m !== "" && Dienste.Konfig.eintrag("modi", m) ? m : "";
    }
    readonly property var gespeichert: Dienste.Konfig.eintrag("zustaende", zustandId)
    readonly property var modus: modusId !== "" ? Dienste.Konfig.eintrag("modi", modusId) : null

    // Arbeitskopien: Vorlage (ohne id) und Anpassung des Modus
    property var vorlage: ({})
    property var anpassung: ({})
    // Was die Felder zeigen: Vorlage + Anpassung
    readonly property var werte: Logik.mischen(Object.assign({}, vorlage, {
        id: zustandId
    }), modusId !== "" ? anpassung : {}) ?? ({})
    property string fehlerText: ""

    readonly property bool istAktiv: zustandId !== "" && zustandId === Dienste.Zustaende.aktivId
    readonly property string anzeigename: typeof vorlage.name === "string" && vorlage.name.trim() !== "" ? vorlage.name : zustandId
    readonly property color akzent: modus && Theme.akzentNamen.indexOf(modus.akzent) >= 0 ? Theme.akzentFarbe(modus.akzent) : Theme.akzent

    property string _geladenFuer: ""
    property bool _vorlageDirty: false
    property bool _anpassungDirty: false
    // Zählen die Änderungen an Vorlage und Anpassung. Ein Rückruf gibt nur frei, wenn seit seinem
    // Speichern nichts dazukam und noch derselbe Zustand (samt Modus) geladen ist; _gesendet* verhindert,
    // dass derselbe Stand zweimal geschrieben wird.
    property int _standVorlage: 0
    property int _standAnpassung: 0
    property int _gesendetVorlage: -1
    property int _gesendetAnpassung: -1

    function _kopie(o: var): var {
        return o && typeof o === "object" ? JSON.parse(JSON.stringify(o)) : {};
    }

    function _laden(): void {
        const schluessel = zustandId + "@" + modusId;
        if ((_vorlageDirty || _anpassungDirty) && _geladenFuer === schluessel)
            return;
        const v = _kopie(gespeichert);
        delete v.id;
        vorlage = v;
        anpassung = _kopie(modus?.anpassungen?.[zustandId]);
        _geladenFuer = schluessel;
        if (nameFeld.text !== (v.name ?? ""))
            nameFeld.text = v.name ?? "";
    }

    // Wert setzen: in der Vorlage oder als Anpassung des Modus (gleich wie Vorlage = keine Anpassung)
    function setzen(schluessel: string, wert: var): void {
        if (modusId === "" || schluessel === "name") {
            const v = _kopie(vorlage);
            if (wert === undefined)
                delete v[schluessel];
            else
                v[schluessel] = wert;
            vorlage = v;
            _vorlageDirty = true;
            _standVorlage++;
        } else {
            const a = _kopie(anpassung);
            if (wert === undefined || JSON.stringify(wert) === JSON.stringify(vorlage[schluessel]))
                delete a[schluessel];
            else
                a[schluessel] = wert;
            anpassung = a;
            _anpassungDirty = true;
            _standAnpassung++;
        }
        speicherTimer.restart();
    }

    function anpassungZuruecksetzen(): void {
        anpassung = {};
        _anpassungDirty = true;
        _standAnpassung++;
        speichern();
    }

    function istAngepasst(schluessel: string): bool {
        return modusId !== "" && (werte.angepasst ?? []).indexOf(schluessel) >= 0;
    }

    function speichern(): void {
        speicherTimer.stop();
        const geladen = _geladenFuer;
        const [zid, mid] = geladen.split("@");
        if (!zid)
            return;
        if (_vorlageDirty && _gesendetVorlage !== _standVorlage) {
            const v = _kopie(vorlage);
            if (typeof v.name !== "string" || v.name.trim() === "")
                v.name = Dienste.Konfig.eintrag("zustaende", zid)?.name ?? "Zustand";
            const stand = _standVorlage;
            _gesendetVorlage = stand;
            Dienste.Zustaende.speichern(zid, v, (ok, meldung) => {
                // Die Seite kann schon geschlossen sein
                if (!root)
                    return;
                // Kam während des Speicherns eine Änderung dazu, bleibt sie offen: Timer oder «Fertig» speichern sie
                if (root._geladenFuer === geladen && root._standVorlage === stand)
                    root._vorlageDirty = false;
                root.fehlerText = ok ? "" : meldung;
            });
        }
        if (_anpassungDirty && mid && _gesendetAnpassung !== _standAnpassung) {
            const m = _kopie(Dienste.Konfig.eintrag("modi", mid));
            if (Object.keys(m).length > 0) {
                const alle = _kopie(m.anpassungen);
                if (Object.keys(anpassung).length > 0)
                    alle[zid] = _kopie(anpassung);
                else
                    delete alle[zid];
                if (Object.keys(alle).length > 0)
                    m.anpassungen = alle;
                else
                    delete m.anpassungen;
                const stand = _standAnpassung;
                _gesendetAnpassung = stand;
                Dienste.Modi.speichern(mid, m, (ok, meldung) => {
                    if (!root)
                        return;
                    if (root._geladenFuer === geladen && root._standAnpassung === stand)
                        root._anpassungDirty = false;
                    root.fehlerText = ok ? "" : meldung;
                });
            } else {
                _anpassungDirty = false;
            }
        }
    }

    // Auslöser-Liste bearbeiten
    function _ausloeser(): var {
        return Array.isArray(werte.ausloeser) ? werte.ausloeser.slice() : ["manuell"];
    }

    function _ausloeserUmschalten(art: string, an: bool): void {
        let l = _ausloeser().filter(a => a !== art);
        if (an)
            l.push(art);
        setzen("ausloeser", l);
    }

    function _uhrzeiten(): var {
        return _ausloeser().map(a => Logik.uhrzeitAus(a)).filter(z => z !== "").sort();
    }

    function _uhrzeitHinzu(zeit: string): void {
        const l = _ausloeser();
        if (l.indexOf("uhrzeit:" + zeit) < 0)
            l.push("uhrzeit:" + zeit);
        setzen("ausloeser", l);
    }

    function _uhrzeitWeg(zeit: string): void {
        setzen("ausloeser", _ausloeser().filter(a => a !== "uhrzeit:" + zeit));
    }

    readonly property string mitteilungenArt: Logik.gebuendeltMinuten(werte.mitteilungen) > 0 ? "gebuendelt" : (werte.mitteilungen ?? "")
    readonly property int buendelMinuten: Math.max(5, Logik.gebuendeltMinuten(werte.mitteilungen) > 0 ? Logik.gebuendeltMinuten(werte.mitteilungen) : 60)

    // Verzögert, damit kein Schreiben in laufende Bindungen fällt
    onZustandIdChanged: Qt.callLater(_wechsel)
    onModusIdChanged: Qt.callLater(_wechsel)
    onGespeichertChanged: Qt.callLater(_laden)
    onModusChanged: Qt.callLater(_laden)
    Component.onCompleted: _laden()
    Component.onDestruction: speichern()
    onFrischAngelegtChanged: {
        if (frischAngelegt)
            Qt.callLater(() => {
                nameFeld.fokussieren();
                nameFeld.feld.selectAll();
            });
    }

    function _wechsel(): void {
        if (_geladenFuer === zustandId + "@" + modusId)
            return;
        speichern();
        _vorlageDirty = false;
        _anpassungDirty = false;
        fehlerText = "";
        _laden();
    }

    Timer {
        id: speicherTimer

        interval: 500
        onTriggered: root.speichern()
    }

    // --- Kein Zustand ---
    Seite {
        visible: root.zustandId === ""
        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Zustände"
            titel: "Noch kein Zustand"
        }

        Text {
            width: Math.min(parent.width, 560)
            // Die Vorlagen kopiert die Einrichtung genau einmal (55-zustaende); zen benutzer holt
            // gelöschte nicht zurück
            text: "Ein Zustand bestimmt, wie sich zenOS gerade verhält: Mitteilungen, Leiste und «Heute». «Fokus» und «Sitzung» kommen bei der Einrichtung einmal als Vorlagen mit; gelöschte liegen unter " + Dienste.Pfade.code + "/config/vorlagen/zustaende."
            wrapMode: Text.WordWrap
            lineHeightMode: Text.FixedHeight
            lineHeight: Math.round(font.pixelSize * 1.4)
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseGross
        }

        Knopf {
            text: "Neuer Zustand"
            symbol: "plus"
            onClicked: Dienste.Oberflaeche.einstellungenSeite = "zustand/neu"
        }
    }

    // --- Editor ---
    Seite {
        id: seite

        visible: root.zustandId !== ""
        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: root.modusId !== "" ? "Zustand · Anpassung für " + (root.modus?.name ?? root.modusId) : "Zustand"
            titel: root.anzeigename

            Pille {
                visible: root.istAktiv
                text: "aktiv"
                variante: "aktiv"
                akzent: root.akzent
            }

            Chip {
                visible: root.istAktiv
                text: "Beenden"
                variante: "umrandet"
                onClicked: Dienste.Zustaende.beenden()
            }

            Chip {
                visible: !root.istAktiv && Logik.hatAusloeser(root.gespeichert, "manuell")
                text: "Starten"
                variante: "umrandet"
                onClicked: {
                    root.speichern();
                    Dienste.Zustaende.starten(root.zustandId, "manuell");
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
            id: oben

            readonly property real spalte: (width - columnSpacing) / 2

            width: parent.width
            columns: 2
            columnSpacing: 40
            rowSpacing: 18

            Feld {
                width: oben.spalte
                beschriftung: "Name"
                hinweis: root.modusId !== "" ? "gilt in allen Modi" : ""

                Eingabe {
                    id: nameFeld

                    width: parent.width
                    implicitHeight: 38
                    schriftGroesse: Theme.groesseText
                    maximaleLaenge: 60
                    platzhalter: "z. B. Fokus"
                    fehler: text.trim().length === 0
                }
            }

            Feld {
                width: oben.spalte
                beschriftung: "Werte für"
                hinweis: root.modusId !== "" && (root.werte.angepasst ?? []).length > 0 ? "angepasst" : ""
                hinweisBetont: true
                akzent: root.akzent

                Row {
                    width: parent.width
                    spacing: 10

                    Auswahl {
                        width: parent.width - (zuruecksetzen.visible ? zuruecksetzen.width + 10 : 0)
                        wert: root.modusId
                        optionen: [
                            {
                                wert: "",
                                text: "Vorlage (alle Modi)"
                            }
                        ].concat(Dienste.Modi.liste.map(m => ({
                                    wert: m.id,
                                    text: "Modus " + (typeof m.name === "string" && m.name !== "" ? m.name : m.id)
                                })))
                        onGewaehlt: wert => {
                            root.speichern();
                            Dienste.Oberflaeche.einstellungenSeite = "zustand/" + root.zustandId + (wert !== "" ? "@" + wert : "");
                        }
                    }

                    Knopf {
                        id: zuruecksetzen

                        visible: root.modusId !== "" && Object.keys(root.anpassung).length > 0
                        implicitHeight: 38
                        variante: "still"
                        text: "Wie Vorlage"
                        onClicked: root.anpassungZuruecksetzen()
                    }
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Mitteilungen"
            hinweis: root.istAngepasst("mitteilungen") ? "angepasst" : ""
            hinweisBetont: true
            akzent: root.akzent

            Row {
                spacing: 12

                Segmente {
                    optionen: [
                        {
                            wert: "alle",
                            text: "Sofort"
                        },
                        {
                            wert: "gebuendelt",
                            text: "Gebündelt"
                        },
                        {
                            wert: "nur-dringend",
                            text: "Nur Dringendes"
                        },
                        {
                            wert: "keine",
                            text: "Keine"
                        }
                    ]
                    wert: root.mitteilungenArt
                    onGewaehlt: wert => root.setzen("mitteilungen", wert === "gebuendelt" ? "gebuendelt-" + root.buendelMinuten : wert)
                }

                Stufenwahl {
                    visible: root.mitteilungenArt === "gebuendelt"
                    wert: root.buendelMinuten
                    min: 5
                    max: 240
                    schritt: 5
                    einheit: "Min."
                    onGeaendert: wert => root.setzen("mitteilungen", "gebuendelt-" + wert)
                }
            }
        }

        Grid {
            id: mitte

            readonly property real spalte: (width - columnSpacing) / 2

            width: parent.width
            columns: 2
            columnSpacing: 40
            rowSpacing: 18

            Feld {
                width: mitte.spalte
                beschriftung: "Leiste"
                hinweis: root.istAngepasst("leiste") ? "angepasst" : ""
                hinweisBetont: true
                akzent: root.akzent

                Segmente {
                    optionen: [
                        {
                            wert: "normal",
                            text: "Normal"
                        },
                        {
                            wert: "reduziert",
                            text: "Reduziert"
                        },
                        {
                            wert: "aus",
                            text: "Aus"
                        }
                    ]
                    wert: root.werte.leiste ?? "normal"
                    onGewaehlt: wert => root.setzen("leiste", wert)
                }
            }

            // «Fenster» und «Widgets» wirken in 0.1 noch nicht (wie «Kalender»): Der gespeicherte Wert
            // bleibt sichtbar, lässt sich hier aber nicht ändern.
            Feld {
                width: mitte.spalte
                beschriftung: "Fenster"
                hinweis: root.istAngepasst("fenster") ? "angepasst" : ""
                hinweisBetont: true
                akzent: root.akzent

                Row {
                    spacing: 8

                    Segmente {
                        aktiv: false
                        optionen: [
                            {
                                wert: "normal",
                                text: "Normal"
                            },
                            {
                                wert: "fokus",
                                text: "Nur das aktive im Vordergrund"
                            }
                        ]
                        wert: root.werte.fenster ?? "normal"
                    }

                    Pille {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "später"
                        variante: "spaeter"
                    }
                }
            }

            Feld {
                width: mitte.spalte
                beschriftung: "«Heute» im Hintergrund"
                hinweis: root.istAngepasst("heute") ? "angepasst" : ""
                hinweisBetont: true
                akzent: root.akzent

                Item {
                    width: parent.width
                    height: 38

                    Schalter {
                        anchors.verticalCenter: parent.verticalCenter
                        an: root.werte.heute !== false
                        beschriftung: "«Heute» im Hintergrund"
                        onUmgeschaltet: an => root.setzen("heute", an)
                    }
                }
            }

            Feld {
                width: mitte.spalte
                beschriftung: "Widgets"
                hinweis: root.istAngepasst("widgets") ? "angepasst" : ""
                hinweisBetont: true
                akzent: root.akzent

                Item {
                    width: parent.width
                    height: 38

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Schalter {
                            anchors.verticalCenter: parent.verticalCenter
                            enabled: false
                            an: root.werte.widgets !== false
                            beschriftung: "Widgets"
                        }

                        Pille {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "später"
                            variante: "spaeter"
                        }
                    }
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Startet"
            hinweis: root.istAngepasst("ausloeser") ? "angepasst" : ""
            hinweisBetont: true
            akzent: root.akzent

            Column {
                width: parent.width
                spacing: 10

                Row {
                    spacing: 24

                    Kontrollkaestchen {
                        text: "Von Hand"
                        akzent: root.akzent
                        an: root._ausloeser().indexOf("manuell") >= 0
                        onUmgeschaltet: an => root._ausloeserUmschalten("manuell", an)
                    }

                    Kontrollkaestchen {
                        text: "Bei Bildschirmfreigabe"
                        akzent: root.akzent
                        an: root._ausloeser().indexOf("bildschirmfreigabe") >= 0
                        onUmgeschaltet: an => root._ausloeserUmschalten("bildschirmfreigabe", an)
                    }

                    Kontrollkaestchen {
                        text: "Beim Wechsel in einen Modus"
                        akzent: root.akzent
                        an: root._ausloeser().indexOf("moduswechsel") >= 0
                        onUmgeschaltet: an => root._ausloeserUmschalten("moduswechsel", an)
                    }

                    Row {
                        spacing: 8

                        Kontrollkaestchen {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Kalender"
                            aktiv: false
                            an: root._ausloeser().indexOf("kalender") >= 0
                        }

                        Pille {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "später"
                            variante: "spaeter"
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Text {
                        height: 30
                        verticalAlignment: Text.AlignVCenter
                        rightPadding: 6
                        text: "Um"
                        color: Theme.text
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                    }

                    Repeater {
                        model: root._uhrzeiten()

                        Entfernbar {
                            required property string modelData

                            text: modelData
                            onEntfernen: root._uhrzeitWeg(modelData)
                        }
                    }

                    Zeitfeld {
                        id: neueZeit

                        implicitHeight: 30
                        schriftGroesse: Theme.groesseLabel
                        platzhalter: "HH:MM"
                        onGesetzt: zeit => {
                            root._uhrzeitHinzu(zeit);
                            neueZeit.zeit = "";
                            neueZeit.leeren();
                        }
                    }

                    Text {
                        height: 30
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 6
                        text: root._uhrzeiten().length === 0 ? "Uhrzeit eintragen, Enter übernimmt" : "Uhr"
                        color: Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseLabel
                    }
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Endet"
            hinweis: root.istAngepasst("ende") ? "angepasst" : ""
            hinweisBetont: true
            akzent: root.akzent

            Row {
                spacing: 12

                Segmente {
                    optionen: [
                        {
                            wert: "manuell",
                            text: "Von Hand"
                        },
                        {
                            wert: "timer",
                            text: "Nach einer Zeit"
                        },
                        {
                            wert: "ausloeser-endet",
                            text: "Wenn der Auslöser endet"
                        }
                    ]
                    wert: root.werte.ende?.art ?? "manuell"
                    onGewaehlt: wert => root.setzen("ende", wert === "timer" ? {
                            art: "timer",
                            minuten: root.werte.ende?.minuten ?? 50
                        } : {
                            art: wert
                        })
                }

                Stufenwahl {
                    visible: root.werte.ende?.art === "timer"
                    wert: root.werte.ende?.minuten ?? 50
                    min: 5
                    max: 480
                    schritt: 5
                    einheit: "Min."
                    onGeaendert: wert => root.setzen("ende", {
                            art: "timer",
                            minuten: wert
                        })
                }
            }
        }

        // Leitplanken: sichtbar, nicht änderbar
        Rectangle {
            width: parent.width
            height: leitSpalte.implicitHeight + 28
            radius: Theme.radiusFeld
            color: Qt.alpha(Theme.flaeche2, 0.55)

            Column {
                id: leitSpalte

                x: 16
                y: 14
                width: parent.width - 32
                spacing: 8

                Row {
                    spacing: 12

                    Symbol {
                        name: "schloss"
                        groesse: 16
                        farbe: Theme.gedaempft
                    }

                    Text {
                        text: "Leitplanken – gelten in jedem Zustand und lassen sich nicht ändern"
                        color: Theme.text
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                        font.weight: Font.DemiBold
                    }
                }

                Repeater {
                    model: [
                        ["Mitteilungsinhalte bei Bildschirmfreigabe", "immer verborgen"],
                        ["Sperrbildschirm", "zeigt nie Inhalte"],
                        ["Automatische Sperre", "immer aktiv, nach " + Dienste.Leitplanken.sperreMinuten(Dienste.Einstellungen.sperreNachMinuten) + " Min."]
                    ]

                    Item {
                        required property var modelData

                        width: leitSpalte.width
                        height: 24

                        Text {
                            x: 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData[0]
                            color: Theme.text
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseText
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData[1]
                            color: Theme.gedaempft
                            font.family: Theme.schriftMono
                            font.pixelSize: Theme.groesseKlein
                        }
                    }
                }
            }
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: root.modusId !== "" ? "~/.config/zenos/modi/" + root.modusId + ".json (Anpassung) · lokal, nicht im Repo" : "~/.config/zenos/zustaende/" + root.zustandId + ".json · lokal, nicht im Repo"
            loeschenText: root.modusId === "" ? "Zustand löschen" : ""
            rueckfrage: "Zustand «" + root.anzeigename + "» löschen? Er verschwindet aus allen Modi."
            akzent: root.akzent
            onLoeschen: {
                const id = root.zustandId;
                root._vorlageDirty = false;
                root._anpassungDirty = false;
                speicherTimer.stop();
                Dienste.Zustaende.loeschen(id);
                Dienste.Oberflaeche.einstellungenSeite = "zustand";
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
                root.setzen("name", nameFeld.text);
        }
    }
}
