# zenOS

Ein ruhiges, persönliches Desktop-System für den Raspberry Pi 5. Basiert auf Ubuntu.

> Gebaut von Zeno ([@Zenovs](https://github.com/Zenovs)) zusammen mit Claude von Anthropic, mit Claude Code.

*English: zenOS is a calm, personal desktop for the Raspberry Pi 5, based on Ubuntu. Built by one person for one person, together with Claude. Documentation is in German.*

## Was zenOS ist

zenOS ist kein eigener Kernel. Unter der Haube läuft Ubuntu LTS, darauf ein schlanker Fenstermanager (labwc) und eine selbst gebaute Oberfläche (Quickshell). Alle Linux-Programme laufen normal weiter.

- **Ruhig:** Mitteilungen kommen gebündelt statt einzeln.
- **Modi und Zustände:** Du legst eigene Modi an, zum Beispiel Arbeit oder privat, dazu Zustände wie Fokus oder Sitzung.
- **Befehlsfeld:** Apps, Projekte, Werkzeuge und Einstellungen an einer Stelle, geöffnet mit `Super + Leertaste`.
- **Raster:** Fenster rasten per Tastendruck ein, bis zum 4er-Grid, passend zum Bildschirm-Setup.
- **Ein Terminal, das man versteht:** `Ctrl+C` kopiert, wenn Text markiert ist, sonst bricht es ab. Befehle erscheinen als Blöcke, Erklärungen gibt es offline.
- **Sicher ab Werk:** Der Sperrbildschirm zeigt keine Inhalte, bei Bildschirmfreigabe bleibt Privates verborgen, und es gibt keine Telemetrie.

Die Grundsätze stehen im [Manifest](MANIFEST.md).

## Status

Version 0.1 wird gebaut, nach [BAUAUFTRAG.md](BAUAUFTRAG.md). Installation per Skript und Testliste: [ANLEITUNG.md](ANLEITUNG.md). Nächste Schritte: [ROADMAP.md](ROADMAP.md).

## Herunterladen und installieren

Bis das erste Image erscheint, wird zenOS per Skript auf Ubuntu Server 26.04 LTS installiert, siehe [ANLEITUNG.md](ANLEITUNG.md). Danach geht es so:

1. Unter [Releases](../../releases) die neuste Datei `zenos-<version>-pi5-arm64.img.xz` herunterladen.
2. Prüfsumme vergleichen: `sha256sum -c SHA256SUMS`
3. Das Image mit dem Raspberry Pi Imager (eigenes Image wählen) oder mit balenaEtcher auf SD-Karte, USB-Stick oder NVMe schreiben.
4. Pi starten. Die Einrichtung fragt nach Name, optional Ort, Erscheinungsbild und erstem Modus.

Chrome, VS Code und 1Password sind nicht im Image. Sie werden beim ersten Start aus den offiziellen Paketquellen der Hersteller installiert. Das hat Lizenzgründe, und die Updates kommen so direkt vom Hersteller.

## Hardware

- Raspberry Pi 5, entwickelt und getestet im Argon ONE Gehäuse
- Später: x86-Rechner als eigene Installer-Variante

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
