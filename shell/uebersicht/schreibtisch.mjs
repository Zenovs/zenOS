// Schreibtisch zeigen ohne QML: welche Fenster minimiert werden, was Super+H gerade bewirkt und in welcher
// Reihenfolge die Fenster zurückkommen. Der Dienst dazu ist shell/dienste/Schreibtisch.qml.
// Getestet mit node (test/einheiten/uebersicht.test.mjs).
// Fenster sind Toplevel-Objekte aus Quickshell (in den Tests {appId, minimized}); verglichen wird ihre Identität.
//
// labwc 0.9.3 gibt die Stapelreihenfolge nicht heraus. Sie wird über den Verlauf der aktiven Fenster angenähert
// (ein Klick hebt ein Fenster und macht es aktiv). labwc hebt und aktiviert ein Fenster, wenn es nicht mehr
// minimiert ist, und aktiviert beim Minimieren des aktiven Fensters das oberste übrige. Deshalb geht beides von
// unten nach oben: Beim Zeigen wird das aktive Fenster als letztes minimiert (der Verlauf bleibt dabei ruhig),
// beim Zurück kommt das zuletzt aktive als letztes und liegt dann oben.
import * as Fenster from "../appleiste/fenster.mjs";

// Sichtbare App-Fenster: nicht minimiert, ohne die Fenster der Oberfläche (wie in der App-Leiste). Vollbild-Fenster
// zählen mit.
export function sichtbare(fenster) {
    return Fenster.alsListe(fenster).filter(t => t && !Fenster.istOberflaeche(t.appId) && t.minimized !== true);
}

// Gemerkte Fenster, die noch offen sind, in der Reihenfolge des Merkers
export function nochOffen(merker, offen) {
    const offene = Fenster.alsListe(offen);
    const liste = [];
    for (const t of Fenster.alsListe(merker)) {
        if (t && offene.indexOf(t) >= 0 && liste.indexOf(t) < 0)
            liste.push(t);
    }
    return liste;
}

// Ist der Schreibtisch frei? Es gibt gemerkte Fenster, die noch offen sind, und kein App-Fenster ist sichtbar.
// Nur aus der Lage der Fenster berechnet: Eine Aktivierung allein ändert nichts (labwc aktiviert beim Minimieren
// kurz das jeweils nächste Fenster). Holst du ein Fenster anders zurück oder erscheint ein neues, ist es vorbei.
export function frei(fenster, merker) {
    return sichtbare(fenster).length === 0 && nochOffen(merker, fenster).length > 0;
}

// Was Super+H gerade bewirkt: "zeigen" (die sichtbaren App-Fenster minimieren), "zurueck" (die gemerkten
// zurückholen) oder "nichts" (keine App-Fenster, oder nur solche, die schon vorher minimiert waren).
export function entscheiden(fenster, merker) {
    if (sichtbare(fenster).length > 0)
        return "zeigen";
    return nochOffen(merker, fenster).length > 0 ? "zurueck" : "nichts";
}

// Fenster von unten nach oben, angenähert über den Verlauf (zuletzt aktiv zuerst): Fenster ohne Eintrag im
// Verlauf zuunterst in ihrer Reihenfolge, darüber die übrigen vom am längsten nicht mehr aktiven bis zum zuletzt
// aktiven.
export function vonUntenNachOben(fenster, verlauf) {
    const liste = [];
    for (const t of Fenster.alsListe(fenster)) {
        if (t && liste.indexOf(t) < 0)
            liste.push(t);
    }
    const imVerlauf = [];
    for (const t of Fenster.alsListe(verlauf)) {
        if (t && liste.indexOf(t) >= 0 && imVerlauf.indexOf(t) < 0)
            imVerlauf.push(t);
    }
    return liste.filter(t => imVerlauf.indexOf(t) < 0).concat(imVerlauf.reverse());
}

// Merker beim Zeigen: die sichtbaren App-Fenster von unten nach oben. In dieser Reihenfolge werden sie minimiert,
// das aktive zuletzt. Von Hand minimierte Fenster gehören nicht dazu und bleiben beim Zurück unten.
export function merken(fenster, verlauf) {
    return vonUntenNachOben(sichtbare(fenster), verlauf);
}

// Reihenfolge beim Zurück: nur gemerkte Fenster, die noch offen sind, von unten nach oben (das zuletzt aktive als
// letztes). offen: alle offenen Fenster.
export function zurueckReihenfolge(merker, offen) {
    return nochOffen(merker, offen);
}
