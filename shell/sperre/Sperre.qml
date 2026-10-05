pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.theme
import qs.dienste
import qs.komponenten
import "../dienste/energie.js" as EnergieLogik

// Sperrbildschirm: ext-session-lock (WlSessionLock) mit einer Fläche pro Bildschirm, Anmeldung über PAM.
//
// - Sperren: Oberflaeche.sperren(), IPC «sperre sperren», zen lock (Marker + IPC) und beim Start der
//   Shell, wenn der Marker $XDG_RUNTIME_DIR/zenos/gesperrt existiert (Absturz, Neustart, Neuladen).
// - Der Marker wird vor dem Sperren gesetzt und erst nach dem Entsperren gelöscht. Stirbt die Shell
//   dazwischen, hält labwc die Sperre, und die neu gestartete Shell sperrt über den Marker wieder.
// - Das Passwort wird nur an PAM weitergereicht (Dienst zenos-sperre unter <code>/system/pam) und das
//   Feld sofort geleert.
// - Offene Overlays (Befehlsfeld, Zentrale, Modus-/Zustandswahl, Menüs der Leiste) schliessen beim Sperren,
//   sonst hätte nach dem Entsperren nichts die Tastatur (siehe _overlaysSchliessen). Die Einrichtung bleibt
//   offen und gibt die Tastatur während der Sperre ab (Oberflaeche.gesperrt, gesetzt nur hier).
// - Während der Sperre ruht das automatische Neuladen der Oberfläche: Quickshell v0.3.1 stürzt ab, wenn es
//   bei gesetzter Sperre neu lädt (neue Sperrflächen vor dem Abbau der alten). Wurde die Oberfläche in der
//   Zwischenzeit geändert (z. B. zen update), lädt sie nach dem Entsperren neu und hält den Zeitpunkt in
//   $XDG_RUNTIME_DIR/zenos/oberflaeche-geladen fest (install.sh startet sie dann nicht nochmals neu). Läuft beim
//   Entsperren gerade eine Übernahme aus dem Kanal (Kanal.uebernahmeLaeuft), bleibt das Nachladen aus, und die Sperre
//   lädt nicht neu: Nach der Übernahme richtet Kanal die Benutzerteile ein und startet die Oberfläche neu, wenn nötig.
// - Leitplanke (Code): Der Sperrbildschirm zeigt nie Inhalte, nur die Anzahl der Mitteilungen – keine
//   Vorschau, keine App-Namen.
// - Bildschirm aus (Leitplanke: dunkel heisst gesperrt): bildschirmAusNachSperre Min. (1–10) nach der Sperre ohne
//   Eingabe geht der Bildschirm aus (Energie.bildschirm, zenos-bildschirm). Gezählt wird ab der Sperre, auch nach
//   Super+L, und ohne Rücksicht auf Idle-Hemmer (ein Video hinter der Sperre sieht niemand). zenos-idle schaltet
//   zusätzlich nach Sperre plus dieser Zeit ab, als Rückfallebene ohne Oberfläche. Jede Eingabe weckt ihn wieder.
// - Wecktaste: Die Taste, die einen dunklen Bildschirm weckt, landet nicht im Passwortfeld (sonst ein Fehlversuch
//   bei PAM). Verworfen wird genau eine Taste (Logik in dienste/energie.js). Dunkel ist die Sperre durch den
//   eigenen Aufruf von zenos-bildschirm oder dessen Meldung «sperre bildschirm aus», nie ungesperrt.
// - Neustart der Oberfläche (Absturz, Neuladen) bei dunklem Bildschirm: Beim Start fragt die Sperre
//   «zenos-bildschirm status». Ist es dunkel und gesperrt, gilt es als dunkel (Eingaben wecken, die Wecktaste wird
//   verworfen); ungesperrt geht der Bildschirm an. Entsperren schaltet ihn immer an: Dunkel heisst gesperrt.
// - Vorwarnung vor dem Ausschalten (dienste/Energie.qml): eine ruhige Zeile mit der Uhrzeit, ohne Sekunden. Das
//   Passwortfeld ist dabei zu sehen: Wer tippt, tippt ins Feld (die Eingabe bricht die Vorwarnung ab).
// - Ausschalten bei leerem Akku (zenos-argon, Geraet.akkuAusschaltenUm): dieselbe Zeile mit dem Akku-Symbol und der
//   Uhrzeit. Sie hat Vorrang, eine Taste bricht nicht ab (nur das Netzteil), und den Bildschirm schaltet sie nicht an.
// - Ein/Aus-Taste (IPC «sperre taste», von zenos-energie taste): Bildschirm an, wenn er dunkel ist oder eben geweckt
//   wurde, sonst sofort aus.
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
    // Beginn der Suche nach geänderten Dateien (Unix-Sekunden): Was vorher geändert wurde, lädt das Neuladen
    property real _suchBeginn: 0
    // sperren() läuft (das Signal sperrenAngefordert kommt dabei hierher zurück)
    property bool _sperrtGerade: false
    readonly property bool pruefe: pam.active && _geantwortet
    onPruefeChanged: {
        if (!pruefe)
            pruefhinweis = false;
    }
    // PAM fragt etwas anderes als das Passwort (z. B. einen Code): dann steht die Frage über dem Feld
    readonly property string frage: pam.active && pam.responseRequired && !_geantwortet ? pam.message.trim().replace(/:$/, "") : ""

    // Nie Inhalte: nur Zahlen aus dem Mitteilungsdienst (wartende und zugestellte ungelesene)
    readonly property int anzahlMitteilungen: Math.max(0, Mitteilungen.anzahlWartend) + Math.max(0, Mitteilungen.anzahlUngelesen)

    // Bildschirm und Wecktaste: { dunkel, gewecktUm, offen } aus energie.js
    property var _weck: EnergieLogik.weckzustand()
    readonly property bool dunkel: root._weck.dunkel === true
    // Uhrzeit des Ausschaltens während der Vorwarnung, z. B. «22:41» (leer: keine Vorwarnung)
    readonly property string ausschaltenUm: Energie.vorwarnungLaeuft && Energie.ausschaltenUm > 0 ? Qt.formatDateTime(new Date(Energie.ausschaltenUm), "HH:mm") : ""
    // Uhrzeit des Ausschaltens bei leerem Akku (zenos-argon), z. B. «22:41» (leer: keins)
    readonly property string akkuAusschaltenUm: Geraet.akkuAusschaltenUm > 0 ? Qt.formatDateTime(new Date(Geraet.akkuAusschaltenUm), "HH:mm") : ""
    // Zeile auf der Sperre: leerer Akku vor der Vorwarnung nach langer Sperre
    readonly property string vorwarnungText: EnergieLogik.vorwarnungText(akkuAusschaltenUm, ausschaltenUm)

    // Der Bildschirm ist aus bzw. wieder an (Meldung von zenos-bildschirm oder eigener Aufruf über Energie)
    function bildschirmGemeldet(was: string): void {
        if (was === "aus") {
            // Dunkel heisst gesperrt: ungesperrt gibt es keinen dunklen Zustand und keine Wecktaste
            if (lock.locked)
                root._weck = EnergieLogik.bildschirmDunkel(root._weck);
        } else if (was === "an") {
            root._weck = EnergieLogik.bildschirmHell(root._weck, Date.now());
        }
    }

    // Vor jeder Taste im Passwortfeld: true verwirft sie (die Taste, die den Bildschirm weckt). Ist es noch
    // dunkel, weckt die Taste ihn auch selbst (falls kein swayidle mit resume darauf wartet).
    function _wecktaste(): bool {
        const verwerfen = EnergieLogik.wecktasteVerwerfen(root._weck, Date.now());
        root._weck = EnergieLogik.wecktasteGesehen(root._weck);
        if (root.dunkel)
            Energie.bildschirm("an");
        return verwerfen;
    }

    // Ein/Aus-Taste kurz gedrückt, während gesperrt ist: "an" oder "aus" (wie es danach sein soll), "offen" ohne Sperre
    function taste(): string {
        if (!lock.locked)
            return "offen";
        const was = EnergieLogik.tasteGesperrt(root._weck, Date.now());
        if (was === "an") {
            if (root.dunkel)
                Energie.bildschirm("an");
        } else {
            // Wie Super+Shift+L: über zen energie aus (eine Eingabe weckt wieder)
            Energie.aus();
        }
        return was;
    }

    function sperren(): void {
        if (lock.locked || root._sperrtGerade)
            return;
        root._sperrtGerade = true;
        try {
            Quickshell.watchFiles = false;
            // Erst der Marker, dann die Sperre (siehe oben)
            markerDatei.setText(new Date().toISOString() + "\n");
            zustand.gesperrt = true;
            root._weck = EnergieLogik.weckzustand();
            _zuruecksetzen();
            lock.locked = true;
            // Ohne ext-session-lock bleibt locked false
            if (lock.locked)
                Oberflaeche.gesperrt = true;
            // Erst sperren, dann schliessen: Was beim Schliessen schiefgeht, hält die Sperre nicht auf.
            // Für labwc ist die Reihenfolge gleich, es gibt die Fläche auch während der Sperre frei.
            _overlaysSchliessen(true);
        } finally {
            root._sperrtGerade = false;
        }
        Quickshell.execDetached([Pfade.bin + "/zenos-1password-sperren"]);
    }

    // Overlays mit exklusivem Tastaturfokus (Befehlsfeld, Zentrale, Modus- und Zustandswahl, Menüs der
    // Leiste) schliessen. labwc gibt einer solchen Fläche den Fokus nach dem Entsperren nicht zurück und
    // fokussiert dann auch kein Fenster: Die Tastatur wirkte tot. Schliesst sie während der Sperre, gibt
    // labwc sie frei und fokussiert beim Entsperren wieder das letzte Fenster.
    // melden: auch das Signal sperrenAngefordert senden, auf das die Menüs der Leiste und die übrigen
    // Oberflächen schliessen – auf jedem Weg (IPC, zen lock, Marker), nicht nur über Oberflaeche.sperren().
    // Es kommt bei der Sperre selbst wieder an und endet an _sperrtGerade (auch wenn die Sperre nicht
    // zustande kam, lock.locked also false blieb).
    function _overlaysSchliessen(melden: bool): void {
        Oberflaeche.befehlsfeldOffen = false;
        Oberflaeche.zentraleOffen = false;
        Oberflaeche.modusWahlOffen = false;
        Oberflaeche.zustandWahlOffen = false;
        if (melden)
            Oberflaeche.sperrenAngefordert();
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
        root._weck = EnergieLogik.weckzustand();
        lock.locked = false;
        Oberflaeche.gesperrt = false;
        _zuruecksetzen();
        _aufraeumen();
        // Dunkel heisst gesperrt: Entsperrt ist der Bildschirm immer an, auch wenn die Sperre nichts von «aus» wusste
        // (z. B. nach einem Neustart der Oberfläche, blind entsperrt). Ist er schon an, schaltet der Helfer nichts.
        Energie.bildschirm("an");
    }

    // Nach dem Entsperren: geänderte Dateien der Oberfläche suchen (neuer als der Marker), dann den Marker
    // löschen und erst danach neu laden – sonst sperrt die neu geladene Oberfläche gleich wieder.
    function _aufraeumen(): void {
        root._neuLaden = false;
        if (!aenderungenSuchen.running) {
            root._suchBeginn = Math.floor(Date.now() / 1000);
            aenderungenSuchen.running = true;
        }
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
        // Neuladen durch die Sperre: Beginn der Suche davor (Unix-Sekunden, 0 = keins). Die neue Generation
        // schreibt ihn nach oberflaeche-geladen, erst wenn das Neuladen gelungen ist.
        property real geladenAb: 0

        onReloaded: {
            if (geladenAb > 0) {
                geladenDatei.setText(geladenAb.toFixed(0) + "\n");
                geladenAb = 0;
            }
            if (gesperrt)
                root.sperren();
        }
    }

    WlSessionLock {
        id: lock

        onLockStateChanged: {
            if (locked)
                return;
            Oberflaeche.gesperrt = false;
            // Beendet labwc die Sperre von sich aus (z. B. weil schon ein anderes Programm sperrt),
            // bleibt kein alter Marker liegen.
            if (zustand.gesperrt) {
                console.warn("Sperre: labwc hat die Sperre nicht übernommen oder beendet");
                zustand.gesperrt = false;
                root._weck = EnergieLogik.weckzustand();
                root._zuruecksetzen();
                root._aufraeumen();
                Energie.bildschirm("an");
            }
        }

        WlSessionLockSurface {
            color: Theme.grund

            Item {
                anchors.fill: parent

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

                    // Vorwarnung vor dem Ausschalten: ruhig, mit Uhrzeit statt Sekunden. Ein Systemzustand, kein Inhalt.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.vorwarnungText.length > 0
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
                                name: root.akkuAusschaltenUm.length > 0 ? "akku-leer" : "ausschalten"
                                groesse: 14
                                strichbreite: 1.8
                                farbe: root.akkuAusschaltenUm.length > 0 ? Theme.warnung : Theme.text2
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.vorwarnungText
                                color: Theme.text2
                                font.family: Theme.schriftText
                                font.pixelSize: Theme.groesseText
                            }
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
                                    // Die Taste, die einen dunklen Bildschirm weckt, landet nicht im Feld
                                    onVorTaste: event => {
                                        if (root._wecktaste())
                                            event.accepted = true;
                                    }
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

                // Zeichen 16 px einfarbig, auf ganzen Pixeln (sonst verschwimmt die Pixel-Variante)
                Row {
                    x: Math.round((parent.width - width) / 2)
                    y: Math.round(parent.height - Theme.a6 - height)
                    spacing: Theme.a2

                    ZenZeichen {
                        y: Math.round((parent.height - height) / 2)
                        groesse: 16
                        obenFarbe: Theme.gedaempft
                        einfarbig: true
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

    // Stand der geladenen Oberfläche nach einem Neuladen durch die Sperre (für install.sh, nur Schreiben)
    FileView {
        id: geladenDatei

        path: Pfade.laufzeit + "/oberflaeche-geladen"
        preload: false
        blockWrites: true
        printErrors: false

        onSaveFailed: error => console.warn("Sperre: oberflaeche-geladen nicht geschrieben:", FileViewError.toString(error))
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
            // Während einer Übernahme aus dem Kanal nicht: sonst lüde sie einen halben Stand
            Quickshell.watchFiles = !Kanal.uebernahmeLaeuft;
            if (root._neuLaden && Kanal.uebernahmeLaeuft) {
                console.info("Sperre: Oberfläche geändert, aber die Übernahme läuft noch; neu geladen wird danach");
            } else if (root._neuLaden) {
                console.info("Sperre: Oberfläche während der Sperre geändert, lade neu");
                zustand.geladenAb = root._suchBeginn;
                Quickshell.reload(false);
                // Gelungen, hat die neue Generation den Wert schon übernommen. Sonst läuft diese mit dem alten
                // Stand weiter, und es gilt der bisherige Zeitpunkt.
                zustand.geladenAb = 0;
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

    // Bildschirm aus nach der Sperre: Zeit ab der Sperre, ohne Rücksicht auf Idle-Hemmer. Eingabe weckt.
    IdleMonitor {
        enabled: lock.secure
        respectInhibitors: false
        timeout: Energie.bildschirmMinuten * 60
        onIsIdleChanged: {
            if (isIdle) {
                if (lock.secure)
                    Energie.bildschirm("aus");
            } else if (root.dunkel) {
                Energie.bildschirm("an");
            }
        }
    }

    // Wecken: Solange es dunkel ist, weckt jede Eingabe (Taste, Maus, Touchpad), auch wenn den Bildschirm jemand
    // anderes ausgeschaltet hat (Sofort-Aktion ohne zenos-idle). Scharf nach 1 s Ruhe; eine Taste davor weckt über
    // _wecktaste().
    IdleMonitor {
        enabled: lock.secure && root.dunkel
        respectInhibitors: false
        timeout: 1
        onIsIdleChanged: {
            if (!isIdle && root.dunkel)
                Energie.bildschirm("an");
        }
    }

    Connections {
        target: Energie

        function onBildschirmGeschaltet(was: string): void {
            root.bildschirmGemeldet(was);
        }
    }

    Connections {
        target: Oberflaeche

        function onSperrenAngefordert(): void {
            root.sperren();
        }

        // Während der Sperre öffnet sich kein Overlay (z. B. per IPC aus einer SSH-Sitzung): Hinter der
        // Sperre sieht es niemand, nach dem Entsperren hätte es keine Tastatur (siehe _overlaysSchliessen),
        // und die Zentrale zählte Mitteilungen als angesehen.
        function onBefehlsfeldOffenChanged(): void {
            if (lock.locked && Oberflaeche.befehlsfeldOffen)
                root._overlaysSchliessen(false);
        }
        function onZentraleOffenChanged(): void {
            if (lock.locked && Oberflaeche.zentraleOffen)
                root._overlaysSchliessen(false);
        }
        function onModusWahlOffenChanged(): void {
            if (lock.locked && Oberflaeche.modusWahlOffen)
                root._overlaysSchliessen(false);
        }
        function onZustandWahlOffenChanged(): void {
            if (lock.locked && Oberflaeche.zustandWahlOffen)
                root._overlaysSchliessen(false);
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

        // Meldung von zenos-bildschirm: "aus" kurz vor dem Abschalten, "an" danach. Ungesperrt bleibt es hell
        // (dunkel heisst gesperrt). Antwort: "aus" oder "an", wie die Sperre den Bildschirm sieht.
        function bildschirm(was: string): string {
            root.bildschirmGemeldet(was);
            return root.dunkel ? "aus" : "an";
        }

        // Ein/Aus-Taste (zenos-energie taste): "an", "aus" oder "offen" (nicht gesperrt, nichts getan)
        function taste(): string {
            return root.taste();
        }
    }

    // Beim Start: Ist der Bildschirm schon aus (die Oberfläche startete neu, während es gesperrt und dunkel war)? Dann
    // weiss die Sperre davon: Eingaben wecken, die Wecktaste wird verworfen. Ungesperrt geht er an.
    Process {
        id: startStatus

        command: [Pfade.bin + "/zenos-bildschirm", "status"]
        workingDirectory: Pfade.home
        stdout: StdioCollector {
            onStreamFinished: {
                const zeile = text.trim().split("\n").pop() ?? "";
                if (zeile !== "aus" && zeile !== "teils")
                    return;
                if (lock.locked) {
                    console.info("Sperre: Bildschirm beim Start schon aus, eine Eingabe weckt ihn");
                    root.bildschirmGemeldet("aus");
                } else {
                    console.info("Sperre: Bildschirm beim Start aus, aber nicht gesperrt: schalte ihn an");
                    Energie.bildschirm("an");
                }
            }
        }
    }

    Component.onCompleted: {
        // Blockierendes Lesen: Existiert der Marker, ist die Sperre gesetzt, bevor die Shell etwas zeigt
        markerDatei.text();
        if (markerDatei.loaded)
            sperren();
        startStatus.running = true;
    }
}
