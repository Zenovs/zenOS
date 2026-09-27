// Tests für den Rechner des Befehlsfelds (shell/befehlsfeld/rechner.mjs).
// Ohne Abhängigkeiten: node --test test/einheiten/

import { test } from "node:test";
import assert from "node:assert/strict";
import { berechnen, formatieren, runden, zerlegen } from "../../shell/befehlsfeld/rechner.mjs";

function anzeige(text) {
    const r = berechnen(text);
    return r === null ? null : r.anzeige;
}

test("Grundrechenarten", () => {
    assert.equal(anzeige("1440 / 16"), "90");
    assert.equal(anzeige("1440/16"), "90");
    assert.equal(anzeige("2 + 3 * 4"), "14");
    assert.equal(anzeige("(2 + 3) * 4"), "20");
    assert.equal(anzeige("10 - 4 - 3"), "3");
    assert.equal(anzeige("100 / 10 / 5"), "2");
    assert.equal(anzeige("7 * 6"), "42");
});

test("Operatorzeichen", () => {
    assert.equal(anzeige("6 × 7"), "42");
    assert.equal(anzeige("6 · 7"), "42");
    assert.equal(anzeige("84 ÷ 2"), "42");
    assert.equal(anzeige("84 : 2"), "42");
    assert.equal(anzeige("50 − 8"), "42");
    assert.equal(anzeige("2 ^ 10"), "1024");
    assert.equal(anzeige("2 ** 10"), "1024");
});

test("Potenz: rechtsassoziativ und stärker als das Vorzeichen", () => {
    assert.equal(anzeige("2 ^ 3 ^ 2"), "512");
    assert.equal(anzeige("-2 ^ 2"), "-4");
    assert.equal(anzeige("(-2) ^ 2"), "4");
    assert.equal(anzeige("2 ^ -1"), "0,5");
});

test("Vorzeichen", () => {
    assert.equal(anzeige("-5 + 3"), "-2");
    assert.equal(anzeige("+5 - -3"), "8");
    assert.equal(anzeige("3 * -2"), "-6");
    assert.equal(anzeige("-(2 + 3) * 2"), "-10");
});

test("Dezimalkomma und -punkt; die Anzeige folgt der Eingabe", () => {
    assert.equal(anzeige("1,5 * 2"), "3");
    assert.equal(anzeige("1,5 + 1"), "2,5");
    assert.equal(anzeige("1.5 + 1"), "2.5");
    assert.equal(anzeige("10 / 4"), "2,5");
    assert.equal(anzeige(".5 + .25"), "0.75");
    assert.equal(anzeige(",5 + 1"), "1,5");
    assert.equal(anzeige("0.1 + 0.2"), "0.3");
    assert.equal(anzeige("1 / 3"), "0,333333333333");
});

test("Tausender-Apostroph", () => {
    assert.equal(anzeige("1'440 / 16"), "90");
    assert.equal(anzeige("1’000’000 / 4"), "250000");
    assert.equal(anzeige("12'345.5 * 2"), "24691");
    assert.equal(berechnen("14'40 / 2"), null);
    assert.equal(berechnen("1'4400 / 2"), null);
    assert.equal(berechnen("1234'567 + 1"), null);
});

test("Prozent und Rest", () => {
    assert.equal(anzeige("15% * 200"), "30");
    assert.equal(anzeige("200 * 15%"), "30");
    assert.equal(anzeige("200 + 10%"), "220");
    assert.equal(anzeige("200 - 10%"), "180");
    assert.equal(anzeige("50%"), "0,5");
    assert.equal(anzeige("50% - 2"), "-1,5");
    assert.equal(anzeige("10 % 3"), "1");
    assert.equal(anzeige("10 % (4 - 1)"), "1");
});

test("Division durch 0 und nicht endliche Ergebnisse ergeben kein Ergebnis", () => {
    assert.equal(berechnen("1 / 0"), null);
    assert.equal(berechnen("5 % 0"), null);
    assert.equal(berechnen("0 ^ -1"), null);
    assert.equal(berechnen("10 ^ 400"), null);
    assert.equal(berechnen("(-8) ^ 0.5"), null);
    assert.equal(anzeige("0 / 5"), "0");
});

test("Keine Rechnung: einzelne Zahlen und Text", () => {
    assert.equal(berechnen("42"), null);
    assert.equal(berechnen("-5"), null);
    assert.equal(berechnen("(5)"), null);
    assert.equal(berechnen("ter"), null);
    assert.equal(berechnen("firefox"), null);
    assert.equal(berechnen(""), null);
    assert.equal(berechnen("   "), null);
    assert.equal(berechnen(null), null);
    assert.equal(berechnen("7-zip"), null);
});

test("Ungültige Ausdrücke", () => {
    assert.equal(berechnen("1 +"), null);
    assert.equal(berechnen("* 2"), null);
    assert.equal(berechnen("(1 + 2"), null);
    assert.equal(berechnen("1 + 2)"), null);
    assert.equal(berechnen("2(3 + 4)"), null);
    assert.equal(berechnen("1..5 + 1"), null);
    assert.equal(berechnen("1.000,5 + 1"), null);
    assert.equal(berechnen("5. + 1"), null);
    assert.equal(berechnen("192.168.1.1"), null);
    assert.equal(berechnen("27.09.2026"), null);
    assert.equal(berechnen("+41 79 123 45 67"), null);
    assert.equal(berechnen("1 + 1; rm -rf ~"), null);
    assert.equal(berechnen("Math.PI * 2"), null);
    assert.equal(berechnen("constructor"), null);
});

test("Gleichheitszeichen am Ende wird ignoriert", () => {
    assert.equal(anzeige("1440 / 16 ="), "90");
    assert.equal(anzeige("2*3="), "6");
});

test("Grenzen: Länge und Verschachtelung", () => {
    assert.equal(berechnen("1+".repeat(150) + "1"), null);
    assert.equal(anzeige("1+".repeat(90) + "1"), "91");
    assert.equal(berechnen("(".repeat(100) + "1+1" + ")".repeat(100)), null);
    assert.equal(anzeige("(".repeat(20) + "1+1" + ")".repeat(20)), "2");
    assert.equal(berechnen("-".repeat(150) + "1+1"), null);
});

test("Ergebnis als Zahl", () => {
    assert.deepEqual(berechnen("1440 / 16"), { wert: 90, anzeige: "90" });
    assert.equal(berechnen("-0 * 5").wert, 0);
    assert.equal(Object.is(berechnen("-0 * 5").wert, -0), false);
});

test("Formatieren", () => {
    assert.equal(formatieren(2.5, ","), "2,5");
    assert.equal(formatieren(2.5, "."), "2.5");
    assert.equal(formatieren(1e21, "."), "1e21");
    assert.equal(formatieren(1.5e22, ","), "1,5e22");
    assert.equal(formatieren(1e-7, "."), "1e-7");
    assert.equal(formatieren(0, ","), "0");
    assert.equal(anzeige("10^21 * 1.5"), "1.5e21");
});

test("Runden", () => {
    assert.equal(runden(0.1 + 0.2), 0.3);
    assert.equal(runden(Infinity), null);
    assert.equal(runden(NaN), null);
    assert.equal(runden(-0), 0);
});

test("Zerlegen", () => {
    assert.deepEqual(zerlegen("1+2"), [
        { art: "zahl", wert: 1, trenner: "" },
        { art: "op", wert: "+" },
        { art: "zahl", wert: 2, trenner: "" }
    ]);
    assert.equal(zerlegen("1 & 2"), null);
    assert.equal(zerlegen("a"), null);
});
