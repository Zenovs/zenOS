pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste
import "fenster.mjs" as Fenster

// App-Leiste am rechten Rand: ein Symbol pro offener App, ein Klick holt sie nach vorne. Auch über Vollbild-Fenstern
// (Ebene Overlay; labwc legt Vollbild nur über die Ebene Top). Sonst ist nichts zu sehen: Pro Bildschirm liegt im
// mittleren Drittel des rechten Rands eine unsichtbare Auslösezone von 1 px. Verweilt der Zeiger dort
// root.verweilen ms, gleitet die Karte herein; verlässt er Karte und Zone, verschwindet sie nach root.gnadenfrist ms,
// ebenso nach einem Klick auf eine App. Nie während Sperre und Einrichtung; offene Menüs, Befehlsfeld, Wahl und
// Zentrale gehen vor. Mausbedienung, keine Tastatur (das Befehlsfeld ist die Zentrale). Doku: docs/design.md.
// IPC «appleiste»: zeigen, verbergen, status (offen/zu), apps (eine Zeile pro App).
Scope {
    id: root

    // Verweilen am Rand, bis die Leiste erscheint: länger als ein Vorbeistreifen oder Überschiessen beim Zielen auf
    // Bildlaufleiste oder Schliessen-Knopf (meist unter 200 ms), kürzer als die 500 ms der Einrast-Vorschau von labwc
    readonly property int verweilen: 300
    // Gnadenfrist nach dem Verlassen: ein kurzes Abrutschen von der Karte schliesst sie nicht
    readonly property int gnadenfrist: 400
    // So weit darf der Zeiger am Rand auf und ab wandern, ohne dass das Verweilen neu beginnt (Streifen entlang des
    // Rands zur Bildlaufleiste zählt nicht als Verweilen)
    readonly property int ruheSpielraum: 24
    // Masse der Karte: Zellen 48 px (Symbol 40), Innenabstand oben/unten Theme.a2, links/rechts Theme.a3 (rechts
    // steht der Akzentpunkt), Abstand zum Rand Theme.a2. Beschriftung höchstens 240 px breit.
    readonly property int zelle: 48
    readonly property int kartenBreite: zelle + 2 * Theme.a3
    readonly property int beschriftungMax: 240

    // Darf die Leiste erscheinen? Leitplanken (Sperre, Einrichtung) und andere Oberflächen gehen vor.
    readonly property bool erlaubt: !Oberflaeche.gesperrt && !Oberflaeche.einrichtungOffen && !Oberflaeche.befehlsfeldOffen && Oberflaeche.leisteMenueBildschirm === "" && !Oberflaeche.modusWahlOffen && !Oberflaeche.zustandWahlOffen && !Oberflaeche.zentraleOffen
    // Gibt es keine offene App, erscheint die Leiste nicht (auch die Auslösezone fehlt dann)
    readonly property bool bereit: erlaubt && gruppen.length > 0

    // Bildschirm (ShellScreen.name), auf dem die Leiste offen ist; leer = zu
    property string offenAuf: ""

    // Apps in fester Reihenfolge: {schluessel, appId, name, symbol, buchstabe, fenster: [Toplevel]}
    property var gruppen: []
    readonly property var aktivesFenster: ToplevelManager.activeToplevel
    // Schlüssel der Apps in der Reihenfolge ihres ersten Fensters; zuletzt aktive Fenster (neueste zuerst)
    property var _reihenfolge: []
    property var _verlauf: []

    // Ordnet neu, wenn Fenster kommen oder gehen oder eine appId sich ändert (Titel bleiben aussen vor: Browser
    // und Terminals ändern sie dauernd). Schon beim Start gebunden: ToplevelManager füllt sich erst nach dem ersten
    // Zugriff, und die Reihenfolge des ersten Öffnens gilt ab Sitzungsbeginn.
    readonly property var fensterListe: ToplevelManager.toplevels.values
    readonly property string appKennungen: fensterListe.map(t => t?.appId ?? "").join("\n")

    // Liste und Kennungen ändern sich meist zusammen: einmal ordnen, nach dem aktuellen Ereignis. Auch beim Laden:
    // Hat ein anderer Teil der Oberfläche ToplevelManager schon gefüllt (Modi bindet ihn beim Start, die Leiste lädt
    // danach im Hintergrund), meldet die Liste keine Änderung mehr, und die Leiste bliebe bis zum nächsten Fenster leer.
    Component.onCompleted: Qt.callLater(_ordnen)
    onFensterListeChanged: Qt.callLater(_ordnen)
    onAppKennungenChanged: Qt.callLater(_ordnen)
    onAktivesFensterChanged: _verlauf = Fenster.verlaufNachfuehren(_verlauf, aktivesFenster, fensterListe)
    onBereitChanged: {
        if (!bereit)
            schliessen();
    }

    function zeigen(bildschirm: string): void {
        if (bereit && bildschirm !== "")
            offenAuf = bildschirm;
    }

    function schliessen(): void {
        offenAuf = "";
    }

    // Klick auf eine App: zuletzt aktives Fenster nach vorne; ist die App schon aktiv, ihr nächstes Fenster.
    // activate() holt bei labwc auch ein minimiertes Fenster zurück (desktop_focus_view) und hebt es über ein
    // Vollbild-Fenster.
    function waehlen(app: var): void {
        const t = Fenster.ziel(app?.fenster, aktivesFenster, _verlauf);
        schliessen();
        t?.activate();
    }

    function _ordnen(): void {
        const liste = fensterListe;
        const ergebnis = Fenster.gruppieren(liste, _reihenfolge);
        _reihenfolge = ergebnis.reihenfolge;
        _verlauf = Fenster.verlaufNachfuehren(_verlauf, aktivesFenster, liste);
        gruppen = ergebnis.gruppen.map(g => _mitStarter(g));
    }

    // Name und Symbol aus dem Starter der App (wie im Befehlsfeld), sonst aus dem Icon-Theme unter der appId
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

    function _bildschirmFuerIpc(): string {
        const s = aktivesFenster?.screens;
        if (s && s.length > 0 && s[0]?.name)
            return s[0].name;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    // Neue oder entfernte Starter (z. B. eine App eben installiert): Namen und Symbole neu
    Connections {
        target: DesktopEntries.applications

        function onValuesChanged(): void {
            Qt.callLater(root._ordnen);
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: proBildschirm

            required property ShellScreen modelData
            // beim Abziehen des Bildschirms wird modelData null, der Name bleibt
            property string bildschirmName: ""
            readonly property bool hier: root.offenAuf !== "" && root.offenAuf === bildschirmName
            readonly property int hoehe: modelData?.height ?? 0
            // Zeiger in der Auslösezone bzw. über Karte und Randstreifen
            property bool amRand: false
            property bool ueberLeiste: false
            // Höhe des Zeigers beim Beginn des Verweilens
            property real _start: 0
            // Index der gezeigten App (Beschriftung) oder -1
            property int gezeigt: -1

            // Nur ein Verlassen startet die Gnadenfrist. Per IPC geöffnet bleibt die Leiste so stehen, bis der
            // Zeiger einmal darüber war oder verbergen kommt.
            function _verlassen(): void {
                if (hier && !amRand && !ueberLeiste)
                    gnade.restart();
            }

            function _bewegt(y: real): void {
                if (!amRand || hier || Math.abs(y - _start) <= root.ruheSpielraum)
                    return;
                _start = y;
                verweilUhr.restart();
            }

            Component.onCompleted: bildschirmName = modelData?.name ?? ""
            Component.onDestruction: {
                if (root.offenAuf === bildschirmName)
                    root.schliessen();
            }

            onAmRandChanged: {
                if (amRand) {
                    gnade.stop();
                    if (!hier) {
                        _start = zonenMaus.mouseY;
                        verweilUhr.restart();
                    }
                } else {
                    verweilUhr.stop();
                    _verlassen();
                }
            }
            onUeberLeisteChanged: {
                if (ueberLeiste)
                    gnade.stop();
                else
                    _verlassen();
            }
            onHierChanged: {
                gnade.stop();
                gezeigt = -1;
                if (hier) {
                    ausblenden.stop();
                    karte.opacity = 0;
                    karte.versatz = root.kartenBreite + Theme.a2;
                    einblenden.restart();
                } else {
                    einblenden.stop();
                    ausblenden.restart();
                }
            }

            Timer {
                id: verweilUhr

                interval: root.verweilen
                onTriggered: {
                    if (proBildschirm.amRand)
                        root.zeigen(proBildschirm.bildschirmName);
                }
            }

            Timer {
                id: gnade

                interval: root.gnadenfrist
                onTriggered: {
                    if (proBildschirm.hier && !proBildschirm.amRand && !proBildschirm.ueberLeiste)
                        root.schliessen();
                }
            }

            // Auslösezone: 1 px am rechten Rand, mittleres Drittel der Höhe, unsichtbar. Der Zeiger stösst am Rand an
            // (labwc begrenzt ihn auf die letzte Spalte), 1 px genügt also und nimmt einem Vollbild-Fenster dort am
            // wenigsten weg (z. B. die Bildlaufleiste eines Browsers).
            PanelWindow {
                screen: proBildschirm.modelData
                visible: root.bereit
                anchors.right: true
                implicitWidth: 1
                implicitHeight: Math.max(1, Math.round(proBildschirm.hoehe / 3))
                exclusionMode: ExclusionMode.Ignore
                color: Theme.durchsichtig

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                WlrLayershell.namespace: "zenos-appleiste-rand"

                // Ein verborgenes Fenster meldet kein Verlassen mehr: Zustand selbst zurücksetzen
                onVisibleChanged: {
                    if (!visible)
                        proBildschirm.amRand = false;
                }

                MouseArea {
                    id: zonenMaus

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onContainsMouseChanged: proBildschirm.amRand = containsMouse
                    onPositionChanged: mouse => proBildschirm._bewegt(mouse.y)
                }
            }

            // Leiste: Karte am rechten Rand, mittig; links daneben die Beschriftung der gezeigten App. Eingaben nimmt
            // nur die Karte mit dem Streifen bis zum Rand an, über der Beschriftung gehen Klicks durch.
            PanelWindow {
                id: leistenFenster

                screen: proBildschirm.modelData
                visible: proBildschirm.hier || karte.opacity > 0
                anchors.right: true
                implicitWidth: root.beschriftungMax + Theme.a2 + root.kartenBreite + Theme.a2
                implicitHeight: karte.height
                exclusionMode: ExclusionMode.Ignore
                color: Theme.durchsichtig
                // Beim Ausblenden fängt die Leiste keine Klicks mehr
                mask: proBildschirm.hier ? greifRegion : leer

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                WlrLayershell.namespace: "zenos-appleiste"

                onVisibleChanged: {
                    if (!visible)
                        proBildschirm.ueberLeiste = false;
                }

                Region {
                    id: greifRegion

                    item: greifFlaeche
                }

                Region {
                    id: leer
                }

                // Fläche, die Eingaben annimmt (Region oben)
                Item {
                    id: greifFlaeche

                    x: parent.width - width
                    width: root.kartenBreite + Theme.a2
                    height: parent.height
                }

                // Einblenden: gleitet in Theme.dauerMax von rechts herein, Deckkraft in Theme.dauerKurz.
                // Ausblenden nur über die Deckkraft (wie das Befehlsfeld).
                ParallelAnimation {
                    id: einblenden

                    NumberAnimation {
                        target: karte
                        property: "versatz"
                        to: 0
                        duration: Theme.dauerMax
                        easing.type: Theme.kurve
                    }
                    NumberAnimation {
                        target: karte
                        property: "opacity"
                        to: 1
                        duration: Theme.dauerKurz
                        easing.type: Theme.kurve
                    }
                }

                NumberAnimation {
                    id: ausblenden

                    target: karte
                    property: "opacity"
                    to: 0
                    duration: Theme.dauerKurz
                    easing.type: Theme.kurve
                }

                // Gemeinsamer Vorfahr von Karte und Beschriftung: Der Zeiger zählt als «über der Leiste», auch wenn
                // er über einem Eintrag steht (dessen MouseArea nimmt das Zeigen sonst für sich). Eingaben kommen
                // nur innerhalb der Region an.
                Item {
                    anchors.fill: parent

                    HoverHandler {
                        onHoveredChanged: proBildschirm.ueberLeiste = hovered
                    }

                    // Karte im Stil der Menüs: flaeche, Rahmen linie2, Radius 12, ohne Schatten
                    Rectangle {
                        id: karte

                        property real versatz: 0
                        readonly property int inhaltHoehe: root.gruppen.length * root.zelle + Math.max(0, root.gruppen.length - 1) * Theme.a1

                        x: parent.width - Theme.a2 - width
                        width: root.kartenBreite
                        height: Math.max(root.zelle, Math.min(inhaltHoehe, proBildschirm.hoehe - 2 * Theme.a6 - 2 * Theme.a2)) + 2 * Theme.a2
                        opacity: 0
                        radius: Theme.radiusFenster
                        color: Theme.flaeche
                        border.width: 1
                        border.color: Theme.linie2
                        transform: Translate {
                            x: karte.versatz
                        }

                        // Mehr Apps, als die Höhe fasst: die Spalte scrollt (Mausrad, Touchpad)
                        Flickable {
                            id: liste

                            x: Theme.a3
                            y: Theme.a2
                            width: root.zelle + Theme.a3
                            height: karte.height - 2 * Theme.a2
                            contentHeight: karte.inhaltHoehe
                            interactive: contentHeight > height
                            clip: interactive
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                spacing: Theme.a1

                                Repeater {
                                    model: ScriptModel {
                                        values: root.gruppen
                                        objectProp: "schluessel"
                                    }

                                    // Daten über den Index aus root.gruppen (immer der neueste Stand); das Modell hält die
                                    // Einträge nur pro App fest, damit beim Öffnen und Schliessen nichts neu lädt
                                    AppEintrag {
                                        id: eintrag

                                        required property int index

                                        width: root.zelle
                                        height: root.zelle
                                        app: root.gruppen[eintrag.index] ?? null
                                        punktStreifen: Theme.a3
                                        zeigbar: !einblenden.running
                                        aktiv: !!root.aktivesFenster && (eintrag.app?.fenster ?? []).indexOf(root.aktivesFenster) >= 0
                                        onGewaehlt: root.waehlen(eintrag.app)
                                        onGezeigt: ja => {
                                            if (ja)
                                                proBildschirm.gezeigt = eintrag.index;
                                            else if (proBildschirm.gezeigt === eintrag.index)
                                                proBildschirm.gezeigt = -1;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Beschriftung der gezeigten App: kleine Pille links neben der Karte, auf Höhe des Symbols
                    Rectangle {
                        id: beschriftung

                        readonly property var app: proBildschirm.gezeigt >= 0 ? root.gruppen[proBildschirm.gezeigt] ?? null : null
                        property string text: ""

                        x: karte.x - Theme.a2 - width
                        y: Math.round(karte.y + liste.y - liste.contentY + Math.max(0, proBildschirm.gezeigt) * (root.zelle + Theme.a1) + (root.zelle - height) / 2)
                        width: Math.min(root.beschriftungMax, beschriftungsText.implicitWidth + 2 * Theme.a3)
                        height: 28
                        radius: Theme.radiusChip
                        color: Theme.flaeche
                        border.width: 1
                        border.color: Theme.linie2
                        opacity: app !== null && proBildschirm.hier ? 1 : 0
                        visible: opacity > 0

                        // Text bleibt beim Ausblenden stehen
                        onAppChanged: {
                            if (app !== null)
                                text = String(app.name ?? "");
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.dauerKurz
                                easing.type: Theme.kurve
                            }
                        }

                        Text {
                            id: beschriftungsText

                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.a3
                            width: parent.width - 2 * Theme.a3
                            text: beschriftung.text
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                        }
                    }
                }
            }
        }
    }

    // zenos-ipc appleiste zeigen|verbergen|status|apps (für Tests und eigene Tastenkürzel). zeigen öffnet auf dem
    // Bildschirm des aktiven Fensters, sonst auf dem ersten, und nur, wenn die Leiste erscheinen darf.
    IpcHandler {
        target: "appleiste"

        function zeigen(): void {
            root.zeigen(root._bildschirmFuerIpc());
        }

        function verbergen(): void {
            root.schliessen();
        }

        function status(): string {
            return root.offenAuf !== "" ? "offen" : "zu";
        }

        // Eine Zeile pro App in der Reihenfolge der Leiste: appId, Anzahl Fenster, «aktiv» bei der aktiven App
        function apps(): string {
            return root.gruppen.map(g => [g.appId || "-", String(g.fenster.length), g.fenster.indexOf(root.aktivesFenster) >= 0 ? "aktiv" : ""].join(" ").trim()).join("\n");
        }
    }
}
