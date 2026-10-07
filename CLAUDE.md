# CLAUDE.md – Arbeitsanweisungen für Claude Code

## Projekt in einem Satz

zenOS ist eine eigene Desktop-Oberfläche auf Ubuntu 26.04 LTS für einen Raspberry Pi 5, gebaut für genau eine Person (Zeno). Später soll sie auch auf einem x86-Bürorechner laufen.

## Zuerst lesen

1. `MANIFEST.md`: die Grundsätze in Rangordnung. Bei einem Konflikt gewinnt der höhere Grundsatz.
2. `BAUAUFTRAG.md`: Ist ein Bauauftrag aktiv, gilt er. Dann arbeitest du selbstständig durch und hältst `docs/baufortschritt.md` aktuell.
3. `ROADMAP.md`: der aktuelle Checkpoint. Ohne aktiven Bauauftrag arbeitest du nur an diesem.
4. `docs/`: Architektur, Konfiguration, Design, Sicherheit, Image und Releases.

## Sprache und Stil

- **Mit Zeno:** Hochdeutsch, Du-Form, «ss» statt «ß», kurz und direkt. Widersprich ehrlich, wenn etwas gegen das Manifest geht.
- **Doku und Kommentare:** Deutsch.
- **Code-Bezeichner:** Englisch.
- **Konfigurationsschlüssel:** Deutsch ohne Umlaute, zum Beispiel `zustaende`, `ausloeser`.
- **Befehle für Zeno:** Wenn Zeno einen Terminal-Befehl selbst ausführen soll, gib immer nur einen und warte auf seine Rückmeldung.

## Architektur in Kürze

| Ebene | Wahl | Hinweis |
|---|---|---|
| Unterbau | Ubuntu 26.04 LTS Server (arm64 auf dem Pi, später amd64) | ohne GNOME |
| Fenstermanager | labwc (Wayland) | Einrasten per `SnapToRegion`, kein automatisches Kacheln |
| Oberfläche | Quickshell (QML, Qt 6) | Leiste, Befehlsfeld, Mitteilungen, Sperrbildschirm, Login, Einstellungen |
| Terminal | kitty mit fish | schlaues Ctrl+C, Shell-Integration |
| Apps | Chrome (Standardbrowser), Firefox, VS Code, 1Password, coremail (Standard-Mail), Nubix | proprietäre Apps nie ins Image |

Details: `docs/architektur.md`.

## Repo-Struktur

```
zenos/
├── MANIFEST.md            Grundsätze
├── CLAUDE.md              diese Datei
├── BAUAUFTRAG.md          aktueller Bauauftrag (Version 0.1)
├── ANLEITUNG.md           Installation und Testliste für Zeno
├── ROADMAP.md             Checkpoints
├── docs/                  Architektur, Konfiguration, Design, Sicherheit, Image, Baufortschritt
├── assets/                Zeichen, Schriften
├── shell/                 Quickshell-Oberfläche (QML), Einstieg shell.qml, Login greeter.qml
│   └── theme/tokens.json  einzige Quelle für Farben, Schrift, Radien, Bewegung
├── system/                Konfiguration für labwc, greetd, systemd, Portale, PAM, kitty, fish, apt, Richtlinien
├── scripts/               install.sh (idempotent, Module), zen, Hilfsprogramme, pruefen.sh
├── image/                 Bau des Pi-Images
├── config/                Schemas, Vorlagen (Zustände, Raster) und neutrale Beispiele
├── test/                  Testumgebung im Container (Mac), Einheitentests
└── .github/workflows/     Prüfung bei jedem Push, Image-Build und Releases
```

## Arbeitsweise

- **Checkpoints:** Ohne aktiven Bauauftrag wird iterativ nach `ROADMAP.md` gearbeitet. Pro Checkpoint: kurz planen, Zeno den Plan zeigen, umsetzen, auf dem Pi testen, Tag setzen.
- **Bauauftrag:** Ist einer aktiv, arbeitest du ohne Zwischenfragen durch. Du fragst nur bei den Punkten, die der Auftrag unter «Nur nach Rückfrage» nennt, oder bei echten Blockern.
- **Commits:** klein und thematisch. Commit-Nachrichten auf Deutsch im Format `bereich: was und warum`, zum Beispiel `leiste: Uhrzeit aus Tokens`.
- **Attribution:** Die Claude-Attribution in Commits bleibt drin (`Co-Authored-By`). zenOS macht kein Geheimnis daraus, dass es mit Claude entsteht.
- **Rückfrage vor Eingriffen:** Vor Änderungen an System, Paketen oder Netzwerk kurz beschreiben, was passiert, und auf ein Ja warten. Ausnahme: was ein aktiver Bauauftrag ausdrücklich freigibt.

## Deploy und Test

- Der Branch `dev` läuft auf dem Pi. Tags `v0.x` dürfen auf den Bürorechner.
- **Deploy auf den Pi:** pushen, dann per SSH `zen update --nur-zenos` auslösen. Es zieht `dev` und führt `scripts/install.sh` aus. Paketänderungen der Ubuntu-Basis (Schritt 2 von `zen update`) bleiben bei Zeno.
- **Live-Reload:** Änderungen an der Oberfläche (QML) lädt Quickshell live nach. Systemänderungen laufen immer über `scripts/install.sh`, das beliebig oft laufen darf.
- **Wo gebaut wird:** am liebsten direkt auf dem Pi (Claude Code per SSH in einer tmux-Sitzung). Auf dem Mac laufen labwc und Quickshell nicht nativ, aber in der Testumgebung `test/container/` (Docker, Ubuntu 26.04 arm64, headless labwc mit Screenshots). Version 0.1 wurde so gebaut; die Abnahme auf echter Hardware ersetzt das nicht.
- **Selbsttest:** `scripts/pruefen.sh` (shellcheck, JSON-Schemas, Hex- und sh-c-Regel, Einheitentests, qmllint, gitleaks, Start-Test der Oberfläche).
- **Zurück:** Jeder funktionierende Stand bekommt einen Tag. Mit `zen rollback <tag>` geht es zurück.

## Harte Regeln

Diese Regeln gelten immer:

1. **Keine persönlichen Daten im Repo:** keine Namen, Konten, Modi, Orte, Hostnamen oder IP-Adressen. Beispiele bleiben neutral (`config/beispiele/`).
2. **Keine Geheimnisse im Repo:** API-Schlüssel kommen zur Laufzeit aus 1Password (`op`). Vor jedem Commit läuft gitleaks.
3. **SSH, Firewall und Netzwerk** nie ohne ausdrückliche Anweisung anfassen. Solange SSH geht, ist alles reparierbar.
4. **Eingaben aus dem Befehlsfeld** nie ungeprüft an eine Shell geben. Prozesse mit Argument-Listen starten, nie mit `sh -c`.
5. **Sperrbildschirm** nur über `ext-session-lock` und PAM. zenOS fasst nie selbst ein Passwort an.
6. **Leitplanken** aus `MANIFEST.md` sind Code, nicht Konfiguration. Sie dürfen nie abschaltbar werden.
7. **Proprietäre Software** (Chrome, VS Code, 1Password) kommt nie ins Image. Sie wird beim ersten Start aus den offiziellen Paketquellen installiert.
8. **Keine Telemetrie, keine automatischen Uploads.** Nichts verlässt den Rechner ohne Zenos ausdrückliche Aktion.

## Design-Regeln

- Farben, Schriften, Radien, Abstände und Bewegung kommen nur aus `shell/theme/tokens.json`. Im QML stehen keine Hex-Werte.
- Kein Weichzeichnen (Blur). Der Hintergrund wird nur abgedunkelt.
- Animationen dauern höchstens 200 ms, mit `Easing.OutCubic`. Keine Animation ist besser als eine ruckelnde.
- Hell und dunkel sind gleichwertig. Jede Komponente wird in beiden geprüft.
- Details und Komponenten stehen in `docs/design.md`.

## Definition of Done

- Läuft flüssig auf dem Pi 5, in hell und dunkel.
- Enthält keine persönlichen Daten und keine Geheimnisse, gitleaks ist sauber.
- `scripts/install.sh` läuft zweimal hintereinander ohne Fehler.
- Die Doku in `docs/` ist angepasst, falls sich Verhalten geändert hat.
- Zeno hat auf echter Hardware abgenommen.
