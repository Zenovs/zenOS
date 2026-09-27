.pragma library

// Zeiten und Mengen für die Mitteilungen, ohne Abhängigkeit von Qt-Formaten.

function _zwei(n) {
    return (n < 10 ? "0" : "") + n;
}

// «09:12»
function uhrzeit(d) {
    if (!d || isNaN(d.getTime()))
        return "";
    return _zwei(d.getHours()) + ":" + _zwei(d.getMinutes());
}

// Zeit einer Mitteilung: heute «09:12», gestern «gestern 09:12», sonst «28.09. 09:12»
function zeit(d, jetzt) {
    if (!d || isNaN(d.getTime()))
        return "";
    const heute = new Date(jetzt.getFullYear(), jetzt.getMonth(), jetzt.getDate());
    const tag = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    const tage = Math.round((heute - tag) / 86400000);
    if (tage <= 0)
        return uhrzeit(d);
    if (tage === 1)
        return "gestern " + uhrzeit(d);
    return _zwei(d.getDate()) + "." + _zwei(d.getMonth() + 1) + ". " + uhrzeit(d);
}

// «1 Mitteilung», «3 Mitteilungen»
function mitteilungen(n) {
    return n + (n === 1 ? " Mitteilung" : " Mitteilungen");
}

// «1 wartet», «3 warten»
function warten(n) {
    return n + (n === 1 ? " wartet" : " warten");
}

// Beschreibung der Regel für die Zentrale
function regel(r, naechste, zustandAktiv) {
    if (!r)
        return "";
    switch (r.art) {
    case "alle":
        return "Mitteilungen kommen sofort";
    case "gebuendelt":
        return "Gesammelt alle " + r.minuten + " Min. · nächste Zustellung " + uhrzeit(naechste);
    case "nur-dringend":
        return zustandAktiv ? "Nur Dringendes kommt sofort, der Rest nach dem Zustand" : "Nur Dringendes kommt sofort";
    case "keine":
        return zustandAktiv ? "Pausiert bis zum Ende des Zustands" : "Pausiert";
    }
    return "";
}
