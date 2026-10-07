pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.theme
import qs.dienste
import qs.komponenten
import "zeit.js" as Zeit
import "wlan.js" as Wlan

// Inhalt der Leiste nach Entwurf 2 (Innenabstand 0 10 px):
// links «wo bin ich» (Zeichen, Modus, Zustand, Raster) und die Ablage, in der Mitte Datum und Uhrzeit,
// rechts Mitteilungen, Hell/Dunkel und System.
Item {
    id: root

    // aktuelle Zeit (SystemClock, Minutentakt)
    property var jetzt: new Date()
    // offenes Menü dieser Leiste: "" | "system" | "raster"
    property string offenesMenue: ""
    // Name des Bildschirms dieser Leiste (Anker für Modus-/Zustandswahl und Zentrale)
    property string bildschirm: ""
    // WlanQuelle aus Leiste.qml (null ohne NetworkManager): Signalstufe des verbundenen WLANs
    property var wlan: null

    // x in Fensterkoordinaten: Raster-Menü beginnt an der linken Kante des Knopfs,
    // das System-Menü endet an der rechten Kante des System-Knopfs
    signal menueGewuenscht(string name, real x)

    function menueX(name: string): real {
        if (name === "raster")
            return rasterChip.mapToItem(null, 0, 0).x;
        return systemKnopf.mapToItem(null, systemKnopf.width, 0).x;
    }

    // Modus- bzw. Zustandswahl unter dem Chip (modi/Umschalter.qml, Anker Oberflaeche.wahlAnker).
    // Ein zweiter Klick schliesst. Ist die Wahl mittig (Super+M/Z, ohne Anker) oder auf einem anderen
    // Bildschirm offen, wandert sie unter diesen Chip.
    function _toggleChoice(kind: string, chip: Item): void {
        const isOpen = kind === "modus" ? Oberflaeche.modusWahlOffen : Oberflaeche.zustandWahlOffen;
        const anchor = Oberflaeche.wahlAnker;
        const close = () => {
            if (kind === "modus")
                Oberflaeche.modusWahlOffen = false;
            else
                Oberflaeche.zustandWahlOffen = false;
        };
        if (isOpen) {
            close();
            if (anchor && anchor.bildschirm === bildschirm)
                return;
        }
        Oberflaeche.wahlAnker = {
            bildschirm: bildschirm,
            x: chip.mapToItem(null, 0, 0).x
        };
        // Wahl und Zentrale beanspruchen beide die Tastatur: nur eine von beiden offen
        Oberflaeche.zentraleOffen = false;
        if (kind === "modus")
            Oberflaeche.modusWahlOffen = true;
        else
            Oberflaeche.zustandWahlOffen = true;
    }

    // Zentrale auf diesem Bildschirm offen (Oberflaeche.zentraleBildschirm; leer = erster Bildschirm)
    readonly property bool _centerHere: {
        if (!Oberflaeche.zentraleOffen)
            return false;
        const name = Oberflaeche.zentraleBildschirm !== "" ? Oberflaeche.zentraleBildschirm : (Quickshell.screens[0]?.name ?? "");
        return name === bildschirm;
    }

    function _toggleCenter(): void {
        if (_centerHere) {
            Oberflaeche.zentraleOffen = false;
            return;
        }
        Oberflaeche.zentraleBildschirm = bildschirm;
        Oberflaeche.modusWahlOffen = false;
        Oberflaeche.zustandWahlOffen = false;
        Oberflaeche.zentraleOffen = true;
    }

    // Leiste laut wirksamem Zustand: "normal" | "reduziert" (ohne Raster, Ablage und Hell/Dunkel) |
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

    // WLAN ohne Standardroute («ohne Internet») bleibt beim WLAN-Symbol, dann gedämpft
    readonly property string _networkSymbol: System.netzArt === "kabel" ? "kabel" : System.netzArt === "wlan" || System.wlanVerbunden ? "wlan" : "wlan-aus"
    // Signalstufe des WLAN-Symbols (1–3; 0 = «wlan-aus»): von NetworkManager, sonst aus /proc/net/wireless
    readonly property int _wlanStufe: {
        if (_networkSymbol === "wlan-aus")
            return 0;
        if (wlan && wlan.bereit && wlan.geraetDa && !wlan.wlanAn)
            return 0;
        if (wlan && wlan.bereit && wlan.verbundenStufe > 0)
            return wlan.verbundenStufe;
        return Wlan.stufe(System.wlanSignal);
    }
    readonly property string _systemDescription: {
        const parts = [];
        parts.push(System.netzArt === "wlan" ? "WLAN verbunden, Signal " + _wlanStufe + " von 3" : System.netzArt === "kabel" ? "Kabel verbunden" : System.wlanVerbunden ? "WLAN ohne Internet" : "nicht verbunden");
        parts.push(!System.tonVerfuegbar ? "kein Tonausgang" : System.stumm ? "Ton stumm" : "Lautstärke " + Math.round(System.lautstaerke * 100) + " %");
        if (System.einsPasswortInstalliert)
            parts.push(System.einsPasswortLaeuft ? "1Password läuft" : "1Password nicht gestartet");
        if (System.temperatur >= 0)
            parts.push(System.temperatur + " Grad");
        if (Geraet.akkuVorhanden)
            parts.push(!Geraet.akkuBekannt ? "Akku unbekannt" : "Akku " + Geraet.akkuProzent + " Prozent" + (Geraet.akkuLaedt ? ", lädt" : ""));
        if (Basis.neustartHinweis)
            parts.push("Neustart nötig");
        return "System: " + parts.join(", ");
    }
    // Akku: ohne Messwert gedämpft, bei höchstens 10 % und Entladen in der Warnfarbe (ruhig, ohne Blinken)
    readonly property color _akkuFarbe: !Geraet.akkuBekannt ? Theme.gedaempft : Geraet.akkuNiedrig ? Theme.warnung : Theme.text

    // --- Platz links: lange Namen kürzen, damit nichts in die Uhrzeit ragt ---

    // Breite vom linken Rand bis kurz vor die Uhrzeit
    readonly property real _leftBudget: (width - uhrzeit.implicitWidth) / 2 - Theme.a4 - 10
    // alles ausser den beiden Namen: Zeichen, Innenabstände, Punkt, Pfeil, Zusatz, Raster, Ablage, Abstände
    readonly property real _leftFixed: (stufe !== "aus" ? 30 + 6 + 10 + 7 + 8 + 8 + 12 + 8 : 0) + (zustandChip.visible ? 6 + 10 + (_sharing ? 7 + 8 : 0) + (_stateExtra !== "" ? 8 + extraMetrics.advanceWidth : 0) + 10 : 0) + (rasterChip.visible ? 6 + rasterChip.implicitWidth : 0) + (ablageKnopf.visible ? 6 + ablageKnopf.width : 0)
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

        // Zeichen (18 px, Pixel-Variante, unterer Stein im Modus-Akzent) mit 6 px Luft links und rechts.
        // Ein Klick öffnet das Befehlsfeld mit allen installierten Apps, ein zweiter schliesst es.
        LeistenKnopf {
            id: zeichenKnopf

            visible: root.stufe !== "aus"
            width: 30
            aktiv: Oberflaeche.befehlsfeldOffen && Oberflaeche.befehlsfeldAnsicht === "apps"
            beschreibung: "Apps zeigen"
            onClicked: Oberflaeche.befehlsfeldApps(true)

            ZenZeichen {
                groesse: 18
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
            onClicked: root._toggleChoice("modus", modusChip)
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
            onClicked: root._toggleChoice("zustand", zustandChip)
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

        // Ablage (~/Ablage) im Dateimanager öffnen; sichtbar wie das Raster
        LeistenKnopf {
            id: ablageKnopf

            visible: root.stufe === "normal"
            width: 32
            beschreibung: "Ablage öffnen"
            onClicked: Aktionen.ablageOeffnen()

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                name: "ordner"
                groesse: 15
                farbe: Theme.text
            }
        }
    }

    // Wo das Zeichen liegt (Fensterkoordinaten der Leiste = Bildschirmkoordinaten). Auf jedem Bildschirm
    // gleich; das Befehlsfeld legt darüber eine Klickfläche und gleitet von dort auf.
    Binding {
        target: Oberflaeche
        property: "zeichenBereich"
        value: zeichenKnopf.visible ? Qt.rect(links.x + zeichenKnopf.x, links.y + zeichenKnopf.y, zeichenKnopf.width, zeichenKnopf.height) : Qt.rect(0, 0, 0, 0)
        restoreMode: Binding.RestoreNone
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
            aktiv: root._centerHere
            beschreibung: root._noticeDescription
            onClicked: root._toggleCenter()

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
                visible: root._networkSymbol === "kabel"
                name: "kabel"
                groesse: 14
                farbe: System.netzVerbunden ? Theme.text : Theme.gedaempft
            }

            // WLAN mit Signalstufe (fehlende Bögen blass), ohne Verbindung «wlan-aus»
            WlanSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: root._networkSymbol !== "kabel"
                stufe: root._wlanStufe
                groesse: 14
                farbe: System.netzVerbunden ? Theme.text : Theme.gedaempft
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

            // Neustart nötig (/run/reboot-required nach Updates): still und gedämpft, ohne Farbe und ohne Mitteilung.
            // Nur bei voller Leiste, nie bei Bildschirmfreigabe (Leitplanke in dienste/basis.js)
            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: Basis.neustartHinweis
                name: "neustart"
                groesse: 14
                farbe: Theme.gedaempft
            }

            // Akku (nur mit Akku, z. B. Argon ONE UP): Füllstand oder Ladeblitz, Prozent in Mono. Ruhig: bei
            // höchstens 10 % und Entladen nur in der Warnfarbe, ohne Blinken; ohne Messwert gedämpft.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                visible: Geraet.akkuVorhanden
                spacing: 3

                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    name: Geraet.akkuSymbol
                    groesse: 15
                    farbe: root._akkuFarbe
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: Geraet.akkuText
                    color: root._akkuFarbe
                    font.family: Theme.schriftMono
                    font.pixelSize: Theme.groesseKlein
                }
            }
        }
    }
}
