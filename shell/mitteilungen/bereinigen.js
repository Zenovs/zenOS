.pragma library
// Bereinigt Texte von Mitteilungen, ohne QML. Absender ist jedes Programm auf dem Sitzungsbus,
// bei Chrome auch jede Webseite. Getestet mit test/einheiten/mitteilungen.test.mjs (node).
//
// Angezeigt wird immer als reiner Text (textFormat: Text.PlainText). Beschriftungen von Aktionen
// enthalten zusätzlich gar keine Tags mehr, auch keine, die erst beim Auflösen der Entitäten
// entstehen: So bleiben sie auch in einem Text ohne diese Einstellung reiner Text (dort würde Qt
// Tags auswerten und z. B. Bilder aus dem Netz laden).

// Auszeichnungen, die Absender trotz «body-markup: nein» senden
var TAGS = /<\/?(b|i|u|s|a|img|span|p|font|small|big|em|strong|tt|code)(\s[^<>]*)?\/?>/gi;
var ENTITIES = Object.freeze({
    "&amp;": "&",
    "&lt;": "<",
    "&gt;": ">",
    "&quot;": "\"",
    "&apos;": "'",
    "&#39;": "'",
    "&#34;": "\""
});
// Steuerzeichen ausser Tab und Zeilenumbruch, Richtungszeichen (Einbettung, Überschreibung, Isolierung)
var UNSICHTBAR = /[\u0000-\u0008\u000b-\u001f\u007f‪-‮⁦-⁩]/g;

// Kürzt auf höchstens max Zeichen (mit «…»), ohne ein Ersatzpaar (z. B. Emoji) zu teilen
function truncate(text, max) {
    if (text.length <= max)
        return text;
    let end = Math.max(0, max - 1);
    const code = text.charCodeAt(end - 1);
    if (code >= 0xd800 && code <= 0xdbff)
        end -= 1;
    return text.slice(0, end) + "…";
}

// Text ohne Markup: bekannte Auszeichnungen entfernen, Entitäten auflösen, Steuer- und
// Richtungszeichen entfernen, Länge begrenzen. Zeilenumbrüche bleiben (höchstens eine Leerzeile).
function plainText(value, max) {
    let t = String(value ?? "");
    t = t.replace(/<br\s*\/?>/gi, "\n");
    t = t.replace(TAGS, "");
    t = t.replace(/&(amp|lt|gt|quot|apos|#39|#34);/g, m => ENTITIES[m]);
    t = t.replace(/\r\n?/g, "\n").replace(UNSICHTBAR, "");
    t = t.replace(/\n{3,}/g, "\n\n").trim();
    return truncate(t, max);
}

// Wie plainText, aber eine Zeile
function singleLine(value, max) {
    return plainText(value, max).replace(/\s*\n\s*/g, " ");
}

// Beschriftung einer Aktion: eine Zeile ohne jeden Tag. Entfernt wird wiederholt alles von «<»
// bis «>», bis nichts mehr passt; danach steht kein «<» mehr vor einem «>», und Qt erkennt
// keinen Tag mehr.
function actionLabel(value, max) {
    let t = singleLine(String(value ?? "").slice(0, 1000), 1000);
    let before = "";
    do {
        before = t;
        t = t.replace(/<[^<>]*>/g, "");
    } while (t !== before);
    return truncate(t.replace(/\s+/g, " ").trim(), max);
}
