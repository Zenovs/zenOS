pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "../mitteilungen/bereinigen.js" as Bereinigen

// Mitteilungsdienst von zenOS. Quickshell ist der einzige Dienst für
// org.freedesktop.Notifications (kein mako, kein dunst).
//
// Regel (wirksamer Zustand, sonst Einstellungen.mitteilungenStandard):
//   alle            sofort
//   gebuendelt-<N>  gesammelt zu jedem Vielfachen von N Minuten ab Mitternacht
//   nur-dringend    nur Dringendes sofort, der Rest wartet bis zum Ende des Zustands
//   keine           alles wartet bis zum Ende des Zustands, auch Dringendes
// Dringendes (urgency critical) kommt ausser bei «keine» immer sofort.
// Endet ein Zustand, wird alles Wartende zugestellt. Wechselt er direkt in einen
// anderen, gilt dessen Regel.
//
// Leitplanke (Code, nicht Konfiguration): Solange der Bildschirm geteilt wird, zeigt
// keine Oberfläche Inhalte, nur die Anzahl. Nicht Dringendes wird in dieser Zeit
// zurückgehalten und danach nach der Regel zugestellt. Töne gibt es nie.
Singleton {
    id: root

    // Muss das erste Kind bleiben: Beim Neuladen der Oberfläche ordnet Quickshell die
    // Kinder eines Singletons nach ihrer Reihenfolge zu. Hält nur Nummern und Zeiten,
    // nie Inhalte, und nur im Speicher.
    PersistentProperties {
        id: persist

        property string stand: ""

        onReloaded: root._restoreState(stand)
    }

    // Einträge: ein Objekt je Mitteilung (siehe Instantiator unten) mit nummer, app, titel,
    // text, symbol, bild, dringend, aktionen, standardAktion, fluechtig, ankunft (date),
    // zugestelltUm (date oder null), zustand ("wartend" | "zugestellt") und gesehen (bool).
    // Texte sind bereinigt (bereinigen.js); aktionen: [{ identifier, text }] ohne «default».
    // wartend: älteste zuerst · zugestellt: neueste zuerst
    property var wartend: []
    property var zugestellt: []
    readonly property int anzahlWartend: wartend.length
    readonly property int anzahlZugestellt: zugestellt.length
    readonly property int anzahl: anzahlWartend + anzahlZugestellt
    // Zugestellt, aber noch nicht angesehen (Zentrale geöffnet oder Karte angeklickt).
    // Die Sperre zeigt wartend + ungelesen als Anzahl.
    readonly property int anzahlUngelesen: zugestellt.filter(e => !e.gesehen).length

    // Wirksame Regel: "alle" | "gebuendelt-<N>" | "nur-dringend" | "keine"
    readonly property string modus: {
        const fromState = Zustaende.wirksam?.mitteilungen;
        if (typeof fromState === "string" && _parse(fromState) !== null)
            return fromState;
        const standard = Einstellungen.mitteilungenStandard;
        if (typeof standard === "string" && _parse(standard) !== null)
            return standard;
        return _defaultMode;
    }
    // Zerlegte Regel: { art: "alle" | "gebuendelt" | "nur-dringend" | "keine", minuten: int }
    readonly property var regel: _parse(modus) ?? ({
            art: "gebuendelt",
            minuten: 60
        })
    // Nächste gesammelte Zustellung (date) bei gebuendelt-<N>, sonst null
    property var naechsteZustellung: null

    // Leitplanke: bei Bildschirmfreigabe nie Inhalte. Fehlt der Wert, bleibt es verborgen.
    readonly property bool inhalteVerborgen: Freigabe.aktiv === true && Leitplanken.inhalteBeiFreigabe !== true

    // Obergrenzen; darüber werden die ältesten verworfen (als abgelaufen gemeldet)
    readonly property int maxWartend: 100
    readonly property int maxZugestellt: 100

    // Frisch zugestellte Einträge, für die Sammelkarte und die dringende Karte
    signal ausgeliefert(var eintraege)

    // Alles Wartende sofort zustellen («Jetzt zustellen»)
    function zustellen(): void {
        _deliver(wartend.slice());
    }

    // Eine Mitteilung verwerfen (wartend oder zugestellt). nummer: Nummer der Mitteilung
    function verwerfen(nummer: var): void {
        const entry = eintrag(nummer);
        if (entry)
            entry.modelData.dismiss();
    }

    // Alle zugestellten Mitteilungen verwerfen. Wartende bleiben, bis sie zugestellt sind.
    function alleVerwerfen(): void {
        for (const entry of zugestellt.slice())
            entry.modelData.dismiss();
    }

    // Aktion einer Mitteilung auslösen; true, wenn es sie gab
    function aktionAusfuehren(nummer: var, kennung: string): bool {
        const entry = eintrag(nummer);
        if (!entry)
            return false;
        const action = Array.from(entry.modelData.actions ?? []).find(a => a.identifier === kennung);
        if (!action)
            return false;
        action.invoke();
        return true;
    }

    // Als angesehen merken (Karte angeklickt). nummer: Nummer der Mitteilung
    function alsGesehen(nummer: var): void {
        const entry = zugestellt.find(e => e.nummer === Number(nummer));
        if (entry && !entry.gesehen) {
            entry.gesehen = true;
            _save();
        }
    }

    // Alle zugestellten als angesehen merken (Zentrale geöffnet)
    function alleAlsGesehen(): void {
        const unseen = zugestellt.filter(e => !e.gesehen);
        for (const entry of unseen)
            entry.gesehen = true;
        if (unseen.length > 0)
            _save();
    }

    // Eintrag zu einer Nummer oder null
    function eintrag(nummer: var): var {
        const n = Number(nummer);
        return zugestellt.find(e => e.nummer === n) ?? wartend.find(e => e.nummer === n) ?? null;
    }

    // --- Server ---------------------------------------------------------------

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        // Text wird nie als Markup dargestellt
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false

        onNotification: notification => {
            notification.tracked = true;
        }
    }

    // Ein Eintrag je Mitteilung, solange der Server sie führt. Schliesst die App sie oder
    // wird sie verworfen, verschwindet der Eintrag mit ihr.
    Instantiator {
        model: server.trackedNotifications

        delegate: QtObject {
            id: entry

            required property Notification modelData

            readonly property int nummer: modelData ? modelData.id : 0
            readonly property string app: Bereinigen.singleLine(modelData?.appName || modelData?.desktopEntry || "", 80)
            readonly property string titel: Bereinigen.singleLine(modelData?.summary ?? "", 200)
            readonly property string text: Bereinigen.plainText(modelData?.body ?? "", 2000)
            readonly property string symbol: root._iconSource(modelData?.appIcon ?? "")
            readonly property string bild: root._imageSource(modelData?.image ?? "")
            readonly property bool dringend: modelData?.urgency === NotificationUrgency.Critical
            readonly property bool fluechtig: modelData?.transient ?? false
            readonly property var standardAktion: Array.from(modelData?.actions ?? []).find(a => a.identifier === "default") ?? null
            // Nur Kennung und bereinigte Beschriftung; ausgelöst wird über aktionAusfuehren
            readonly property var aktionen: Array.from(modelData?.actions ?? []).filter(a => a.identifier !== "default").map(a => ({
                        identifier: String(a.identifier ?? ""),
                        text: Bereinigen.actionLabel(a.text ?? "", 40)
                    })).filter(a => a.text.length > 0)

            property date ankunft: new Date()
            property var zugestelltUm: null
            property string zustand: ""
            property bool gesehen: false

            // Ersetzt eine App ihre Mitteilung (gleiche Nummer), ändert sich der Inhalt
            readonly property string signatur: (modelData?.summary ?? "") + "\u0001" + (modelData?.body ?? "") + "\u0001" + (modelData?.urgency ?? 0)
            property bool geaendert: false

            onSignaturChanged: {
                if (zustand === "")
                    return;
                geaendert = true;
                Qt.callLater(root._processChanged);
            }
        }

        onObjectAdded: (index, object) => root._added(object)
        onObjectRemoved: (index, object) => root._removed(object)
    }

    // --- Zeitpunkte -------------------------------------------------------------

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
        enabled: root.regel.art === "gebuendelt"
        onDateChanged: root._tick()
    }

    // Flüchtige Mitteilungen (Hinweis «transient») bleiben nicht in der Zentrale
    Timer {
        interval: 5000
        repeat: true
        running: root.zugestellt.some(e => e.fluechtig)
        onTriggered: {
            const limit = Date.now() - 10000;
            for (const entry of root.zugestellt.filter(e => e.fluechtig && e.zugestelltUm && e.zugestelltUm.getTime() < limit))
                entry.modelData.expire();
        }
    }

    Connections {
        target: Zustaende

        function onAktivIdChanged(): void {
            root._stateChanged();
        }
    }

    // regel (nicht modus): so ist die zerlegte Regel beim Auswerten schon neu
    onRegelChanged: _evaluate()
    onInhalteVerborgenChanged: _evaluate()

    Component.onCompleted: {
        _lastState = Zustaende.aktivId ?? "";
        _ready = true;
        _evaluate();
    }

    // --- intern -----------------------------------------------------------------

    readonly property string _defaultMode: "gebuendelt-60"
    // erst nach dem Aufbau entscheiden (Einstellungen und Zustände laden währenddessen)
    property bool _ready: false
    property string _lastState: ""
    // Ein Zeitpunkt ist erreicht und Wartendes noch nicht zugestellt (z. B. wegen der Freigabe)
    property bool _slotDue: false
    // Ein Zustand ist zu Ende: Wartendes kommt, sobald die Freigabe nicht mehr zurückhält
    property bool _releasePending: false
    // Stand vor dem Neuladen: nummer → [zustand, ankunft, zugestelltUm, gesehen (0/1)]
    property var _restored: ({})

    function _parse(mode: string): var {
        if (mode === "alle" || mode === "nur-dringend" || mode === "keine")
            return {
                art: mode,
                minuten: 0
            };
        const m = /^gebuendelt-(\d{1,4})$/.exec(mode ?? "");
        if (m) {
            const minutes = Number(m[1]);
            if (minutes >= 1 && minutes <= 1440)
                return {
                    art: "gebuendelt",
                    minuten: minutes
                };
        }
        return null;
    }

    function _now(): var {
        const now = new Date();
        return clock.enabled && clock.date > now ? clock.date : now;
    }

    // Nächstes Vielfaches von N Minuten ab Mitternacht (Ortszeit), echt nach «jetzt»
    function _nextSlot(now: var, minutes: int): var {
        const current = now.getHours() * 60 + now.getMinutes();
        const next = (Math.floor(current / minutes) + 1) * minutes;
        if (next >= 1440)
            return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0, 0);
        return new Date(now.getFullYear(), now.getMonth(), now.getDate(), Math.floor(next / 60), next % 60, 0, 0);
    }

    function _updateNext(): void {
        if (!_ready)
            return;
        if (regel.art !== "gebuendelt") {
            if (naechsteZustellung !== null)
                naechsteZustellung = null;
            return;
        }
        const next = _nextSlot(_now(), regel.minuten);
        if (!naechsteZustellung || naechsteZustellung.getTime() !== next.getTime())
            naechsteZustellung = next;
    }

    function _tick(): void {
        if (!_ready || regel.art !== "gebuendelt" || !naechsteZustellung)
            return;
        if (_now().getTime() >= naechsteZustellung.getTime()) {
            if (wartend.length > 0)
                _slotDue = true;
            _evaluate();
        }
    }

    function _stateChanged(): void {
        if (!_ready)
            return;
        const current = Zustaende.aktivId ?? "";
        const previous = _lastState;
        _lastState = current;
        if (previous !== "" && current === "")
            _releasePending = true;
        else if (current !== "")
            _releasePending = false;
        _evaluate();
    }

    // Entscheidet, ob Wartendes jetzt zugestellt wird
    function _evaluate(): void {
        if (!_ready)
            return;
        _updateNext();
        const art = regel.art;
        if (art !== "gebuendelt")
            _slotDue = false;
        if (wartend.length === 0) {
            _slotDue = false;
            _releasePending = false;
            return;
        }
        // Leitplanke: während der Freigabe nichts zustellen, ausser Dringendem beim Eintreffen
        if (inhalteVerborgen)
            return;
        if (_releasePending || _slotDue || art === "alle")
            _deliver(wartend.slice());
        else if (art !== "keine") {
            // z. B. nach «keine»: Dringendes, das gewartet hat, kommt jetzt
            const urgent = wartend.filter(e => e.dringend);
            if (urgent.length > 0)
                _deliver(urgent);
        }
    }

    // Neu eingetroffen oder ersetzt
    function _route(entry: var): void {
        const art = regel.art;
        if (entry.dringend && art !== "keine")
            _deliver([entry]);
        else if (art === "alle" && !inhalteVerborgen)
            _deliver([entry]);
        else
            _hold(entry);
    }

    function _hold(entry: var): void {
        entry.zustand = "wartend";
        entry.zugestelltUm = null;
        entry.gesehen = false;
        const list = wartend.filter(e => e !== entry);
        list.push(entry);
        list.sort((a, b) => a.ankunft - b.ankunft);
        wartend = list;
        _save();
        _enforceLimits();
    }

    function _deliver(entries: var): void {
        const fresh = entries.filter(e => e && e.zustand !== "");
        if (fresh.length === 0)
            return;
        const now = new Date();
        for (const entry of fresh) {
            entry.zustand = "zugestellt";
            entry.zugestelltUm = now;
            entry.gesehen = false;
        }
        wartend = wartend.filter(e => fresh.indexOf(e) < 0);
        // neueste zuerst: die zuletzt eingetroffene steht oben
        const newest = fresh.slice().sort((a, b) => b.ankunft - a.ankunft);
        zugestellt = newest.concat(zugestellt.filter(e => fresh.indexOf(e) < 0));
        if (wartend.length === 0) {
            _slotDue = false;
            _releasePending = false;
        }
        _save();
        ausgeliefert(newest);
        _enforceLimits();
    }

    function _enforceLimits(): void {
        const dropped = [];
        if (wartend.length > maxWartend)
            dropped.push(...wartend.slice(0, wartend.length - maxWartend));
        if (zugestellt.length > maxZugestellt)
            dropped.push(...zugestellt.slice(maxZugestellt));
        for (const entry of dropped)
            entry.modelData.expire();
    }

    function _added(entry: var): void {
        if (!entry || !entry.modelData)
            return;
        if (entry.modelData.lastGeneration) {
            // Neu geladene Oberfläche: Stand übernehmen, nichts erneut zeigen
            const saved = _restored[entry.nummer];
            entry.ankunft = saved ? new Date(saved[1]) : new Date();
            if (saved && saved[0] === "w") {
                _hold(entry);
            } else {
                entry.zustand = "zugestellt";
                entry.zugestelltUm = saved && saved[2] ? new Date(saved[2]) : entry.ankunft;
                entry.gesehen = saved ? saved[3] === 1 : false;
                const list = zugestellt.concat([entry]);
                list.sort((a, b) => (b.zugestelltUm - a.zugestelltUm) || (b.ankunft - a.ankunft));
                zugestellt = list;
                _save();
            }
            return;
        }
        entry.ankunft = new Date();
        entry.zustand = "neu";
        _route(entry);
    }

    function _removed(entry: var): void {
        if (!entry)
            return;
        entry.zustand = "";
        const waiting = wartend.filter(e => e !== entry);
        const delivered = zugestellt.filter(e => e !== entry);
        if (waiting.length !== wartend.length)
            wartend = waiting;
        if (delivered.length !== zugestellt.length)
            zugestellt = delivered;
        _save();
    }

    // Ersetzte Mitteilungen gelten als neu eingetroffen
    function _processChanged(): void {
        const changed = wartend.concat(zugestellt).filter(e => e.geaendert);
        for (const entry of changed) {
            entry.geaendert = false;
            wartend = wartend.filter(e => e !== entry);
            zugestellt = zugestellt.filter(e => e !== entry);
            entry.ankunft = new Date();
            _route(entry);
        }
    }

    function _save(): void {
        const state = {};
        for (const e of wartend)
            state[e.nummer] = ["w", e.ankunft.getTime(), 0, 0];
        for (const e of zugestellt)
            state[e.nummer] = ["z", e.ankunft.getTime(), e.zugestelltUm ? e.zugestelltUm.getTime() : 0, e.gesehen ? 1 : 0];
        persist.stand = JSON.stringify(state);
    }

    function _restoreState(text: string): void {
        try {
            const parsed = JSON.parse(text || "{}");
            _restored = parsed && typeof parsed === "object" ? parsed : {};
        } catch (e) {
            _restored = {};
        }
    }

    // Symbolname, Pfad oder URL → Bildquelle; "" wenn nichts gefunden
    function _iconSource(icon: string): string {
        if (!icon)
            return "";
        if (/^(file|image|qrc):/.test(icon))
            return icon;
        if (icon.startsWith("/"))
            return "file://" + icon.split("/").map(encodeURIComponent).join("/");
        return Quickshell.iconPath(icon, true) ?? "";
    }

    // Bild der Mitteilung; Symbolnamen nur, wenn das Thema sie kennt (sonst zeigt Qt ein
    // Ersatzbild)
    function _imageSource(image: string): string {
        if (!image)
            return "";
        if (image.startsWith("image://icon/")) {
            const name = decodeURIComponent(image.slice(13).split("?")[0]);
            return name && Quickshell.hasThemeIcon(name) ? image : "";
        }
        return image;
    }
}
