# Sicherheit

Grundsatz 1: Sicherheit ist Standard und geht vor Design und Bequemlichkeit. Sie wird übernommen, nicht selbst erfunden.

## Unterbau

- Nur LTS-Versionen von Ubuntu. Sicherheitsupdates laufen automatisch (`unattended-upgrades`).
- Ubuntu Server holt ab Werk Nachrichten, ohne dass jemand etwas tut. zenOS schaltet beide ab, auf dem Weg, den
  Ubuntu dafür vorsieht (`scripts/module/70-sicherheit.sh`, `zen doctor` prüft es):
  - **motd-news** (Paket `motd-news-config`): Ein Timer ruft zweimal täglich `motd.ubuntu.com` auf und schickt im
    User-Agent Ubuntu-Version, Kernel, Architektur und `cloud_id` mit. zenOS setzt `ENABLED=0` in
    `/etc/default/motd-news`, nur wenn die Datei da ist. Der Timer bleibt, das Skript endet dann sofort.
  - **apt-news** (`ubuntu-pro-client`): holt bei `apt update` höchstens einmal täglich
    `motd.ubuntu.com/aptnews.json`. zenOS setzt `pro config set apt_news=false`, nur wenn der Client installiert ist.
  - Rückgängig: `ENABLED=1` in `/etc/default/motd-news` bzw. `sudo pro config set apt_news=true`. `install.sh`
    schaltet beides beim nächsten Lauf wieder ab; dauerhaft nur, wenn `_sicherheit_nachrichten` aus
    `modul_system` in `scripts/module/70-sicherheit.sh` entfernt wird.
  - Es bleiben die Verbindungen, die Updates holen: apt und `unattended-upgrades`, snapd (falls installiert) und
    `esm-cache` von `ubuntu-pro-client`. Dieser fragt bei `apt update` `contracts.canonical.com` nach verfügbaren
    Diensten (mit Architektur, Serie, Kernel und Virtualisierung, das Ergebnis wird zwischengespeichert) und lädt
    Paketlisten von `esm.ubuntu.com`. Ob er auch abgeschaltet werden soll, ist offen (`docs/module/m11.md`).
  - `apport` sammelt Absturzberichte nur lokal; gesendet wird erst mit `ubuntu-bug` (whoopsie gehört nicht zu
    Ubuntu Server).
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

Dazu kommen fünf Abschaltungen von Telemetrie: `MetricsReportingEnabled`, `UrlKeyedAnonymizedDataCollectionEnabled`,
`DomainReliabilityAllowed`, `FeedbackSurveysEnabled` und `SafeBrowsingSurveysEnabled`, alle `false`.

**Offene Entscheidung (Zeno): Safe Browsing Stufe 2 oder 1.** Stufe 2 (erweitert, wie oben) schickt Adressen in
Echtzeit sowie Proben von Seiten und Downloads an Google. Sie schliesst die erweiterte Berichterstattung ein, die
sich dann per Richtlinie nicht abschalten lässt. Das steht im Zielkonflikt mit der Leitplanke «keine Telemetrie»,
wird aber von Grundsatz 1 (Sicherheit) gestützt. Stufe 1 (Standard) gleicht Adressen über gekürzte Hash-Präfixe ab
und schickt keine Proben; dazu gehörte `"SafeBrowsingExtendedReportingEnabled": false`. Bis zur Entscheidung gilt
Stufe 2. Danach werden dieser Abschnitt und `system/chrome/policies/zenos.json` gemeinsam angepasst.

## VS Code-Richtlinie

Datei: `system/vscode/policy.json`, wird nach `/etc/vscode/policy.json` kopiert (root, 0644, Ordner nur für root
schreibbar). Wie die Chrome-Richtlinie liegt sie auch ohne VS Code und im Image bereit; sie ist nur Konfiguration.

```json
{
  "TelemetryLevel": "off"
}
```

VS Code liest diese Datei unter Linux ab Version 1.106. `off` schaltet Nutzungsdaten, Fehlerberichte und
Absturzberichte ab, dazu A/B-Experimente. Der Wert ist gesperrt: Die Einstellungen zeigen
`telemetry.telemetryLevel` als von der Organisation verwaltet, eine eigene Einstellung ändert nichts. Erweiterungen
anderer Anbieter halten sich nicht alle daran. Bewusst nicht gesetzt: `EnableFeedback` (Problembericht und Umfrage
senden nur auf Aktion) und `UpdateMode` (Updates kommen über apt, die Prüfung auf neue Versionen ist keine
Telemetrie).

## Terminal

- Bei gefährlichen Befehlen wie `rm -rf` auf Systemordnern, `curl … | sh` oder Rechte-Änderungen fragt zenOS einmal nach. «Abbrechen» ist die Vorauswahl.
- Terminal-Ausgaben verlassen den Rechner nie automatisch. «Fehler erklären» mit Claude braucht eine ausdrückliche Aktion und zeigt vorher, was gesendet wird.

## Repo und Releases

- Keine Geheimnisse und keine persönlichen Daten im Repo. gitleaks läuft als Pre-Commit-Hook und in GitHub Actions.
- GitHub nur mit 2FA. Das Repo ist das System: Wer das Konto übernimmt, bringt Code auf die Rechner.
- Releases enthalten `SHA256SUMS`, optional mit Signatur.
- Im Image werden SSH-Hostschlüssel und `machine-id` gelöscht und beim ersten Start neu erzeugt. Sonst hätten alle Kopien dieselben Schlüssel.
