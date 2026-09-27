# Image und Releases

Ziel: Ein fertiges Pi-Image liegt als Release auf GitHub und lässt sich direkt herunterladen und flashen.

## Ablauf in GitHub Actions

1. **Auslöser:** ein Tag `v*`.
2. **Runner:** `ubuntu-24.04-arm`. Er läuft nativ auf arm64 und ist für öffentliche Repos kostenlos.
3. **Basis:** das offizielle Ubuntu 26.04 LTS Server-Image für den Raspberry Pi herunterladen und die Prüfsumme kontrollieren.
4. **Anpassen:** das Image als Loop-Gerät einhängen und per `chroot` `scripts/install.sh --image` ausführen. Das Image enthält nur freie Pakete und zenOS.
5. **Aufräumen:**
   - Paket-Cache und Logs löschen.
   - SSH-Hostschlüssel und `machine-id` entfernen; beide werden beim ersten Start neu erzeugt.
   - Das Dateisystem verkleinern.
6. **Packen:** `xz -T0 -9`, dazu `SHA256SUMS` erzeugen und optional signieren.
7. **Veröffentlichen:** als Release-Asset `zenos-<version>-pi5-arm64.img.xz`.

## Grenzen

- **Speicher:** Der Runner hat 14 GB SSD. Das Image muss beim Bau also schlank bleiben.
- **Dateigrösse:** Einzelne Release-Dateien müssen kleiner als 2 GiB sein. Ein schlankes Image ist besser als ein zerstückeltes.

## Was nicht ins Image kommt

Chrome, VS Code und 1Password sind proprietär und dürfen in der Regel nicht selbst weiterverteilt werden. Die Einrichtung beim ersten Start installiert sie aus den offiziellen Paketquellen der Hersteller. Vorher zeigt sie klar an, was installiert wird. Updates kommen danach direkt vom Hersteller.

## Erster Start

1. Neue SSH-Hostschlüssel und eine neue `machine-id` werden erzeugt.
2. Die Einrichtung fragt nach Name, optional Ort, Erscheinungsbild und erstem Modus.
3. Die proprietären Apps werden installiert.
4. Persönliches wird nur unter `~/.config/zenos/` abgelegt.

## Flashen

Mit dem Raspberry Pi Imager (eigenes Image wählen) oder mit balenaEtcher auf SD-Karte, USB-Stick oder NVMe.

## Name und Marke

Das Image heisst zenOS und trägt kein Ubuntu-Logo. zenOS wird als «basiert auf Ubuntu» beschrieben. Vor dem ersten Release die aktuelle Markenrichtlinie von Canonical prüfen.

## Bürorechner

Für x86 kommt später ein eigener Installer-Stick: ein Ubuntu-ISO mit Autoinstall, das nach der Installation `scripts/install.sh` ausführt. Die Verschlüsselung fragt der Installer interaktiv ab. Kein Passwort steht in einer Datei.
