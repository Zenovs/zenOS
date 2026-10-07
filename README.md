<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/zeichen/zenos-schriftzug-dunkel.svg">
    <img src="assets/zeichen/zenos-schriftzug-hell.svg" alt="zenOS" height="56">
  </picture>
</h1>

zenOS ist eine eigenständige Linux®-Distribution für den Raspberry Pi 5: ein ruhiger, persönlicher Desktop mit eigener Oberfläche, eigenem Befehlsfeld und eigenem Fenster-Raster. zenOS basiert auf Ubuntu 26.04 LTS. Pakete und Sicherheitsupdates kommen direkt aus dem Ubuntu-Archiv.

> Gebaut von Zeno ([@Zenovs](https://github.com/Zenovs)) zusammen mit Claude von Anthropic, mit Claude Code.

*English: zenOS is an independent Linux® distribution for the Raspberry Pi 5 – a calm, personal desktop. It is based on Ubuntu 26.04 LTS; packages and security updates come straight from the Ubuntu archive. zenOS is not affiliated with or endorsed by Canonical. Built by one person for one person, together with Claude. Documentation is in German.*

## Was zenOS ist

zenOS ist kein eigener Kernel. Unter der Haube läuft Ubuntu LTS, darauf ein schlanker Fenstermanager (labwc) und eine selbst gebaute Oberfläche (Quickshell). Alle Linux-Programme laufen normal weiter.

- **Ruhig:** Mitteilungen kommen gebündelt statt einzeln.
- **Modi und Zustände:** Du legst eigene Modi an, zum Beispiel Arbeit oder privat, dazu Zustände wie Fokus oder Sitzung.
- **Befehlsfeld:** Apps, Web-Apps, Rechner, Dateien, Werkzeuge und Einstellungen an einer Stelle, geöffnet mit `Super + Leertaste`.
- **Raster:** Fenster rasten per Tastendruck ein, bis zum 4er-Grid, passend zum Bildschirm-Setup.
- **Ein Terminal, das man versteht:** `Ctrl+C` kopiert, wenn Text markiert ist, sonst bricht es ab. Befehle erscheinen als Blöcke, Erklärungen gibt es offline.
- **Sicher ab Werk:** Der Sperrbildschirm zeigt keine Inhalte, bei Bildschirmfreigabe bleibt Privates verborgen, und es gibt keine Telemetrie. Sicherheitsupdates für das Grundsystem kommen automatisch von Ubuntu; Programme aus «universe» (etwa labwc, greetd, kitty und fish) bekommen verlässliche Sicherheitsfixes nur mit Ubuntu Pro.

Die Grundsätze stehen im [Manifest](MANIFEST.md).

## Status

Version 0.1 ist gebaut und liegt auf dem Branch `dev`; der letzte Release-Kandidat ist `v0.1.0-rc3` (nur als Workflow-Artefakt). Als Nächstes kommt der erste signierte, `v0.1.0-rc4`, mit Release-Seite als Vorabversion, nach der Abnahme dann `v0.1.0`. Alle Module sind in Docker-Containern mit Ubuntu 26.04 arm64 getestet, der gleichen Architektur wie der Pi. Die Abnahme auf echter Hardware steht noch aus; was dort zu prüfen ist, steht in der Testliste in [ANLEITUNG.md](ANLEITUNG.md). Was 0.1 kann: [docs/funktionen.md](docs/funktionen.md). Nächste Schritte: [ROADMAP.md](ROADMAP.md).

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

So installiert, folgt zenOS dem Kanal `dev`: `zen update` zeigt die neuen Commits und installiert sie nur nach deinem «ja», automatisch kommt auf `dev` nichts. Signierte Versionen (Kanäle `stabil` und `vorschau`, `sudo zen kanal wechseln …`) brauchen den Vertrauensanker, den nur das Image mitbringt. Von Hand setzt ihn `sudo zen kanal anker /opt/zenos/system/vertrauen`; die Fingerabdrücke zum Eintippen stehen in [docs/image-und-releases.md](docs/image-und-releases.md) unter «Signierte Releases». Empfohlen ist deshalb das Image.

Chrome, VS Code, 1Password (mit CLI) und coremail installiert zenOS beim ersten Start, erst nach deiner ausdrücklichen Zustimmung. Sie kommen aus den offiziellen Quellen der Hersteller und nie ins Image; das hat Lizenzgründe, und die Updates kommen so direkt vom Hersteller. Nubix hat noch keinen ARM-Build und wird angeboten, sobald es einen gibt.

## Herunterladen und installieren

Bis das erste Release mit der Marke «Latest» (`v0.1.0`) erscheint, wird zenOS per Skript auf Ubuntu Server 26.04 LTS installiert (siehe oben). Release-Kandidaten (`-rcN`, Marke «Pre-release») sind nur zum Testen da: Ein Gerät daraus folgt dem Kanal `vorschau` und bekommt auch die Release-Kandidaten späterer Versionen. Danach geht es so:

1. Auf der Seite des [neusten Releases](../../releases/latest) (Marke «Latest», nicht «Pre-release») die Datei `zenos-<version>-pi5-arm64.img.xz` herunterladen, dazu `SHA256SUMS` und `zenos-<version>.rpi-imager-manifest`.
2. Prüfsummen vergleichen: `sha256sum -c --ignore-missing SHA256SUMS` (die Liste nennt auch die Paketliste, die du nicht brauchst). Die Herkunft bestätigt `gh attestation verify zenos-<version>-pi5-arm64.img.xz --repo Zenovs/zenOS`, ebenso für die Manifest-Datei. Über das Manifest lädt der Imager das Image selbst und prüft es gegen die Prüfsummen darin.
3. Das Image am besten mit dem Raspberry Pi Imager ab 2.0.11 auf SD-Karte, USB-Stick oder NVMe schreiben: die Manifest-Datei per Doppelklick öffnen (oder «App Options › Content Repository › Edit › Use custom file»), zenOS wählen und unter «Einstellungen» Benutzer und Passwort setzen (optional SSH mit deinem öffentlichen Schlüssel), dazu Zeitzone und Tastaturbelegung. «sudo ohne Passwort» bleibt aus: Damit, und mit einem Imager bis 2.0.10, schreibt cloud-init eine sudo-Regel ohne Passwort (`zen doctor` warnt dann). Wählst du die `.img.xz` direkt als eigenes Image, bietet der Imager keine Einstellungen an. balenaEtcher geht auch, dann ohne Einstellungen.
4. Pi starten, ein bis zwei Minuten warten und im zenOS-Login anmelden. Ohne Einstellungen heisst der Benutzer `user` mit Passwort `user`, und das Passwort muss zuerst an der Textkonsole geändert werden: mit `Ctrl + Alt + F2` wechseln, als `user` / `user` anmelden, ein neues Passwort setzen, mit `exit` abmelden und mit `Ctrl + Alt + F7` zurück zum zenOS-Login. Für `user` fragt sudo immer nach dem Passwort, SSH nimmt nur Schlüssel an.
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

zenOS ist ein unabhängiges Projekt. Es basiert auf Ubuntu, ist aber nicht mit Canonical verbunden und wird von Canonical weder unterstützt noch geprüft. Das System weist sich als zenOS aus; «basiert auf Ubuntu» steht in der Systemkennung, in `zen version` und bei der Anmeldung.

Der Code von zenOS steht unter der [MIT-Lizenz](LICENSE). Das Image enthält Pakete aus Ubuntu unter ihren eigenen Lizenzen und unfreie, weitergebbare Firmware von Raspberry Pi, Broadcom und Cypress; die Lizenztexte liegen im System unter `/usr/share/doc/*/copyright`. Schriften und Quickshell (LGPL 3) behalten ihre eigenen Lizenzen. Den Quellcode von zenOS gibt es in diesem Repo; den aller Pakete im Image, in genau den ausgelieferten Versionen, und den von Quickshell auf derselben Release-Seite wie das Image (`zenos-<version>-quellen-teil*.tar`, Übersicht in `zenos-<version>-QUELLEN.txt`). Im System stehen die Hinweise unter `/usr/local/share/doc/zenos/`.

Ubuntu and Canonical are registered trademarks of Canonical Ltd. Linux® is the registered trademark of Linus Torvalds in the U.S. and other countries. Raspberry Pi is a trademark of Raspberry Pi Ltd.
