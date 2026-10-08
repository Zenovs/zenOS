# Roadmap

Jeder Checkpoint endet mit einem Tag und einer Abnahme durch Zeno auf echter Hardware.

**Version 0.1:** C1 bis C8 werden gemeinsam in einem Durchgang gebaut, nach `BAUAUFTRAG.md`. Den Workflow für C9 baut Claude Code mit; das erste Release mit Image entsteht als Vorabversion mit `v0.1.0-rc6`, das erste «Latest» erst nach Zenos Abnahme mit dem Tag `v0.1.0`.

**Stand 0.1 (Oktober 2026):** C1 bis C9 sind gebaut und im Container getestet. Seit `v0.1.0-rc2` kamen dazu: der signierte Update-Kanal (`stabil`, `vorschau`, `dev`, Vertrauensanker, Automatik mit einstellbarem Zeitpunkt), Energie (Bildschirm aus nach der Sperre, Ausschalten nach langer Sperre und bei 3 % Akku), die Systemkennung zenOS (`ID=zenos`) und das Image als eigenständige Distribution mit Release-Seite und Quellcode aller Pakete. `v0.1.0-rc3` ist gebaut (unsigniert, nur als Workflow-Artefakt). Dazu die Fensterübersicht mit Wischen, Bildschirm aus am Login und Updates der Ubuntu-Basis über `zen update` samt Sperre gegen einen Wechsel der Hauptversion. `v0.1.0-rc4` ist der erste signierte Release-Kandidat; sein Image-Bau scheiterte an einer Dateiberechtigung im Workflow (behoben). Nächster Schritt ist `v0.1.0-rc6` (rc5 übersprungen), erstmals mit Release-Seite, als Vorabversion, danach die Abnahme auf echter Hardware und `v0.1.0`. Abweichungen sind unten mit «0.1:» markiert. Was genau umgesetzt ist, steht in `docs/funktionen.md`.

## C0 · Grundlagen

- [x] Manifest, CLAUDE.md und Doku
- [ ] Repo öffentlich, Issues deaktiviert, 2FA auf GitHub aktiv
- [x] gitleaks als Pre-Commit-Hook (dazu gitleaks in GitHub Actions)

## C1 · Basis auf dem Pi

- Ubuntu Server 26.04 LTS auf dem Pi 5
- `scripts/install.sh`, idempotent: labwc, Quickshell, kitty, fish, Schriften
- Autostart: Der Pi bootet direkt in eine leere labwc-Sitzung (0.1: Login über greetd mit Quickshell-Greeter, kein Autologin)
- Sicherheit Basis: automatische Sicherheitsupdates, Firewall, SSH nur mit Schlüssel über den 1Password-Agent (0.1: Firewall standardmässig an, Ausschalten nur mit Passwort, bis `v0.1.0-rc2` nur vorbereitet; SSH-Konfiguration fasst zenOS nicht an)
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
- Release mit Prüfsummen, Download direkt von GitHub; `vX.Y.Z` als «Latest», `-rcN` als Vorabversion (nie «Latest»).
  Bis `v0.1.0-rc3` bauten Tags mit `-rc` nur ein Workflow-Artefakt, ab `v0.1.0-rc4` bekommen sie eine Release-Seite (die erste hat
  `v0.1.0-rc6`, der Bau zu rc4 scheiterte, rc5 wurde übersprungen)
- Image nur aus einem mit dem Release-Schlüssel signierten Tag, Kanal aus dem Tag (`vX.Y.Z` → stabil, `-rcN` →
  vorschau), Anker und Zustand ab Werk im Image; Release nur bei grüner Prüfung

**Abnahme:** Ein frischer Pi wird mit dem Image in zehn Minuten zu zenOS.

## Danach

Projekt-Starter · Arbeitsstand pro Modus · zenOS-Check · Dev-Server-Übersicht · «Heute»-Ansicht mit Kalender und planbar · Tagesabschluss · Mikropausen · Zeiterfassung aus den Modi · Textbausteine pro Modus · Messen und Kontrast · Clip aufnehmen · Text aus Bild · QR-Codes · Notizzettel · Ans iPhone senden · Musiksteuerung · Abendlicht · Datei-Verlauf · Diktieren · Claude im Befehlsfeld · Fokus-Fenster (Zustand `fenster: fokus`) · Auslöser «Kalender» für Zustände

## Später

- Bürorechner (amd64) als eigener Installer
