pragma Singleton

import QtQuick
import Quickshell
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "../modi/zustandslogik.js" as Logik

// Leitplanken sind Code, nicht Konfiguration.
// Kein Modus, kein Zustand und keine Einstellung kann sie ändern oder abschalten:
// - Bei Bildschirmfreigabe bleiben Mitteilungsinhalte verborgen.
// - Der Sperrbildschirm zeigt nie Inhalte.
// - Die automatische Sperre lässt sich nicht abschalten (1–15 Minuten).
// Die Werte stehen eingefroren in modi/zustandslogik.js (dort auch getestet).
Singleton {
    readonly property bool inhalteBeiFreigabe: Logik.LEITPLANKEN.inhalteBeiFreigabe
    readonly property bool sperreZeigtInhalte: Logik.LEITPLANKEN.sperreZeigtInhalte
    readonly property bool sperreAbschaltbar: Logik.LEITPLANKEN.sperreAbschaltbar
    readonly property int sperreMinutenMin: Logik.LEITPLANKEN.sperreMinutenMin
    readonly property int sperreMinutenMax: Logik.LEITPLANKEN.sperreMinutenMax

    // Inhalte gerade verbergen? (Bildschirm wird geteilt)
    readonly property bool inhalteVerbergen: Freigabe.aktiv && !inhalteBeiFreigabe

    // Text für die Einstellungen
    readonly property string hinweis: "Bei Bildschirmfreigabe bleiben Mitteilungsinhalte immer verborgen, und die automatische Sperre bleibt aktiv. Kein Modus und kein Zustand kann das ändern."

    // Minuten bis zur automatischen Sperre, immer 1–15 (Standard 5)
    function sperreMinuten(wunsch: var): int {
        return Logik.sperreMinuten(wunsch);
    }

    // Erzwingt die Leitplanken in einem wirksamen Zustand (zuletzt angewendet)
    function anwenden(zustand: var): var {
        return Logik.leitplankenAnwenden(zustand, {
            freigabe: Freigabe.aktiv
        });
    }
}
