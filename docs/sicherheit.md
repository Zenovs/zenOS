# Sicherheit

Grundsatz 1: Sicherheit ist Standard und geht vor Design und Bequemlichkeit. Sie wird übernommen, nicht selbst erfunden.

## Unterbau

- Nur LTS-Versionen von Ubuntu. Sicherheitsupdates laufen automatisch (`unattended-upgrades`).
- Die Firewall (`ufw`) blockiert alles Eingehende. SSH ist nur mit Schlüssel und nur im eigenen Netz erlaubt.
- Festplattenverschlüsselung: auf dem Bürorechner Pflicht. Auf dem Pi ist sie das Ziel; wie sie beim ersten Start eingerichtet wird, klären C4 und C9.
- Secure Boot: auf dem Bürorechner aktiv. Auf dem Pi bewusst nicht, weil dort Schlüssel dauerhaft in den Chip geschrieben werden.
- Backups laufen automatisch und verschlüsselt auf einen eigenen Server oder ein NAS.

## Oberfläche

- Der Sperrbildschirm nutzt `ext-session-lock`. Stürzt die Oberfläche ab, bleibt der Bildschirm gesperrt.
- Die Anmeldung läuft über PAM. zenOS verarbeitet nie selbst Passwörter.
- Automatische Sperre bei Inaktivität und Standby. Sie ist nicht abschaltbar.
- Bei Bildschirmfreigabe werden Mitteilungsinhalte immer verborgen.
- Das Befehlsfeld startet Prozesse mit Argument-Listen, nie über `sh -c`.
- Die Nutzungsstatistik speichert App-Namen und Zeiten, aber keine Fenstertitel.
- Eine Zwischenablage-Historie, falls sie kommt, ignoriert 1Password und löscht sich selbst.

## 1Password

- Passwörter, Karten und Schlüssel liegen nur in 1Password.
- Der SSH-Agent von 1Password authentifiziert Git und SSH. Er funktioniert nicht mit Snap- oder Flatpak-Installationen, deshalb wird 1Password direkt installiert.
- API-Schlüssel, etwa für Claude, holt zenOS zur Laufzeit über die Kommandozeile `op`.
- Sperrt zenOS den Bildschirm, sperrt sich 1Password mit.

## Chrome-Richtlinien

Datei: `system/chrome/policies/zenos.json`, wird nach `/etc/opt/chrome/policies/managed/` kopiert.

```json
{
  "HttpsOnlyMode": "force_enabled",
  "SafeBrowsingProtectionLevel": 2,
  "PasswordManagerEnabled": false,
  "AutofillCreditCardEnabled": false,
  "BlockThirdPartyCookies": true,
  "ExtensionInstallBlocklist": ["*"],
  "ExtensionInstallAllowlist": ["<1Password-Erweiterungs-ID>"],
  "ExtensionInstallForcelist": ["<1Password-Erweiterungs-ID>"]
}
```

Die ID der 1Password-Erweiterung vor dem Einbau im Chrome Web Store prüfen.

## Terminal

- Bei gefährlichen Befehlen wie `rm -rf` auf Systemordnern, `curl … | sh` oder Rechte-Änderungen fragt zenOS einmal nach. «Abbrechen» ist die Vorauswahl.
- Terminal-Ausgaben verlassen den Rechner nie automatisch. «Fehler erklären» mit Claude braucht eine ausdrückliche Aktion und zeigt vorher, was gesendet wird.

## Repo und Releases

- Keine Geheimnisse und keine persönlichen Daten im Repo. gitleaks läuft als Pre-Commit-Hook und in GitHub Actions.
- GitHub nur mit 2FA. Das Repo ist das System: Wer das Konto übernimmt, bringt Code auf die Rechner.
- Releases enthalten `SHA256SUMS`, optional mit Signatur.
- Im Image werden SSH-Hostschlüssel und `machine-id` gelöscht und beim ersten Start neu erzeugt. Sonst hätten alle Kopien dieselben Schlüssel.
