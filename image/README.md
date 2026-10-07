# image

Bau des Pi-Images: `zenos-<version>-pi5-arm64.img.xz`, Paketliste und `SHA256SUMS`, dazu der Quellcode aller
Pakete für die Release-Seite. Grundlage ist das offizielle
Ubuntu 26.04 LTS Server-Image für den Raspberry Pi. Zielbild: `docs/image-und-releases.md`.

| Datei | Zweck |
|---|---|
| `image/bauen.sh` | baut das Image (lokal und in GitHub Actions, als root auf arm64-Linux), nur aus einem gültig signierten Tag |
| `image/tag-pruefen.sh` | prüft, ob ein Release-Tag gültig signiert ist (vor dem Bau, in `bauen.sh` und `image.yml`) |
| `image/erststart/` | erster Start ohne Imager: `user-data`, `90-zenos-benutzer.cfg`, README der Startpartition |
| `image/quellen.sh` | holt den Quellcode aller Pakete einer Paketliste und packt ihn in Teile unter 2 GiB |
| `.github/workflows/image.yml` | baut bei jedem Tag `v*`, veröffentlicht Releases |

## Ablauf von `bauen.sh`

0. **Tag und Signatur.** Gebaut wird nur ein Release-Tag `vX.Y.Z` oder `vX.Y.Z-rcN` (`--ref`), und nur, wenn
   `image/tag-pruefen.sh` ihn gültig signiert findet (siehe «Signatur des Tags»). Der Kanal folgt dem Tag: `vX.Y.Z` →
   `stabil`, `vX.Y.Z-rcN` → `vorschau`; die Version ist der Tag ohne «v». Passen `--kanal` oder `--version` nicht dazu,
   bricht der Bau ab. Das alles läuft vor allem anderen, ohne root und ohne Download; `--nur-pruefen` hört danach auf.
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
4. **`/opt/zenos`.** `git clone --no-local` der Quelle, losgelöst auf dem Tag,
   ohne Zweige, mit allen Tags, `origin` auf GitHub (https), leere Reflogs, Besitz root. Der Pfad der Quelle
   landet nicht im Image. Ins Image kommt nur der Commit, nicht der Arbeitsstand.
5. **chroot.** `ZENOS_KANAL=<kanal> /opt/zenos/scripts/install.sh --image` mit leerer Umgebung (`env -i`), damit
   nichts aus der CI ins Image gelangt. Das Install-Log liegt danach als `<arbeit>/install.log` daneben.
   Danach «Kennung und Sicherheitsquelle prüfen» im chroot: Umlenkung von `/usr/lib/os-release`, `ID=zenos`,
   `lsb_release -cs` gleich dem Codenamen aus `os-release.ubuntu`, `51zenos-ubuntu-quellen`,
   `zenos-sicherheitsquelle` mit Exit 0, `zenos-kennung pruefen` und kein Ubuntu in `PRETTY_NAME`. Fehlt eines,
   bricht der Bau ab (kein Image ohne nachgewiesene Ubuntu-Sicherheitsupdates). Weicht `ZENOS_VERSION` von der
   Version im Dateinamen ab (`--version`), gibt es eine Warnung. Mit `--nur-mechanik` entfällt der Schritt.
   Dann «Kanal, Vertrauensanker und Zustand ab Werk» (nicht mit `--nur-mechanik`):
   - `/etc/xdg/zenos/kanal` muss der Kanal des Tags sein.
   - Den Anker `/etc/zenos/vertrauen` füllt `12-vertrauen` nur im Image aus `system/vertrauen` des Stands (auf einem
     Gerät nie von selbst). Er muss Datei für Datei genau diesen Inhalt haben und für `zenos-kanal anker --pruefen`
     vollständig sein.
   - `zenos-kanal image <tag>` prüft den Tag im chroot ein drittes Mal, wie ein Gerät (git und ssh-keygen des Images,
     Anker des Images, `/opt/zenos` sauber auf dem Commit des Tags), und legt den Zustand ab Werk in
     `/var/lib/zenos/kanal` an: `gut.json` (der Tag als guter Stand, auch für den Rückweg), `hoechste` (seine Version,
     darunter installiert der Kanal nie) und `gesehen.json` (der Tag als gültig gesehen: Zeigt er auf origin später
     gültig signiert auf einen anderen Commit, ist das schon beim ersten Kontakt ALARM). `zen kanal status` und
     `zen version` zeigen ab dem ersten Start «<tag>, installiert am …».
   Dann «Erster Start und Paketliste» (ebenfalls nicht mit `--nur-mechanik`):
   - `user-data` und `README` aus `image/erststart/` auf die Startpartition, `90-zenos-benutzer.cfg` nach
     `/etc/cloud/cloud.cfg.d/`: Benutzer `user` mit Passwort `user` (abgelaufen), sudo nur mit Passwort,
     SSH ohne Passwörter. Die beiden Dateien gehören zusammen (chpasswd setzt das Passwort für den Benutzer aus
     `default_user`).
   - `/etc/hostname` `zenos`, in `/etc/hosts` eine Zeile `127.0.1.1 ubuntu` auf `zenos`.
   - `config.txt`: `[cm5]` mit `dtoverlay=dwc2,dr_mode=host` (USB-2 des Compute Module 5 im Host-Modus, nötig für
     Tastatur, Touchpad und USB am Argon ONE UP), danach wieder `[all]`; nur, wenn es dort noch fehlt.
   - Paketliste über `dpkg-query` im chroot (installierte Pakete: Paket, Version, Quellpaket, Quellversion), nach
     `<arbeit>/pakete.txt` und ins Image unter `/usr/local/share/doc/zenos/pakete.txt`.
6. **Aufräumen im Image.** `apt-get clean`, `policy-rc.d` weg, SSH-Hostschlüssel löschen, `machine-id`
   leeren, `random-seed` löschen, Logs leeren (rotierte löschen, `/var/log/zenos/install.log` löschen),
   Verlauf und Caches von root, `/opt/zenos` sauber (sonst Warnung und Zurücksetzen), `fstrim` (gelöschte
   Daten verschwinden, xz packt Nullen; ohne fstrim nullt `zerofree` nach dem Verkleinern).
7. **Verkleinern.** `e2fsck`, `resize2fs -M`, dazu 256 MiB Luft, Partition und Datei kürzen, Gegenprobe
   mit `e2fsck -n`. Beim ersten Start wächst die Partition über cloud-init auf die ganze Karte.
8. **Packen.** Grösse und SHA-256 des entpackten Images (für das Manifest des Imagers, in `basis.txt`), `xz -T0 -9`,
   `xz -t`, die Paketliste als `zenos-<version>-pi5-arm64.pakete.txt` daneben, `SHA256SUMS` über beide, Hinweis
   bei 2 GiB und mehr.

Bricht der Bau ab (Fehler, Ctrl+C, `SIGTERM`), beendet ein Trap die Prozesse im chroot, hängt alles aus und
löst die Loop-Geräte. Nach einem harten Abbruch (`SIGKILL`) räumt der nächste Lauf im selben Arbeitsordner
die Reste weg.

## Kanal

Das Image folgt dem Kanal seines Tags (Entscheid Zeno): `vX.Y.Z` → `stabil`, `vX.Y.Z-rcN` → `vorschau`. `dev` gibt es
im Image nicht, ausser in einem Testbau; auf `dev` kommt nie etwas automatisch. Ab dem ersten Start holt und prüft
`zenos-kanal.timer` und installiert neuere, gültig signierte Tags des Kanals zum Zeitpunkt aus Einstellungen › System ›
Updates (`docs/image-und-releases.md`, «Automatik»).

## Signatur des Tags

`image/tag-pruefen.sh [--quelle REPO] [--commit SHA] vX.Y.Z[-rcN]` prüft wie ein Gerät (`scripts/bin/zenos-kanal`):

- Name `vX.Y.Z` oder `vX.Y.Z-rcN`, ohne führende Nullen. Andere Tags (etwa `v0.2.0-beta1`) gehören zu keinem Kanal.
- Annotierter Tag, Kopf genau `object`, `type`, `tag`, `tagger`, Feld `tag` gleich dem Namen, `type commit`, mit
  `--commit` genau auf diesen Commit. Genau eine SSH-Signatur am Ende, kein OpenPGP, kein X.509.
- Der Anker `system/vertrauen` **im Commit des Tags** (nicht im Arbeitsbaum) ist vollständig und streng im Format.
- `git verify-tag` nimmt den Tag gegen `release` und `widerrufen` dieses Ankers für den Prinzipal `zenos-release` an.
  git läuft dabei gehärtet: leere Umgebung, keine System- und Benutzer-config, keine Ersatzobjekte, Hooks und
  fsmonitor aus, `gpg.ssh.program=/usr/bin/ssh-keygen`, OpenPGP und X.509 aus; was die config des Repos zu Signaturen
  sagt, überschreibt die Befehlszeile. Unabhängig davon nimmt `ssh-keygen -Y verify` die Signatur über die Nutzlast an
  (Namespace `git`, mit den Widerrufen), und beide nennen denselben Schlüssel.
- Der Anker ist der, den ein Gerät über das Netz hätte. Die Wurzel ist die von zenOS: Ihr Fingerabdruck steht fest
  im Skript (`SERIE1_WURZEL`), sie ändert sich nie. In Serie 1 sind die Release-Schlüssel genau die festen von Serie 1
  (`SERIE1_RELEASE`). Ab Serie 2 braucht jede Serie K von 2 bis zur Serie des Stands den Tag `vertrauen/KKKK`, mit der
  Wurzel gültig signiert (gegen die Widerrufe der Serien davor), auf einem Commit mit Serie K und derselben Wurzel,
  ohne einen schon widerrufenen Release-Schlüssel. Der Stand trägt genau den Anker aus `vertrauen/NNNN` der letzten
  Serie und alle Widerrufe der Kette. So fängt die Prüfung einen fremden Anker (fremde Wurzel, auch mit eigenem
  `vertrauen/0002`) und einen Release-Schlüssel, der in einem echten Release ohne neue Serie mitkam.
- Grenze: In GitHub Actions kommen Workflow und Skript aus dem Tag selbst. Wer Tags pushen kann, kann beides ändern;
  dagegen helfen nur die Regeln auf GitHub (Tag-Rulesets, unveränderliche Releases, `docs/image-und-releases.md`).
  Ein frisch geflashtes Gerät übernimmt den Anker des Images; Geräte, die über das Netz aktualisieren, nicht.

Ausgabe bei Exit 0 auf stdout: `tag`, `version`, `kanal`, `release`, `vorab`, `commit`, `objekt`, `schluessel`,
`serie`, `wurzel` (je `schluessel=wert`, für `$GITHUB_OUTPUT`). `release` ist immer `true`: Jeder gültige Tag bekommt
eine Release-Seite. `vorab` ist `true` bei `vX.Y.Z-rcN` (Vorabversion, Kanal `vorschau`) und `false` bei `vX.Y.Z`
(«Latest», Kanal `stabil`); beides kommt allein aus dem geprüften Namen, nie aus der Nachricht des Tags. Exit 1 heisst
ungültig (Grund auf stderr, dann gibt es keine Ausgabe und kein Release), 2 falscher Aufruf.

Geprüft in `test/einheiten/image-signatur.test.py` mit Wegwerf-Schlüsseln: gültig (rc als Vorabversion, final als
«Latest»), Vorabversion nur aus dem Namen (nicht aus der Nachricht), anderer Commit, unsigniert, leichter Tag, fremder
Schlüssel, Wurzel statt Release, widerrufen, falscher Name im Objekt, zwei Signaturen, keine Release-Version (auch
`-rc0`, `-rc01`, `-RC1`, `-rc1-fix`), Anker leer, unvollständig, mit Option oder nur im Arbeitsbaum, fremde config mit
eigenem Prüfprogramm, Schlüsselliste, Hooks und fsmonitor, Serie 2 mit und ohne `vertrauen/0002` (auch mit dem
Release-Schlüssel signiert oder auf einem anderen Anker), der echte Anker im Format und als fester Anker im Skript,
ein fremder Anker in Serie 1 und mit eigener Wurzel und eigenem `vertrauen/0002`, ein zusätzlicher Release-Schlüssel
ohne neue Serie, Serie 3 ohne `vertrauen/0002`, die ganze Kette bis Serie 3, ein fehlender Widerruf der Kette und ein
widerrufener Schlüssel, der zurückkommt (die Tests laufen mit einer Kopie des Skripts, in der der Wegwerf-Anker als
Serie 1 steht); dazu `bauen.sh --nur-pruefen` (unter Linux): Kanal und Version aus dem Tag, Abbruch ohne Tag,
unsigniert, fremd signiert, fremder Anker, mit anderem Kanal oder anderer Version, Testbau sowie Testbau und
`--nur-mechanik` in GitHub Actions. Aus `image.yml` laufen die Schritte «Signatur prüfen», «Versionshinweise»,
«Manifest» (mit jq, unter Linux) und «Release erstellen» so, wie GitHub sie ausführt; «Release erstellen» mit einem
nachgebauten `gh`, das nur mitschreibt (Klassen `Workflow` und `ReleaseSchritt`). `zenos-kanal image` in
`test/einheiten/kanal.test.py` (Klasse `Image`).

## Lokal ausführen

Voraussetzungen: arm64-Linux (Pi 5 mit Ubuntu, arm64-VM oder privilegierter Container), root, etwa 12 GB
frei und diese Werkzeuge:

```
sudo apt-get install curl gpgv xz-utils e2fsprogs fdisk util-linux mount git openssh-client zerofree
```

```
image/bauen.sh --nur-pruefen --ref v0.2.0              # nur Tag, Signatur, Kanal, Version (ohne root)
sudo image/bauen.sh --ref v0.2.0 --cache /var/tmp/zenos-cache
sudo image/bauen.sh --testbau-ohne-signatur            # Testbau von HEAD, Kanal dev, Version …-testbau
sudo image/bauen.sh --nur-mechanik --xz-stufe 1        # Schnelltest ohne install.sh (nur lokal)
```

Ein Testbau (`--testbau-ohne-signatur`) baut auch einen Zweig, einen Commit oder einen unsignierten Tag und erlaubt
einen anderen Kanal. Er warnt deutlich, die Version endet auf `-testbau`, und ohne gültige Signatur (oder mit anderem
Kanal als dem des Tags) bekommt das Image keinen Zustand ab Werk. In GitHub Actions verweigert `bauen.sh` die Option;
ein Release kommt nie aus einem Testbau.

| Option | Standard | Bedeutung |
|---|---|---|
| `--ref REF` | `HEAD` (nur im Testbau) | Release-Tag `vX.Y.Z` oder `vX.Y.Z-rcN`, gültig signiert; im Testbau auch Zweig oder Commit |
| `--version V` | der Tag ohne «v» | Version im Dateinamen; muss zum Tag passen (im Testbau ohne Tag: `git describe`) |
| `--quelle ORDNER` | dieses Repo | Git-Repo mit zenOS |
| `--origin URL` | origin der Quelle | origin in `/opt/zenos`, nur https ohne Zugangsdaten |
| `--kanal K` | aus dem Tag | `stabil` (`vX.Y.Z`) oder `vorschau` (`-rcN`); ein anderer, auch `dev`, nur im Testbau |
| `--ubuntu V` | `26.04` | Ubuntu-Version auf cdimage.ubuntu.com |
| `--arbeit ORDNER` | `/var/tmp/zenos-image` | Arbeitsordner |
| `--ausgabe ORDNER` | `<arbeit>/ausgabe` | Ziel für `.img.xz`, Paketliste und `SHA256SUMS` |
| `--cache ORDNER` | – | Ubuntu-Image dort behalten und wiederverwenden |
| `--zusatz-mib N` | `6144` | Vergrösserung vor dem chroot |
| `--reserve-mib N` | `256` | Luft nach dem Verkleinern |
| `--xz-stufe N` | `9` | Kompression |
| `--testbau-ohne-signatur` | – | lokaler Testbau ohne gültig signierten Tag; Version bekommt `-testbau`, kein Zustand ab Werk ohne Signatur; nie in GitHub Actions |
| `--nur-mechanik` | – | Test: im chroot nur Prüfbefehle (Architektur, `apt-get update`, `install.sh --hilfe`, `/var/tmp`, git) statt `install.sh`; Version bekommt `-mechanik`; ohne Pflicht zur Signatur, deshalb in GitHub Actions verweigert |
| `--nur-pruefen` | – | nur Tag, Signatur, Kanal und Version prüfen und zeigen, dann Ende (ohne root, baut nichts) |

Auf dem Mac in einem privilegierten Container (grosse Dateien bleiben im Container):

```
docker run -d --name zenos-image --privileged -v "$PWD":/repo:ro ubuntu:24.04 sleep infinity
docker exec zenos-image bash -c 'apt-get update && apt-get install -y curl ca-certificates gpgv xz-utils e2fsprogs fdisk util-linux mount git openssh-client'
docker exec zenos-image /repo/image/bauen.sh --nur-mechanik --xz-stufe 1 --arbeit /srv/image
docker rm -f zenos-image
```

## GitHub Actions

`.github/workflows/image.yml` läuft nur bei `push` von Tags `v*`. Alle Actions sind per Commit-SHA gepinnt,
die Rechte sind minimal (`contents: read` beim Bau, `contents: write` nur im Release-Job).

- **Tag und Signatur** (`ubuntu-24.04`, 10 min): auschecken mit ganzer Geschichte (so kommen alle Tags als
  Tag-Objekte, auch `vertrauen/NNNN` samt Commit; geprüft im Quelltext von `actions/checkout` v7.0.1), dann
  `image/tag-pruefen.sh --commit <github.sha> <tag>` («verify-tag gegen system/vertrauen»). Scheitert er, läuft kein
  anderer Job ausser der Prüfung. Seine Ausgabe (Version, Kanal, Release, Vorabversion ja/nein, Fingerabdruck,
  Serie) nutzen alle folgenden Jobs; die Zusammenfassung nennt Kanal und Art des Releases.
- **Prüfung** (`uses: ./.github/workflows/pruefen.yml`, derselbe Stand): `scripts/pruefen.sh` wie bei jedem Push.
  `pruefen.yml` läuft für den Tag ausserdem selbst (Auslöser `tags: v*`); die beiden Läufe brechen sich nicht ab
  (eigene concurrency-Gruppe je Workflow).
- **Image bauen** (`ubuntu-24.04-arm`, nativ arm64, für öffentliche Repos kostenlos, Timeout 180 min, braucht «Tag
  und Signatur»): auschecken (ganze Geschichte, ohne gespeicherte Zugangsdaten),
  `bauen.sh --ref refs/tags/<tag> --version <v> --kanal <kanal>` (prüft die Signatur noch einmal),
  `SHA256SUMS` (Image und Paketliste) und Grösse unter 2 GiB prüfen, Zusammenfassung im Lauf. Danach das Manifest
  für den Raspberry Pi Imager (mit `jq` aus `basis.txt`: Grösse und SHA-256 des entpackten Images; seine Prüfsumme
  kommt mit in `SHA256SUMS`), die Herkunftsbestätigung (`actions/attest-build-provenance` über `SHA256SUMS`, also
  Image, Paketliste und Manifest; dafür hat nur dieser Job `id-token: write` und `attestations: write`) und die
  zweisprachigen Versionshinweise. Die `url` im Manifest zeigt auf die Datei der Release-Seite, auch bei `-rc`; bei
  `-rc` nennt die Beschreibung im Manifest den Release-Kandidaten, und die Versionshinweise beginnen in beiden
  Sprachen mit «Release-Kandidat zum Testen, nicht für den Alltag» und dem Kanal `vorschau`, in dem ein Gerät
  daraus auch nach der Endversion bleibt (auf `stabil` mit `sudo zen kanal wechseln stabil`). Image,
  Paketliste, `SHA256SUMS`, Manifest und Versionshinweise gehen als Artefakt `zenos-<version>-pi5-arm64` mit
  (3 Tage, bei `-rc` wie bei `vX.Y.Z`: Sie dienen nur den folgenden Jobs und einem Neustart, danach liegt alles auf
  der Release-Seite), die Paketliste zusätzlich als kleines Artefakt `zenos-<version>-pakete`
  für den Quellen-Job, das Install-Log (14 Tage) als eigenes Artefakt, auch wenn der Bau scheitert.
- **Quellcode** (Job «quellen», `ubuntu-24.04-arm` im Container `ubuntu:26.04` mit festem Digest wie
  `pruefen.yml`, Timeout 240 min): `image/quellen.sh <paketliste> <ziel>` holt zu jedem Paar aus Quellpaket und
  Version die `.dsc` samt Dateien, zuerst mit `apt-get source --download-only --only-source` aus dem
  Ubuntu-Archiv (eigene apt-Konfiguration, apt prüft Signatur und Prüfsummen), sonst über die API von Launchpad
  (jede Datei gegen `Checksums-Sha256` der `.dsc` geprüft). Dazu Quickshell als `git archive` am Commit aus
  `25-quickshell.sh`. Gepackt in ganze Quellpakete je Teil unter 1900 MiB, mit `zenos-<version>-QUELLEN.txt` und
  `SHA256SUMS-quellen`; Artefakt `zenos-<version>-quellen` (3 Tage). Fehlt eine Quelle, scheitert der Job.
- **Annotationen:** `bauen.sh` läuft mit `sudo --preserve-env=GITHUB_ACTIONS`. sudo setzt die Umgebung zurück
  (`env_reset`), ohne diese eine Variable stünden Warnungen und Fehler von `bauen.sh` nur im Log und nicht als
  `::warning::`/`::error::` im Lauf. Weitere Variablen reicht der Workflow nicht durch, der chroot bekommt
  ohnehin eine leere Umgebung.
- **Release** (`ubuntu-24.04`, 60 min, nur dieser Job hat `contents: write`; braucht «Tag und Signatur», «Prüfung»,
  «Image bauen» samt Herkunftsbestätigung und «Quellcode», läuft also nur, wenn alle grün sind): prüft beide
  Artefakte erneut und erstellt mit `gh release create --verify-tag` das Release mit Image, Paketliste,
  `SHA256SUMS`, Manifest, allen Quellen-Teilen, dem Quickshell-Archiv, `QUELLEN.txt` und `SHA256SUMS-quellen`. Die
  Versionshinweise nennen Kanal und Fingerabdruck des Release-Schlüssels.
  - **`vX.Y.Z`** (Kanal `stabil`): mit `--latest`.
  - **Tags mit `-rc`** (z. B. `v0.1.0-rc4`, Kanal `vorschau`): als Vorabversion, `--prerelease --latest=false`, also
    nie «Latest» (Entscheid Zeno, 06.10.2026: So läuft der Job schon vor `v0.1.0`, und Fehler darin fallen früh
    auf). Bis `v0.1.0-rc3` gab es für `-rc` nur die Artefakte.
  - Welche Art, sagt allein die Ausgabe `vorab` von «Tag und Signatur»; der Schritt prüft sie noch einmal gegen den
    Tag und bricht ohne gültigen Wert ab.
  - **Neustart:** Liegt das Release noch als Entwurf vor (ein früherer Lauf brach ab; `gh` legt es zuerst als Entwurf
    an, lädt hoch und veröffentlicht dann), löscht der Job den Entwurf, der Tag bleibt, und legt das Release neu an.
    Ein veröffentlichtes Release bleibt, wie es ist: Der Job prüft nur, ob alle Dateien da sind und die Markierung
    stimmt, und ist dann grün. Mit Immutable Releases (ANLEITUNG G) liesse es sich ohnehin nicht mehr ändern.
- Andere Tags `v*` (etwa `v0.2.0-beta1`) scheitern schon bei «Tag und Signatur», ohne Ausgabe und ohne Release.

Die Grundlage (Ubuntu-Datei und SHA-256) steht in den Versionshinweisen und in `<arbeit>/basis.txt`.

## Grenzen

- **Platz auf dem Runner: 14 GB.** Spitze etwa 9–10 GB: entpacktes Ubuntu-Image (2,8 GB belegt), Pakete,
  Quickshell-Bau (3,5 GB unter `/var/tmp`, also im Arbeitsordner), danach das `.xz`. Der Download wird nach
  dem Entpacken gelöscht. `bauen.sh` warnt unter 11 GiB freiem Platz.
- **Release-Dateien unter 2 GiB.** Sonst bricht der Workflow vor dem Release ab. Das Ubuntu-Image allein
  ergibt etwa 1,5 GB. Was zenOS dazu bringt, zeigt `bauen.sh` unter «Grösste Ordner».
- **Kein `apt upgrade` beim Bau.** flash-kernel läuft im chroot nicht, ein neuer Kernel käme nicht nach
  `/boot/firmware`. Sicherheitsupdates holt unattended-upgrades nach dem ersten Start.
- **Signatur:** Der Tag ist mit dem Release-Schlüssel signiert, und nur ein solcher Tag wird gebaut. Image,
  Paketliste und Manifest haben eine Herkunftsbestätigung von GitHub (Sigstore, ohne eigenen Schlüssel), geprüft mit
  `gh attestation verify`. Eine eigene Signatur der Image-Dateien (`SHA256SUMS.sig`) gibt es noch nicht.
- **Vertrauen in die CI:** Den Workflow und `bauen.sh` liest GitHub aus dem Stand des Tags. Wer auf GitHub einen
  Tag mit eigenem Workflow schieben kann, kann auch die Prüfung darin ändern. Davor schützen die Regeln auf GitHub
  (ANLEITUNG G: Tags `v*` und `vertrauen/*` nur für Admins verschiebbar und löschbar, kein Force-Push) und vor allem
  die Geräte: Sie prüfen jeden Tag selbst gegen ihren eigenen Anker.
- **Marke:** Das Image heisst zenOS und «basiert auf Ubuntu» (geprüft am 04.10.2026, `docs/image-und-releases.md`,
  «Name und Marke»).
- **Quellen:** etwa 3 GB je Release, so lange online wie das Image (GPL). Sie hängen an der Paketliste aus genau
  diesem Bau.
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
- **Ohne Einstellungen** (balenaEtcher, oder der Imager ohne Manifest-Datei) legt cloud-init den Benutzer `user`
  («Default User») mit dem abgelaufenen Passwort `user` an (`image/erststart/user-data` und
  `90-zenos-benutzer.cfg`, sudo nur mit Passwort). Im zenOS-Login lässt sich das Passwort nicht ändern: greetd 0.10
  ruft kein `pam_chauthtok` auf und lehnt ab (`pam_acct_mgmt: NEW_AUTHTOK_REQD`); der Login weist darauf hin. Der
  Wechsel geht an der Textkonsole (`Ctrl + Alt + F2`, mit `user`/`user` anmelden, neues Passwort setzen, `exit`,
  zurück mit `Ctrl + Alt + F7`); SSH nimmt nur Schlüssel an. greetd läuft auf VT 7, die Textkonsolen auf den anderen. Die
  Versionshinweise jedes Releases beschreiben das. Die erzwungene Passwortänderung bleibt bewusst, sonst
  bliebe das Standardpasswort bestehen.
- Die Benutzerteile von zenOS kommen beim ersten Login (`zenos-sitzung` ruft `install.sh --nur-benutzer`).
