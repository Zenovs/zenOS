pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.theme
import qs.dienste
import qs.komponenten

// polkit-Agent der Sitzung: fragt das Passwort ab, wenn ein Programm Rechte verlangt, die polkit nur nach einer
// Anmeldung gibt – etwa «Firewall ausschalten» aus den Einstellungen (pkexec), später auch NetworkManager.
//
// - Ein ruhiger Dialog mittig über abgedunkeltem Hintergrund (kein Weichzeichnen) mit exklusivem
//   Tastaturfokus. Er zeigt, was polkit bestätigen lässt (Nachricht der Aktion, darunter ihre Kennung) und für
//   welches Konto. Enter bestätigt, Esc oder «Abbrechen» bricht ab; ein Klick daneben tut nichts.
// - Das Passwort geht nur an polkit (AuthFlow.submit). Das Feld wird beim Weiterreichen sofort geleert; das
//   Passwort steht in keiner Eigenschaft, wird nie gespeichert und nie protokolliert. polkit prüft es über PAM
//   in einem eigenen Prozess (polkit-agent-helper-1); zenOS sieht nur «stimmt» oder «stimmt nicht».
// - Falsches Passwort: polkit beginnt von selbst eine neue Runde; der Dialog bleibt offen, zeigt ruhig «Das
//   Passwort stimmt nicht.» (kein Wackeln) und wartet auf den nächsten Versuch.
// - Sperre: Während der Sperre gibt es keine Dialoge. Eine offene Anfrage bricht beim Sperren ab, eine neue
//   während der Sperre sofort. Begründung: Hinter der Sperre sieht sie niemand; nach dem Entsperren hätte ein
//   nachgereichter Dialog keine Tastatur (labwc gibt sie einer exklusiven Fläche nicht zurück, siehe
//   sperre/Sperre.qml), und eine Passwortfrage direkt nach dem Entsperren lädt dazu ein, das Passwort aus
//   Gewohnheit ein zweites Mal einzutippen, ohne zu lesen, wofür. Das Programm erfährt «abgebrochen» und kann
//   neu fragen; der Schalter in den Einstellungen springt zurück.
// - Solange der Dialog offen ist, bleiben Befehlsfeld, Zentrale und Modus-/Zustandswahl zu (sonst stritten
//   zwei exklusive Flächen um die Tastatur).
// - Mehrere Anfragen nacheinander stellt Quickshell in eine Reihe; der Dialog zeigt jeweils die vorderste.
// - IPC «polkit»: status (offen/zu), agent (angemeldet/nicht angemeldet), abbrechen.
Scope {
    id: root

    // Laufende Anfrage (AuthFlow) oder null
    readonly property var anfrage: agent.flow
    readonly property bool offen: !!anfrage && !Oberflaeche.gesperrt
    readonly property bool agentAngemeldet: agent.isRegistered

    // Angezeigtes bleibt beim Ausblenden stehen (die Anfrage ist dann schon weg), damit nichts springt
    property string titel: ""
    property string erklaerung: ""
    property string aktion: ""
    property string konto: ""

    property string meldung: ""
    property bool fehlerAnzeigen: false
    // Antwort ist bei polkit, bis es neu fragt oder die Anfrage endet
    property bool _geantwortet: false
    readonly property bool pruefe: !!anfrage && _geantwortet && !anfrage.isResponseRequired
    property bool pruefhinweis: false
    onPruefeChanged: {
        if (!pruefe)
            pruefhinweis = false;
    }

    // polkit fragt etwas anderes als ein Passwort (Antwort sichtbar, z. B. ein Code): die Frage über dem Feld
    readonly property bool frageSichtbar: !!anfrage && anfrage.isResponseRequired && anfrage.responseVisible
    readonly property string frage: frageSichtbar ? String(anfrage.inputPrompt ?? "").trim().replace(/:$/, "") : ""

    function bestaetigen(): void {
        const a = root.anfrage;
        if (!a || !a.isResponseRequired || root._geantwortet)
            return;
        // Das Passwort nur lokal halten und das Feld sofort leeren
        const wert = feld.text;
        feld.leeren();
        if (wert.length === 0)
            return;
        root._geantwortet = true;
        root.meldung = "";
        root.fehlerAnzeigen = false;
        a.submit(wert);
    }

    function abbrechen(): void {
        feld.leeren();
        const a = root.anfrage;
        if (a && !a.isCompleted)
            a.cancelAuthenticationRequest();
    }

    function _neueAnfrage(): void {
        const a = agent.flow;
        if (!a)
            return;
        feld.leeren();
        if (Oberflaeche.gesperrt) {
            console.info("polkit: Anfrage während der Sperre abgebrochen:", a.actionId);
            a.cancelAuthenticationRequest();
            return;
        }
        _kontoWaehlen(a);
        // Erster Satz als Titel, der Rest als Erklärung (polkit liefert nur eine Nachricht)
        const nachricht = String(a.message ?? "").trim();
        const ende = nachricht.search(/[.!?](\s|$)/);
        root.titel = ende > 0 ? nachricht.slice(0, ende) : nachricht;
        root.erklaerung = ende > 0 ? nachricht.slice(ende + 1).trim() : "";
        root.aktion = String(a.actionId ?? "");
        root.konto = _kontoName(a.selectedIdentity);
        root.meldung = "";
        root.fehlerAnzeigen = false;
        root._geantwortet = false;
        _overlaysSchliessen();
    }

    // polkit bietet die Konten an, die bestätigen dürfen (bei Ubuntu die Gruppe sudo). Das eigene zuerst.
    function _kontoWaehlen(a: var): void {
        const ich = Quickshell.env("USER") ?? "";
        const liste = a.identities ?? [];
        for (let i = 0; i < liste.length; i++) {
            const k = liste[i];
            if (k && !k.isGroup && _kontoName(k) === ich) {
                if (a.selectedIdentity !== k)
                    a.selectedIdentity = k;
                return;
            }
        }
    }

    // Anmeldename (nicht der Anzeigename: der kann von cloud-init stammen, z. B. «Ubuntu»)
    function _kontoName(k: var): string {
        if (!k)
            return "";
        const name = String(k.string ?? k.name ?? "").trim();
        return name !== "" ? name : String(k.displayName ?? "").trim();
    }

    function _overlaysSchliessen(): void {
        Oberflaeche.befehlsfeldOffen = false;
        Oberflaeche.zentraleOffen = false;
        Oberflaeche.modusWahlOffen = false;
        Oberflaeche.zustandWahlOffen = false;
    }

    // Nach dem Neuladen der Oberfläche übernimmt Quickshell den Agenten samt laufender Anfrage, ohne das Signal
    // erneut zu senden: Titel, Konto und Sperre dann hier nachziehen.
    Component.onCompleted: {
        if (agent.flow)
            _neueAnfrage();
    }

    PolkitAgent {
        id: agent

        onAuthenticationRequestStarted: root._neueAnfrage()
        onIsRegisteredChanged: {
            if (isRegistered)
                console.info("polkit: Agent angemeldet");
        }
    }

    Connections {
        target: root.anfrage
        ignoreUnknownSignals: true

        function onAuthenticationFailed(): void {
            root._geantwortet = false;
            const a = root.anfrage;
            const zusatz = a && a.supplementaryIsError ? String(a.supplementaryMessage ?? "").trim() : "";
            root.meldung = zusatz !== "" ? zusatz : "Das Passwort stimmt nicht.";
            root.fehlerAnzeigen = true;
            feld.fokussieren();
        }

        // Neue Frage von polkit (z. B. nach einem Fehlversuch): die Antwort davor ist erledigt
        function onIsResponseRequiredChanged(): void {
            if (root.anfrage && root.anfrage.isResponseRequired)
                root._geantwortet = false;
        }

        function onSelectedIdentityChanged(): void {
            if (root.anfrage)
                root.konto = root._kontoName(root.anfrage.selectedIdentity);
        }
    }

    Connections {
        target: Oberflaeche

        // Jeder Weg zur Sperre (Super+L, zen lock, swayidle, Marker) sendet sperrenAngefordert
        function onSperrenAngefordert(): void {
            root.abbrechen();
        }
        function onGesperrtChanged(): void {
            if (Oberflaeche.gesperrt)
                root.abbrechen();
        }
        function onBefehlsfeldOffenChanged(): void {
            if (root.offen && Oberflaeche.befehlsfeldOffen)
                root._overlaysSchliessen();
        }
        function onZentraleOffenChanged(): void {
            if (root.offen && Oberflaeche.zentraleOffen)
                root._overlaysSchliessen();
        }
        function onModusWahlOffenChanged(): void {
            if (root.offen && Oberflaeche.modusWahlOffen)
                root._overlaysSchliessen();
        }
        function onZustandWahlOffenChanged(): void {
            if (root.offen && Oberflaeche.zustandWahlOffen)
                root._overlaysSchliessen();
        }
    }

    // «Wird geprüft …» erst nach einer Weile, damit bei Erfolg nichts aufblitzt (PAM wartet nach einem
    // Fehlversuch rund 2 s)
    Timer {
        interval: 300
        running: root.pruefe
        onTriggered: root.pruefhinweis = true
    }

    IpcHandler {
        target: "polkit"

        // "offen", solange eine Anfrage auf Bestätigung wartet, sonst "zu"
        function status(): string {
            return root.anfrage ? "offen" : "zu";
        }

        // "angemeldet", wenn polkit diese Oberfläche als Agent der Sitzung kennt
        function agent(): string {
            return root.agentAngemeldet ? "angemeldet" : "nicht angemeldet";
        }

        // Laufende Anfrage abbrechen (das Programm erfährt «abgebrochen»)
        function abbrechen(): void {
            root.abbrechen();
        }
    }

    PanelWindow {
        id: fenster

        // Ohne feste Ausgabe wählt labwc den Bildschirm (wie beim Befehlsfeld)
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
        WlrLayershell.namespace: "zenos-polkit"

        onVisibleChanged: {
            if (visible)
                feld.fokussieren();
            else
                feld.leeren();
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

            // Abgedunkelter Hintergrund (kein Weichzeichnen). Ein Klick daneben bricht nicht ab: Eine
            // Bestätigung soll nicht aus Versehen verschwinden.
            Rectangle {
                anchors.fill: parent
                color: Theme.abdunkeln

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: feld.fokussieren()
                }
            }

            Rectangle {
                id: karte

                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                width: Math.min(460, parent.width - 2 * Theme.a4)
                height: spalte.implicitHeight + fuss.height + 2
                radius: Theme.radiusBefehlsfeld
                color: Theme.flaeche
                border.width: 1
                border.color: Theme.linie2

                // Klicks auf die Karte selbst fallen nicht durch
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                }

                FocusScope {
                    anchors.fill: parent
                    focus: true

                    Keys.onEscapePressed: root.abbrechen()

                    Column {
                        id: spalte

                        x: 28
                        y: 1
                        width: parent.width - 56
                        topPadding: 26
                        bottomPadding: 24
                        spacing: 0

                        // Bildmarke wie in Sperre und Login: 16 px, einfarbig, auf ganzen Pixeln
                        Row {
                            spacing: Theme.a2

                            ZenZeichen {
                                y: Math.round((parent.height - height) / 2)
                                groesse: 16
                                obenFarbe: Theme.gedaempft
                                einfarbig: true
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Bestätigung nötig"
                                color: Theme.gedaempft
                                font.family: Theme.schriftMono
                                font.pixelSize: Theme.groesseKlein
                            }
                        }

                        Item {
                            width: 1
                            height: Theme.a4
                        }

                        // Was bestätigt wird (Nachricht der polkit-Aktion, reiner Text)
                        Text {
                            width: parent.width
                            text: root.titel !== "" ? root.titel : "Ein Programm verlangt Administratorrechte"
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            lineHeight: 1.05
                            color: Theme.text
                            font.family: Theme.schriftAnzeige
                            font.pixelSize: text.length > 32 ? Math.round(Theme.groesseTitel * 2 / 3) : Theme.groesseTitel
                        }

                        Item {
                            visible: root.erklaerung !== ""
                            width: 1
                            height: Theme.a2
                        }

                        Text {
                            visible: root.erklaerung !== ""
                            width: parent.width
                            text: root.erklaerung
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            lineHeightMode: Text.FixedHeight
                            lineHeight: Math.round(font.pixelSize * 1.45)
                            color: Theme.text2
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseText
                        }

                        Item {
                            visible: root.aktion !== ""
                            width: 1
                            height: Theme.a2
                        }

                        // Kennung der polkit-Aktion: was genau erlaubt wird
                        Text {
                            visible: root.aktion !== ""
                            width: parent.width
                            text: root.aktion
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: Theme.gedaempft
                            font.family: Theme.schriftMono
                            font.pixelSize: Theme.groesseKlein
                        }

                        Item {
                            width: 1
                            height: Theme.a5
                        }

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.frage !== "" ? root.frage : root.konto !== "" ? "Passwort von " + root.konto : "Passwort"
                            textFormat: Text.PlainText
                            color: Theme.gedaempft
                            font.family: Theme.schriftText
                            font.pixelSize: Theme.groesseLabel
                        }

                        Item {
                            width: 1
                            height: Theme.a2
                        }

                        Eingabe {
                            id: feld

                            width: parent.width
                            focus: true
                            passwort: !root.frageSichtbar
                            platzhalter: root.frage !== "" ? "" : "Passwort"
                            fehler: root.fehlerAnzeigen
                            nurLesen: root.pruefe
                            maximaleLaenge: 1024
                            onTextChanged: {
                                if (text.length > 0 && root.fehlerAnzeigen) {
                                    root.fehlerAnzeigen = false;
                                    root.meldung = "";
                                }
                            }
                            onAccepted: root.bestaetigen()
                        }

                        // Meldung unter dem Feld; die Zeile ist immer reserviert, damit nichts springt
                        Item {
                            width: parent.width
                            height: Theme.a3 + meldungText.font.pixelSize + Theme.a2

                            Text {
                                id: meldungText

                                y: Theme.a3
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.meldung !== "" ? root.meldung : root.pruefhinweis ? "Wird geprüft …" : ""
                                textFormat: Text.PlainText
                                color: root.fehlerAnzeigen ? Theme.text2 : Theme.gedaempft
                                font.family: Theme.schriftText
                                font.pixelSize: Theme.groesseLabel
                                opacity: text !== "" ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.dauerKurz
                                        easing.type: Theme.kurve
                                    }
                                }
                            }
                        }

                        Item {
                            width: 1
                            height: Theme.a3
                        }

                        Row {
                            anchors.right: parent.right
                            spacing: Theme.a3

                            Knopf {
                                variante: "sekundaer"
                                text: "Abbrechen"
                                onClicked: root.abbrechen()
                            }

                            Knopf {
                                variante: "primaer"
                                text: "Bestätigen"
                                enabled: !root.pruefe
                                onClicked: root.bestaetigen()
                            }
                        }
                    }

                    // Fusszeile mit den Tasten (wie im Befehlsfeld)
                    Item {
                        id: fuss

                        anchors.top: spalte.bottom
                        x: 1
                        width: parent.width - 2
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
                            x: 27
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 20

                            Repeater {
                                model: ["↵ bestätigen", "Esc abbrechen"]

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
