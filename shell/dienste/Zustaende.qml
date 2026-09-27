pragma Singleton

import QtQuick
import Quickshell
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "../modi/zustandslogik.js" as Logik

// Zustände (~/.config/zenos/zustaende/<id>.json) und der aktive Zustand (laufzeit.json, «zustand»).
// Wirksamer Zustand = Vorlage + Anpassung des aktiven Modus + Leitplanken (zuletzt).
// Auslöser: manuell, bildschirmfreigabe, uhrzeit:HH:MM, moduswechsel («kalender» kommt später und
// wird ignoriert). Ende: manuell, timer, ausloeser-endet. Nach einer automatisch gestarteten Sitzung
// kommt ein vorher aktiver Zustand zurück, falls er noch gilt (Timer läuft noch oder Ende manuell).
// Die Regeln stehen in modi/zustandslogik.js und sind dort getestet.
Singleton {
    id: root

    // Alle Zustände (Objekte mit id), nach Name sortiert
    readonly property var liste: _sorted(Konfig.zustaende)
    // Zustände, die der aktive Modus anbietet (ohne Modus: alle)
    readonly property var angeboten: Logik.angeboten(liste, Modi.aktiv)
    // Davon von Hand startbar (Auslöser «manuell»), z. B. für Umschalter und Befehlsfeld
    readonly property var startbar: Logik.startbar(liste, Modi.aktiv)

    // ID des aktiven Zustands ("" = keiner)
    readonly property string aktivId: _entry?.id ?? ""
    // Vorlage des aktiven Zustands (Objekt mit id) oder null
    readonly property var aktiv: _find(aktivId)
    // Vorlage + Anpassung des Modus + Leitplanken, oder null ohne aktiven Zustand
    readonly property var wirksam: aktiv ? Logik.wirksam(aktiv, Modi.aktiv, {
        freigabe: Freigabe.aktiv
    }) : null
    // Restzeit des Timers in Minuten, -1 ohne Timer
    readonly property int restMinuten: Logik.restMinuten(_entry, _now)
    // Wie der Zustand gestartet wurde: manuell | bildschirmfreigabe | uhrzeit | moduswechsel | ""
    readonly property string ausloeser: _entry?.ausloeser ?? ""
    readonly property date seit: _entry ? new Date(_entry.seit) : new Date(NaN)
    // Ende des Timers (ungültig ohne Timer)
    readonly property date ende: _entry?.ende ? new Date(_entry.ende) : new Date(NaN)
    // Laufzeit-Eintrag (siehe zustandslogik.js) oder null
    readonly property var eintrag: _entry

    signal gestartet(string id, string ausloeser)
    signal beendet(string id)

    // Zustand starten. ausloeser: "manuell" (Standard), "bildschirmfreigabe", "uhrzeit", "moduswechsel"
    function starten(id: string, ausloeser: var): void {
        if (!Konfig.verfuegbar)
            return;
        const vorlage = _find(id);
        if (!vorlage) {
            console.warn("Zustaende: unbekannter Zustand");
            return;
        }
        const art = typeof ausloeser === "string" && ausloeser.length > 0 ? ausloeser : "manuell";
        _set(Logik.starten(_entry, _effective(vorlage), art, Date.now()));
    }

    // Aktiven Zustand beenden (ein gemerkter Zustand kommt zurück, falls er noch gilt)
    function beenden(): void {
        if (!_entry)
            return;
        _set(Logik.beenden(_entry, Date.now()));
    }

    function speichern(id: string, daten: var, fertig: var): void {
        Konfig.schreiben("zustaende", id, _clean(daten), fertig);
    }

    // Neuen Zustand anlegen; gibt die neue ID zurück
    function anlegen(daten: var, fertig: var): string {
        if (!Konfig.verfuegbar)
            return "";
        const d = _clean(daten);
        if (!d.name || !String(d.name).trim())
            d.name = "Neuer Zustand";
        const id = Logik.slug(d.name, Konfig.zustaende.map(z => z.id), "zustand");
        Konfig.schreiben("zustaende", id, d, fertig);
        return id;
    }

    // Zustand löschen; Verweise in den Modi (Angebot, Anpassungen) verschwinden mit
    function loeschen(id: string, fertig: var): void {
        if (id === aktivId)
            _set(null);
        for (const modus of Konfig.modi) {
            const bietet = Array.isArray(modus.zustaende) && modus.zustaende.indexOf(id) >= 0;
            const passt = modus.anpassungen && typeof modus.anpassungen === "object" && modus.anpassungen[id] !== undefined;
            if (!bietet && !passt)
                continue;
            const neu = JSON.parse(JSON.stringify(modus));
            if (bietet)
                neu.zustaende = neu.zustaende.filter(z => z !== id);
            if (passt)
                delete neu.anpassungen[id];
            Modi.speichern(modus.id, neu);
        }
        Konfig.loeschen("zustaende", id, fertig);
    }

    // Wirksamer Zustand eines beliebigen Zustands im aktiven (oder angegebenen) Modus
    function wirksamFuer(id: string, modus: var): var {
        const vorlage = _find(id);
        return vorlage ? Logik.wirksam(vorlage, modus === undefined ? Modi.aktiv : modus, {
            freigabe: Freigabe.aktiv
        }) : null;
    }

    property var _entry: null
    property double _now: Date.now()
    property bool _restored: false
    property string _lastClockMinute: ""

    function _find(id: string): var {
        if (!id)
            return null;
        return Konfig.zustaende.find(z => z.id === id) ?? null;
    }

    function _sorted(list: var): var {
        return (Array.isArray(list) ? list.slice() : []).sort((a, b) => String(a.name ?? a.id).localeCompare(String(b.name ?? b.id), "de"));
    }

    function _clean(daten: var): var {
        const d = daten && typeof daten === "object" ? JSON.parse(JSON.stringify(daten)) : {};
        delete d.id;
        return d;
    }

    function _effective(vorlage: var): var {
        return Logik.wirksam(vorlage, Modi.aktiv, {
            freigabe: Freigabe.aktiv
        });
    }

    function _set(neu: var): void {
        const alt = _entry;
        if (JSON.stringify(alt) === JSON.stringify(neu))
            return;
        _entry = neu;
        _now = Date.now();
        if (Konfig.verfuegbar)
            Konfig.aendern("laufzeit", "", {
                zustand: neu
            });
        const altId = alt?.id ?? "";
        const neuId = neu?.id ?? "";
        if (altId !== "" && altId !== neuId)
            beendet(altId);
        if (neuId !== "" && (altId !== neuId || alt?.seit !== neu?.seit))
            gestartet(neuId, neu.ausloeser);
        _arm();
    }

    // Timer auf die nächste Änderung der Restzeit stellen
    function _arm(): void {
        const ms = Logik.naechsteAenderung(_entry, Date.now());
        if (ms < 0) {
            tick.stop();
            return;
        }
        tick.interval = Math.max(50, ms + 50);
        tick.restart();
    }

    function _check(): void {
        _now = Date.now();
        _set(Logik.pruefen(_entry, _now));
        _arm();
    }

    function _restore(): void {
        if (_restored || !Konfig.geladen)
            return;
        _restored = true;
        const saved = Konfig.laufzeitStart?.zustand ?? null;
        const ids = Konfig.zustaende.map(z => z.id);
        const entry = Logik.wiederherstellen(saved, ids, Date.now(), Freigabe.aktiv);
        if (entry) {
            _entry = entry;
            _now = Date.now();
            _arm();
        }
        if (JSON.stringify(saved) !== JSON.stringify(entry))
            Konfig.aendern("laufzeit", "", {
                zustand: entry
            });
        if (Freigabe.aktiv)
            _sharingStarted();
    }

    function _sharingStarted(): void {
        const z = Logik.waehleFuer(liste, Modi.aktiv, "bildschirmfreigabe", "sitzung");
        if (z && _entry?.id !== z.id)
            starten(z.id, "bildschirmfreigabe");
    }

    function _minuteChanged(): void {
        // Nach Standby kann ein Timer schon abgelaufen sein
        _check();
        const hhmm = ("0" + clock.hours).slice(-2) + ":" + ("0" + clock.minutes).slice(-2);
        if (hhmm === _lastClockMinute)
            return;
        _lastClockMinute = hhmm;
        if (!Logik.darfAutomatisch(_entry, "uhrzeit"))
            return;
        const z = Logik.waehleFuer(liste, Modi.aktiv, "uhrzeit:" + hhmm, "");
        if (z && _entry?.id !== z.id)
            starten(z.id, "uhrzeit");
    }

    Connections {
        target: Konfig

        function onGeladenChanged(): void {
            root._restore();
        }

        function onGeaendert(art: string): void {
            if (art !== "zustaende" || !root._entry)
                return;
            // Aktiver Zustand gelöscht? Dann endet er.
            const ids = Konfig.zustaende.map(z => z.id);
            if (ids.indexOf(root._entry.id) < 0)
                root._set(Logik.wiederherstellen(root._entry.vorher, ids, Date.now(), Freigabe.aktiv));
        }
    }

    Connections {
        target: Freigabe

        function onAktivChanged(): void {
            if (!root._restored)
                return;
            if (Freigabe.aktiv)
                root._sharingStarted();
            else
                root._set(Logik.ausloeserEndet(root._entry, "bildschirmfreigabe", Date.now()));
        }
    }

    Connections {
        target: Modi

        function onGewechselt(alt: string, neu: string): void {
            if (!root._restored)
                return;
            // Ein Zustand, den der alte Modus ausgelöst hat, endet mit ihm
            root._set(Logik.ausloeserEndet(root._entry, "moduswechsel", Date.now()));
            if (neu === "" || !Logik.darfAutomatisch(root._entry, "moduswechsel"))
                return;
            const z = Logik.waehleFuer(root.liste, Modi.aktiv, "moduswechsel", "");
            if (z && root._entry?.id !== z.id)
                root.starten(z.id, "moduswechsel");
        }
    }

    Timer {
        id: tick

        onTriggered: root._check()
    }

    // Uhrzeit-Auslöser und Restzeit (auch nach Standby)
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
        enabled: root._restored
        onDateChanged: root._minuteChanged()
    }

    Component.onCompleted: _restore()
}
