pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste
import qs.komponenten
import "rechner.mjs" as Rechner
import "suche.mjs" as Suche

// Befehlsfeld (Super+Leertaste) nach Entwurf 2: Apps, Web-Apps, Aktionen, Modus und Zustand,
// Rechnen, Dateien und Werkzeuge. Eingaben gehen nie an eine Shell; Prozesse starten mit
// Argumentlisten (Aktionen, Dateisuche, wl-copy).
Scope {
    id: root

    readonly property bool offen: Oberflaeche.befehlsfeldOffen
    readonly property string anfrage: eingabe.text.trim()

    // Beim Ausblenden bleibt der Inhalt stehen (nichts springt), danach ist die Liste leer
    readonly property bool _sichtbar: offen || fenster.visible
    // Flache Liste der Einträge; jeder kennt seinen Abschnitt
    readonly property var eintraege: _sichtbar ? _erstellen(anfrage) : []
    property int auswahl: 0
    // Tab: Auswahl liegt bei den Werkzeugen statt in der Liste
    property bool werkzeugModus: false
    property int werkzeugAuswahl: 0
    // Schlüssel eines Eintrags, der auf die Bestätigung wartet (Ausschalten …)
    property string bestaetigen: ""

    readonly property string abschnittRechnen: "Rechnen"
    readonly property string abschnittApps: "Apps und Aktionen"
    readonly property string abschnittModus: "Modus und Zustand"
    readonly property string abschnittDateien: "Dateien"

    // Werkzeuge aus «Danach» (Messen, Clip, Text aus Bild, QR, Zwischenablage) kommen später dazu
    readonly property var werkzeuge: [
        {
            id: "pipette",
            titel: "Pipette",
            symbol: "pipette",
            woerter: "pipette farbe farbwert farbpipette color picker hex"
        },
        {
            id: "bildschirmfoto",
            titel: "Screenshot",
            symbol: "bildschirmfoto",
            woerter: "screenshot bildschirmfoto foto bildschirm bereich aufnehmen"
        }
    ]

    readonly property var aktionen: [
        {
            id: "einstellungen",
            titel: "Einstellungen",
            symbol: "zahnrad",
            woerter: "einstellungen settings optionen konfiguration"
        },
        {
            id: "erscheinung",
            titel: Theme.dunkel ? "Hell" : "Dunkel",
            symbol: Theme.dunkel ? "sonne" : "mond",
            woerter: "erscheinungsbild hell dunkel thema theme light dark"
        },
        {
            id: "sperren",
            titel: "Sperren",
            symbol: "schloss",
            woerter: "sperren bildschirm lock"
        },
        {
            id: "abmelden",
            titel: "Abmelden",
            frage: "Wirklich abmelden?",
            symbol: "abmelden",
            woerter: "abmelden logout sitzung",
            gefahr: true
        },
        {
            id: "neustarten",
            titel: "Neu starten",
            frage: "Wirklich neu starten?",
            symbol: "neustart",
            woerter: "neustart neustarten reboot",
            gefahr: true
        },
        {
            id: "ausschalten",
            titel: "Ausschalten",
            frage: "Wirklich ausschalten?",
            symbol: "ausschalten",
            woerter: "ausschalten herunterfahren shutdown poweroff",
            gefahr: true
        },
        {
            id: "apps",
            titel: "Apps installieren",
            symbol: "plus",
            woerter: "apps installieren programme chrome vscode code 1password"
        }
    ]

    // Suchindex der Apps (neu, wenn sich die Desktop-Dateien ändern)
    readonly property var _apps: {
        const werte = DesktopEntries.applications.values;
        const apps = [];
        for (let i = 0; i < werte.length; i++) {
            const e = werte[i];
            // Quickshell selbst gehört nicht ins Befehlsfeld, Einträge ohne Befehl auch nicht
            if (!e || !e.id || e.id.startsWith("org.quickshell") || !e.command || e.command.length === 0)
                continue;
            const name = e.name || e.id;
            const befehl = String(e.command[0]);
            const webApp = e.id.startsWith("zenos-webapp-");
            apps.push({
                eintrag: e,
                id: e.id,
                name: name,
                webApp: webApp,
                icon: e.icon ? Quickshell.iconPath(e.icon, true) : "",
                felder: [
                    {
                        text: Suche.normalisieren(name),
                        gewicht: 1
                    },
                    {
                        text: Suche.normalisieren(e.genericName),
                        gewicht: 0.8
                    },
                    {
                        text: Suche.normalisieren(Array.from(e.keywords ?? []).join(" ")),
                        gewicht: 0.7
                    },
                    {
                        text: Suche.normalisieren(Suche.programmName(befehl)),
                        gewicht: 0.7
                    },
                    {
                        text: webApp ? "web-app webapp" : "",
                        gewicht: 0.6
                    }
                ]
            });
        }
        return apps;
    }

    function oeffnen(werkzeugeZuerst: bool): void {
        if (!offen)
            Oberflaeche.befehlsfeldOffen = true;
        werkzeugModus = werkzeugeZuerst;
    }

    function schliessen(): void {
        Oberflaeche.befehlsfeldOffen = false;
    }

    function ausfuehren(index: int): void {
        if (werkzeugModus) {
            werkzeugStarten(werkzeuge[werkzeugAuswahl].id);
            return;
        }
        const e = eintraege[index];
        if (!e)
            return;
        if (e.gefahr === true && bestaetigen !== e.schluessel) {
            bestaetigen = e.schluessel;
            return;
        }
        switch (e.art) {
        case "app":
            nutzung.merken(e.appId);
            schliessen();
            Aktionen.appStarten(e.desktop);
            break;
        case "aktion":
            schliessen();
            _aktionAusfuehren(e.id);
            break;
        case "werkzeug":
            werkzeugStarten(e.id);
            break;
        case "modus":
            schliessen();
            Modi.wechseln(e.id);
            break;
        case "zustand":
            schliessen();
            Zustaende.starten(e.id, "manuell");
            break;
        case "zustand-beenden":
            schliessen();
            Zustaende.beenden();
            break;
        case "rechnen":
            // «--»: ein negatives Ergebnis ist keine Option für wl-copy
            Quickshell.execDetached(["wl-copy", "--", e.wert]);
            schliessen();
            Oberflaeche.hinweis(e.wert + " kopiert");
            break;
        case "datei":
            schliessen();
            Aktionen.dateiOeffnen(e.pfad);
            break;
        }
    }

    // Werkzeuge starten erst, wenn das Befehlsfeld nicht mehr zu sehen ist
    // (sonst wäre es auf dem Bildschirmfoto bzw. unter der Pipette)
    property string _werkzeugDanach: ""

    function werkzeugStarten(id: string): void {
        _werkzeugDanach = id;
        if (fenster.visible)
            schliessen();
        else
            nachDemSchliessen.restart();
    }

    function _aktionAusfuehren(id: string): void {
        switch (id) {
        case "einstellungen":
            Aktionen.einstellungen("");
            break;
        case "erscheinung":
            Erscheinung.umschalten();
            break;
        case "sperren":
            Aktionen.sperren();
            break;
        case "abmelden":
            Aktionen.abmelden();
            break;
        case "neustarten":
            Aktionen.neustarten();
            break;
        case "ausschalten":
            Aktionen.ausschalten();
            break;
        case "apps":
            Aktionen.einstellungen("apps");
            break;
        }
    }

    function _buchstabe(text: string): string {
        return text.length > 0 ? text.charAt(0).toUpperCase() : "";
    }

    function _appEintrag(app: var): var {
        return {
            schluessel: "app:" + app.id,
            abschnitt: abschnittApps,
            art: "app",
            appId: app.id,
            desktop: app.eintrag,
            titel: app.name,
            hinweis: app.webApp ? "Web-App" : "App",
            icon: app.icon,
            buchstabe: _buchstabe(app.name)
        };
    }

    function _aktionEintrag(a: var): var {
        return {
            schluessel: "aktion:" + a.id,
            abschnitt: abschnittApps,
            art: "aktion",
            id: a.id,
            titel: a.titel,
            frage: a.frage ?? "",
            gefahr: a.gefahr === true,
            hinweis: "Aktion",
            symbol: a.symbol
        };
    }

    function _werkzeugEintrag(w: var): var {
        return {
            schluessel: "werkzeug:" + w.id,
            abschnitt: abschnittApps,
            art: "werkzeug",
            id: w.id,
            titel: w.titel,
            hinweis: "Werkzeug",
            symbol: w.symbol
        };
    }

    // Modi zum Wechseln, startbare Zustände und der aktive Zustand. q leer: alle, sonst gefiltert.
    function _modusUndZustand(q: string): var {
        const treffer = [];
        const bewerten = (name, woerter) => q.length === 0 ? 1 : Suche.bewerten([
                {
                    text: Suche.normalisieren(name),
                    gewicht: 1
                },
                {
                    text: woerter,
                    gewicht: 0.7
                }
            ], q);
        const nameVon = z => typeof z?.name === "string" && z.name.trim().length > 0 ? z.name : z.id;

        // Der aktive Zustand lässt sich immer beenden, auch wenn er nicht von Hand startbar ist (Sitzung)
        const aktivId = Zustaende.aktivId;
        if (aktivId.length > 0) {
            const name = nameVon(Zustaende.aktiv ?? {
                id: aktivId
            });
            const p = bewerten(name, "zustand beenden");
            if (p > 0)
                treffer.push({
                    punkte: p + 3,
                    name: name,
                    e: {
                        schluessel: "zustand-ende",
                        abschnitt: abschnittModus,
                        art: "zustand-beenden",
                        titel: name + " beenden",
                        hinweis: Zustaende.restMinuten >= 0 ? "noch " + Zustaende.restMinuten + " Min." : (Freigabe.aktiv && Zustaende.ausloeser === "bildschirmfreigabe" ? "geteilt" : "aktiv"),
                        symbol: "kreis-ziel"
                    }
                });
        }

        // Angeboten im aktiven Modus und mit Auslöser «manuell»
        const startbar = Array.isArray(Zustaende.startbar) ? Zustaende.startbar : [];
        for (const z of startbar) {
            if (!z || typeof z.id !== "string" || z.id.length === 0 || z.id === aktivId)
                continue;
            const name = nameVon(z);
            const p = bewerten(name, "zustand starten");
            if (p <= 0)
                continue;
            // Dauer aus dem wirksamen Zustand (mit der Anpassung des aktiven Modus)
            const ende = Zustaende.wirksamFuer(z.id)?.ende;
            const minuten = ende?.art === "timer" && Number.isInteger(ende?.minuten) && ende.minuten > 0 ? ende.minuten : 0;
            treffer.push({
                punkte: p + 1,
                name: name,
                e: {
                    schluessel: "zustand:" + z.id,
                    abschnitt: abschnittModus,
                    art: "zustand",
                    id: z.id,
                    titel: name + " starten",
                    hinweis: minuten > 0 ? minuten + " Min." : "Zustand",
                    symbol: "kreis-ziel"
                }
            });
        }

        const modi = Array.isArray(Modi.liste) ? Modi.liste : [];
        for (const m of modi) {
            if (!m || typeof m.id !== "string" || m.id.length === 0 || m.id === Modi.aktivId)
                continue;
            const name = nameVon(m);
            const p = bewerten(name, "modus wechseln");
            if (p <= 0)
                continue;
            treffer.push({
                punkte: p + 2,
                name: name,
                e: {
                    schluessel: "modus:" + m.id,
                    abschnitt: abschnittModus,
                    art: "modus",
                    id: m.id,
                    titel: "Wechseln zu " + name,
                    hinweis: "Modus",
                    punkt: Theme.akzentFarbe(typeof m.akzent === "string" ? m.akzent : "")
                }
            });
        }
        // Ohne Eingabe: aktiver Zustand, Modi, Zustände, jeweils in der Reihenfolge der Dienste
        // (sort ist in Qt nicht stabil, deshalb mit Position als Rückfall)
        const sortiert = q.length === 0 ? treffer.map((t, i) => ({
                    t: t,
                    i: i
                })).sort((a, b) => b.t.punkte - a.t.punkte || a.i - b.i).map(x => x.t) : Suche.sortieren(treffer);
        return sortiert.slice(0, 6).map(t => t.e);
    }

    function _dateien(q: string): var {
        if (q.length < 2)
            return [];
        // Bei Bildschirmfreigabe keine Dateinamen zeigen (die Sitzung blendet Privates aus)
        if (Freigabe.aktiv)
            return [
                {
                    schluessel: "datei-freigabe",
                    abschnitt: abschnittDateien,
                    art: "info",
                    titel: "Während der Bildschirmfreigabe aus",
                    hinweis: "Sitzung",
                    symbol: "monitor"
                }
            ];
        let treffer = dateisuche.treffer;
        // Bis die neue Suche fertig ist, bleiben passende Treffer der vorigen stehen
        if (dateisuche.trefferAnfrage !== q)
            treffer = treffer.filter(t => Suche.dateiPasst(t.name, q));
        return treffer.map(t => ({
                    schluessel: "datei:" + t.pfad,
                    abschnitt: abschnittDateien,
                    art: "datei",
                    pfad: t.pfad,
                    titel: Suche.einzeilig(t.name),
                    hinweis: Suche.einzeilig(Suche.pfadAnzeige(t.pfad, Pfade.home)),
                    symbol: t.ordner ? "ordner" : "datei"
                }));
    }

    function _erstellen(q: string): var {
        const ergebnis = [];
        const daten = nutzung.daten;

        // Leeres Feld: zuletzt und oft genutzte Apps, Modus und Zustand
        if (q.length === 0) {
            let anzahl = 0;
            for (const id of Suche.nutzungRangliste(daten)) {
                const app = _apps.find(a => a.id === id);
                if (!app)
                    continue;
                ergebnis.push(_appEintrag(app));
                if (++anzahl >= 5)
                    break;
            }
            if (anzahl === 0) {
                for (const a of aktionen) {
                    if (a.id === "einstellungen" || a.id === "erscheinung")
                        ergebnis.push(_aktionEintrag(a));
                }
            }
            return ergebnis.concat(_modusUndZustand(""));
        }

        const rechnung = rechnungErgebnis;
        if (rechnung !== null) {
            ergebnis.push({
                schluessel: "rechnen",
                abschnitt: abschnittRechnen,
                art: "rechnen",
                titel: "= " + rechnung.anzeige,
                wert: rechnung.anzeige,
                hinweis: "kopieren",
                symbol: "zwischenablage"
            });
        }

        const treffer = [];
        for (const app of _apps) {
            const p = Suche.bewerten(app.felder, q);
            if (p > 0)
                treffer.push({
                    punkte: p + Suche.nutzungBonus(daten, app.id),
                    name: app.name,
                    e: _appEintrag(app)
                });
        }
        for (const a of aktionen) {
            const roh = Suche.bewerten([
                {
                    text: Suche.normalisieren(a.titel),
                    gewicht: 1
                },
                {
                    text: a.woerter,
                    gewicht: 0.9
                }
            ], q);
            // Aktionen mit Folgen nur bei klaren Treffern (Anfang eines Worts)
            const p = roh * (a.gefahr === true ? 0.9 : 0.95);
            if (p > 0 && (a.gefahr !== true || p >= 70))
                treffer.push({
                    punkte: p,
                    name: a.titel,
                    e: _aktionEintrag(a)
                });
        }
        for (const w of werkzeuge) {
            const p = Suche.bewerten([
                {
                    text: Suche.normalisieren(w.titel),
                    gewicht: 1
                },
                {
                    text: w.woerter,
                    gewicht: 0.9
                }
            ], q) * 0.95;
            if (p > 0)
                treffer.push({
                    punkte: p,
                    name: w.titel,
                    e: _werkzeugEintrag(w)
                });
        }
        for (const t of Suche.sortieren(treffer).slice(0, 8))
            ergebnis.push(t.e);

        return ergebnis.concat(_modusUndZustand(q), _dateien(q));
    }

    readonly property var rechnungErgebnis: _sichtbar ? Rechner.berechnen(anfrage) : null

    // Auswahl nach einer Änderung der Liste: neue Eingabe → erster Eintrag;
    // nachgeladene Treffer (Dateien) → der gewählte Eintrag bleibt gewählt
    property string _letzteAnfrage: ""
    property string _gewaehlt: ""

    onEintraegeChanged: {
        let neu = 0;
        if (anfrage === _letzteAnfrage && _gewaehlt.length > 0) {
            const i = eintraege.findIndex(e => e.schluessel === _gewaehlt);
            neu = i >= 0 ? i : Math.max(0, Math.min(auswahl, eintraege.length - 1));
        }
        _letzteAnfrage = anfrage;
        auswahl = neu;
        _gewaehlt = eintraege[neu]?.schluessel ?? "";
        if (bestaetigen.length > 0 && !eintraege.some(e => e.schluessel === bestaetigen))
            bestaetigen = "";
        Qt.callLater(_sichtbarMachen);
    }

    onAuswahlChanged: {
        _gewaehlt = eintraege[auswahl]?.schluessel ?? "";
        if (bestaetigen !== _gewaehlt)
            bestaetigen = "";
        Qt.callLater(_sichtbarMachen);
    }

    onWerkzeugModusChanged: bestaetigen = ""

    onOffenChanged: {
        if (!offen)
            return;
        eingabe.text = "";
        auswahl = 0;
        // Neu geöffnet: immer der erste Eintrag, nicht die Auswahl vom letzten Mal
        _gewaehlt = "";
        werkzeugModus = false;
        werkzeugAuswahl = 0;
        bestaetigen = "";
        _werkzeugDanach = "";
        listenAnsicht.contentY = 0;
        eingabe.forceActiveFocus();
    }

    function _schritt(d: int): void {
        const n = eintraege.length;
        if (werkzeugModus) {
            if (d < 0) {
                werkzeugModus = false;
                if (n > 0)
                    auswahl = n - 1;
            }
            return;
        }
        if (n === 0) {
            if (d > 0)
                werkzeugModus = true;
            return;
        }
        // ↓ am Ende der Liste geht weiter zu den Werkzeugen
        if (d === 1 && auswahl === n - 1) {
            werkzeugModus = true;
            return;
        }
        auswahl = Math.max(0, Math.min(n - 1, auswahl + d));
    }

    function _taste(event: KeyEvent): void {
        const strg = (event.modifiers & Qt.ControlModifier) !== 0;
        let erledigt = true;
        switch (event.key) {
        case Qt.Key_Escape:
            schliessen();
            break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            werkzeugModus = !werkzeugModus;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            ausfuehren(auswahl);
            break;
        case Qt.Key_Down:
            _schritt(1);
            break;
        case Qt.Key_Up:
            _schritt(-1);
            break;
        case Qt.Key_PageDown:
            _schritt(werkzeugModus ? 0 : Math.max(1, Math.min(5, eintraege.length - 1 - auswahl)));
            break;
        case Qt.Key_PageUp:
            _schritt(-5);
            break;
        case Qt.Key_N:
        case Qt.Key_P:
            erledigt = strg;
            if (strg)
                _schritt(event.key === Qt.Key_N ? 1 : -1);
            break;
        case Qt.Key_Left:
        case Qt.Key_Right:
            erledigt = werkzeugModus;
            if (werkzeugModus)
                werkzeugAuswahl = Math.max(0, Math.min(werkzeuge.length - 1, werkzeugAuswahl + (event.key === Qt.Key_Right ? 1 : -1)));
            break;
        default:
            erledigt = false;
        }
        if (erledigt) {
            event.accepted = true;
            return;
        }
        // Tippen führt aus den Werkzeugen zurück in die Suche
        if (werkzeugModus && event.text.length > 0)
            werkzeugModus = false;
    }

    function _sichtbarMachen(): void {
        const item = wiederholer.itemAt(auswahl);
        if (!item)
            return;
        const hoehe = listenZiel;
        if (item.y < listenAnsicht.contentY || auswahl === 0)
            listenAnsicht.contentY = auswahl === 0 ? 0 : item.y;
        else if (item.y + item.height > listenAnsicht.contentY + hoehe)
            listenAnsicht.contentY = item.y + item.height - hoehe;
    }

    // Höhe der Liste ohne Animation (für das Scrollen)
    readonly property real listenZiel: Math.max(0, Math.min(spalte.implicitHeight, _maxPanel - _festeHoehe))
    readonly property real _festeHoehe: 2 + zeile.height + werkzeugBlock.height + fuss.height
    readonly property real _maxPanel: Math.max(240, fenster.height - Theme.befehlsfeldOben - Theme.a7)

    Dateisuche {
        id: dateisuche

        home: Pfade.home
        anfrage: root._sichtbar && root.rechnungErgebnis === null && !Freigabe.aktiv ? root.anfrage : ""
    }

    Nutzung {
        id: nutzung

        pfad: Pfade.home.length > 0 ? Pfade.home + "/.local/share/zenos/befehlsfeld.json" : ""
    }

    Timer {
        id: nachDemSchliessen

        interval: 100
        onTriggered: {
            const id = root._werkzeugDanach;
            root._werkzeugDanach = "";
            if (id === "bildschirmfoto")
                Aktionen.bildschirmfoto([]);
            else if (id === "pipette")
                Aktionen.pipette();
        }
    }

    Connections {
        target: Oberflaeche

        function onSperrenAngefordert(): void {
            root.schliessen();
        }
    }

    IpcHandler {
        target: "befehlsfeld"

        function umschalten(): void {
            if (root.offen)
                root.schliessen();
            else
                root.oeffnen(false);
        }

        function oeffnen(): void {
            root.oeffnen(false);
        }

        function schliessen(): void {
            root.schliessen();
        }

        function werkzeuge(): void {
            root.oeffnen(true);
        }
    }

    PanelWindow {
        id: fenster

        // Ohne feste Ausgabe wählt labwc den Bildschirm (den mit dem Zeiger)
        visible: root.offen || inhalt.opacity > 0
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.durchsichtig
        // Beim Ausblenden fängt das Fenster keine Klicks mehr
        mask: root.offen ? null : leer

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.offen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "zenos-befehlsfeld"

        onVisibleChanged: {
            if (visible)
                eingabe.forceActiveFocus();
            else if (root._werkzeugDanach.length > 0)
                nachDemSchliessen.restart();
        }

        Region {
            id: leer
        }

        Item {
            id: inhalt

            anchors.fill: parent
            opacity: root.offen ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.dauerKurz
                    easing.type: Theme.kurve
                }
            }

            // Abgedunkelter Hintergrund (kein Weichzeichnen); ein Klick darauf schliesst
            Rectangle {
                anchors.fill: parent
                color: Theme.abdunkeln

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: root.schliessen()
                }
            }

            // Schatten ohne Weichzeichnen der Umgebung; braucht die GPU (fehlt im Software-Backend)
            RectangularShadow {
                visible: GraphicsInfo.api !== GraphicsInfo.Software
                anchors.fill: panel
                offset: Qt.vector2d(0, 30)
                blur: 80
                radius: panel.radius
                color: Theme.schatten
            }

            Rectangle {
                id: panel

                x: Math.round((parent.width - width) / 2)
                y: Theme.befehlsfeldOben
                width: Math.min(Theme.befehlsfeldBreite, parent.width - 2 * Theme.a4)
                height: root._festeHoehe + root.listenZiel
                radius: Theme.radiusBefehlsfeld
                color: Theme.flaeche
                border.width: 1
                border.color: Theme.linie2

                Behavior on height {
                    enabled: root.offen && inhalt.opacity === 1

                    NumberAnimation {
                        duration: Theme.dauerKurz
                        easing.type: Theme.kurve
                    }
                }

                // Klicks auf das Feld selbst schliessen nicht
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: 1

                    // Eingabezeile (62 px)
                    Item {
                        id: zeile

                        width: parent.width
                        height: 62

                        Symbol {
                            id: lupe

                            x: 20
                            anchors.verticalCenter: parent.verticalCenter
                            name: "suche"
                            groesse: 18
                            farbe: Theme.gedaempft
                        }

                        Text {
                            anchors.fill: eingabe
                            verticalAlignment: Text.AlignVCenter
                            visible: eingabe.text.length === 0 && eingabe.preeditText.length === 0
                            text: "Suchen, rechnen, starten"
                            color: Theme.gedaempft
                            font: eingabe.font
                            elide: Text.ElideRight
                        }

                        TextInput {
                            id: eingabe

                            anchors.left: lupe.right
                            anchors.leftMargin: 12
                            anchors.right: esc.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            height: 40
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            focus: true
                            color: Theme.text
                            selectionColor: Qt.alpha(Theme.akzent, 0.35)
                            selectedTextColor: Theme.text
                            font.family: Theme.schriftText
                            font.pixelSize: 20
                            maximumLength: 200
                            selectByMouse: true
                            inputMethodHints: Qt.ImhNoPredictiveText
                            Accessible.name: "Befehlsfeld"

                            Keys.onPressed: event => root._taste(event)
                        }

                        Kbd {
                            id: esc

                            anchors.right: parent.right
                            anchors.rightMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Esc"
                            leise: true
                        }

                        Trenner {
                            anchors.bottom: parent.bottom
                            width: parent.width
                        }
                    }

                    // Einträge, nach Abschnitten
                    Flickable {
                        id: listenAnsicht

                        anchors.top: zeile.bottom
                        width: parent.width
                        height: Math.max(0, parent.height - root._festeHoehe + 2)
                        contentHeight: spalte.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        Column {
                            id: spalte

                            width: listenAnsicht.width

                            Repeater {
                                id: wiederholer

                                model: root.eintraege

                                delegate: Item {
                                    id: zeileEintrag

                                    required property var modelData
                                    required property int index

                                    readonly property bool mitTitel: index === 0 || root.eintraege[index - 1]?.abschnitt !== modelData.abschnitt
                                    readonly property real titelHoehe: mitTitel ? (index === 0 ? 10 : 12) + titel.implicitHeight + 4 : 0

                                    width: spalte.width
                                    height: titelHoehe + zeilenInhalt.height

                                    // Zeilen ausserhalb des sichtbaren Bereichs nicht zeichnen
                                    // (die Column braucht die Zeile selbst weiterhin sichtbar)
                                    Item {
                                        anchors.fill: parent
                                        visible: zeileEintrag.y + zeileEintrag.height > listenAnsicht.contentY && zeileEintrag.y < listenAnsicht.contentY + listenAnsicht.height

                                        Abschnittstitel {
                                            id: titel

                                            visible: zeileEintrag.mitTitel
                                            x: 20
                                            y: zeileEintrag.index === 0 ? 10 : 12
                                            width: parent.width - 40
                                            text: zeileEintrag.modelData.abschnitt
                                        }

                                        Eintrag {
                                            id: zeilenInhalt

                                            x: 8
                                            y: zeileEintrag.titelHoehe
                                            width: parent.width - 16
                                            eintrag: zeileEintrag.modelData
                                            gewaehlt: !root.werkzeugModus && root.auswahl === zeileEintrag.index
                                            fragt: root.bestaetigen.length > 0 && root.bestaetigen === zeileEintrag.modelData.schluessel
                                            onGezeigt: {
                                                root.werkzeugModus = false;
                                                root.auswahl = zeileEintrag.index;
                                            }
                                            onAusgefuehrt: {
                                                root.werkzeugModus = false;
                                                root.auswahl = zeileEintrag.index;
                                                root.ausfuehren(zeileEintrag.index);
                                            }
                                        }
                                    }
                                }
                            }

                            // Nichts gefunden (erst, wenn auch die Dateisuche fertig ist)
                            Item {
                                visible: root.anfrage.length > 0 && root.eintraege.length === 0 && !dateisuche.sucht
                                width: spalte.width
                                height: visible ? 52 : 0

                                Text {
                                    x: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: 4
                                    text: "Keine Treffer"
                                    color: Theme.gedaempft
                                    font.family: Theme.schriftText
                                    font.pixelSize: Theme.groesseText
                                }
                            }
                        }
                    }

                    // Werkzeuge (Tab)
                    Item {
                        id: werkzeugBlock

                        anchors.top: listenAnsicht.bottom
                        width: parent.width
                        height: 12 + werkzeugTitel.implicitHeight + 6 + 34 + 16

                        Abschnittstitel {
                            id: werkzeugTitel

                            x: 20
                            y: 12
                            text: "Werkzeuge"
                        }

                        Row {
                            x: 20
                            y: 12 + werkzeugTitel.implicitHeight + 6
                            spacing: 6

                            Repeater {
                                model: root.werkzeuge

                                delegate: Item {
                                    id: werkzeug

                                    required property var modelData
                                    required property int index

                                    implicitWidth: chip.implicitWidth
                                    implicitHeight: 34

                                    Chip {
                                        id: chip

                                        anchors.fill: parent
                                        implicitHeight: 34
                                        text: werkzeug.modelData.titel
                                        symbol: werkzeug.modelData.symbol
                                        variante: "umrandet"
                                        randFarbe: Theme.linie2
                                        textFarbe: Theme.text2
                                        schriftGroesse: Theme.groesseLabel
                                        activeFocusOnTab: false
                                        onClicked: root.werkzeugStarten(werkzeug.modelData.id)
                                    }

                                    Fokusrahmen {
                                        aktiv: root.werkzeugModus && root.werkzeugAuswahl === werkzeug.index
                                        eckenRadius: Theme.radiusChip
                                    }
                                }
                            }
                        }
                    }

                    // Fusszeile mit den Tasten
                    Item {
                        id: fuss

                        anchors.top: werkzeugBlock.bottom
                        width: parent.width
                        height: 12 + Math.ceil(monoMetrik.height) + 12

                        FontMetrics {
                            id: monoMetrik

                            font.family: Theme.schriftMono
                            font.pixelSize: Theme.groesseKlein
                        }

                        Trenner {
                            width: parent.width
                        }

                        Row {
                            x: 20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 20

                            Repeater {
                                model: ["↑↓ wählen", "↵ ausführen", "Tab Werkzeuge", "Esc schliessen"]

                                delegate: Text {
                                    required property string modelData

                                    text: modelData
                                    color: Theme.gedaempft
                                    font.family: Theme.schriftMono
                                    font.pixelSize: Theme.groesseKlein
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
