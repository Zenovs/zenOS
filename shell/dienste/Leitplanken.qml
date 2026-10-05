pragma Singleton

import QtQuick
import Quickshell
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "../modi/zustandslogik.js" as Logik
import "energie.js" as EnergieLogik

// Leitplanken sind Code, nicht Konfiguration.
// Kein Modus, kein Zustand und keine Einstellung kann sie ändern oder abschalten:
// - Bei Bildschirmfreigabe bleiben Mitteilungsinhalte verborgen.
// - Der Sperrbildschirm zeigt nie Inhalte.
// - Die automatische Sperre lässt sich nicht abschalten (1–15 Minuten). Ein Idle-Hemmer (Video) darf sie
//   höchstens sperreTrotzHemmerMinuten aufhalten.
// - Dunkel heisst gesperrt: Der Bildschirm geht nur gesperrt aus, 1–10 Minuten nach der Sperre
//   (zenos-bildschirm sperrt immer zuerst).
// - Ausschalten frühestens 30 Minuten nach der Sperre und immer mit 60 s Vorwarnung.
// Die Werte stehen eingefroren in modi/zustandslogik.js (dort auch getestet), die Logik in energie.js.
Singleton {
    readonly property bool inhalteBeiFreigabe: Logik.LEITPLANKEN.inhalteBeiFreigabe
    readonly property bool sperreZeigtInhalte: Logik.LEITPLANKEN.sperreZeigtInhalte
    readonly property bool sperreAbschaltbar: Logik.LEITPLANKEN.sperreAbschaltbar
    readonly property int sperreMinutenMin: Logik.LEITPLANKEN.sperreMinutenMin
    readonly property int sperreMinutenMax: Logik.LEITPLANKEN.sperreMinutenMax
    readonly property int sperreTrotzHemmerMinuten: Logik.LEITPLANKEN.sperreTrotzHemmerMinuten

    readonly property bool bildschirmNurGesperrt: Logik.LEITPLANKEN.bildschirmNurGesperrt
    readonly property int bildschirmAusNachSperreMin: Logik.LEITPLANKEN.bildschirmAusNachSperreMin
    readonly property int bildschirmAusNachSperreMax: Logik.LEITPLANKEN.bildschirmAusNachSperreMax
    readonly property int ausschaltenMinutenMin: Logik.LEITPLANKEN.ausschaltenMinutenMin
    readonly property int ausschaltenMinutenMax: Logik.LEITPLANKEN.ausschaltenMinutenMax
    readonly property int vorwarnungSekunden: Logik.LEITPLANKEN.vorwarnungSekunden
    readonly property int akkuAusschaltenProzent: Logik.LEITPLANKEN.akkuAusschaltenProzent

    // Inhalte gerade verbergen? (Bildschirm wird geteilt)
    readonly property bool inhalteVerbergen: Freigabe.aktiv && !inhalteBeiFreigabe

    // Text für die Einstellungen
    readonly property string hinweis: "Bei Bildschirmfreigabe bleiben Mitteilungsinhalte immer verborgen, und die automatische Sperre bleibt aktiv. Kein Modus und kein Zustand kann das ändern."
    // Text für die Seite «Energie»
    readonly property string energieHinweis: "Die automatische Sperre bleibt immer aktiv, nichts auf dieser Seite verzögert sie. Auch ein Video hält sie höchstens " + sperreTrotzHemmerMinuten + " Min. ohne Eingabe auf. Der Bildschirm geht nur aus, wenn zenOS gesperrt ist, und zenOS schaltet nie ohne " + vorwarnungSekunden + " s Vorwarnung aus."

    // Minuten bis zur automatischen Sperre, immer 1–15 (Standard 5)
    function sperreMinuten(wunsch: var): int {
        return Logik.sperreMinuten(wunsch);
    }

    // Minuten nach der Sperre, bis der Bildschirm ausgeht, immer 1–10 (Standard 1)
    function bildschirmMinuten(wunsch: var): int {
        return EnergieLogik.bildschirmMinuten(wunsch);
    }

    // Minuten gesperrt, bis zenOS ausschaltet, immer 30–240 (Standard 60)
    function ausschaltenMinuten(wunsch: var): int {
        return EnergieLogik.ausschaltenMinuten(wunsch);
    }

    // Erzwingt die Leitplanken in einem wirksamen Zustand (zuletzt angewendet)
    function anwenden(zustand: var): var {
        return Logik.leitplankenAnwenden(zustand, {
            freigabe: Freigabe.aktiv
        });
    }
}
