pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.komponenten
import "../dienste/energie.js" as EnergieLogik

// Ein Bildschirm des Logins, gestaltet wie der Sperrbildschirm in Entwurf 2: grosse Uhrzeit, Datum, Konto,
// Formular, unten die Bildmarke. Formular, Knöpfe und Tastaturfokus nur auf einem Bildschirm.
// Ist der Bildschirm aus (Bildschirm.qml), weckt die erste Taste, der erste Klick oder die erste Berührung nur: Solange
// die Wecktaste aussteht, hat der Wecker den Tastaturfokus und der Klickfang liegt über allem. Beide verwerfen genau
// eine Eingabe, dann geht der Fokus dorthin zurück, wo er war. Wird die Wecktaste gehalten, verwirft das Formular
// ihre Wiederholungen, bis sie losgelassen wird (_gehalten). Was im Formular steht, bleibt unverändert.
PanelWindow {
    id: root

    required property Konten konten
    required property Ablauf ablauf
    required property Leerlauf leerlauf
    required property Bildschirm bildschirm
    property bool mitFormular: true
    // Ein Update aus dem Kanal läuft gerade: ruhige Zeile über dem Formular
    property bool updateLaeuft: false

    readonly property var _konto: konten.liste.length === 1 ? konten.liste[0] : null

    // Wecktaste: Fokus auf den Wecker, solange sie aussteht, danach zurück (sonst ins Formular). Geprüft wird «focus»,
    // nicht «activeFocus»: Auch wenn das Fenster gerade keinen Tastaturfokus hat, bleibt der Wecker nie hängen.
    function _weckerFokus(): void {
        if (!root.mitFormular)
            return;
        if (!root.bildschirm.wecktasteOffen) {
            root._weckerZurueck();
            return;
        }
        if (!wecker.focus) {
            const vorher = wecker.Window.activeFocusItem;
            wecker.vorher = vorher !== wecker ? vorher : null;
            wecker.forceActiveFocus();
        }
    }

    function _weckerZurueck(): void {
        if (!wecker.focus)
            return;
        const ziel = wecker.vorher;
        wecker.vorher = null;
        wecker.focus = false;
        if (ziel !== null && ziel.visible && ziel.enabled)
            ziel.forceActiveFocus();
        else
            formular.fokussieren();
    }

    // Vor jeder Taste in einem Feld des Formulars (Drücken und Loslassen): Hält man die Wecktaste fest, wiederholt der
    // Client sie, und die Wiederholungen kämen ins Feld (der Fokus ist schon zurück). Sie werden verworfen, bis die
    // Taste losgelassen wird. Nie eine andere Taste (energie.js, wecktasteGehalten).
    function _gehalten(event: KeyEvent, druck: bool): void {
        const r = EnergieLogik.wecktasteGehalten(wecker.gehalten, druck, event.nativeScanCode, event.isAutoRepeat);
        wecker.gehalten = r.gehalten;
        if (r.verwerfen)
            event.accepted = true;
    }

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: Theme.grund

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: mitFormular ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "zenos-greeter"

    SystemClock {
        id: uhr

        precision: SystemClock.Minutes
    }

    // Klick ins Leere: Fokus zurück ins Formular
    MouseArea {
        anchors.fill: parent
        enabled: root.mitFormular
        onClicked: formular.fokussieren()
    }

    Column {
        anchors.centerIn: parent
        spacing: 28

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // Zeilenhöhe 0.9 wie im Entwurf: Kasten 0.9 × Schriftgrösse, Schrift darin mittig (wie CSS)
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: zeit.implicitWidth
                implicitHeight: Math.round(Theme.groesseAnzeige * 0.9)

                FontMetrics {
                    id: zeitMass

                    font: zeit.font
                }

                Text {
                    id: zeit

                    y: Math.round((parent.height - zeitMass.ascent - zeitMass.descent) / 2)
                    text: Qt.formatTime(uhr.date, "HH:mm")
                    color: Theme.text
                    font.family: Theme.schriftAnzeige
                    font.pixelSize: Theme.groesseAnzeige
                    font.letterSpacing: -Theme.groesseAnzeige * 0.01
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.locale("de_DE").toString(uhr.date, "dddd, d. MMMM")
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: 18
            }
        }

        // Vorwarnung vor dem Ausschalten (Leerlauf im Akkubetrieb oder leerer Akku), wie auf dem Sperrbildschirm: ruhig,
        // mit Uhrzeit statt Sekunden, auf jedem Bildschirm
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.leerlauf.text.length > 0
            implicitWidth: vorwarnungZeile.implicitWidth + 38
            implicitHeight: vorwarnungZeile.implicitHeight + 22
            radius: Theme.radiusPille
            color: Theme.durchsichtig
            border.width: 1
            border.color: Theme.linie2

            Row {
                id: vorwarnungZeile

                anchors.centerIn: parent
                spacing: 10

                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.leerlauf.akkuLeer ? "akku-leer" : "ausschalten"
                    groesse: 14
                    strichbreite: 1.8
                    farbe: root.leerlauf.akkuLeer ? Theme.warnung : Theme.text2
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.leerlauf.text
                    textFormat: Text.PlainText
                    color: Theme.text2
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }
            }
        }

        // Update läuft (zenos-kanal übernimmt gerade den Code): dieselbe ruhige Pille, auf jedem Bildschirm
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.updateLaeuft
            implicitWidth: updateZeile.implicitWidth + 38
            implicitHeight: updateZeile.implicitHeight + 22
            radius: Theme.radiusPille
            color: Theme.durchsichtig
            border.width: 1
            border.color: Theme.linie2

            Row {
                id: updateZeile

                anchors.centerIn: parent
                spacing: 10

                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "info"
                    groesse: 14
                    strichbreite: 1.8
                    farbe: Theme.text2
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "zenOS wird aktualisiert. Mit der Anmeldung bitte warten, bis das fertig ist."
                    textFormat: Text.PlainText
                    color: Theme.text2
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }
            }
        }

        // Genau ein Konto: als Pille wie die Mitteilungszeile im Sperrbildschirm
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mitFormular && root._konto !== null
            implicitWidth: pille.implicitWidth + 36
            implicitHeight: pille.implicitHeight + 20
            radius: Theme.radiusPille
            color: Theme.durchsichtig
            border.width: 1
            border.color: Theme.linie2

            Row {
                id: pille

                anchors.centerIn: parent
                spacing: 10

                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "schloss"
                    groesse: 14
                    farbe: Theme.gedaempft
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Anmelden als " + (root._konto?.anzeige ?? "")
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }
            }
        }

        Item {
            visible: root.mitFormular
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: formular.implicitWidth
            implicitHeight: formular.implicitHeight + 24

            Formular {
                id: formular

                y: 24
                width: 380
                konten: root.konten
                ablauf: root.ablauf
                onVorTaste: (event, druck) => root._gehalten(event, druck)
            }
        }
    }

    // Unten die Bildmarke (48 px, unterer Stein im Standardakzent), rechts Neustart und Ausschalten
    ZenZeichen {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.a6
        groesse: 48
        akzent: Theme.standardAkzent
    }

    Energie {
        visible: root.mitFormular
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Theme.a5
        anchors.bottomMargin: Theme.a5
    }

    // Hält den Tastaturfokus, solange die Wecktaste aussteht, und verwirft die erste Taste (auch Return, Escape, Tab).
    // Ihr Loslassen landet danach im Formular und bewirkt dort nichts, ihre Wiederholungen verwirft es (_gehalten).
    Item {
        id: wecker

        // Wo der Fokus vorher war (zurück nach der Wecktaste)
        property Item vorher: null
        // Code der verworfenen Wecktaste, bis sie losgelassen ist (-1: keine)
        property int gehalten: -1

        Keys.onPressed: event => {
            event.accepted = true;
            wecker.gehalten = event.nativeScanCode;
            root.bildschirm.verworfen("Taste");
            // Spätestens jetzt zurück: nie mehr als eine Taste
            root._weckerZurueck();
        }
    }

    Connections {
        target: root.bildschirm

        function onWecktasteOffenChanged(): void {
            root._weckerFokus();
        }
    }

    // Klickfang über allem: Der Klick oder die Berührung, die den dunklen Bildschirm weckt, löst nichts aus (auch nicht
    // «Anmelden», «Neustart» oder «Ausschalten»). Nur solange die Wecktaste aussteht, sonst gehen Klicks durch.
    MouseArea {
        id: klickfang

        anchors.fill: parent
        z: 10
        enabled: root.bildschirm.wecktasteOffen || klickfang.pressed
        acceptedButtons: Qt.AllButtons
        onPressed: root.bildschirm.verworfen("Klick")
    }

    Component.onCompleted: {
        if (mitFormular)
            Qt.callLater(() => {
                formular.fokussieren();
                root._weckerFokus();
            });
    }
}
