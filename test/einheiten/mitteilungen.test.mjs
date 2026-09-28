// Einheitentests für shell/mitteilungen/bereinigen.js (Texte von Mitteilungen).
// Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const quelle = readFileSync(join(wurzel, "shell", "mitteilungen", "bereinigen.js"), "utf8");

// Die Datei ist ein QML-Skript («.pragma library»); ohne diese Zeile ist es gewöhnliches JavaScript.
const B = vm.createContext({});
vm.runInContext(quelle.replace(/^\.pragma library\s*$/m, ""), B);

// Qt deutet einen Text ohne textFormat als Rich Text, wenn ein Tag darin steht («<» … «>»).
// Eine Beschriftung ist sicher, wenn kein «<» vor einem «>» steht.
function ohneTag(text) {
    return !/<[^]*>/.test(text);
}

test("Aktion mit Tags und Bild aus dem Netz (Befund aus der Prüfung)", () => {
    assert.equal(B.actionLabel('<b>x</b><img src="http://127.0.0.1:8765/p.png">', 40), "x");
    assert.equal(B.actionLabel('<img src="http://127.0.0.1:8765/p.png">', 40), "");
    assert.equal(B.actionLabel("<IMG SRC=http://127.0.0.1:8765/p.png>Öffnen", 40), "Öffnen");
});

test("Aktion: Tags, die erst beim Auflösen der Entitäten entstehen, fallen auch weg", () => {
    assert.equal(B.actionLabel('&lt;img src="http://127.0.0.1:8765/p.png"&gt;Zwei', 40), "Zwei");
    assert.equal(B.actionLabel("&lt;b&gt;fett&lt;/b&gt;", 40), "fett");
});

test("Aktion: unbekannte und verschachtelte Tags", () => {
    assert.equal(B.actionLabel("<div>Mehr</div>", 40), "Mehr");
    assert.equal(B.actionLabel("<table><tr><td>Zelle</td></tr></table>", 40), "Zelle");
    assert.equal(B.actionLabel('<<b>img src="http://x/p.png">>OK', 40), ">OK");
    assert.ok(ohneTag(B.actionLabel("<<<img>>>", 40)));
    assert.ok(ohneTag(B.actionLabel("<!-- Kommentar -->Weiter", 40)));
});

test("Aktion: gewöhnliche Beschriftungen bleiben", () => {
    assert.equal(B.actionLabel("Öffnen", 40), "Öffnen");
    assert.equal(B.actionLabel("Speichern & schliessen", 40), "Speichern & schliessen");
    assert.equal(B.actionLabel("Antworten &amp; archivieren", 40), "Antworten & archivieren");
    assert.equal(B.actionLabel("a < b", 40), "a < b");
    assert.equal(B.actionLabel("  zwei\n  Zeilen \t ", 40), "zwei Zeilen");
});

test("Aktion: höchstens 40 Zeichen, mit «…», ohne ein Emoji zu teilen", () => {
    const lang = B.actionLabel("x".repeat(100), 40);
    assert.equal(lang.length, 40);
    assert.ok(lang.endsWith("…"));
    const emoji = B.actionLabel("x".repeat(38) + "😀😀", 40);
    assert.equal(emoji, "x".repeat(38) + "…");
    assert.equal(B.actionLabel("x".repeat(40), 40), "x".repeat(40));
    // sehr lange Eingaben werden vorher gekürzt
    assert.equal(B.actionLabel("<b>" + "y".repeat(100000), 40).length, 40);
});

test("Aktion: Zufallseingaben ergeben nie ein Tag", () => {
    // fester Startwert, damit ein Fehler nachvollziehbar bleibt
    let s = 20260928;
    const zufall = n => {
        s = (s * 1103515245 + 12345) % 2147483648;
        return s % n;
    };
    const teile = ["<", ">", "&lt;", "&gt;", "&amp;", "img", "b", "/", " ", "src=", "\"", "x", "<b>", "</b>", "\n", "<br>", "&"];
    for (let i = 0; i < 5000; i++) {
        let text = "";
        const laenge = 1 + zufall(24);
        for (let j = 0; j < laenge; j++)
            text += teile[zufall(teile.length)];
        const ergebnis = B.actionLabel(text, 40);
        assert.ok(ohneTag(ergebnis), JSON.stringify(text) + " → " + JSON.stringify(ergebnis));
        assert.ok(ergebnis.length <= 40);
        assert.ok(!ergebnis.includes("\n"));
    }
});

test("Text: bekannte Auszeichnungen weg, Entitäten aufgelöst, Zeilen bleiben", () => {
    assert.equal(B.plainText("<b>Fett</b> und <a href=\"https://example.org\">Link</a>", 100), "Fett und Link");
    assert.equal(B.plainText("eins<br>zwei<br/>drei", 100), "eins\nzwei\ndrei");
    assert.equal(B.plainText("a\n\n\n\nb", 100), "a\n\nb");
    assert.equal(B.plainText("&lt;tag&gt; &quot;x&quot; &#39;y&#39;", 100), "<tag> \"x\" 'y'");
    assert.equal(B.plainText("Windows\r\nZeile", 100), "Windows\nZeile");
});

test("Text: Steuer- und Richtungszeichen fallen weg", () => {
    assert.equal(B.plainText("a\u0007b‮c⁦d\u007f", 100), "abcd");
    assert.equal(B.plainText("Tab\tbleibt", 100), "Tab\tbleibt");
});

test("Zeile: Umbrüche werden zu Leerzeichen, Länge begrenzt", () => {
    assert.equal(B.singleLine("Titel\nzweite Zeile", 100), "Titel zweite Zeile");
    assert.equal(B.singleLine("x".repeat(300), 200).length, 200);
    assert.equal(B.singleLine(null, 10), "");
    assert.equal(B.singleLine(undefined, 10), "");
});
