// Tests für die Suche des Befehlsfelds (shell/befehlsfeld/suche.mjs).
// Ohne Abhängigkeiten: node --test test/einheiten/

import { test } from "node:test";
import assert from "node:assert/strict";
import {
    bewerten, dateiPasst, dateienSortieren, einzeilig, findArgumente, findZeile, globMaskieren, normalisieren, nutzungBonus,
    nutzungLeer, nutzungMerken, nutzungPruefen, nutzungRangliste, pfadAnzeige, programmName, sortieren,
    wortBewerten, woerter
} from "../../shell/befehlsfeld/suche.mjs";

test("Normalisieren", () => {
    assert.equal(normalisieren("  Über Größe "), "uber grosse");
    assert.equal(normalisieren("Café"), "cafe");
    assert.equal(normalisieren(null), "");
    assert.deepEqual(woerter("  VS   Code "), ["vs", "code"]);
});

test("Wortbewertung: Präfix vor Wortanfang vor enthalten", () => {
    assert.equal(wortBewerten("terminal", "ter"), 100);
    assert.equal(wortBewerten("kitty terminal", "ter"), 80);
    assert.equal(wortBewerten("gnome-terminal", "ter"), 80);
    assert.equal(wortBewerten("printer", "ter"), 60);
    assert.equal(wortBewerten("printer", "t"), 0);
    assert.equal(wortBewerten("printer", "er"), 0);
    assert.equal(wortBewerten("firefox", "xyz"), 0);
    assert.equal(wortBewerten("", "a"), 0);
});

test("Bewertung über mehrere Felder und Wörter", () => {
    const kitty = [{ text: "kitty", gewicht: 1 }, { text: "terminal emulator", gewicht: 0.8 }, { text: "kitty", gewicht: 0.6 }];
    assert.equal(bewerten(kitty, "ter"), 80);
    assert.equal(bewerten(kitty, "kit"), 110);
    assert.equal(bewerten(kitty, "kitty term"), (100 + 80) / 2);
    assert.equal(bewerten([{ text: "kitty terminal", gewicht: 1 }], "kitty term"), (100 + 80) / 2 + 10);
    assert.equal(bewerten(kitty, "kitty xyz"), 0);
    assert.equal(bewerten(kitty, ""), 0);
    assert.equal(bewerten([], "a"), 0);
});

test("Sortieren: Punkte, dann kürzerer Name", () => {
    const s = sortieren([
        { name: "Terminal lang", punkte: 100 },
        { name: "Tor", punkte: 80 },
        { name: "Terminal", punkte: 100 }
    ]);
    assert.deepEqual(s.map(x => x.name), ["Terminal", "Terminal lang", "Tor"]);
});

test("Programmname aus dem Exec-Befehl", () => {
    assert.equal(programmName(["/usr/bin/firefox", "%u"]), "firefox");
    assert.equal(programmName("code --new-window %F"), "code");
    assert.equal(programmName([]), "");
    assert.equal(programmName(null), "");
});

test("find-Argumente: Liste, keine Shell, Glob maskiert", () => {
    const args = findArgumente("/home/t", "ter", 5);
    assert.equal(args[0], "find");
    assert.equal(args[1], "/home/t");
    assert.ok(args.includes("-prune"));
    assert.ok(args.includes(".*"));
    assert.ok(args.includes("node_modules"));
    assert.deepEqual(args.slice(-4), ["-iname", "*ter*", "-printf", "%y\\t%p\\0"]);

    const zwei = findArgumente("/home/t", "rechnung 2024", 5);
    assert.deepEqual(zwei.slice(-6, -2), ["-iname", "*rechnung*", "-iname", "*2024*"]);

    const boese = findArgumente("/home/t", "a*b?[c] $(rm -rf ~); `x`", 5);
    assert.ok(boese.includes("*a\\*b\\?\\[c\\]*"));
    assert.ok(boese.includes("*$(rm*"));
    assert.ok(boese.every(a => typeof a === "string"));

    assert.equal(findArgumente("/home/t", "a", 5), null);
    assert.equal(findArgumente("/home/t", "  a ", 5), null);
    assert.equal(findArgumente("", "abc", 5), null);
    assert.equal(findArgumente("relativ", "abc", 5), null);
    // Eine Eingabe, die mit «-» beginnt, bleibt Teil des Musters und wird nie zur Option
    assert.deepEqual(findArgumente("/home/t", "-delete", 5).slice(-4, -2), ["-iname", "*-delete*"]);
    // Schrägstriche trennen Wörter (-iname prüft nur den Namen)
    assert.deepEqual(findArgumente("/home/t", "bilder/urlaub", 5).slice(-6, -2), ["-iname", "*bilder*", "-iname", "*urlaub*"]);
    assert.equal(findArgumente("/home/t", "//", 5), null);
});

test("Glob maskieren", () => {
    assert.equal(globMaskieren("a*b"), "a\\*b");
    assert.equal(globMaskieren("[x]?"), "\\[x\\]\\?");
    assert.equal(globMaskieren("a\\b"), "a\\\\b");
    assert.equal(globMaskieren("normal"), "normal");
});

test("find-Ausgabe lesen", () => {
    assert.deepEqual(findZeile("f\t/home/t/Dokumente/brief.txt", "/home/t"),
        { ordner: false, pfad: "/home/t/Dokumente/brief.txt", name: "brief.txt", tiefe: 2 });
    assert.deepEqual(findZeile("d\t/home/t/Bilder", "/home/t"),
        { ordner: true, pfad: "/home/t/Bilder", name: "Bilder", tiefe: 1 });
    assert.equal(findZeile("f\t/etc/passwd", "/home/t"), null);
    assert.equal(findZeile("l\t/home/t/x", "/home/t"), null);
    assert.equal(findZeile("", "/home/t"), null);
    assert.equal(findZeile("kaputt", "/home/t"), null);
    // Zeilenumbrüche im Namen stören nicht (Trenner ist \0)
    assert.equal(findZeile("f\t/home/t/a\nb", "/home/t").name, "a\nb");
});

test("Datei passt noch zur Eingabe", () => {
    assert.equal(dateiPasst("Rechnung-2024.pdf", "rech"), true);
    assert.equal(dateiPasst("Rechnung-2024.pdf", "rechnung 2024"), true);
    assert.equal(dateiPasst("Rechnung-2024.pdf", "rechnungx"), false);
    assert.equal(dateiPasst("Rechnung-2024.pdf", ""), false);
    assert.equal(dateiPasst(null, "a"), false);
});

test("Einzeilig", () => {
    assert.equal(einzeilig("a\nb\tc"), "a?b?c");
    assert.equal(einzeilig("normal.txt"), "normal.txt");
    assert.equal(einzeilig(undefined), "");
});

test("Pfad für die Anzeige", () => {
    assert.equal(pfadAnzeige("/home/t/Dokumente/brief.txt", "/home/t"), "~/Dokumente");
    assert.equal(pfadAnzeige("/home/t/brief.txt", "/home/t"), "~");
});

test("Dateitreffer ordnen", () => {
    const t = [
        { name: "alte-rechnung.pdf", tiefe: 1 },
        { name: "rechnung.pdf", tiefe: 3 },
        { name: "rechnung.pdf", tiefe: 2 },
        { name: "Rechnungen", tiefe: 1 }
    ];
    const s = dateienSortieren(t, "rechnung");
    assert.deepEqual(s.map(x => x.name + ":" + x.tiefe), ["Rechnungen:1", "rechnung.pdf:2", "rechnung.pdf:3", "alte-rechnung.pdf:1"]);
});

test("Nutzung: zählen, zuletzt, Rangliste", () => {
    let d = nutzungLeer();
    d = nutzungMerken(d, "firefox");
    d = nutzungMerken(d, "kitty");
    d = nutzungMerken(d, "kitty");
    d = nutzungMerken(d, "code");
    assert.deepEqual(d.anzahl, { firefox: 1, kitty: 2, code: 1 });
    assert.deepEqual(d.zuletzt, ["code", "kitty", "firefox"]);
    // Die zuletzt genutzte App bekommt einen Bonus (wie zehn Starts), danach zählt die Häufigkeit
    assert.deepEqual(nutzungRangliste(d), ["code", "kitty", "firefox"]);
    for (let i = 0; i < 10; i++)
        d = nutzungMerken(d, "firefox");
    d = nutzungMerken(d, "code");
    assert.deepEqual(nutzungRangliste(d), ["firefox", "code", "kitty"]);
    assert.ok(nutzungBonus(d, "firefox") > nutzungBonus(d, "kitty"));
    assert.ok(nutzungBonus(d, "unbekannt") === 0);
    assert.ok(nutzungBonus({ anzahl: { x: 500 }, zuletzt: ["x"] }, "x") <= 10);
});

test("Nutzung: nur gültige Daten, keine Pfade", () => {
    const d = nutzungPruefen({ anzahl: { "ok": 3, "../x": 2, "a/b": 1, "neg": -1, "text": "5", "f": 1.5 }, zuletzt: ["ok", "ok", "fehlt", 7], titel: "geheim" });
    assert.deepEqual(d, { version: 1, anzahl: { ok: 3 }, zuletzt: ["ok"] });
    assert.deepEqual(nutzungPruefen(null), nutzungLeer());
    assert.deepEqual(nutzungPruefen("kaputt"), nutzungLeer());
    assert.deepEqual(nutzungMerken(nutzungLeer(), "a/b"), nutzungLeer());
});

test("Nutzung: Alterung und Obergrenze", () => {
    let d = { version: 1, anzahl: { a: 999, b: 1, c: 10 }, zuletzt: ["a"] };
    d = nutzungMerken(d, "a");
    assert.deepEqual(d.anzahl, { a: 500, c: 5 });
    assert.deepEqual(d.zuletzt, ["a"]);

    let viele = nutzungLeer();
    for (let i = 0; i < 250; i++)
        viele = nutzungMerken(viele, "app" + i);
    assert.equal(Object.keys(viele.anzahl).length, 200);
    assert.equal(viele.zuletzt.length, 20);
    assert.equal(viele.zuletzt[0], "app249");
    assert.ok(viele.anzahl.app249 === 1);
});
