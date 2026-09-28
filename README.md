<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/zeichen/zenos-schriftzug-dunkel.svg">
    <img src="assets/zeichen/zenos-schriftzug-hell.svg" alt="zenOS" height="56">
  </picture>
</h1>

Ein ruhiges, persönliches Desktop-System für den Raspberry Pi 5. Basiert auf Ubuntu.

> Gebaut von Zeno ([@Zenovs](https://github.com/Zenovs)) zusammen mit Claude von Anthropic, mit Claude Code.

*English: zenOS is a calm, personal desktop for the Raspberry Pi 5, based on Ubuntu. Built by one person for one person, together with Claude. Documentation is in German.*

## Was zenOS ist

zenOS ist kein eigener Kernel. Unter der Haube läuft Ubuntu LTS, darauf ein schlanker Fenstermanager (labwc) und eine selbst gebaute Oberfläche (Quickshell). Alle Linux-Programme laufen normal weiter.

- **Ruhig:** Mitteilungen kommen gebündelt statt einzeln.
- **Modi und Zustände:** Du legst eigene Modi an, zum Beispiel Arbeit oder privat, dazu Zustände wie Fokus oder Sitzung.
- **Befehlsfeld:** Apps, Web-Apps, Rechner, Dateien, Werkzeuge und Einstellungen an einer Stelle, geöffnet mit `Super + Leertaste`.
- **Raster:** Fenster rasten per Tastendruck ein, bis zum 4er-Grid, passend zum Bildschirm-Setup.
- **Ein Terminal, das man versteht:** `Ctrl+C` kopiert, wenn Text markiert ist, sonst bricht es ab. Befehle erscheinen als Blöcke, Erklärungen gibt es offline.
- **Sicher ab Werk:** Der Sperrbildschirm zeigt keine Inhalte, bei Bildschirmfreigabe bleibt Privates verborgen, und es gibt keine Telemetrie.

Die Grundsätze stehen im [Manifest](MANIFEST.md).

## Status

Version 0.1 ist gebaut und steht als Release-Kandidat (`v0.1.0-rc2`) auf dem Branch `dev`. Alle Module sind in Docker-Containern mit Ubuntu 26.04 arm64 getestet, der gleichen Architektur wie der Pi. Die Abnahme auf echter Hardware steht noch aus; was dort zu prüfen ist, steht in der Testliste in [ANLEITUNG.md](ANLEITUNG.md). Was 0.1 kann: [docs/funktionen.md](docs/funktionen.md). Nächste Schritte: [ROADMAP.md](ROADMAP.md).

## Installieren per Skript

Auf einem frisch installierten Ubuntu Server 26.04 LTS auf dem Pi 5, per SSH, Befehl für Befehl:

```
git clone https://github.com/Zenovs/zenOS.git ~/zenOS
cd ~/zenOS
git switch dev
./scripts/install.sh
sudo reboot
```

`install.sh` fragt einmal nach dem sudo-Passwort und baut beim ersten Mal Quickshell aus dem Quellcode. Ein zweiter Lauf meldet `0 Änderungen`, `zen doctor` prüft das Ergebnis. Nach dem Neustart erscheint der zenOS-Login. Alle Schritte, Voraussetzungen (Imager-Einstellungen, aktueller Bootloader) und die Testliste stehen in [ANLEITUNG.md](ANLEITUNG.md).

Chrome, VS Code, 1Password (mit CLI) und coremail installiert zenOS beim ersten Start, erst nach deiner ausdrücklichen Zustimmung. Sie kommen aus den offiziellen Quellen der Hersteller und nie ins Image; das hat Lizenzgründe, und die Updates kommen so direkt vom Hersteller. Nubix hat noch keinen ARM-Build und wird angeboten, sobald es einen gibt.

## Herunterladen und installieren

Bis das erste Image erscheint, wird zenOS per Skript auf Ubuntu Server 26.04 LTS installiert (siehe oben). Danach geht es so:

1. Unter [Releases](../../releases) die neuste Datei `zenos-<version>-pi5-arm64.img.xz` herunterladen.
2. Prüfsumme vergleichen: `sha256sum -c SHA256SUMS`
3. Das Image am besten mit dem Raspberry Pi Imager (eigenes Image wählen) auf SD-Karte, USB-Stick oder NVMe schreiben und dort unter «Einstellungen» Benutzer und Passwort setzen (optional SSH mit deinem öffentlichen Schlüssel), dazu Zeitzone und Tastaturbelegung. balenaEtcher geht auch, dann ohne Einstellungen.
4. Pi starten, ein bis zwei Minuten warten und im zenOS-Login anmelden. Ohne Einstellungen heisst der Benutzer `ubuntu` mit Passwort `ubuntu`, und das Passwort muss zuerst an der Textkonsole geändert werden: mit `Ctrl + Alt + F2` wechseln, als `ubuntu` / `ubuntu` anmelden, ein neues Passwort setzen, mit `exit` abmelden und mit `Ctrl + Alt + F7` zurück zum zenOS-Login.
5. Die Einrichtung fragt nach Name, optional Ort, Erscheinungsbild und erstem Modus.

Ubuntu 26.04 braucht auf dem Pi 5 einen Bootloader (EEPROM) vom 11.02.2025 oder neuer, sonst startet es nicht. Wie du ihn prüfst und aktualisierst, steht in [ANLEITUNG.md](ANLEITUNG.md) und in [docs/image-und-releases.md](docs/image-und-releases.md).

## Hardware

- Raspberry Pi 5, entwickelt und getestet im Argon ONE Gehäuse
- Später: x86-Rechner als eigene Installer-Variante

## Dokumentation

- [docs/architektur.md](docs/architektur.md): Aufbau, Datenorte, Installer, Update-Fluss
- [docs/konfiguration.md](docs/konfiguration.md): Modi, Zustände, Raster, Bildschirme, Einstellungen
- [docs/design.md](docs/design.md): Design-Tokens und Komponenten
- [docs/sicherheit.md](docs/sicherheit.md): Sicherheit und Datenschutz
- [docs/image-und-releases.md](docs/image-und-releases.md): Image, Releases, erster Start
- [docs/module/](docs/module/): ausführliche Notizen zu jedem Baustein

## Gebaut mit Claude

zenOS entsteht offen im Dialog mit Claude. Zeno gestaltet, entscheidet und testet auf echter Hardware. Claude Code schreibt einen Grossteil des Codes.

- Commits von Claude Code sind mit `Co-Authored-By: Claude` gekennzeichnet.
- Die Arbeitsanweisungen für Claude liegen offen in [CLAUDE.md](CLAUDE.md).

## Mitmachen

zenOS ist für eine Person gebaut. Issues und Pull Requests werden nicht angenommen.

Passt's dir, nimm's. Passt's dir nicht, bau dein eigenes.

## Rechtliches

zenOS ist ein unabhängiges Projekt, basiert auf Ubuntu und ist nicht mit Canonical verbunden. Ubuntu ist eine Marke von Canonical Ltd.

Der Code von zenOS steht unter der [MIT-Lizenz](LICENSE). Enthaltene Pakete und Schriften behalten ihre eigenen Lizenzen.
