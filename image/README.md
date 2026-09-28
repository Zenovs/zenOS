# image

Bau des Pi-Images: `zenos-<version>-pi5-arm64.img.xz` und `SHA256SUMS`. Grundlage ist das offizielle
Ubuntu 26.04 LTS Server-Image für den Raspberry Pi. Zielbild: `docs/image-und-releases.md`.

| Datei | Zweck |
|---|---|
| `image/bauen.sh` | baut das Image (lokal und in GitHub Actions, als root auf arm64-Linux) |
| `.github/workflows/image.yml` | baut bei jedem Tag `v*`, veröffentlicht Releases |

## Ablauf von `bauen.sh`

1. **Grundlage holen.** `SHA256SUMS` und `SHA256SUMS.gpg` von
   `https://cdimage.ubuntu.com/releases/26.04/release/`. Die Signatur prüft `gpgv` gegen den im Skript
   hinterlegten «Ubuntu CD Image Automatic Signing Key (2012)», Fingerabdruck
   `8439 38DF 228D 22F7 B374 2BC0 D94A A3F0 EFE2 1092`. Gewählt wird die neueste Punktversion von
   `ubuntu-26.04*-preinstalled-server-arm64+raspi.img.xz` (heute `26.04.1`), nach dem Download wird die
   Prüfsumme kontrolliert.
2. **Entpacken und vergrössern.** Die Datei wächst um 6 GiB (sparse, kostet nur, was belegt wird),
   Partition 2 reicht bis zum Ende, danach `e2fsck` und `resize2fs`.
3. **Einhängen.** Boot- und Root-Partition über Loop-Geräte mit Offset (ohne Partitionsscan, geht auch in
   Containern). Root nach `<arbeit>/wurzel`, Boot nach `/boot/firmware`, dazu `/proc`, `/sys` und `/dev`.
   `/run` und `/tmp` sind frische tmpfs: ohne `/run/systemd/system` weiss `install.sh`, dass kein systemd
   läuft. `/var/tmp` kommt aus dem Arbeitsordner, damit der Quickshell-Bau (etwa 3,5 GB) keinen Platz im
   Image belegt. Namensauflösung über `/run/systemd/resolve/` im tmpfs (die Datei `/etc/resolv.conf` im
   Image bleibt unberührt), eine eigene `policy-rc.d` verhindert Dienststarts.
4. **`/opt/zenos`.** `git clone --no-local` der Quelle, losgelöst auf dem gewünschten Stand (in CI der Tag),
   ohne Zweige, mit allen Tags, `origin` auf GitHub (https), leere Reflogs, Besitz root. Der Pfad der Quelle
   landet nicht im Image. Ins Image kommt nur der Commit, nicht der Arbeitsstand.
5. **chroot.** `ZENOS_KANAL=dev /opt/zenos/scripts/install.sh --image` mit leerer Umgebung (`env -i`), damit
   nichts aus der CI ins Image gelangt. Das Install-Log liegt danach als `<arbeit>/install.log` daneben.
6. **Aufräumen im Image.** `apt-get clean`, `policy-rc.d` weg, SSH-Hostschlüssel löschen, `machine-id`
   leeren, `random-seed` löschen, Logs leeren (rotierte löschen, `/var/log/zenos/install.log` löschen),
   Verlauf und Caches von root, `/opt/zenos` sauber (sonst Warnung und Zurücksetzen), `fstrim` (gelöschte
   Daten verschwinden, xz packt Nullen; ohne fstrim nullt `zerofree` nach dem Verkleinern).
7. **Verkleinern.** `e2fsck`, `resize2fs -M`, dazu 256 MiB Luft, Partition und Datei kürzen, Gegenprobe
   mit `e2fsck -n`. Beim ersten Start wächst die Partition über cloud-init auf die ganze Karte.
8. **Packen.** `xz -T0 -9`, `xz -t`, `SHA256SUMS`, Hinweis bei 2 GiB und mehr.

Bricht der Bau ab (Fehler, Ctrl+C, `SIGTERM`), beendet ein Trap die Prozesse im chroot, hängt alles aus und
löst die Loop-Geräte. Nach einem harten Abbruch (`SIGKILL`) räumt der nächste Lauf im selben Arbeitsordner
die Reste weg.

## Kanal

Das Image bekommt `/etc/xdg/zenos/kanal` mit `dev`, wie der Pi. `zen update` holt damit `origin/dev`. Das
bleibt so, bis `main` Releases trägt (Entscheidung beim Bau von 0.1). Danach: `--kanal main` im Workflow.

## Lokal ausführen

Voraussetzungen: arm64-Linux (Pi 5 mit Ubuntu, arm64-VM oder privilegierter Container), root, etwa 12 GB
frei und diese Werkzeuge:

```
sudo apt-get install curl gpgv xz-utils e2fsprogs fdisk util-linux mount git zerofree
```

```
sudo image/bauen.sh                                    # HEAD, Version aus git describe
sudo image/bauen.sh --ref v0.1.0 --cache /var/tmp/zenos-cache
sudo image/bauen.sh --nur-mechanik --xz-stufe 1        # Schnelltest ohne install.sh
```

| Option | Standard | Bedeutung |
|---|---|---|
| `--ref REF` | `HEAD` | Stand für `/opt/zenos` (Tag, Zweig, Commit) |
| `--version V` | `git describe`, ohne «v» | Version im Dateinamen |
| `--quelle ORDNER` | dieses Repo | Git-Repo mit zenOS |
| `--origin URL` | origin der Quelle | origin in `/opt/zenos`, nur https ohne Zugangsdaten |
| `--kanal K` | `dev` | Kanal für `zen update` |
| `--ubuntu V` | `26.04` | Ubuntu-Version auf cdimage.ubuntu.com |
| `--arbeit ORDNER` | `/var/tmp/zenos-image` | Arbeitsordner |
| `--ausgabe ORDNER` | `<arbeit>/ausgabe` | Ziel für `.img.xz` und `SHA256SUMS` |
| `--cache ORDNER` | – | Ubuntu-Image dort behalten und wiederverwenden |
| `--zusatz-mib N` | `6144` | Vergrösserung vor dem chroot |
| `--reserve-mib N` | `256` | Luft nach dem Verkleinern |
| `--xz-stufe N` | `9` | Kompression |
| `--nur-mechanik` | – | Test: im chroot nur Prüfbefehle (Architektur, `apt-get update`, `install.sh --hilfe`, `/var/tmp`, git) statt `install.sh`; Version bekommt `-mechanik` |

Auf dem Mac in einem privilegierten Container (grosse Dateien bleiben im Container):

```
docker run -d --name zenos-image --privileged -v "$PWD":/repo:ro ubuntu:24.04 sleep infinity
docker exec zenos-image bash -c 'apt-get update && apt-get install -y curl ca-certificates gpgv xz-utils e2fsprogs fdisk util-linux mount git'
docker exec zenos-image /repo/image/bauen.sh --nur-mechanik --xz-stufe 1 --arbeit /srv/image
docker rm -f zenos-image
```

## GitHub Actions

`.github/workflows/image.yml` läuft nur bei `push` von Tags `v*`. Alle Actions sind per Commit-SHA gepinnt,
die Rechte sind minimal (`contents: read` beim Bau, `contents: write` nur im Release-Job).

- **Image bauen** (`ubuntu-24.04-arm`, nativ arm64, für öffentliche Repos kostenlos, Timeout 180 min): Form des
  Tags prüfen, auschecken (ganze Geschichte, ohne gespeicherte Zugangsdaten), `bauen.sh --ref refs/tags/<tag>`,
  `SHA256SUMS` und Grösse unter 2 GiB prüfen, Zusammenfassung im Lauf. Image, `SHA256SUMS` und
  Versionshinweise gehen als Artefakt `zenos-<version>-pi5-arm64` mit (Release-Tags 3 Tage, `-rc` 14 Tage),
  das Install-Log als eigenes Artefakt, auch wenn der Bau scheitert.
- **Annotationen:** `bauen.sh` läuft mit `sudo --preserve-env=GITHUB_ACTIONS`. sudo setzt die Umgebung zurück
  (`env_reset`), ohne diese eine Variable stünden Warnungen und Fehler von `bauen.sh` nur im Log und nicht als
  `::warning::`/`::error::` im Lauf. Weitere Variablen reicht der Workflow nicht durch, der chroot bekommt
  ohnehin eine leere Umgebung.
- **Tags mit `-rc`** (z. B. `v0.1.0-rc1`): nur das Artefakt, kein Release.
- **Andere Tags**: Job «Release» (`ubuntu-24.04`) prüft das Artefakt erneut und erstellt mit
  `gh release create --verify-tag` das Release mit `zenos-<version>-pi5-arm64.img.xz` und `SHA256SUMS`. Tags mit
  Bindestrich (z. B. `v0.2.0-beta1`) werden als Vorabversion markiert. Gibt es das Release schon (Workflow neu
  gestartet), werden die Dateien ersetzt.

Die Grundlage (Ubuntu-Datei und SHA-256) steht in den Versionshinweisen und in `<arbeit>/basis.txt`.

## Grenzen

- **Platz auf dem Runner: 14 GB.** Spitze etwa 9–10 GB: entpacktes Ubuntu-Image (2,8 GB belegt), Pakete,
  Quickshell-Bau (3,5 GB unter `/var/tmp`, also im Arbeitsordner), danach das `.xz`. Der Download wird nach
  dem Entpacken gelöscht. `bauen.sh` warnt unter 11 GiB freiem Platz.
- **Release-Dateien unter 2 GiB.** Sonst bricht der Workflow vor dem Release ab. Das Ubuntu-Image allein
  ergibt etwa 1,5 GB. Was zenOS dazu bringt, zeigt `bauen.sh` unter «Grösste Ordner».
- **Kein `apt upgrade` beim Bau.** flash-kernel läuft im chroot nicht, ein neuer Kernel käme nicht nach
  `/boot/firmware`. Sicherheitsupdates holt unattended-upgrades nach dem ersten Start.
- **Keine Signatur der Release-Dateien**, nur `SHA256SUMS`.
- **Marke:** Das Image heisst zenOS und «basiert auf Ubuntu». Vor dem ersten Release die Markenrichtlinie von
  Canonical prüfen.
- **Schlüsselwechsel bei Ubuntu:** Signiert cdimage.ubuntu.com einmal mit einem anderen Schlüssel, bricht
  `bauen.sh` ab. Dann Schlüssel und Fingerabdruck in `bauen.sh` ersetzen (Quelle: keyserver.ubuntu.com,
  Fingerabdruck mit der Ubuntu-Dokumentation abgleichen).

## Erster Start eines Images

- cloud-init aus dem Ubuntu-Image legt den Benutzer an, erzeugt neue SSH-Hostschlüssel und vergrössert
  Partition und Dateisystem. systemd erzeugt eine neue `machine-id`.
- **Mit Einstellungen im Raspberry Pi Imager** (Benutzer, Passwort, optional SSH-Schlüssel) geht die erste
  Anmeldung direkt im zenOS-Login. Das ist der empfohlene Weg. Zeitzone und Tastaturbelegung dort ebenfalls
  setzen: Die Belegung gilt auch für das Passwortfeld im Login, die Zeitzone für Uhr und Mitteilungen. Ohne sie
  gelten UTC und die Vorgabe-Belegung des Images (nachholen mit `sudo timedatectl set-timezone <Zone>` und
  `sudo dpkg-reconfigure keyboard-configuration`, danach neu starten).
- **Bootloader:** Ubuntu 26.04 verlangt auf dem Pi 5 einen Bootloader (EEPROM) vom 11.02.2025 oder neuer
  (`sudo rpi-eeprom-update` zeigt den Stand). Das Image fasst die Firmware nicht an.
- **Ohne Einstellungen** (balenaEtcher, oder der Imager bietet keine an) legt cloud-init `ubuntu`/`ubuntu` mit
  abgelaufenem Passwort an. Im zenOS-Login lässt sich das Passwort nicht ändern: greetd 0.10 ruft kein
  `pam_chauthtok` auf und lehnt ab (`pam_acct_mgmt: NEW_AUTHTOK_REQD`); der Login weist darauf hin. Der
  Wechsel geht an der Textkonsole (`Ctrl + Alt + F2`, mit `ubuntu`/`ubuntu` anmelden, neues Passwort setzen,
  `exit`, zurück mit `Ctrl + Alt + F7`) oder per SSH. greetd läuft auf VT 7, die Textkonsolen auf den anderen. Die
  Versionshinweise jedes Releases beschreiben das. Die erzwungene Passwortänderung bleibt bewusst, sonst
  bliebe das Standardpasswort bestehen.
- Die Benutzerteile von zenOS kommen beim ersten Login (`zenos-sitzung` ruft `install.sh --nur-benutzer`).
