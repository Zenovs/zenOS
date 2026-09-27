pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.dienste as Dienste

// Mitteilungen: Sammelkarte und dringende Karten oben rechts unter der Leiste, Zentrale
// als Panel rechts, IPC «mitteilungen». Die Logik (Bündelung, Leitplanke) steckt im
// Dienst Mitteilungen; hier wird nur gezeigt.
Scope {
    id: root

    readonly property int kartenBreite: 380
    // Die Sammelkarte verschwindet nach dieser Zeit (ms) und bleibt in der Zentrale
    readonly property int sammlungDauer: 10000
    readonly property int maxDringend: 3

    // Karten in der Reihenfolge ihres Erscheinens: "sammlung" und "d<nummer>" je dringender
    // Mitteilung. Neue Karten kommen unten dazu, damit nichts Sichtbares verrutscht.
    property var reihenfolge: []
    property var sammlungNummern: []
    property bool sammlungOffen: false
    property var sammlungZeit: null

    readonly property bool verborgen: Dienste.Mitteilungen.inhalteVerborgen

    // Bildschirm der Zentrale und der Karten: der, auf dem die Zentrale zuletzt geöffnet wurde
    // (Oberflaeche.zentraleBildschirm, setzt die Leiste), sonst der erste
    readonly property string bildschirmName: String(Dienste.Oberflaeche.zentraleBildschirm ?? "")
    readonly property var bildschirm: {
        const screens = Quickshell.screens;
        const named = bildschirmName !== "" ? screens.find(s => s.name === bildschirmName) : undefined;
        return named ?? screens[0] ?? null;
    }
    // Sichtbare Karten wechseln den Bildschirm nicht (nichts springt); erst die nächsten
    property var kartenBildschirm: null
    // Einträge der Sammelkarte (neueste zuerst); verschwindet eine Mitteilung, fällt sie heraus
    readonly property var sammlung: sammlungNummern.length === 0 ? [] : Dienste.Mitteilungen.zugestellt.filter(e => root.sammlungNummern.indexOf(e.nummer) >= 0)
    // Modell der Kartenspalte: { schluessel, eintrag } (eintrag nur bei dringenden Karten)
    readonly property var karten: {
        const liste = [];
        for (const schluessel of reihenfolge) {
            if (schluessel === "sammlung") {
                liste.push({
                    schluessel: schluessel,
                    eintrag: null
                });
                continue;
            }
            const eintrag = Dienste.Mitteilungen.zugestellt.find(e => "d" + e.nummer === schluessel);
            if (eintrag)
                liste.push({
                    schluessel: schluessel,
                    eintrag: eintrag
                });
        }
        return liste;
    }
    readonly property int anzahlDringendKarten: karten.filter(k => k.schluessel !== "sammlung").length

    // Frisch zugestellt: Nicht Dringendes auf die Sammelkarte, Dringendes einzeln
    function zeigen(eintraege: var): void {
        if (Dienste.Oberflaeche.zentraleOffen)
            return;
        const normal = eintraege.filter(e => !e.dringend).map(e => e.nummer);
        const eilig = eintraege.filter(e => e.dringend).map(e => "d" + e.nummer);
        let liste = reihenfolge.slice();
        if (normal.length > 0) {
            // Eine sichtbare Karte wird ergänzt, sonst beginnt eine neue
            const bisher = liste.indexOf("sammlung") >= 0 ? sammlungNummern.filter(n => normal.indexOf(n) < 0) : [];
            sammlungNummern = normal.concat(bisher);
            sammlungZeit = new Date();
            if (liste.indexOf("sammlung") < 0)
                liste.push("sammlung");
            sammlungOffen = true;
            sammlungUhr.restart();
        }
        for (const schluessel of eilig) {
            if (liste.indexOf(schluessel) < 0)
                liste.push(schluessel);
        }
        // höchstens maxDringend dringende Karten; die ältesten bleiben nur in der Zentrale
        let ueberzahl = liste.filter(k => k !== "sammlung").length - maxDringend;
        liste = liste.filter(k => k === "sammlung" || ueberzahl-- <= 0);
        reihenfolge = liste;
    }

    function entfernen(schluessel: string): void {
        if (reihenfolge.indexOf(schluessel) >= 0)
            reihenfolge = reihenfolge.filter(k => k !== schluessel);
    }

    function allesAusblenden(): void {
        sammlungOffen = false;
        reihenfolge = reihenfolge.filter(k => k === "sammlung");
    }

    function zentraleOeffnen(): void {
        Dienste.Oberflaeche.zentraleOffen = true;
    }

    // Klick auf eine Mitteilung: Standardaktion, sonst die Zentrale
    function geklickt(eintrag: var): void {
        gesehen([eintrag]);
        if (eintrag?.standardAktion)
            Dienste.Mitteilungen.aktionAusfuehren(eintrag.nummer, "default");
        else
            zentraleOeffnen();
    }

    function aktion(eintrag: var, kennung: string): void {
        gesehen([eintrag]);
        Dienste.Mitteilungen.aktionAusfuehren(eintrag.nummer, kennung);
    }

    // Angeklickte oder von Hand geschlossene Karten gelten als angesehen, ausser bei Freigabe
    // (dann war kein Inhalt zu sehen)
    function gesehen(eintraege: var): void {
        if (verborgen)
            return;
        for (const eintrag of eintraege) {
            if (eintrag)
                Dienste.Mitteilungen.alsGesehen(eintrag.nummer);
        }
    }

    function kartenBildschirmAktualisieren(): void {
        if (!fenster.visible && kartenBildschirm !== bildschirm)
            kartenBildschirm = bildschirm;
    }

    onBildschirmChanged: kartenBildschirmAktualisieren()
    Component.onCompleted: kartenBildschirm = bildschirm

    onSammlungChanged: if (sammlungOffen && sammlung.length === 0)
        sammlungOffen = false
    // Geschlossene Mitteilungen aus der Reihenfolge nehmen (später, sonst Bindungsschleife)
    onKartenChanged: if (karten.length !== reihenfolge.length)
        Qt.callLater(aufraeumen)

    function aufraeumen(): void {
        const gueltig = karten.map(k => k.schluessel);
        if (gueltig.length !== reihenfolge.length)
            reihenfolge = gueltig;
    }

    Connections {
        target: Dienste.Mitteilungen

        function onAusgeliefert(eintraege: var): void {
            root.zeigen(eintraege);
        }

        // Leitplanke: beginnt eine Freigabe, verschwindet die Sammelkarte sofort
        function onInhalteVerborgenChanged(): void {
            if (Dienste.Mitteilungen.inhalteVerborgen)
                root.sammlungOffen = false;
        }
    }

    Connections {
        target: Dienste.Oberflaeche

        function onZentraleOffenChanged(): void {
            if (Dienste.Oberflaeche.zentraleOffen)
                root.allesAusblenden();
        }

        // Eine Sache im Fokus: das Befehlsfeld schliesst die Zentrale
        function onBefehlsfeldOffenChanged(): void {
            if (Dienste.Oberflaeche.befehlsfeldOffen)
                Dienste.Oberflaeche.zentraleOffen = false;
        }
    }

    Timer {
        id: sammlungUhr

        interval: root.sammlungDauer
        // Solange der Zeiger auf den Karten liegt, bleibt die Sammelkarte
        running: root.sammlungOffen && !hover.hovered
        onTriggered: root.sammlungOffen = false
    }

    IpcHandler {
        target: "mitteilungen"

        // Zentrale öffnen oder schliessen
        function zentrale(): void {
            Dienste.Oberflaeche.zentraleOffen = !Dienste.Oberflaeche.zentraleOffen;
        }

        function oeffnen(): void {
            Dienste.Oberflaeche.zentraleOffen = true;
        }

        function schliessen(): void {
            Dienste.Oberflaeche.zentraleOffen = false;
        }

        // Alles Wartende jetzt zustellen
        function zustellen(): void {
            Dienste.Mitteilungen.zustellen();
        }

        function verwerfen(nummer: int): void {
            Dienste.Mitteilungen.verwerfen(nummer);
        }

        function alleVerwerfen(): void {
            Dienste.Mitteilungen.alleVerwerfen();
        }

        // Aktion auslösen, z. B. «default»; Rückgabe «ok» oder «unbekannt»
        function aktion(nummer: int, kennung: string): string {
            return Dienste.Mitteilungen.aktionAusfuehren(nummer, kennung) ? "ok" : "unbekannt";
        }

        // Stand als JSON, ohne Inhalte
        function status(): string {
            const m = Dienste.Mitteilungen;
            const naechste = m.naechsteZustellung;
            return JSON.stringify({
                modus: m.modus,
                wartend: m.anzahlWartend,
                zugestellt: m.anzahlZugestellt,
                ungelesen: m.anzahlUngelesen,
                dringend: m.wartend.concat(m.zugestellt).filter(e => e.dringend).length,
                naechsteZustellung: naechste ? naechste.toISOString() : null,
                inhalteVerborgen: m.inhalteVerborgen,
                zentraleOffen: Dienste.Oberflaeche.zentraleOffen,
                bildschirm: root.bildschirm?.name ?? "",
                kartenBildschirm: root.kartenBildschirm?.name ?? "",
                sammelkarte: root.sammlungOffen ? root.sammlung.length : 0,
                dringendeKarten: root.anzahlDringendKarten,
                karten: root.karten.map(k => k.schluessel),
                nummern: m.zugestellt.map(e => e.nummer)
            });
        }
    }

    // Karten oben rechts unter der Leiste. Das Fenster reicht bis unten, damit sich die
    // Karten ohne Abschneiden verschieben können; Eingaben nimmt nur die Kartenspalte an.
    PanelWindow {
        id: fenster

        visible: root.karten.length > 0
        screen: root.kartenBildschirm
        anchors {
            top: true
            right: true
            bottom: true
        }
        margins {
            top: Theme.a2
            right: Theme.a2
        }
        implicitWidth: root.kartenBreite
        exclusiveZone: 0
        color: Theme.durchsichtig
        mask: Region {
            item: spalte
        }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "zenos-mitteilungen"

        onVisibleChanged: root.kartenBildschirmAktualisieren()

        Column {
            id: spalte

            width: parent.width
            spacing: Theme.a2

            // Schliesst sich eine Karte, rücken die folgenden ruhig nach
            move: Transition {
                NumberAnimation {
                    property: "y"
                    duration: Theme.dauerMax
                    easing.type: Theme.kurve
                }
            }

            HoverHandler {
                id: hover
            }

            Repeater {
                model: ScriptModel {
                    values: root.karten
                    objectProp: "schluessel"
                }

                Loader {
                    id: karte

                    required property var modelData
                    readonly property string schluessel: modelData.schluessel
                    readonly property var eintrag: modelData.eintrag

                    width: spalte.width
                    sourceComponent: schluessel === "sammlung" ? sammelkarteKomponente : dringendKomponente

                    Component {
                        id: sammelkarteKomponente

                        Sammelkarte {
                            eintraege: root.sammlung
                            offen: root.sammlungOffen && root.sammlung.length > 0
                            verborgen: root.verborgen
                            zeitpunkt: root.sammlungZeit
                            onSchliessen: {
                                root.gesehen(root.sammlung);
                                root.sammlungOffen = false;
                            }
                            onZentrale: root.zentraleOeffnen()
                            onGeklickt: eintrag => root.geklickt(eintrag)
                            onAktion: (eintrag, kennung) => root.aktion(eintrag, kennung)
                            // Ausgeblendet: Karte und Liste weg, damit nichts Unsichtbares bleibt
                            onAusgeblendet: {
                                if (root.sammlungOffen)
                                    return;
                                root.sammlungNummern = [];
                                root.entfernen("sammlung");
                            }
                        }
                    }

                    Component {
                        id: dringendKomponente

                        DringendKarte {
                            eintrag: karte.eintrag
                            verborgen: root.verborgen
                            onGeschlossen: root.gesehen([karte.eintrag])
                            onEntfernt: root.entfernen(karte.schluessel)
                            onGeklickt: root.geklickt(karte.eintrag)
                            onAktion: kennung => root.aktion(karte.eintrag, kennung)
                        }
                    }
                }
            }
        }
    }

    Zentrale {
        screen: root.bildschirm
    }
}
