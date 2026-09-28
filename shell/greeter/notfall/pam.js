.pragma library

// Ablehnungen von greetd (PAM, Englisch und technisch, z. B. «pam_authenticate: AUTH_ERR») als
// verständliche Meldung. Genutzt vom Login (greeter/Ablauf.qml) und vom Notfall-Login; die Datei liegt
// hier, weil der Notfall-Login nur Dateien aus seinem eigenen Ordner laden kann. Tests:
// test/einheiten/greeter.test.mjs

// Das Passwort muss vor der Anmeldung geändert werden (z. B. ubuntu/ubuntu eines Images ohne Einstellungen
// im Raspberry Pi Imager). greetd 0.10 ruft kein pam_chauthtok auf, im Login geht das also nicht.
const PASSWORD_CHANGE = "Das Passwort muss zuerst geändert werden: Mit Ctrl+Alt+F2 zur Textkonsole, dort anmelden, ein neues Passwort setzen und mit «exit» abmelden. Zurück mit Ctrl+Alt+F7.";

// description: Beschreibung aus dem auth_error von greetd; typedName: der Benutzername wurde eingetippt
function failureText(description, typedName) {
    const t = String(description ?? "").toLowerCase();
    // vor «expired» und «acct_mgmt» prüfen: greetd meldet «pam_acct_mgmt: NEW_AUTHTOK_REQD»
    if (t.includes("new_authtok_reqd") || t.includes("authtok_expired") || t.includes("new one required"))
        return PASSWORD_CHANGE;
    if (t.includes("maxtries") || t.includes("too many") || t.includes("locked"))
        return "Zu viele Versuche. Bitte einen Moment warten und noch einmal versuchen.";
    if (t.includes("expired"))
        return "Dieses Konto ist abgelaufen.";
    if (t.includes("perm_denied") || t.includes("permission denied") || t.includes("acct_mgmt"))
        return "Dieses Konto darf sich hier nicht anmelden.";
    return typedName ? "Benutzername oder Passwort stimmt nicht." : "Das Passwort stimmt nicht. Bitte noch einmal.";
}
