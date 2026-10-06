pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste
import qs.komponenten
import "../appleiste/fenster.mjs" as Fenster
import "liste.mjs" as Liste

// Fensterübersicht (Super+Tab, Befehlsfeld «Fensterübersicht», IPC): alle offenen App-Fenster als Karten ohne
// Vorschaubilder (labwc 0.9.3 gibt einzelne Fenster nicht heraus), mit App-Symbol, App-Name und Titel. Bleibt offen,
// ohne dass eine Taste gehalten wird. Reihenfolge fest wie in der App-Leiste (nichts springt). Die Startauswahl ist das
// vorige Fenster: Super+Tab und ↵ führt zurück wie Alt+Tab. Tippen filtert (Bewertung wie im Befehlsfeld), Pfeile,
// Tab, Pos1 und Ende wählen, ↵ wechselt, Esc schliesst. Zeigen wählt (nur echte Bewegung), Klick wechselt, Klick
// daneben schliesst. Wechselt das aktive Fenster doch einmal von aussen, geht sie zu.
// Hintergrund «zudecken» (grund fast deckend, kein Weichzeichnen) auf der Ebene Overlay, also auch über Vollbild.
// Tastatur und Kacheln nur auf dem Bildschirm des aktiven Fensters (sonst dem ersten); die anderen sind nur zugedeckt,
// ein Klick dort schliesst. Offen oder zu: Oberflaeche.uebersichtOffen (gesperrt während Sperre und Einrichtung, eine
// Fläche zur Zeit). Während einer Freigabe sind die Titel verborgen und werden nicht durchsucht.
// Doku: docs/design.md. IPC «uebersicht»: umschalten, oeffnen, schliessen, status (offen/zu), fenster.
Scope {
    id: root

    readonly property bool offen: Oberflaeche.uebersichtOffen

    // Masse der Kacheln und der Filterzeile
    readonly property int kachelBreite: 216
    readonly property int kachelHoehe: 164
    readonly property int luecke: Theme.a4
    readonly property int pilleBreite: 360
    readonly property int pilleHoehe: 40
    // Rand um die Kacheln im Raster: Der Fokusrahmen (3 px ausserhalb) bleibt auch beim Scrollen ganz sichtbar
    readonly property int rasterRand: Theme.a1

    // Deckkraft der ganzen Fläche: blendet in Theme.dauerKurz ein und aus
    property real deckkraft: offen ? 1 : 0
    readonly property bool sichtbar: offen || deckkraft > 0

    Behavior on deckkraft {
        NumberAnimation {
            duration: Theme.dauerKurz
            easing.type: Theme.kurve
        }
    }

    // --- Fenster wie in der App-Leiste: Gruppen in fester Reihenfolge, Verlauf der aktiven Fenster ------------
    // Schon beim Start gebunden (Laden im Hintergrund): Die Reihenfolge des ersten Öffnens und der Verlauf gelten ab
    // Sitzungsbeginn, wie in der App-Leiste.
    readonly property var fensterListe: ToplevelManager.toplevels.values
    readonly property var aktivesFenster: ToplevelManager.activeToplevel
    readonly property string appKennungen: fensterListe.map(t => t?.appId ?? "").join("\n")
    property var _reihenfolge: []
    property var _verlauf: []
    property var _gruppenRoh: []

    // Beim Öffnen festgehalten: aktives Fenster (Akzentpunkt) und Bildschirm mit Tastatur und Kacheln
    property var aktivBeimOeffnen: null
    property string hauptBildschirm: ""
    readonly property var hauptScreen: Quickshell.screens.find(s => s?.name === hauptBildschirm) ?? Quickshell.screens[0] ?? null
    readonly property bool mehrereBildschirme: Quickshell.screens.length > 1

    // true vom Öffnen bis zum Ende des Ausblendens: so lange gibt es Einträge und Kacheln, danach nichts
    property bool _aufgebaut: false
    // true, solange die Kacheln einblenden: Kacheln, die jetzt entstehen, blenden gestaffelt mit ein
    property bool _blendet: false
    // Staffel wie im App-Raster: höchstens 8 Stufen, alles nach Theme.dauerMax fertig
    readonly property int _staffel: Math.max(0, Math.floor((Theme.dauerMax - Theme.dauerKurz) / 8))

    // --- Einträge, Filter, Auswahl -----------------------------------------------------------------------------
    // Gruppen mit Name und Symbol aus dem Starter (nur solange die Übersicht zu sehen ist)
    readonly property var gruppen: _aufgebaut ? _gruppenRoh.map(g => _mitStarter(g)) : []
    readonly property var alle: Liste.eintraege(gruppen)
    property string filterText: ""
    readonly property var gezeigt: Liste.filtern(alle, filterText, !Freigabe.aktiv)
    property int auswahl: 0
    // Die Auswahl kommt von der Tastatur: mit Fokusrahmen. Die Maus wählt ohne.
    property bool tastatur: true
    readonly property int spaltenMax: Liste.spaltenMax(hauptScreen?.width ?? 0, kachelBreite, luecke, Theme.a7)
    readonly property int spalten: Liste.spalten(gezeigt.length, spaltenMax)

    // Filterfeld leeren und fokussieren (an die Fläche mit der Tastatur)
    signal geleert

    Component.onCompleted: Qt.callLater(_ordnen)
    onFensterListeChanged: Qt.callLater(_ordnen)
    onAppKennungenChanged: Qt.callLater(_ordnen)
    onAktivesFensterChanged: {
        _verlauf = Fenster.verlaufNachfuehren(_verlauf, aktivesFenster, fensterListe);
        // Wechsel von aussen: zu. Solange die Übersicht die Tastatur hat, meldet labwc das vorige Fenster weiter als
        // aktiv und aktiviert kein anderes (im Container weder ein neues noch eines über wlr-foreign-toplevel);
        // geschieht es doch, geht sie zu. Kein aktives Fenster (null) zählt nicht als Wechsel.
        if (offen && aktivesFenster && aktivesFenster !== aktivBeimOeffnen)
            schliessen();
    }
    onOffenChanged: {
        if (offen)
            _aufbauen();
    }
    // Ausgeblendet: Kacheln weg und Filter leer. Was getippt war, bleibt nicht bis zum nächsten Öffnen stehen.
    onSichtbarChanged: {
        if (sichtbar)
            return;
        _aufgebaut = false;
        filterText = "";
        geleert();
    }
    onGezeigtChanged: {
        if (auswahl >= gezeigt.length)
            auswahl = Math.max(0, gezeigt.length - 1);
    }

    function schliessen(): void {
        Oberflaeche.uebersichtSchliessen();
    }

    // Fenster wählen: zu, dann activate(). labwc holt so auch ein minimiertes Fenster zurück und hebt es über ein
    // Vollbild-Fenster. Das Ausblenden läuft darüber.
    function waehlen(index: int): void {
        const t = gezeigt[index]?.fenster ?? null;
        schliessen();
        t?.activate();
    }

    function verzoegerung(index: int): int {
        return Math.min(Math.floor(index / spalten) + index % spalten, 8) * _staffel;
    }

    function _aufbauen(): void {
        aktivBeimOeffnen = aktivesFenster ?? null;
        hauptBildschirm = _bildschirmVon(aktivBeimOeffnen);
        tastatur = true;
        filterText = "";
        geleert();
        _verlauf = Fenster.verlaufNachfuehren(_verlauf, aktivesFenster, fensterListe);
        // Neu aufbauen, auch wenn sie noch ausblendet: Die Kacheln entstehen neu und blenden gestaffelt ein
        _blendet = true;
        blendUhr.restart();
        _aufgebaut = false;
        _aufgebaut = true;
        auswahl = Math.max(0, Liste.startIndex(gezeigt, aktivBeimOeffnen, _verlauf));
    }

    // Bildschirm eines Fensters, sonst der erste
    function _bildschirmVon(t: var): string {
        const s = t?.screens;
        const name = s && s.length > 0 ? String(s[0]?.name ?? "") : "";
        if (name !== "" && Quickshell.screens.some(b => b?.name === name))
            return name;
        return Quickshell.screens.length > 0 ? String(Quickshell.screens[0].name ?? "") : "";
    }

    // Name eines anderen Bildschirms für die Karte (nur bei mehreren Bildschirmen), sonst leer
    function bildschirmFuer(t: var): string {
        if (!mehrereBildschirme)
            return "";
        const s = t?.screens;
        const name = s && s.length > 0 ? String(s[0]?.name ?? "") : "";
        return name !== hauptBildschirm ? name : "";
    }

    function _ordnen(): void {
        const liste = fensterListe;
        const ergebnis = Fenster.gruppieren(liste, _reihenfolge);
        _reihenfolge = ergebnis.reihenfolge;
        _verlauf = Fenster.verlaufNachfuehren(_verlauf, aktivesFenster, liste);
        _gruppenRoh = ergebnis.gruppen;
    }

    // Name und Symbol aus dem Starter der App (wie in der App-Leiste), sonst aus dem Icon-Theme unter der appId
    function _mitStarter(g: var): var {
        const eintrag = _starter(g.appId);
        const name = String(eintrag?.name || Fenster.nameOhneStarter(g.appId));
        const symbolName = eintrag?.icon || g.appId;
        return {
            schluessel: g.schluessel,
            appId: g.appId,
            fenster: g.fenster,
            name: name,
            symbol: symbolName ? (Quickshell.iconPath(symbolName, true) ?? "") : "",
            buchstabe: Fenster.buchstabe(name)
        };
    }

    function _starter(appId: string): var {
        if (appId === "")
            return null;
        // Web-Apps aus Chrome tragen den Host in der appId; ihr Starter (zenos-webapp) nennt ihn im Kommentar
        const host = Fenster.webAppHost(appId);
        if (host !== "") {
            const webApp = DesktopEntries.applications.values.find(e => e.id.startsWith("zenos-webapp-") && e.comment === "Web-App · " + host);
            if (webApp)
                return webApp;
        }
        return DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId) ?? null;
    }

    // Tasten im Filterfeld: Pfeile, Tab und Shift+Tab wählen, Pos1 und Ende (nur bei leerem Filter) springen an den
    // Anfang bzw. ans Ende, ↵ wechselt, Esc schliesst. Alles andere geht an das Feld: Tippen filtert.
    function _taste(event: KeyEvent): void {
        const n = gezeigt.length;
        let erledigt = true;
        switch (event.key) {
        case Qt.Key_Escape:
            schliessen();
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (n > 0)
                waehlen(auswahl);
            break;
        case Qt.Key_Left:
        case Qt.Key_Backtab:
            _bewegen(-1, 0);
            break;
        case Qt.Key_Right:
            _bewegen(1, 0);
            break;
        case Qt.Key_Tab:
            // Shift+Tab kommt je nach Tastaturbelegung als Backtab oder als Tab mit Shift
            _bewegen((event.modifiers & Qt.ShiftModifier) ? -1 : 1, 0);
            break;
        case Qt.Key_Up:
            _bewegen(0, -1);
            break;
        case Qt.Key_Down:
            _bewegen(0, 1);
            break;
        case Qt.Key_Home:
        case Qt.Key_End:
            erledigt = filterText.length === 0;
            if (erledigt && n > 0) {
                tastatur = true;
                auswahl = event.key === Qt.Key_Home ? 0 : n - 1;
            }
            break;
        default:
            erledigt = false;
        }
        if (erledigt)
            event.accepted = true;
    }

    function _bewegen(dx: int, dy: int): void {
        tastatur = true;
        auswahl = Math.max(0, Liste.bewegen(auswahl, dx, dy, gezeigt.length, spalten));
    }

    Timer {
        id: blendUhr

        interval: Theme.dauerMax
        onTriggered: root._blendet = false
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: flaeche

            required property ShellScreen modelData
            // Bildschirm mit Tastatur, Filter und Kacheln; die anderen sind nur zugedeckt
            readonly property bool haupt: root.hauptBildschirm !== "" && (modelData?.name ?? "") === root.hauptBildschirm

            // Ausgewählte Kachel ganz zeigen, wenn das Raster scrollt (ohne Animation, wie im Befehlsfeld)
            function _auswahlZeigen(): void {
                if (!gitter.interactive) {
                    gitter.contentY = 0;
                    return;
                }
                const oben = Math.floor(root.auswahl / root.spalten) * (root.kachelHoehe + root.luecke);
                const unten = oben + root.kachelHoehe + 2 * root.rasterRand;
                if (oben < gitter.contentY)
                    gitter.contentY = oben;
                else if (unten > gitter.contentY + gitter.height)
                    gitter.contentY = unten - gitter.height;
            }

            screen: modelData
            visible: root.sichtbar
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.durchsichtig
            // Beim Ausblenden fängt die Fläche keine Klicks mehr
            mask: root.offen ? null : leer

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.offen && haupt ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "zenos-uebersicht"

            onVisibleChanged: {
                if (visible && haupt)
                    filter.forceActiveFocus();
            }

            Connections {
                target: root

                function onGeleert(): void {
                    filter.text = "";
                    gitter.contentY = 0;
                    if (flaeche.haupt)
                        filter.forceActiveFocus();
                }

                function onAuswahlChanged(): void {
                    if (flaeche.haupt && root.tastatur)
                        Qt.callLater(flaeche._auswahlZeigen);
                }
            }

            Region {
                id: leer
            }

            Item {
                id: inhalt

                anchors.fill: parent
                opacity: root.deckkraft

                // Zugedeckt (kein Weichzeichnen); ein Klick daneben schliesst, ebenso Rechts- und Mittelklick
                Rectangle {
                    anchors.fill: parent
                    color: Theme.zudecken

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: root.schliessen()
                    }
                }

                Item {
                    id: bedienung

                    anchors.fill: parent
                    visible: flaeche.haupt

                    // Filterzeile: Pille oben mittig, zeigt, was getippt ist (sonst den Hinweis)
                    Rectangle {
                        id: pille

                        x: Math.round((parent.width - width) / 2)
                        y: Theme.leisteHoehe + Theme.a6
                        width: root.pilleBreite
                        height: root.pilleHoehe
                        radius: Theme.radiusPille
                        color: Theme.flaeche
                        border.width: 1
                        border.color: Theme.linie2

                        Symbol {
                            id: lupe

                            x: Theme.a4
                            anchors.verticalCenter: parent.verticalCenter
                            name: "suche"
                            groesse: 16
                            farbe: Theme.gedaempft
                        }

                        Text {
                            anchors.fill: filter
                            verticalAlignment: Text.AlignVCenter
                            visible: filter.text.length === 0 && filter.preeditText.length === 0
                            text: "Tippen filtert"
                            textFormat: Text.PlainText
                            color: Theme.gedaempft
                            font: filter.font
                        }

                        TextInput {
                            id: filter

                            anchors.left: lupe.right
                            anchors.leftMargin: Theme.a3
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.a4
                            anchors.verticalCenter: parent.verticalCenter
                            height: 28
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            focus: true
                            color: Theme.text
                            selectionColor: Qt.alpha(Theme.akzent, 0.35)
                            selectedTextColor: Theme.text
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseText
                            maximumLength: 100
                            inputMethodHints: Qt.ImhNoPredictiveText
                            Accessible.name: "Fenster filtern"
                            // Ruhiger Cursor: stehender Strich, 1 px (wie im Befehlsfeld)
                            cursorDelegate: Rectangle {
                                width: 1
                                color: Theme.text
                                visible: filter.cursorVisible
                            }
                            // Neue Eingabe: der erste Treffer ist gewählt
                            onTextChanged: {
                                if (root.filterText === text)
                                    return;
                                root.filterText = text;
                                root.tastatur = true;
                                root.auswahl = 0;
                            }

                            Keys.onPressed: event => root._taste(event)
                        }
                    }

                    // Kacheln mittig zwischen Filterzeile und Fusszeile; scrollt, wenn es mehr sind, als passen
                    Flickable {
                        id: gitter

                        readonly property int zeilen: Math.ceil(root.gezeigt.length / root.spalten)
                        readonly property real inhaltBreite: root.spalten * (root.kachelBreite + root.luecke) - root.luecke + 2 * root.rasterRand
                        readonly property real inhaltHoehe: zeilen > 0 ? zeilen * (root.kachelHoehe + root.luecke) - root.luecke + 2 * root.rasterRand : 0
                        readonly property real oben: pille.y + pille.height + Theme.a6
                        readonly property real unten: bedienung.height - Theme.a7 - fuss.height - Theme.a5

                        visible: root.gezeigt.length > 0
                        x: Math.round((parent.width - width) / 2)
                        y: Math.round(oben + Math.max(0, (unten - oben - height) / 2))
                        width: inhaltBreite
                        height: Math.max(0, Math.min(inhaltHoehe, unten - oben))
                        contentWidth: inhaltBreite
                        contentHeight: inhaltHoehe
                        interactive: inhaltHoehe > height
                        clip: interactive
                        boundsBehavior: Flickable.StopAtBounds

                        // Lücken zwischen den Kacheln: ein Klick schliesst wie daneben
                        MouseArea {
                            width: gitter.contentWidth
                            height: gitter.contentHeight
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: root.schliessen()
                        }

                        Repeater {
                            model: flaeche.haupt ? root.gezeigt : []

                            delegate: FensterKachel {
                                id: kachel

                                required property var modelData
                                required property int index

                                x: root.rasterRand + (index % root.spalten) * (root.kachelBreite + root.luecke)
                                y: root.rasterRand + Math.floor(index / root.spalten) * (root.kachelHoehe + root.luecke)
                                width: root.kachelBreite
                                height: root.kachelHoehe
                                eintrag: modelData
                                aktiv: modelData?.fenster === root.aktivBeimOeffnen
                                gewaehlt: root.auswahl === index
                                fokus: root.tastatur && root.auswahl === index
                                titelVerborgen: Freigabe.aktiv
                                bildschirm: root.bildschirmFuer(modelData?.fenster)
                                onGezeigt: {
                                    root.tastatur = false;
                                    root.auswahl = kachel.index;
                                }
                                onAusgefuehrt: root.waehlen(kachel.index)
                                Component.onCompleted: {
                                    if (root._blendet)
                                        kachel.einblenden(root.verzoegerung(kachel.index));
                                }
                            }
                        }
                    }

                    // Leer: keine Fenster bzw. keine Treffer
                    Column {
                        id: leerHinweis

                        visible: root.gezeigt.length === 0
                        anchors.centerIn: parent
                        spacing: Theme.a3

                        ZenZeichen {
                            anchors.horizontalCenter: parent.horizontalCenter
                            groesse: 32
                            obenFarbe: Theme.gedaempft
                            einfarbig: true
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.alle.length === 0 ? "Keine offenen Fenster" : "Keine Treffer"
                            textFormat: Text.PlainText
                            color: Theme.gedaempft
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseText
                        }
                    }

                    // Fusszeile direkt unter den Kacheln (am unteren Rand läge sie auf den Tastenkappen von
                    // «Heute»)
                    Row {
                        id: fuss

                        x: Math.round((parent.width - width) / 2)
                        y: root.gezeigt.length > 0 ? gitter.y + gitter.height + Theme.a5 : leerHinweis.y + leerHinweis.height + Theme.a6
                        spacing: 20

                        Repeater {
                            model: root.alle.length > 0 ? ["←↑↓→ wählen", "↵ wechseln", "Tippen filtert", "Esc schliessen"] : ["Esc schliessen"]

                            delegate: Text {
                                required property string modelData

                                text: modelData
                                textFormat: Text.PlainText
                                color: Theme.gedaempft
                                font.family: Theme.schriftText
                                font.pixelSize: Theme.groesseLabel
                            }
                        }
                    }
                }
            }
        }
    }

    // zenos-ipc uebersicht umschalten|oeffnen|schliessen|status|fenster (Super+Tab, Tests und Abnahme)
    IpcHandler {
        target: "uebersicht"

        function umschalten(): void {
            Oberflaeche.uebersichtUmschalten();
        }

        function oeffnen(): void {
            Oberflaeche.uebersichtOeffnen();
        }

        function schliessen(): void {
            root.schliessen();
        }

        // "offen" oder "zu"; "zu" erst, wenn die Fläche weg ist
        function status(): string {
            return root.sichtbar ? "offen" : "zu";
        }

        // Eine Zeile je Kachel (offen: wie gezeigt, mit Filter; zu: alle): Index, appId, «Titel» (bei Freigabe
        // verborgen), dazu aktiv, minimiert, vollbild, gewaehlt
        function fenster(): string {
            const liste = root._aufgebaut ? root.gezeigt : Liste.eintraege(root._gruppenRoh);
            return liste.map((e, i) => {
                const t = e?.fenster;
                const titel = Freigabe.aktiv ? "Titel verborgen" : String(t?.title ?? "");
                return [String(i), e?.app?.appId || "-", "«" + titel + "»", t === root.aktivesFenster ? "aktiv" : "", t?.minimized ? "minimiert" : "", t?.fullscreen ? "vollbild" : "", root._aufgebaut && i === root.auswahl ? "gewaehlt" : ""].filter(w => w !== "").join(" ");
            }).join("\n");
        }
    }
}
