pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten

// App-Übersicht im Befehlsfeld (Klick auf das Zeichen der Leiste): alle installierten Apps als Raster aus
// Kacheln, in der Reihenfolge von apps. Die Spaltenzahl folgt der Breite (Kacheln mindestens 112 px breit,
// 104 px hoch). Braucht das Raster mehr Platz, als das Befehlsfeld hat, scrollt es. Ohne Apps ein ruhiger
// Leerzustand mit «Apps installieren».
// Fokus und Tasten bleiben beim Befehlsfeld (die Eingabe behält den Fokus); es ruft bewegen(), anfang() und
// einblenden(). Nur die sichtbaren Kacheln existieren (GridView).
Item {
    id: root

    // Apps wie Befehlsfeld._apps ({id, name, icon, buchstabe, webApp, …}), schon sortiert
    property var apps: []
    property int auswahl: 0
    // Die Auswahl kommt von der Tastatur: mit Fokusrahmen. Die Maus wählt ohne.
    property bool tastatur: false

    // Klick auf eine Kachel; Klick auf «Apps installieren» (nur ohne Apps)
    signal ausgefuehrt(int index)
    signal installieren
    // an alle Kacheln: jetzt einblenden (siehe einblenden())
    signal einblendenGestartet

    readonly property int spalten: Math.max(1, Math.floor((width - 2 * _rand) / _kachelBreite))
    // Höhe ohne Scrollen; das Befehlsfeld wächst damit bis zu seiner Höchsthöhe
    readonly property real inhaltHoehe: apps.length > 0 ? gitter.y + Math.ceil(apps.length / spalten) * _kachelHoehe + _unten : leer.implicitHeight + 2 * Theme.a5
    // Zeilen, die auf einmal sichtbar sind (Bild↑/↓)
    readonly property int seitenZeilen: Math.max(1, Math.floor(gitter.height / _kachelHoehe))

    readonly property int _rand: 12
    readonly property int _kachelBreite: 112
    readonly property int _kachelHoehe: 104
    readonly property int _unten: 8
    // Staffel beim Einblenden: höchstens 8 Schritte, damit alles in Theme.dauerMax fertig ist
    // (letzte Kachel: 8 × Schritt Verzögerung + Theme.dauerKurz)
    readonly property int _staffel: Math.max(0, Math.floor((Theme.dauerMax - Theme.dauerKurz) / 8))
    // true, solange das Einblenden läuft: Kacheln, die jetzt erst entstehen, blenden mit ein
    property bool _blendet: false

    // Auswahl bewegen: dx Kacheln nach links/rechts (über Zeilen hinweg), dy Zeilen nach oben/unten.
    // Unter einer Kachel ist nichts mehr, aber es gibt noch eine Zeile: zur letzten App.
    function bewegen(dx: int, dy: int): void {
        const n = apps.length;
        if (n === 0)
            return;
        tastatur = true;
        let i = Math.max(0, Math.min(n - 1, auswahl));
        if (dx !== 0)
            i = Math.max(0, Math.min(n - 1, i + dx));
        if (dy > 0) {
            const zeile = Math.min(Math.floor((n - 1) / spalten), Math.floor(i / spalten) + dy);
            i = Math.min(n - 1, zeile * spalten + i % spalten);
        } else if (dy < 0) {
            i = Math.max(0, Math.floor(i / spalten) + dy) * spalten + i % spalten;
        }
        auswahl = i;
        sichtbarMachen();
    }

    // Ausgewählte Kachel ganz zeigen (ohne Animation, wie die Liste des Befehlsfelds)
    function sichtbarMachen(): void {
        if (auswahl < spalten)
            gitter.positionViewAtBeginning();
        else
            gitter.positionViewAtIndex(auswahl, GridView.Contain);
    }

    function anfang(): void {
        gitter.positionViewAtBeginning();
    }

    // Kacheln von oben links her einblenden (Richtung Zeichen): je Diagonale Theme.dauerMax − Theme.dauerKurz
    // durch 8 später, jede in Theme.dauerKurz. Alles zusammen dauert höchstens Theme.dauerMax.
    function einblenden(): void {
        _blendet = true;
        blendUhr.restart();
        einblendenGestartet();
    }

    function verzoegerung(index: int): int {
        return Math.min(Math.floor(index / spalten) + index % spalten, 8) * _staffel;
    }

    // Ist ein Wort des Namens breiter als die Zeile? (Bindestriche zählen als Trennstelle wie beim Umbruch)
    function _wortZuBreit(name: var, breite: real): bool {
        return String(name ?? "").split(/[\s-]+/).some(w => namenMetrik.advanceWidth(w) > breite);
    }

    FontMetrics {
        id: namenMetrik

        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseLabel
    }

    Timer {
        id: blendUhr

        interval: Theme.dauerMax
        onTriggered: root._blendet = false
    }

    Abschnittstitel {
        id: titel

        visible: root.apps.length > 0
        x: 20
        y: 10
        width: parent.width - 40
        text: "Apps"
    }

    GridView {
        id: gitter

        x: Math.floor((root.width - width) / 2)
        y: titel.y + titel.implicitHeight + 4
        width: root.spalten * cellWidth
        height: Math.max(0, root.height - y)
        cellWidth: Math.floor((root.width - 2 * root._rand) / root.spalten)
        cellHeight: root._kachelHoehe
        bottomMargin: root._unten
        visible: root.apps.length > 0
        model: root.apps
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight + bottomMargin > height
        // Tasten und Scrollen zur Auswahl steuert das Befehlsfeld (bewegen, sichtbarMachen)
        keyNavigationEnabled: false
        highlightFollowsCurrentItem: false
        currentIndex: -1

        delegate: Kachel {
            id: kachel

            required property var modelData
            required property int index

            width: gitter.cellWidth
            height: gitter.cellHeight
            app: kachel.modelData
            einzeilig: root._wortZuBreit(kachel.modelData?.name, kachel.namenBreite)
            gewaehlt: root.auswahl === kachel.index
            fokus: root.tastatur && root.auswahl === kachel.index
            zeigerWaehlt: !root._blendet
            onGezeigt: {
                root.tastatur = false;
                root.auswahl = kachel.index;
            }
            onAusgefuehrt: {
                root.auswahl = kachel.index;
                root.ausgefuehrt(kachel.index);
            }

            Component.onCompleted: {
                if (root._blendet)
                    kachel.einblenden(root.verzoegerung(kachel.index));
            }

            Connections {
                target: root

                function onEinblendenGestartet(): void {
                    kachel.einblenden(root.verzoegerung(kachel.index));
                }
            }
        }
    }

    // Keine App installiert: Zeichen 32 px einfarbig, Hinweis und der Weg zur Installation (Enter genügt)
    Column {
        id: leer

        visible: root.apps.length === 0
        x: Math.round((parent.width - width) / 2)
        y: Theme.a5
        spacing: Theme.a3

        ZenZeichen {
            x: Math.round((leer.width - width) / 2)
            groesse: 32
            obenFarbe: Theme.gedaempft
            einfarbig: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Noch keine Apps installiert"
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: installierenKnopf.implicitWidth
            height: installierenKnopf.implicitHeight + Theme.a1

            Knopf {
                id: installierenKnopf

                y: Theme.a1
                variante: "sekundaer"
                symbol: "plus"
                text: "Apps installieren"
                activeFocusOnTab: false
                onClicked: root.installieren()

                // Enter löst ihn aus (die Eingabe des Befehlsfelds behält den Fokus)
                Fokusrahmen {
                    aktiv: true
                    eckenRadius: Theme.radiusFeld
                }
            }
        }
    }
}
