# Image und Releases

Ziel: Ein fertiges Pi-Image liegt als Release auf GitHub und lässt sich direkt herunterladen und flashen. Wie der
Bau im Einzelnen läuft (Optionen, lokal im Container, Aufräumen), steht in `image/README.md`.

## Ablauf in GitHub Actions

`.github/workflows/image.yml` ruft `image/bauen.sh` auf.

1. **Auslöser:** ein Tag `v*`, sonst nichts.
2. **Runner:** `ubuntu-24.04-arm`. Er läuft nativ auf arm64 und ist für öffentliche Repos kostenlos.
3. **Basis:** das offizielle Ubuntu 26.04 LTS Server-Image für den Raspberry Pi, die neueste Punktversion laut
   `SHA256SUMS` auf cdimage.ubuntu.com (derzeit `ubuntu-26.04.1-preinstalled-server-arm64+raspi.img.xz`). Die
   Signatur von `SHA256SUMS` wird mit GPG gegen den Ubuntu-Schlüssel geprüft (Fingerabdruck fest im Skript), danach
   die Prüfsumme der Datei.
4. **Anpassen:** das Image vergrössern, als Loop-Gerät einhängen, `/opt/zenos` als Checkout des Tags anlegen und
   per `chroot` `ZENOS_KANAL=dev /opt/zenos/scripts/install.sh --image` ausführen. Das Image enthält nur freie
   Pakete und zenOS; Quickshell wird dabei gebaut. Danach prüft `bauen.sh` im chroot die Kennung zenOS und die
   Ubuntu-Sicherheitsquelle (Umlenkung von os-release, `ID=zenos`, Codename wie Ubuntu, `51zenos-ubuntu-quellen`,
   `zenos-sicherheitsquelle` Exit 0, `zenos-kennung pruefen`, kein Ubuntu in `PRETTY_NAME`) und bricht sonst ab.
5. **Aufräumen:**
   - Paket-Cache und Logs löschen.
   - SSH-Hostschlüssel und `machine-id` entfernen; beide werden beim ersten Start neu erzeugt.
   - Das Dateisystem verkleinern (mit 256 MiB Luft); beim ersten Start wächst es auf die ganze Karte.
6. **Packen:** `xz -T0 -9`, dazu `SHA256SUMS`. Eine Signatur der Release-Dateien gibt es nicht.
7. **Veröffentlichen:**
   - Tags mit `-rc` (z. B. `v0.1.0-rc1`): nur ein Workflow-Artefakt, **kein Release**.
   - Andere Tags: Release mit `zenos-<version>-pi5-arm64.img.xz` und `SHA256SUMS`. Tags mit Bindestrich (z. B.
     `v0.2.0-beta1`) werden als Vorabversion markiert.

## Name, Version und Kanal

- Die Datei heisst `zenos-<version>-pi5-arm64.img.xz`, die Version ohne «v»: `v0.1.0` → `zenos-0.1.0-pi5-arm64.img.xz`.
- Im Image steht `/opt/zenos` losgelöst auf dem Tag, mit allen Tags und `origin` auf GitHub.
- Der Kanal für `zen update` ist im Image `dev`, wie auf dem Pi, bis `main` Releases trägt. Das erste `zen update`
  wechselt vom Tag auf `origin/dev`.

## Grösse und Dauer

Gemessen beim Integrationstest mit dem vollen Stand (Container mit 2 CPUs und 4 GB RAM, gleiche Werkzeuge wie der
Runner):

- **Grösse:** `.img.xz` mit `xz -9` 1 553 110 924 Byte (1481 MiB, rund 1,5 GB), also 72 % der Grenze von 2 GiB.
  Entpackt 4882 MiB, im Root-Dateisystem 3,7 GiB belegt.
- **Dauer:** Download und Prüfung knapp 1 Minute, `install.sh --image` 9 Minuten (davon Quickshell-Bau 8 Minuten
  mit 2 Jobs), `xz -9` allein 29 Minuten (bei 4 GB RAM nur einfädig).
- **Auf dem Runner** (`ubuntu-24.04-arm`, `v0.1.0-rc1`, 28.09.2026): 15:29 Minuten für den ganzen Job. Davon
  `install.sh --image` gut 4 Minuten, `xz -T0 -9` 10 Minuten. Ergebnis 1484 MiB (1 556 171 906 Byte als
  Artefakt), entpackt 4884 MiB.
- **Platz:** Die Spitze im Arbeitsordner lag bei 7,7 GB (Image plus Quickshell-Bau).

## Grenzen

- **Speicher:** Der Runner hat 14 GB SSD. Das Image muss beim Bau also schlank bleiben; `bauen.sh` warnt unter
  11 GiB freiem Platz.
- **Dateigrösse:** Einzelne Release-Dateien müssen kleiner als 2 GiB sein. Ein schlankes Image ist besser als ein zerstückeltes. Der Workflow bricht vorher ab.
- **Kein `apt upgrade` beim Bau:** Ein neuer Kernel käme im chroot nicht auf die Boot-Partition. Die ausstehenden
  Sicherheitsupdates holt unattended-upgrades nach dem ersten Start.

## Was nicht ins Image kommt

Chrome, VS Code, 1Password und coremail sind nicht im Image; Chrome, VS Code und 1Password sind proprietär und dürfen in der Regel nicht selbst weiterverteilt werden. Die Einrichtung beim ersten Start installiert sie aus den offiziellen Quellen der Hersteller, erst nach ausdrücklicher Zustimmung. Vorher zeigt sie klar an, was installiert wird. Updates kommen danach direkt vom Hersteller.

## Flashen

- **Bootloader:** Ubuntu 26.04 verlangt auf dem Pi 5 einen Bootloader (EEPROM) vom 11.02.2025 oder neuer
  (Release-Notes von Ubuntu 26.04). Prüfen mit `sudo rpi-eeprom-update`, aktualisieren mit
  `sudo rpi-eeprom-update -a` oder mit dem Raspberry Pi Imager (Bootloader-Image). zenOS selbst fasst die Firmware
  nie an.
- Am besten mit dem Raspberry Pi Imager (eigenes Image wählen) und unter «Einstellungen» Benutzer, Passwort und
  optional einen SSH-Schlüssel setzen, dazu Zeitzone und Tastaturbelegung. Die Belegung gilt auch für das
  Passwortfeld im zenOS-Login, die Zeitzone für Uhr, Bündelung der Mitteilungen und Uhrzeit-Auslöser.
- balenaEtcher geht auch, dann ohne Einstellungen: Beim ersten Start gilt `ubuntu`/`ubuntu`, Zeitzone UTC und die
  Vorgabe-Belegung des Images (siehe «Erster Start»).
- Ziel: SD-Karte, USB-Stick oder NVMe.

## Erster Start

1. cloud-init legt den Benutzer an, erzeugt neue SSH-Hostschlüssel und vergrössert Partition und Dateisystem;
   systemd erzeugt eine neue `machine-id`. Die Firewall ist von Anfang an an (`ufw.service` lädt die Regeln vor
   dem Netz): Herein kommt nur SSH aus lokalen Netzen (`docs/sicherheit.md`).
2. Anmelden: Mit Einstellungen aus dem Raspberry Pi Imager direkt im zenOS-Login. Ohne Einstellungen legt
   cloud-init `ubuntu`/`ubuntu` mit abgelaufenem Passwort an. greetd 0.10 kann Passwörter nicht ändern (kein
   `pam_chauthtok`), der Login zeigt deshalb einen Hinweis. Zuerst an der Textkonsole (`Ctrl + Alt + F2`) oder per
   SSH anmelden, ein neues Passwort setzen, mit `exit` abmelden und mit `Ctrl + Alt + F7` zurück zum zenOS-Login.
   Zeitzone und Tastatur lassen sich dort nachholen: `sudo timedatectl set-timezone <Zone>` und
   `sudo dpkg-reconfigure keyboard-configuration`, danach neu starten.
3. Beim ersten Login kommen die Benutzerteile von zenOS (`zenos-sitzung` ruft `install.sh --nur-benutzer`).
4. Die Einrichtung fragt nach Name, optional Ort, Erscheinungsbild und erstem Modus.
5. Nach Zustimmung werden die proprietären Apps installiert (im Terminal, mit dem sudo-Passwort). Nubix hat noch
   keinen arm64-Build und wird angeboten, sobald es einen gibt.
6. Persönliches wird nur unter `~/.config/zenos/` abgelegt.

## Name und Marke

Geprüft am 04.10.2026 gegen die IPR-Policy von Canonical (Fassung vom 15.07.2015, an dem Tag neu abgerufen und
unverändert). Sie verlangt bei einer veränderten Weitergabe ohne Genehmigung, die Marken zu entfernen und zu ersetzen:
Name, Logo, Systemkennung und Begrüssung. Bis `v0.1.0-rc2` stimmte das nicht: Das Image meldete sich als Ubuntu
(`ID=ubuntu`, `LOGO=ubuntu-logo`, «Welcome to Ubuntu» bei der Anmeldung, «Ubuntu 26.04.1 LTS» an der Konsole), und die
Ubuntu-Logos lagen als Dateien von base-files im Image.

Seit der Systemkennung (`docs/module/kennung.md`, Modul `72-kennung`) gilt:

- **Ersetzt:** Name und Kennung (`/usr/lib/os-release` mit `NAME="zenOS"`, `ID=zenos`, `LOGO=zenos`), die Konsole
  (`/etc/issue`), `/etc/legal` und der Kopf der Begrüssung (`00-zenos` statt `00-header` und `10-help-text`, ohne
  Werbung für Ubuntu Pro). Das Logo ist die Bildmarke von zenOS. `image/bauen.sh` bricht ab, wenn das Image danach
  noch Ubuntu im Namen trägt oder die Ubuntu-Sicherheitsquelle nicht nachgewiesen ist.
- **Bleibt, weil sachlich wahr:** «basiert auf Ubuntu 26.04 LTS» (in `VERSION`, `ID_LIKE="ubuntu debian"`,
  `UBUNTU_CODENAME`, `zen version`, Begrüssung, `/etc/legal`, README), `/etc/lsb-release` (beschreibt die Basis),
  Paketquellen und Schlüssel von Ubuntu, Paketnamen und -versionen, die Kennung des Kernels und von OpenSSH sowie alle
  Lizenz- und Urheberhinweise («Canonical Ltd.» in `/usr/share/doc/*/copyright`). Die Logo-Dateien von base-files
  unter `/usr/share/pixmaps/` bleiben liegen, nichts verweist mehr auf sie. Kein Ubuntu-Paket wird umbenannt oder neu
  gebaut.
- **Nie:** «offiziell», «Ubuntu-Edition» oder ein Name auf -buntu, Ubuntu im Produktnamen oder Logo, das Logo von
  Raspberry Pi, «Linux» im Namen (zenOS ist eine Linux®-Distribution, heisst aber nicht «zenOS Linux»).
- **Markenhinweise** (README, später Website und Versionshinweise): «Ubuntu and Canonical are registered trademarks
  of Canonical Ltd. Linux® is the registered trademark of Linus Torvalds in the U.S. and other countries. Raspberry Pi
  is a trademark of Raspberry Pi Ltd.»

Offen vor einer Weitergabe an andere: die schriftliche Anfrage bei Canonical, eine Ähnlichkeitsrecherche zum Namen
zenOS und der Quellcode zu jedem Release auf derselben Release-Seite.

## Bürorechner

Für x86 kommt später ein eigener Installer-Stick: ein Ubuntu-ISO mit Autoinstall, das nach der Installation `scripts/install.sh` ausführt. Die Verschlüsselung fragt der Installer interaktiv ab. Kein Passwort steht in einer Datei.
