// Rechner für das Befehlsfeld: ein eigener, kleiner Parser (kein eval, kein Function()).
// Wird von Befehlsfeld.qml importiert und mit node getestet (test/einheiten/rechner.test.mjs).
//
// Grammatik, von schwach nach stark bindend:
//   ausdruck   = term { ("+" | "-") term }        «a + b %» rechnet a + a·b/100
//   term       = vorzeichen { ("*" | "/" | "%") vorzeichen }   «%» zwischen zwei Operanden = Rest
//   vorzeichen = ("+" | "-") vorzeichen | potenz     -2^2 = -4
//   potenz     = postfix [ "^" vorzeichen ]          rechtsassoziativ, 2^-1 = 0.5
//   postfix    = primaer { "%" }                     Prozent: 15% = 0.15
//   primaer    = zahl | "(" ausdruck ")"
//
// Zahlen: Dezimalkomma oder -punkt (höchstens einer pro Zahl), Tausender-Apostroph optional
// («1'440», nur vor Dreiergruppen). Operatoren auch als − × · ÷ : und ** (Potenz).

const MAX_LAENGE = 200;
const MAX_TIEFE = 64;

const OPERATOREN = {
    "+": "+",
    "-": "-",
    "−": "-", // −
    "–": "-", // –
    "*": "*",
    "×": "*", // ×
    "·": "*", // ·
    "⋅": "*", // ⋅
    "/": "/",
    "÷": "/", // ÷
    ":": "/",
    "%": "%",
    "^": "^",
    "(": "(",
    ")": ")"
};
const APOSTROPHE = "'’ʼ";
const LEERZEICHEN = " \t   ";

function istZiffer(c) {
    return c !== undefined && c >= "0" && c <= "9";
}

function istApostroph(c) {
    return c !== undefined && c.length === 1 && APOSTROPHE.includes(c);
}

// Text → Liste von Tokens {art: "zahl", wert, trenner} | {art: "op", wert}; null bei ungültiger Eingabe
export function zerlegen(text) {
    const tokens = [];
    let i = 0;
    while (i < text.length) {
        const c = text[i];
        if (c.length === 1 && LEERZEICHEN.includes(c)) {
            i++;
            continue;
        }
        if (c === "*" && text[i + 1] === "*") {
            tokens.push({ art: "op", wert: "^" });
            i += 2;
            continue;
        }
        if (OPERATOREN[c] !== undefined) {
            tokens.push({ art: "op", wert: OPERATOREN[c] });
            i++;
            continue;
        }
        if (istZiffer(c) || ((c === "." || c === ",") && istZiffer(text[i + 1]))) {
            const zahl = zahlLesen(text, i);
            if (zahl === null)
                return null;
            tokens.push({ art: "zahl", wert: zahl.wert, trenner: zahl.trenner });
            i = zahl.ende;
            continue;
        }
        return null;
    }
    return tokens;
}

// Liest eine Zahl ab Position start; null, wenn sie nicht eindeutig ist
function zahlLesen(text, start) {
    let ganz = "";
    let bruch = "";
    let trenner = "";
    let i = start;
    let gruppiert = false;
    while (i < text.length && istZiffer(text[i]))
        ganz += text[i++];
    // Tausender-Apostroph: nur zwischen Ziffern und nur vor genau drei Ziffern
    while (istApostroph(text[i]) && ganz.length > 0) {
        const gruppe = text.slice(i + 1, i + 4);
        if (!/^[0-9]{3}$/.test(gruppe) || istZiffer(text[i + 4]))
            return null;
        if (!gruppiert && ganz.length > 3)
            return null;
        gruppiert = true;
        ganz += gruppe;
        i += 4;
    }
    if (text[i] === "." || text[i] === ",") {
        trenner = text[i];
        i++;
        while (i < text.length && istZiffer(text[i]))
            bruch += text[i++];
        // «5.» oder ein zweiter Trenner («1.000,5») sind mehrdeutig
        if (bruch.length === 0 || text[i] === "." || text[i] === "," || istApostroph(text[i]))
            return null;
    }
    if (ganz.length === 0 && bruch.length === 0)
        return null;
    const wert = Number((ganz.length > 0 ? ganz : "0") + (bruch.length > 0 ? "." + bruch : ""));
    return Number.isFinite(wert) ? { wert, trenner, ende: i } : null;
}

class Parser {
    constructor(tokens) {
        this.tokens = tokens;
        this.pos = 0;
        this.tiefe = 0;
        // Anzahl echter Rechenoperationen (ein Vorzeichen oder Klammern allein zählen nicht)
        this.operationen = 0;
    }

    naechstes() {
        return this.tokens[this.pos];
    }

    istOp(wert) {
        const t = this.tokens[this.pos];
        return t !== undefined && t.art === "op" && t.wert === wert;
    }

    // Folgt an Position p eine Zahl oder Klammer? Dann ist «%» der Rest-Operator, sonst Prozent
    // («50% - 2» = -1.5, «10 % 3» = 1).
    operandAb(p) {
        const t = this.tokens[p];
        return t !== undefined && (t.art === "zahl" || t.wert === "(");
    }

    ausdruck() {
        let links = this.term();
        while (this.istOp("+") || this.istOp("-")) {
            const op = this.naechstes().wert;
            this.pos++;
            const rechts = this.term();
            this.operationen++;
            // «200 + 10%» = 220, wie auf einem Taschenrechner
            const summand = rechts.prozent ? links.wert * rechts.wert : rechts.wert;
            links = { wert: op === "+" ? links.wert + summand : links.wert - summand, prozent: false };
        }
        return links;
    }

    term() {
        let links = this.vorzeichen();
        let anzahl = 0;
        for (;;) {
            let op = null;
            if (this.istOp("*") || this.istOp("/"))
                op = this.naechstes().wert;
            else if (this.istOp("%") && this.operandAb(this.pos + 1))
                op = "%";
            if (op === null)
                break;
            this.pos++;
            const rechts = this.vorzeichen();
            this.operationen++;
            anzahl++;
            if (op === "*") {
                links = { wert: links.wert * rechts.wert };
            } else {
                if (rechts.wert === 0)
                    throw new Error("Division durch 0");
                links = { wert: op === "/" ? links.wert / rechts.wert : links.wert % rechts.wert };
            }
        }
        return { wert: links.wert, prozent: anzahl === 0 && links.prozent === true };
    }

    vorzeichen() {
        if (this.istOp("+") || this.istOp("-")) {
            const minus = this.istOp("-");
            this.pos++;
            this.tiefer();
            const wert = this.vorzeichen();
            this.tiefe--;
            return { wert: minus ? -wert.wert : wert.wert, prozent: wert.prozent };
        }
        return this.potenz();
    }

    potenz() {
        const basis = this.postfix();
        if (!this.istOp("^"))
            return basis;
        this.pos++;
        this.tiefer();
        const exponent = this.vorzeichen();
        this.tiefe--;
        this.operationen++;
        return { wert: Math.pow(basis.wert, exponent.wert) };
    }

    postfix() {
        let wert = this.primaer();
        let prozent = false;
        while (this.istOp("%") && !this.operandAb(this.pos + 1)) {
            this.pos++;
            this.operationen++;
            wert /= 100;
            prozent = true;
        }
        return { wert, prozent };
    }

    primaer() {
        const t = this.naechstes();
        if (t === undefined)
            throw new Error("Ausdruck unvollständig");
        if (t.art === "zahl") {
            this.pos++;
            return t.wert;
        }
        if (t.wert === "(") {
            this.pos++;
            this.tiefer();
            const innen = this.ausdruck();
            this.tiefe--;
            if (!this.istOp(")"))
                throw new Error("Klammer nicht geschlossen");
            this.pos++;
            return innen.wert;
        }
        throw new Error("Operand erwartet");
    }

    tiefer() {
        this.tiefe++;
        if (this.tiefe > MAX_TIEFE)
            throw new Error("zu tief verschachtelt");
    }
}

// Rechnet einen Ausdruck aus. Ergebnis {wert, anzeige} oder null, wenn der Text keine Rechnung ist,
// ungültig ist oder kein endliches Ergebnis hat (z. B. Division durch 0).
// anzeige nutzt den Dezimaltrenner der Eingabe (ohne Trenner in der Eingabe: Komma).
export function berechnen(text) {
    if (typeof text !== "string")
        return null;
    const eingabe = text.trim().replace(/=\s*$/, "").trim();
    if (eingabe.length === 0 || eingabe.length > MAX_LAENGE)
        return null;
    const tokens = zerlegen(eingabe);
    if (tokens === null || tokens.length === 0)
        return null;
    const parser = new Parser(tokens);
    let ergebnis;
    try {
        ergebnis = parser.ausdruck();
    } catch (e) {
        return null;
    }
    if (parser.pos !== tokens.length || parser.operationen === 0)
        return null;
    const wert = runden(ergebnis.wert);
    if (wert === null)
        return null;
    const erster = tokens.find(t => t.art === "zahl" && t.trenner !== "");
    return { wert, anzeige: formatieren(wert, erster ? erster.trenner : ",") };
}

// Auf 12 signifikante Stellen runden (0.1 + 0.2 = 0.3); null bei nicht endlichen Werten
export function runden(wert) {
    if (typeof wert !== "number" || !Number.isFinite(wert))
        return null;
    const gerundet = Number(wert.toPrecision(12));
    return Object.is(gerundet, -0) ? 0 : gerundet;
}

// Zahl als Text mit dem gewünschten Dezimaltrenner, ohne Tausendertrenner (zum Kopieren)
export function formatieren(wert, trenner) {
    const betrag = Math.abs(wert);
    const text = betrag !== 0 && (betrag >= 1e21 || betrag < 1e-6) ? wert.toExponential().replace("e+", "e") : String(wert);
    return trenner === "," ? text.replace(".", ",") : text;
}
