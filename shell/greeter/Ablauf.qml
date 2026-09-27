import QtQuick
import Quickshell
import Quickshell.Services.Greetd
import qs.dienste

// Anmeldung über greetd: Sitzung anlegen, Fragen von PAM beantworten, zenOS-Sitzung starten.
// Das Passwort bleibt im Eingabefeld, bis greetd danach fragt (antwortGebraucht); die Oberfläche
// reicht es dann weiter und leert das Feld. Es wird nie geloggt oder gespeichert.
Scope {
    id: root

    readonly property bool verfuegbar: Greetd.available
    // greetd arbeitet (prüft, startet) und braucht gerade keine Eingabe
    readonly property bool beschaeftigt: Greetd.state !== GreetdState.Inactive && !wartetAufEingabe
    // PAM stellt eine weitere Frage (z. B. einen Einmalcode)
    property bool wartetAufEingabe: false
    property string frage: ""
    property bool frageSichtbar: false
    // Rückmeldung unter dem Formular
    property string meldung: verfuegbar ? "" : "Kein Anmeldedienst (greetd) erreichbar."
    property bool meldungFehler: false

    // Die Oberfläche antwortet mit antworten(feld.text) und leert das Feld
    signal antwortGebraucht
    // Anmeldung abgelehnt oder abgebrochen: Feld leeren, Fokus zurück
    signal fehlgeschlagen

    property bool _antwortBereit: false
    property bool _ausListe: true

    // benutzer: Login-Name; ausListe: aus der Kontoliste gewählt (sonst eingetippt)
    function anmelden(benutzer: string, ausListe: bool): void {
        if (!verfuegbar) {
            _melden("Kein Anmeldedienst (greetd) erreichbar.", true);
            fehlgeschlagen();
            return;
        }
        if (Greetd.state !== GreetdState.Inactive || benutzer.length === 0)
            return;
        _ausListe = ausListe;
        _antwortBereit = true;
        _melden("", false);
        Greetd.createSession(benutzer);
    }

    function antworten(text: string): void {
        if (Greetd.state !== GreetdState.Authenticating)
            return;
        wartetAufEingabe = false;
        frage = "";
        frageSichtbar = false;
        Greetd.respond(text);
    }

    function abbrechen(): void {
        _zuruecksetzen();
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        if (verfuegbar)
            _melden("", false);
    }

    // Hinweis der Oberfläche in der Meldungszeile (z. B. «Bitte zuerst ein Konto wählen.»)
    function melden(text: string, fehler: bool): void {
        _melden(text, fehler);
    }

    function _zuruecksetzen(): void {
        _antwortBereit = false;
        wartetAufEingabe = false;
        frage = "";
        frageSichtbar = false;
    }

    function _melden(text: string, fehler: bool): void {
        meldung = text;
        meldungFehler = fehler;
    }

    // PAM-Fehler (Englisch, technisch) in eine verständliche Meldung übersetzen
    function _fehlertext(text: string): string {
        const t = (text ?? "").toLowerCase();
        if (t.includes("maxtries") || t.includes("too many") || t.includes("locked"))
            return "Zu viele Versuche. Bitte einen Moment warten und noch einmal versuchen.";
        if (t.includes("expired"))
            return "Dieses Konto ist abgelaufen.";
        if (t.includes("perm_denied") || t.includes("permission denied") || t.includes("acct_mgmt"))
            return "Dieses Konto darf sich hier nicht anmelden.";
        return _ausListe ? "Das Passwort stimmt nicht. Bitte noch einmal." : "Benutzername oder Passwort stimmt nicht.";
    }

    Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (responseRequired) {
                // Die erste verdeckte Frage ist das Passwort: es steht schon im Feld
                if (root._antwortBereit && !echoResponse) {
                    root._antwortBereit = false;
                    root.antwortGebraucht();
                    return;
                }
                root._antwortBereit = false;
                root.frage = message.trim();
                root.frageSichtbar = echoResponse;
                root.wartetAufEingabe = true;
            } else if (message.trim().length > 0) {
                root._melden(message.trim(), error);
            }
        }

        function onAuthFailure(message: string): void {
            // Meldung von PAM (ohne Passwort), hilft bei der Fehlersuche im Journal
            console.warn("Greeter: Anmeldung abgelehnt:", message);
            root._zuruecksetzen();
            root._melden(root._fehlertext(message), true);
            root.fehlgeschlagen();
        }

        function onError(message: string): void {
            console.warn("Greeter: greetd meldet einen Fehler:", message);
            root._zuruecksetzen();
            root._melden("Die Anmeldung ist fehlgeschlagen (greetd: " + message + ").", true);
            root.fehlgeschlagen();
        }

        function onReadyToLaunch(): void {
            root._zuruecksetzen();
            root._melden("Sitzung startet …", false);
            Greetd.launch([Pfade.code + "/scripts/bin/zenos-sitzung"], ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=zenos", "XDG_CURRENT_DESKTOP=labwc:wlroots"]);
        }
    }
}
