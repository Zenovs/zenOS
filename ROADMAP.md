# Roadmap

Jeder Checkpoint endet mit einem Tag und einer Abnahme durch Zeno auf echter Hardware.

**Version 0.1:** C1 bis C8 werden gemeinsam in einem Durchgang gebaut, nach `BAUAUFTRAG.md`. Den Workflow für C9 baut Claude Code mit; das erste Image entsteht aber erst nach Zenos Abnahme mit dem Tag `v0.1.0`.

**Stand 0.1 (Release-Kandidat `v0.1.0-rc2`):** C1 bis C8 und der Workflow für C9 sind gebaut und im Container getestet, die Abnahme auf dem Pi steht aus. Abweichungen sind unten mit «0.1:» markiert. Was genau umgesetzt ist, steht in `docs/funktionen.md`.

## C0 · Grundlagen

- [x] Manifest, CLAUDE.md und Doku
- [ ] Repo öffentlich, Issues deaktiviert, 2FA auf GitHub aktiv
- [x] gitleaks als Pre-Commit-Hook (dazu gitleaks in GitHub Actions)

## C1 · Basis auf dem Pi

- Ubuntu Server 26.04 LTS auf dem Pi 5
- `scripts/install.sh`, idempotent: labwc, Quickshell, kitty, fish, Schriften
- Autostart: Der Pi bootet direkt in eine leere labwc-Sitzung (0.1: Login über greetd mit Quickshell-Greeter, kein Autologin)
- Sicherheit Basis: automatische Sicherheitsupdates, Firewall, SSH nur mit Schlüssel über den 1Password-Agent (0.1: Firewall vorbereitet, aber aus; danach standardmässig an, Ausschalten nur mit Passwort; SSH-Konfiguration fasst zenOS nicht an)
- `zen update` und `zen rollback`
- Argon ONE: Lüftersteuerung als Dienst

**Abnahme:** Push auf `dev`, dann `zen update`, und die Änderung ist auf dem Pi sichtbar.

## C2 · Tokens und Leiste

- `shell/theme/tokens.json` wird zum Quickshell-Theme
- Leiste: Modus-Chip (vorerst statisch), Zeit, nächster Termin als Platzhalter, System-Knopf (0.1: Modus-Chip mit Umschalter; Termine erst «Danach», ohne Platzhalter)
- Hell und dunkel mit einem Schalter, systemweit für GTK, Qt, Chrome und VS Code

## C3 · Befehlsfeld

- Apps und Web-Apps starten, rechnen, Dateien suchen
- Erste Werkzeuge: Screenshot, Farbpipette

## C4 · Sperrbildschirm und Sicherheit

- Sperrbildschirm über `ext-session-lock` und PAM, automatische Sperre
- Chrome-Richtlinien, 1Password mit SSH-Agent
- Leitplanken als Code

## C5 · Modi und Zustände

- Konfigurationsmodell nach `docs/konfiguration.md`
- Mitteilungszentrale mit Bündelung
- Editor «Modi & Zustände»
- Zustand «Sitzung» startet automatisch bei Bildschirmfreigabe

## C6 · Raster und Bildschirme

- labwc-Regionen, Tastenkürzel, Overlay beim Ziehen
- Bildschirm-Profile; beim Abstecken ziehen Fenster geordnet um

## C7 · Terminal

- kitty: Ctrl+C kopiert oder bricht ab, Ctrl+V fügt ein, dazu die Super-Kürzel
- fish, klare Eingabezeile, Befehlsblöcke, `?` zum Erklären, Warnung bei gefährlichen Befehlen

## C8 · Apps und erster Start

- Einrichtung beim ersten Start
- Installation von Chrome, VS Code und 1Password aus den offiziellen Quellen
- coremail und Nubix als ARM-Builds (0.1: Nubix hat noch keinen ARM-Build)

## C9 · Image und Releases

- GitHub Actions baut `zenos-<version>-pi5-arm64.img.xz`
- Release mit Prüfsummen, Download direkt von GitHub (0.1: Tags mit `-rc` bauen nur ein Workflow-Artefakt)

**Abnahme:** Ein frischer Pi wird mit dem Image in zehn Minuten zu zenOS.

## Danach

Projekt-Starter · Arbeitsstand pro Modus · zenOS-Check · Dev-Server-Übersicht · «Heute»-Ansicht mit Kalender und planbar · Tagesabschluss · Mikropausen · Zeiterfassung aus den Modi · Textbausteine pro Modus · Messen und Kontrast · Clip aufnehmen · Text aus Bild · QR-Codes · Notizzettel · Ans iPhone senden · Musiksteuerung · Abendlicht · Datei-Verlauf · Diktieren · Claude im Befehlsfeld · Fokus-Fenster (Zustand `fenster: fokus`) · Auslöser «Kalender» für Zustände

## Später

- Bürorechner (amd64) als eigener Installer
