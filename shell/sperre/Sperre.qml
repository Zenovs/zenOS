pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.theme
import qs.dienste
import qs.komponenten

// Sperrbildschirm: ext-session-lock (WlSessionLock) mit einer Fläche pro Bildschirm, Anmeldung über PAM.
//
// - Sperren: Oberflaeche.sperren(), IPC «sperre sperren», zen lock (Marker + IPC) und beim Start der
//   Shell, wenn der Marker $XDG_RUNTIME_DIR/zenos/gesperrt existiert (Absturz, Neustart, Neuladen).
// - Der Marker wird vor dem Sperren gesetzt und erst nach dem Entsperren gelöscht. Stirbt die Shell
//   dazwischen, hält labwc die Sperre, und die neu gestartete Shell sperrt über den Marker wieder.
// - Das Passwort wird nur an PAM weitergereicht (Dienst zenos-sperre unter <code>/system/pam) und das
//   Feld sofort geleert.
// - Während der Sperre ruht das automatische Neuladen der Oberfläche: Quickshell v0.3.1 stürzt ab, wenn es
//   bei gesetzter Sperre neu lädt (neue Sperrflächen vor dem Abbau der alten). Wurde die Oberfläche in der
//   Zwischenzeit geändert (z. B. zen update), lädt sie nach dem Entsperren neu.
// - Leitplanke (Code): Der Sperrbildschirm zeigt nie Inhalte, nur die Anzahl der Mitteilungen – keine
//   Vorschau, keine App-Namen.
Scope {
    id: root

    readonly property string markerPfad: Pfade.laufzeit + "/gesperrt"
    readonly property string pamOrdner: Pfade.code + "/system/pam"

    // Eingabe aller Bildschirme (getippt wird dort, wo der Tastaturfokus liegt)
    property string eingabe: ""
    property string meldung: ""
    property bool fehlerAnzeigen: false
    property bool pruefhinweis: false

    // Antwort, die auf die Frage von PAM wartet; wird beim Weiterreichen sofort geleert
    property string _antwort: ""
    property bool _geantwortet: false
    property bool _ausweichen: false
    // Die Oberfläche wurde während der Sperre geändert und lädt nach dem Entsperren neu
    property bool _neuLaden: false
    readonly property bool pruefe: pam.active && _geantwortet
    onPruefeChanged: {
        if (!pruefe)
            pruefhinweis = false;
    }
    // PAM fragt etwas anderes als das Passwort (z. B. einen Code): dann steht die Frage über dem Feld
    readonly property string frage: pam.active && pam.responseRequired && !_geantwortet ? pam.message.trim().replace(/:$/, "") : ""

    // Nie Inhalte: nur Zahlen aus dem Mitteilungsdienst (wartende und zugestellte ungelesene)
    readonly property int anzahlMitteilungen: Math.max(0, Mitteilungen.anzahlWartend) + Math.max(0, Mitteilungen.anzahlUngelesen)

    function sperren(): void {
        if (lock.locked)
            return;
        Quickshell.watchFiles = false;
        // Erst der Marker, dann die Sperre (siehe oben)
        markerDatei.setText(new Date().toISOString() + "\n");
        zustand.gesperrt = true;
        _zuruecksetzen();
        lock.locked = true;
        Quickshell.execDetached([Pfade.bin + "/zenos-1password-sperren"]);
    }

    function entsperrenVersuchen(): void {
        if (!lock.locked || root.eingabe.length === 0)
            return;
        if (pam.active) {
            // Weitere Frage von PAM direkt beantworten; während der Prüfung nichts annehmen
            if (pam.responseRequired && !root._geantwortet) {
                const antwort = root.eingabe;
                root.eingabe = "";
                root._geantwortet = true;
                pam.respond(antwort);
            }
            return;
        }
        root._antwort = root.eingabe;
        root.eingabe = "";
        root.meldung = "";
        root.fehlerAnzeigen = false;
        root._ausweichen = false;
        _pamStarten();
    }

    function _pamStarten(): void {
        pam.configDirectory = root._ausweichen ? "/etc/pam.d" : root.pamOrdner;
        pam.config = root._ausweichen ? "login" : "zenos-sperre";
        if (pam.start())
            return;
        if (!root._ausweichen) {
            // Ohne eigenen PAM-Dienst nicht aussperren: auf den Login-Dienst des Systems ausweichen
            console.warn("Sperre: PAM-Dienst zenos-sperre fehlt, weiche auf /etc/pam.d/login aus");
            root._ausweichen = true;
            _pamStarten();
            return;
        }
        root._antwort = "";
        _meldungZeigen("Anmeldung gerade nicht möglich.");
    }

    function _entsperren(): void {
        zustand.gesperrt = false;
        lock.locked = false;
        _zuruecksetzen();
        _aufraeumen();
    }

    // Nach dem Entsperren: geänderte Dateien der Oberfläche suchen (neuer als der Marker), dann den Marker
    // löschen und erst danach neu laden – sonst sperrt die neu geladene Oberfläche gleich wieder.
    function _aufraeumen(): void {
        root._neuLaden = false;
        if (!aenderungenSuchen.running)
            aenderungenSuchen.running = true;
    }

    function _zuruecksetzen(): void {
        if (pam.active)
            pam.abort();
        root.eingabe = "";
        root._antwort = "";
        root._geantwortet = false;
        root.meldung = "";
        root.fehlerAnzeigen = false;
    }

    function _meldungZeigen(text: string): void {
        root.meldung = text;
        root.fehlerAnzeigen = true;
    }

    // Die ersten beiden Kinder behalten ihre Reihenfolge: Beim Neuladen ordnet Quickshell alte und neue
    // Objekte eines Scope nach ihrer Position zu (die neue Sperre übernimmt die alte).
    PersistentProperties {
        id: zustand

        property bool gesperrt: false

        onReloaded: {
            if (gesperrt)
                root.sperren();
        }
    }

    WlSessionLock {
        id: lock

        onLockStateChanged: {
            // Beendet labwc die Sperre von sich aus (z. B. weil schon ein anderes Programm sperrt),
            // bleibt kein alter Marker liegen.
            if (!locked && zustand.gesperrt) {
                console.warn("Sperre: labwc hat die Sperre nicht übernommen oder beendet");
                zustand.gesperrt = false;
                root._zuruecksetzen();
                root._aufraeumen();
            }
        }

        WlSessionLockSurface {
            color: Theme.grund

            Item {
                id: inhalt

                anchors.fill: parent

                // Grosser Bogen als Wasserzeichen, sehr zurückhaltend
                Zeichen {
                    anchors.centerIn: parent
                    groesse: Math.round(Math.min(760, inhalt.height * 0.85))
                    strichbreite: 0.9
                    farbe: Theme.wasserzeichen
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: passwortFeld.fokussieren()
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 28

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.a2

                        // Zeilenhöhe 0.9 wie im Entwurf, Schrift mittig in der Zeile (wie line-height in CSS)
                        Item {
                            id: uhrZeile

                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitWidth: uhrText.implicitWidth
                            implicitHeight: Math.round(0.9 * Theme.groesseAnzeige)

                            FontMetrics {
                                id: uhrMass

                                font: uhrText.font
                            }

                            Text {
                                id: uhrText

                                y: Math.round((uhrZeile.implicitHeight - uhrMass.ascent - uhrMass.descent) / 2 + uhrMass.ascent - baselineOffset)
                                text: Qt.formatDateTime(uhr.date, "HH:mm")
                                color: Theme.text
                                font.family: Theme.schriftAnzeige
                                font.pixelSize: Theme.groesseAnzeige
                                font.letterSpacing: -0.01 * Theme.groesseAnzeige
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: uhr.date.toLocaleDateString(Qt.locale("de_CH"), "dddd, d. MMMM")
                            color: Theme.gedaempft
                            font.family: Theme.schriftText
                            font.pixelSize: 18
                        }
                    }

                    // Nur die Anzahl, nie Inhalte
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.anzahlMitteilungen > 0
                        // Innenabstand 10/18 plus 1-px-Rahmen
                        implicitWidth: pille.implicitWidth + 38
                        implicitHeight: pille.implicitHeight + 22
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
                                name: "glocke"
                                groesse: 14
                                strichbreite: 1.8
                                farbe: Theme.gedaempft
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.anzahlMitteilungen === 1 ? "1 Mitteilung" : root.anzahlMitteilungen + " Mitteilungen") + " · Inhalte erst nach dem Entsperren"
                                color: Theme.gedaempft
                                font.family: Theme.schriftText
                                font.pixelSize: Theme.groesseText
                            }
                        }
                    }

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 380
                        height: formular.implicitHeight + Theme.a5

                        Column {
                            id: formular

                            y: Theme.a5
                            width: parent.width
                            spacing: 10

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.frage.length > 0 ? root.frage : "Passwort"
                                color: Theme.gedaempft
                                font.family: Theme.schriftText
                                font.pixelSize: Theme.groesseLabel
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.a2

                                Eingabe {
                                    id: passwortFeld

                                    width: parent.width - knopf.width - parent.spacing
                                    passwort: !(pam.active && pam.responseRequired && pam.responseVisible)
                                    platzhalter: root.frage.length > 0 ? "" : "Passwort"
                                    fehler: root.fehlerAnzeigen
                                    nurLesen: root.pruefe
                                    maximaleLaenge: 1024
                                    onTextChanged: {
                                        if (text !== root.eingabe)
                                            root.eingabe = text;
                                        if (text.length > 0 && root.fehlerAnzeigen) {
                                            root.fehlerAnzeigen = false;
                                            root.meldung = "";
                                        }
                                    }
                                    onAccepted: root.entsperrenVersuchen()
                                    Keys.onEscapePressed: {
                                        root.eingabe = "";
                                        root.meldung = "";
                                        root.fehlerAnzeigen = false;
                                    }

                                    Connections {
                                        target: root

                                        function onEingabeChanged(): void {
                                            if (passwortFeld.text !== root.eingabe)
                                                passwortFeld.text = root.eingabe;
                                        }
                                    }
                                }

                                Knopf {
                                    id: knopf

                                    text: "Entsperren"
                                    variante: "primaer"
                                    enabled: !root.pruefe
                                    onClicked: root.entsperrenVersuchen()
                                }
                            }
                        }

                        // Unter dem Formular, aber ausserhalb seiner Höhe: nichts verschiebt sich
                        Text {
                            anchors.top: formular.bottom
                            anchors.topMargin: Theme.a3
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            text: root.meldung.length > 0 ? root.meldung : root.pruefhinweis ? "Wird geprüft …" : ""
                            color: root.fehlerAnzeigen ? Theme.text2 : Theme.gedaempft
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                            opacity: text.length > 0 ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.dauerKurz
                                    easing.type: Theme.kurve
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.a6
                    spacing: Theme.a2

                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "schloss"
                        groesse: 13
                        strichbreite: 1.8
                        farbe: Theme.gedaempft
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: System.einsPasswortInstalliert ? "zenOS gesperrt · 1Password gesperrt" : "zenOS gesperrt"
                        color: Theme.gedaempft
                        font.family: Theme.schriftMono
                        font.pixelSize: Theme.groesseKlein
                    }
                }
            }

            Component.onCompleted: passwortFeld.fokussieren()
        }
    }

    // Marker: beim Start (auch nach einem Absturz oder Neuladen) sofort sperren, wenn er existiert.
    // Legt zen lock ihn an, während die Shell läuft, sperrt sie ebenfalls (zusätzlich zur IPC).
    FileView {
        id: markerDatei

        path: root.markerPfad
        blockLoading: true
        blockWrites: true
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: root.sperren()
    }

    PamContext {
        id: pam

        onPamMessage: {
            if (responseRequired) {
                if (root._antwort.length > 0) {
                    const antwort = root._antwort;
                    root._antwort = "";
                    root._geantwortet = true;
                    respond(antwort);
                } else {
                    // Weitere Frage: die beantwortet der Mensch selbst
                    root._geantwortet = false;
                }
                return;
            }
            // Hinweise von PAM (z. B. gesperrtes Konto nach zu vielen Versuchen) zeigen
            if (messageIsError && message.trim().length > 0)
                root._meldungZeigen(message.trim());
        }

        onError: error => console.warn("Sperre: PAM:", PamError.toString(error))

        onCompleted: result => {
            const unbeantwortet = root._antwort.length > 0;
            root._geantwortet = false;
            if (result === PamResult.Success) {
                root._entsperren();
                return;
            }
            // PAM-Dienst fehlerhaft, bevor das Passwort weitergereicht war: einmal ausweichen
            if (result === PamResult.Error && unbeantwortet && !root._ausweichen) {
                console.warn("Sperre: PAM-Dienst zenos-sperre fehlerhaft, weiche auf /etc/pam.d/login aus");
                root._ausweichen = true;
                root._pamStarten();
                return;
            }
            root._antwort = "";
            if (result === PamResult.Failed) {
                if (!root.fehlerAnzeigen)
                    root._meldungZeigen("Das Passwort stimmt nicht.");
            } else if (result === PamResult.MaxTries) {
                root._meldungZeigen("Zu viele Versuche. Bitte kurz warten.");
            } else {
                root._meldungZeigen("Anmeldung gerade nicht möglich.");
            }
        }
    }

    Process {
        id: aenderungenSuchen

        command: ["find", "-L", Quickshell.shellDir, "-type", "f", "(", "-name", "*.qml", "-o", "-name", "*.js", "-o", "-name", "*.mjs", "-o", "-name", "qmldir", ")", "-newer", root.markerPfad, "-print", "-quit"]
        stdout: StdioCollector {
            id: geaenderteDatei
        }
        onRunningChanged: {
            if (running || lock.locked)
                return;
            root._neuLaden = geaenderteDatei.text.trim().length > 0;
            markerLoeschen.running = true;
        }
    }

    Process {
        id: markerLoeschen

        command: ["rm", "-f", "--", root.markerPfad]
        onRunningChanged: {
            if (running)
                return;
            // Inzwischen wieder gesperrt: Marker neu setzen
            if (lock.locked) {
                markerDatei.setText(new Date().toISOString() + "\n");
                return;
            }
            Quickshell.watchFiles = true;
            if (root._neuLaden) {
                console.info("Sperre: Oberfläche während der Sperre geändert, lade neu");
                Quickshell.reload(false);
            }
        }
    }

    // «Wird geprüft …» erst nach einer Weile, damit bei Erfolg nichts aufblitzt
    Timer {
        interval: 300
        running: root.pruefe
        onTriggered: root.pruefhinweis = true
    }

    SystemClock {
        id: uhr

        precision: SystemClock.Minutes
    }

    Connections {
        target: Oberflaeche

        function onSperrenAngefordert(): void {
            root.sperren();
        }
    }

    IpcHandler {
        target: "sperre"

        function sperren(): void {
            root.sperren();
        }

        // "gesperrt", sobald labwc die Sperre bestätigt hat, sonst "offen"
        function status(): string {
            return lock.secure ? "gesperrt" : "offen";
        }
    }

    Component.onCompleted: {
        // Blockierendes Lesen: Existiert der Marker, ist die Sperre gesetzt, bevor die Shell etwas zeigt
        markerDatei.text();
        if (markerDatei.loaded)
            sperren();
    }
}
