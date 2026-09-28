// Einheitentests für shell/greeter/notfall/pam.js (Meldungen des Logins bei einer Ablehnung durch greetd).
// Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const quelle = readFileSync(join(wurzel, "shell", "greeter", "notfall", "pam.js"), "utf8");

// Die Datei ist ein QML-Skript («.pragma library»); ohne diese Zeile ist es gewöhnliches JavaScript.
const P = vm.createContext({});
vm.runInContext(quelle.replace(/^\.pragma library\s*$/m, ""), P);

const WECHSEL = /^Das Passwort muss zuerst geändert werden: .*Ctrl\+Alt\+F2.*Ctrl\+Alt\+F7\.$/;

test("Passwort muss geändert werden (greetd 0.10.3, im Container gemessen)", () => {
    assert.match(P.failureText("pam_acct_mgmt: NEW_AUTHTOK_REQD", false), WECHSEL);
    assert.match(P.failureText("pam_acct_mgmt: NEW_AUTHTOK_REQD", true), WECHSEL);
    // nicht «Konto abgelaufen» und nicht «darf sich nicht anmelden»
    assert.match(P.failureText("pam_acct_mgmt: AUTHTOK_EXPIRED", false), WECHSEL);
    assert.match(P.failureText("Authentication token is no longer valid; new one required", false), WECHSEL);
});

test("falsches Passwort", () => {
    assert.equal(P.failureText("pam_authenticate: AUTH_ERR", false), "Das Passwort stimmt nicht. Bitte noch einmal.");
    assert.equal(P.failureText("pam_authenticate: AUTH_ERR", true), "Benutzername oder Passwort stimmt nicht.");
    assert.equal(P.failureText("pam_authenticate: USER_UNKNOWN", true), "Benutzername oder Passwort stimmt nicht.");
    assert.equal(P.failureText("", false), "Das Passwort stimmt nicht. Bitte noch einmal.");
    assert.equal(P.failureText(undefined, true), "Benutzername oder Passwort stimmt nicht.");
});

test("Konto abgelaufen, gesperrt oder nicht erlaubt", () => {
    assert.equal(P.failureText("pam_acct_mgmt: ACCT_EXPIRED", false), "Dieses Konto ist abgelaufen.");
    assert.equal(P.failureText("pam_authenticate: MAXTRIES", false),
        "Zu viele Versuche. Bitte einen Moment warten und noch einmal versuchen.");
    assert.equal(P.failureText("pam_acct_mgmt: PERM_DENIED", false), "Dieses Konto darf sich hier nicht anmelden.");
    assert.equal(P.failureText("pam_acct_mgmt: AUTH_ERR", false), "Dieses Konto darf sich hier nicht anmelden.");
});

test("Die Meldung zum Passwortwechsel nennt den Weg vollständig", () => {
    const t = P.failureText("pam_acct_mgmt: NEW_AUTHTOK_REQD", false);
    for (const teil of ["Textkonsole", "anmelden", "neues Passwort", "exit", "Zurück"])
        assert.ok(t.includes(teil), teil);
});
