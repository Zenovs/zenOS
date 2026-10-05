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
5. **Erster Start und Paketliste** (Dateien aus `image/erststart/`):
   - `user-data` auf der Startpartition: Benutzer `user` mit Passwort `user` (muss bei der ersten Anmeldung geändert
     werden), Rechnername `zenos`, SSH nur mit Schlüssel (`ssh_pwauth: false` wie bei Ubuntu).
   - `/etc/cloud/cloud.cfg.d/90-zenos-benutzer.cfg`: Der Standardbenutzer heisst `user` («Default User») und hat
     **kein sudo ohne Passwort** (`sudo: null` statt `NOPASSWD:ALL` aus Ubuntus `cloud.cfg`). Sonst wären
     Passwortabfragen wie beim Ausschalten der Firewall wirkungslos. sudo geht über die Gruppe `sudo`, mit Passwort.
   - `/etc/hostname` `zenos` (und `/etc/hosts`, falls dort `ubuntu` steht), ein README von zenOS auf der
     Startpartition statt dem von Ubuntu.
   - `config.txt`: ein Abschnitt `[cm5]` mit `dtoverlay=dwc2,dr_mode=host`. Er schaltet den USB-2-Anschluss des
     Compute Module 5 in den Host-Modus; ohne ihn gehen am Argon ONE UP Tastatur, Touchpad und USB nicht. Ein
     normaler Pi 5 ist davon nicht betroffen.
   - Paketliste `zenos-<version>-pi5-arm64.pakete.txt` (Paket, Version, Quellpaket, Quellversion), auch im Image unter
     `/usr/local/share/doc/zenos/pakete.txt`.
6. **Aufräumen:**
   - Paket-Cache und Logs löschen.
   - SSH-Hostschlüssel und `machine-id` entfernen; beide werden beim ersten Start neu erzeugt.
   - Das Dateisystem verkleinern (mit 256 MiB Luft); beim ersten Start wächst es auf die ganze Karte.
7. **Packen:** `xz -T0 -9`, dazu `SHA256SUMS` über Image und Paketliste. Danach bestätigt GitHub die Herkunft
   (Artifact Attestation, siehe «Prüfen»), und der Workflow schreibt das Manifest für den Raspberry Pi Imager.
8. **Quellcode** (eigener Job «quellen», Container `ubuntu:26.04`): `image/quellen.sh` holt zu jedem Paar aus
   Quellpaket und Version der Paketliste die `.dsc` samt Dateien, zuerst aus dem Ubuntu-Archiv (apt prüft Signatur und
   Prüfsummen), sonst von Launchpad (geprüft gegen die Prüfsummen der `.dsc`), dazu Quickshell als `git archive` am
   gebauten Commit. Fehlt eine Quelle, scheitert der Job, und es gibt kein Release.
9. **Veröffentlichen:**
   - Tags mit `-rc` (z. B. `v0.1.0-rc1`): nur Workflow-Artefakte (Image, Quellen), **kein Release**.
   - Andere Tags: ein Release mit allen Dateien unter «Release-Dateien». Tags mit Bindestrich (z. B. `v0.2.0-beta1`)
     werden als Vorabversion markiert.

## Release-Dateien

| Datei | Inhalt |
|---|---|
| `zenos-<v>-pi5-arm64.img.xz` | das Image |
| `zenos-<v>-pi5-arm64.pakete.txt` | alle Pakete im Image mit Version und Quellpaket |
| `SHA256SUMS` | Prüfsummen von Image und Paketliste |
| `zenos-<v>.rpi-imager-manifest` | Manifest für den Raspberry Pi Imager 2.x (siehe «Flashen») |
| `zenos-<v>-quellen-teil<NN>.tar` | Quellcode aller Ubuntu-Pakete im Image, je Teil unter 2 GiB |
| `zenos-<v>-quickshell-<qv>.tar` | Quellcode von Quickshell am gebauten Commit |
| `zenos-<v>-QUELLEN.txt` | welches Quellpaket in welchem Teil liegt und woher es kommt |
| `SHA256SUMS-quellen` | Prüfsummen der Quellen-Dateien |

## Prüfen

- Prüfsummen: `sha256sum -c SHA256SUMS` (und `sha256sum -c SHA256SUMS-quellen` für die Quellen).
- Herkunft: `gh attestation verify zenos-<v>-pi5-arm64.img.xz --repo <besitzer>/zenOS` bestätigt, dass die Datei aus
  dem Workflow dieses Repos zum Tag stammt (dasselbe für die Paketliste). Die Bestätigung erzeugt GitHub ohne eigenen
  Schlüssel über Sigstore; dabei landen Metadaten aus der CI (Repo, Workflow, Commit, Prüfsummen) im öffentlichen
  Transparenz-Log von Sigstore. Vom Rechner, auf dem zenOS läuft, geht dabei nichts weg.
- Signatur des Tags: ab dem ersten signierten Release (siehe «Signierte Releases») mit
  `git -c gpg.ssh.allowedSignersFile=system/vertrauen/release -c gpg.ssh.revocationFile=system/vertrauen/widerrufen verify-tag vX.Y.Z`.
  Nur der Exit-Code zählt, und das Feld `tag` im Objekt (`git cat-file tag vX.Y.Z`) muss dem Namen entsprechen.

## Signierte Releases

**Stand:** Signieren ist eingerichtet, die Prüfung auf den Geräten folgt mit dem Kanal. Bis dahin ändert sich auf den
Geräten nichts, `zen update` zieht weiter den Zweig `dev` ohne Signaturprüfung. Die echten Schlüssel fehlen noch,
Zeno legt sie später an. Solange ist der Anker leer: `scripts/release-signieren.sh` signiert nichts, und der Kanal
installiert nichts («Anker fehlt», fail-closed). Der heutige Weg von Hand über `dev` bleibt.

### Schlüssel und Anker

Zwei SSH-Schlüssel (Ed25519), beide nur in 1Password. Der private Teil verlässt 1Password nie, jede Signatur gibt
Zeno mit Touch ID frei.

| Schlüssel in 1Password | Prinzipal | signiert | öffentlich in |
|---|---|---|---|
| «zenOS Release» | `zenos-release` | Tags `vX.Y.Z` und `vX.Y.Z-rcN` | `system/vertrauen/release` |
| «zenOS Wurzel», eigener Tresor | `zenos-wurzel` | nur Tags `vertrauen/NNNN` | `system/vertrauen/wurzel` |

Der Anker `system/vertrauen/` hat vier Dateien. Zeilen mit `#` und leere Zeilen zählen nirgends.

- `release`, `wurzel`: Format von `gpg.ssh.allowedSignersFile`, je Schlüssel eine Zeile
  `zenos-release namespaces="git" ssh-ed25519 AAAA…` (bei der Wurzel `zenos-wurzel`, genau eine Zeile). Nur Ed25519,
  keine weiteren Optionen, kein Kommentar und kein Name hinter dem Schlüssel.
- `widerrufen`: Format von `gpg.ssh.revocationFile`, je Zeile ein öffentlicher Schlüssel `ssh-ed25519 AAAA…`. Die
  Datei muss es geben, auch leer: Fehlt sie, warnt git nur und nimmt die Signatur an. Die Liste wächst nur.
- `serie`: eine Zahl von 1 bis 9999. Serie 1 ist der erste Anker, er kommt mit dem Image oder einmalig aus dem Repo.

Ein Schlüssel steht nie zugleich in `release` und `wurzel` oder in `release` und `widerrufen`. Öffentliche Schlüssel
sind keine Geheimnisse (Manifest 0, Ausnahme für die Prüfschlüssel); gitleaks lässt sie durch und meldet private.
Auf dem Gerät liegt der Anker später root-eigen unter `/etc/zenos/vertrauen` und wird nie aus `/opt/zenos` gelesen.

Kanäle (umgesetzt mit dem Kanal auf dem Gerät): `stabil` nimmt nur `vX.Y.Z`, mit 24 h Wartezeit; `vorschau` nimmt
auch `vX.Y.Z-rcN`, ohne Wartezeit; `dev` nur von Hand, unsignierte Commits nur mit getipptem «ja» für genau diese
SHA. Den Zeitpunkt automatischer Updates stellt man am Gerät ein.

### Ein Release signieren

Auf dem Mac, in einem eigenen Terminal-Tab, in dem Claude Code nicht läuft. Alles ist committet und gepusht.

```
scripts/release-signieren.sh v0.1.0-rc4
```

1. Das Skript prüft:
   - Der Arbeitsbaum ist sauber, und HEAD liegt auf origin (nach `git fetch`).
   - Den Tag gibt es weder lokal noch auf origin. Er ist höher als jede Version auf origin. Dabei gilt
     `v0.1.0-rc3` < `v0.1.0-rc10` < `v0.1.0` < `v0.1.1`. Ein Tag wird nie verschoben, auch kein alter: `v0.1.0-rc1`
     bis `rc3` bleiben unsigniert, der erste signierte Tag ist `v0.1.0-rc4` oder höher.
   - HEAD baut auf dem letzten Release auf, und dieser Tag ist lokal derselbe wie auf origin.
   - Die Prüfung `pruefen.yml` für HEAD ist per `gh` nicht rot. Läuft sie noch oder fehlt gh, gibt es nur eine
     Warnung.
   - Der Anker in HEAD ist vollständig. Gegenüber dem letzten Release ist er gleich, Kommentare ausgenommen. Oder er
     hat eine höhere Serie, und es gibt den Tag `vertrauen/NNNN`, der genau diesen Anker trägt. Die Wurzel bleibt
     immer gleich.
2. Es zeigt die Commits seit dem letzten Release, die Fingerabdrücke des Ankers und gesondert die Änderungen an
   sensiblen Pfaden (`scripts/lib/sensible-pfade`): Firewall, Netz und Boot (die Rückfrage-Pfade), Anmeldung und
   Rechte, Vertrauen und Updates. Die Liste kommt aus dem neuen Stand und aus dem letzten Release zusammen. «d» zeigt
   den ganzen Diff dieser Pfade.
3. «ja» signiert einen annotierten Tag (Nachricht `zenOS vX.Y.Z`) mit dem ersten Schlüssel aus `release`, über
   `op-ssh-sign` von 1Password, mit Touch ID.
4. Danach prüft es den neuen Tag: annotiert, Feld `tag` gleich dem Namen, zeigt auf HEAD, genau eine SSH-Signatur,
   `git verify-tag` gegen `release` und `widerrufen` für den Prinzipal `zenos-release`. OpenPGP und X.509 sind dabei
   abgeschaltet. Scheitert etwas, löscht das Skript den Tag wieder.
5. Ein zweites «ja» pusht nur diesen Tag (`git push origin refs/tags/vX.Y.Z`). Sonst bleibt er lokal.
6. Danach 1Password sperren.

Das Skript braucht keine eigene git-Einstellung: Es setzt `gpg.format`, `gpg.ssh.program` und `user.signingkey` nur
für den eigenen Aufruf. Es läuft mit bash 3.2. Exit 0 heisst signiert, 1 abgebrochen (dann bleibt kein neuer Tag
liegen), 2 falscher Aufruf.

### Den Anker ändern: Tag vertrauen/NNNN

Für einen neuen Release-Schlüssel oder einen Widerruf, etwa wenn der Release-Schlüssel verloren oder gestohlen ist.

1. In `system/vertrauen/` `release` und `widerrufen` anpassen und `serie` um genau 1 erhöhen, dann committen und
   pushen.
2. `scripts/release-signieren.sh --vertrauen` prüft wie oben und zusätzlich:
   - Die Serie ist genau 1 höher als beim letzten Tag `vertrauen/NNNN` oder, vor dem ersten, als im Stand vor der
     Erhöhung.
   - Die Wurzel ist gleich, widerrufene Schlüssel bleiben widerrufen, und `release` oder `widerrufen` ändert sich
     wirklich.
   Es zeigt neue, entfernte und neu widerrufene Schlüssel, signiert nach «ja» den Tag `vertrauen/NNNN` (vierstellig)
   mit dem Wurzel-Schlüssel und prüft ihn gegen `wurzel` und die Widerrufe von vorher. Gepusht wird nach einem
   zweiten «ja».
3. Erst danach Releases mit dem neuen Schlüssel signieren. Ein Release mit Serie 2 oder höher verlangt den
   passenden Tag `vertrauen/NNNN` auf origin.

Was ein Gerät später prüft (für den Kanal):

- **Release-Tag:** annotiert, Feld `tag` gleich dem Ref-Namen, `type commit`, genau eine SSH-Signatur und kein
  OpenPGP, `verify-tag` auf die Objekt-ID gegen `release` und `widerrufen` des Geräts mit Prinzipal
  `zenos-release`. Die Nachricht hat keine Kopfzeilen und zählt nicht.
- **Tag `vertrauen/NNNN`:** dieselben Formbedingungen, `verify-tag` gegen `wurzel` und `widerrufen` des Geräts mit
  Prinzipal `zenos-wurzel`. Massgeblich ist der Commit, auf den er zeigt: Dort muss `system/vertrauen/serie` gleich
  NNNN sein und `system/vertrauen/wurzel` dieselbe Wurzel tragen wie das Gerät. Dann übernimmt das Gerät `release`
  und `widerrufen` aus diesem Commit (bei den Widerrufen als Vereinigung mit den alten). Es nimmt nur Tags mit
  höherer Serie als der eigenen, aufsteigend und vor allen Releases. Die Fingerabdrücke in der Nachricht sind nur zum
  Lesen da.
- Die Wurzel ändert sich nie über das Netz. Ist sie verloren oder gestohlen, braucht jedes Gerät ein neues Image
  oder einen neuen Anker von Hand.

### Einmalig einrichten (Zeno)

1. 1Password: Einstellungen › Entwickler › «SSH-Agent verwenden».
2. In 1Password zwei SSH-Schlüssel (Ed25519) anlegen: «zenOS Release» im Standard-Tresor und «zenOS Wurzel» in
   einem eigenen Tresor. Ungeprüft: Laut Doku von 1Password bietet der Agent Schlüssel aus anderen Tresoren erst an,
   wenn sie in seiner Konfiguration (`agent.toml`) freigegeben sind; sonst meldet das Skript «Signieren ist
   fehlgeschlagen».
3. Die beiden öffentlichen Schlüssel (nicht geheim) an Claude geben. Sie kommen ohne Kommentar mit Serie 1 nach
   `system/vertrauen/`.

### Geprüft

Mit Wegwerf-Schlüsseln, im Container (git 2.53, OpenSSH 10.2) und auf dem Mac (git 2.50, OpenSSH 10.3, bash 3.2):

- Signieren mit `user.signingkey=key::ssh-ed25519 …`, wenn der Schlüssel nur im SSH-Agent liegt, geht. Liegt er nicht
  dort, scheitert es mit «Couldn't find key in agent».
- `verify-tag` nimmt einen Tag nur mit einem Schlüssel aus der Liste an. Ein fremder Schlüssel, ein Schlüssel aus
  `widerrufen` oder eine Liste nur mit Kommentaren ergibt Exit 1. Kommentare in beiden Dateien stören nicht.
- Eine Widerrufsdatei nur mit Kommentaren oder ganz leer nimmt git an. Fehlt sie, warnt git nur und gibt Exit 0
  (fail-open). Ein Gerät muss die Datei deshalb selbst verlangen.
- `verify-tag` prüft den Namen nicht: Ein Ref `v9.9.9` auf das Objekt von `v1.0.0` ergibt Exit 0. Deshalb wird das
  Feld `tag` verglichen.
- `namespaces="git"` wirkt: Mit einem anderen Namespace in der Liste wird der Tag abgelehnt.
- Die Tests `test/einheiten/release-signieren.test.py` spielen das Skript ganz durch: Release, Vertrauens-Tag,
  Abbruch und Ablehnung, falscher oder fehlender Schlüssel, rote CI, verschobener Tag, Downgrade, Anker ohne Serie
  geändert, Wurzel geändert.

### Grenzen

- Eine Signatur bestätigt die Herkunft, nicht den Inhalt. Was signiert ist, läuft später als root auf allen Geräten.
  Dagegen helfen nur die Durchsicht (das Skript zeigt sensible Pfade gesondert), ein eigener Terminal-Tab und danach
  1Password sperren. Auch das Skript selbst ist Teil des Repos und erscheint deshalb unter «Vertrauen und Updates».
- 1Password gibt einen Schlüssel laut Doku pro Anwendung bzw. Terminal-Sitzung frei, bis es sperrt (nicht selbst
  getestet). Ein Programm im selben Terminal könnte danach mitsignieren.
- Die Rückfrage-Pfade fangen indirekte Änderungen nicht, etwa neue Pakete, die initramfs auslösen.

## Quellcode und Lizenzen

Das Image gibt GPL-Software als Binärpakete von Ubuntu weiter. Das ist nur zusammen mit dem Quellcode in genau den
ausgelieferten Versionen erlaubt (GPLv2 §3, GPLv3 §6). Deshalb liegen die Quellen auf derselben Release-Seite wie das
Image, so lange wie dieses; ein Verweis auf das Ubuntu-Archiv reicht nicht, weil ersetzte Versionen dort
verschwinden. Im System stehen die Hinweise unter `/usr/local/share/doc/zenos/` (`copyright`, `RECHTLICHES`,
`QUELLEN`, `pakete.txt`) und `/usr/local/share/doc/quickshell/` (LGPL 3); `/etc/legal` verweist darauf. Die
`copyright`-Dateien der Ubuntu-Pakete unter `/usr/share/doc/` bleiben vollständig.

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
- Am besten mit dem Raspberry Pi Imager 2.x **über die Manifest-Datei** `zenos-<v>.rpi-imager-manifest`: per
  Doppelklick öffnen oder im Imager «App Options › Content Repository › Edit › Use custom file › Apply & Restart»,
  dann zenOS auswählen. Unter
  «Einstellungen» Benutzer, Passwort und optional einen SSH-Schlüssel setzen, dazu Zeitzone und Tastaturbelegung.
  Wählt man das Image dagegen direkt als «eigenes Image» (`.img.xz`), bietet der Imager 2.x keine Einstellungen an,
  weil er nicht weiss, dass das Image cloud-init versteht; erst das Manifest sagt es ihm (`init_format: cloudinit`).
  Die Belegung gilt auch für das Passwortfeld im zenOS-Login, die Zeitzone für Uhr, Bündelung der Mitteilungen und
  Uhrzeit-Auslöser. Bei einem `-rc`-Image ohne Release-Seite in der Manifest-Datei `url` auf die heruntergeladene
  Datei ändern (`file:///…/zenos-<v>-pi5-arm64.img.xz`).
- balenaEtcher geht auch, dann ohne Einstellungen: Beim ersten Start gilt `user`/`user`, Zeitzone UTC und die
  Vorgabe-Belegung des Images (siehe «Erster Start»).
- **Argon ONE UP (Compute Module 5) mit NVMe:** Damit der Bootloader die SSD findet, muss im EEPROM `PCIE_PROBE=1`
  stehen (`sudo rpi-eeprom-config --edit`). USB ist im Image schon eingestellt (`[cm5]` in `config.txt`).
- Ziel: SD-Karte, USB-Stick oder NVMe.

## Erster Start

1. cloud-init legt den Benutzer an, erzeugt neue SSH-Hostschlüssel und vergrössert Partition und Dateisystem;
   systemd erzeugt eine neue `machine-id`. Die Firewall ist von Anfang an an (`ufw.service` lädt die Regeln vor
   dem Netz): Herein kommt nur SSH aus lokalen Netzen (`docs/sicherheit.md`).
2. Anmelden: Mit Einstellungen aus dem Raspberry Pi Imager direkt im zenOS-Login. Ohne Einstellungen legt
   cloud-init den Benutzer `user` («Default User») mit dem Passwort `user` an, das abgelaufen ist. greetd 0.10 kann
   Passwörter nicht ändern (kein `pam_chauthtok`), der Login zeigt deshalb einen Hinweis. Zuerst an der Textkonsole
   (`Ctrl + Alt + F2`) anmelden, ein neues Passwort setzen, mit `exit` abmelden und mit `Ctrl + Alt + F7` zurück zum
   zenOS-Login. Per SSH geht das nur mit einem Schlüssel, Passwörter nimmt SSH nicht an. sudo fragt immer nach dem
   Passwort.
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
- **Markenhinweise** (README, Versionshinweise, `RECHTLICHES`, später Website): «Ubuntu and Canonical are registered trademarks
  of Canonical Ltd. Linux® is the registered trademark of Linus Torvalds in the U.S. and other countries. Raspberry Pi
  is a trademark of Raspberry Pi Ltd.»

Der Quellcode zu jedem Release liegt auf derselben Release-Seite («Quellcode und Lizenzen»), die Markenhinweise
stehen auch in den Versionshinweisen und unter `/usr/local/share/doc/zenos/RECHTLICHES`. Offen vor einer Weitergabe
an andere: die schriftliche Anfrage bei Canonical, eine Ähnlichkeitsrecherche zum Namen zenOS und ein signierter
Update-Kanal «stabil». Das Signieren ist eingerichtet («Signierte Releases»), die Prüfung auf den Geräten fehlt noch:
Heute zieht `zen update` den Zweig `dev` ohne Signaturprüfung.

## Bürorechner

Für x86 kommt später ein eigener Installer-Stick: ein Ubuntu-ISO mit Autoinstall, das nach der Installation `scripts/install.sh` ausführt. Die Verschlüsselung fragt der Installer interaktiv ab. Kein Passwort steht in einer Datei.
