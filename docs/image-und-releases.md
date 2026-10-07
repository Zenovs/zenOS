# Image und Releases

Ziel: Ein fertiges Pi-Image liegt als Release auf GitHub und lässt sich direkt herunterladen und flashen. Wie der
Bau im Einzelnen läuft (Optionen, lokal im Container, Aufräumen), steht in `image/README.md`.

## Ablauf in GitHub Actions

`.github/workflows/image.yml` ruft `image/bauen.sh` auf.

1. **Auslöser:** ein Tag `v*`, sonst nichts. Gebaut wird nur ein Release-Tag `vX.Y.Z` oder `vX.Y.Z-rcN`, der mit dem
   Release-Schlüssel gültig signiert ist:
   - **Tag und Signatur** (eigener Job, vor allem anderen): `image/tag-pruefen.sh` prüft den Tag auf genau den Commit
     des Laufs gegen den Anker `system/vertrauen` in diesem Commit, mit gehärtetem `git verify-tag` und unabhängig
     davon mit `ssh-keygen -Y verify` (Regeln in `image/README.md`, «Signatur des Tags»). Ab Serie 2 muss der Tag
     `vertrauen/NNNN` dazu passen. Scheitert das, wird nichts gebaut.
   - **Kanal je nach Tag:** `vX.Y.Z` → `stabil`, `vX.Y.Z-rcN` → `vorschau` (Entscheid Zeno). `dev` bekommt kein Image.
     Ebenso aus dem Namen: `vorab` (`true` bei `-rcN`), ob das Release eine Vorabversion wird.
   - **Prüfung:** `scripts/pruefen.sh` läuft im selben Lauf für denselben Stand (`pruefen.yml` als aufgerufener
     Workflow). Ein Release gibt es nur, wenn sie grün ist.
2. **Runner:** `ubuntu-24.04-arm`. Er läuft nativ auf arm64 und ist für öffentliche Repos kostenlos.
3. **Basis:** das offizielle Ubuntu 26.04 LTS Server-Image für den Raspberry Pi, die neueste Punktversion laut
   `SHA256SUMS` auf cdimage.ubuntu.com (derzeit `ubuntu-26.04.1-preinstalled-server-arm64+raspi.img.xz`). Die
   Signatur von `SHA256SUMS` wird mit GPG gegen den Ubuntu-Schlüssel geprüft (Fingerabdruck fest im Skript), danach
   die Prüfsumme der Datei.
4. **Anpassen:** `bauen.sh` prüft Tag und Signatur selbst noch einmal (und bricht ab, wenn Kanal oder Version nicht
   zum Tag passen), vergrössert das Image, hängt es als Loop-Gerät ein, legt `/opt/zenos` als Checkout des Tags an und
   führt per `chroot` `ZENOS_KANAL=<kanal> /opt/zenos/scripts/install.sh --image` aus. Das Image enthält nur freie
   Pakete und zenOS; Quickshell wird dabei gebaut. Danach prüft `bauen.sh` im chroot die Kennung zenOS und die
   Ubuntu-Sicherheitsquelle (Umlenkung von os-release, `ID=zenos`, Codename wie Ubuntu, `51zenos-ubuntu-quellen`,
   `zenos-sicherheitsquelle` Exit 0, `zenos-kennung pruefen`, kein Ubuntu in `PRETTY_NAME`) und bricht sonst ab.
   Dann **Kanal, Anker und Zustand ab Werk:** `/etc/xdg/zenos/kanal` ist der Kanal des Tags. Den Anker
   `/etc/zenos/vertrauen` füllt `12-vertrauen` nur im Image, aus `system/vertrauen` des Stands (Datei für Datei
   verglichen). `zenos-kanal image <tag>` prüft den Tag im chroot ein drittes Mal wie ein Gerät und legt in
   `/var/lib/zenos/kanal` `gut.json` (der Tag als guter, installierter Stand), `hoechste` (seine Version) und
   `gesehen.json` (der Tag als gültig gesehen) an. Ein neues Gerät kennt so ab dem ersten Start seinen Stand, geht nie
   unter diese Version, und ein später verschobener Tag ist schon beim ersten Kontakt ALARM.
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
7. **Packen:** `xz -T0 -9`, dazu `SHA256SUMS` über Image und Paketliste. Danach schreibt der Workflow das Manifest
   für den Raspberry Pi Imager, nimmt es in `SHA256SUMS` auf, und GitHub bestätigt die Herkunft aller drei (Artifact
   Attestation, siehe «Prüfen»).
8. **Quellcode** (eigener Job «quellen», Container `ubuntu:26.04`): `image/quellen.sh` holt zu jedem Paar aus
   Quellpaket und Version der Paketliste die `.dsc` samt Dateien, zuerst aus dem Ubuntu-Archiv (apt prüft Signatur und
   Prüfsummen), sonst von Launchpad (geprüft gegen die Prüfsummen der `.dsc`), dazu Quickshell als `git archive` am
   gebauten Commit. Fehlt eine Quelle, scheitert der Job, und es gibt kein Release.
9. **Veröffentlichen:** Jeder gültige Tag bekommt ein Release mit allen Dateien unter «Release-Dateien», nur wenn
   Signatur, Prüfung, Bau mit Herkunftsbestätigung und Quellen grün sind. Die Versionshinweise nennen Kanal und
   Fingerabdruck des Release-Schlüssels.
   - `vX.Y.Z` (Kanal `stabil`): als «Latest».
   - Tags mit `-rc` (z. B. `v0.1.0-rc4`, Kanal `vorschau`): als **Vorabversion** (Pre-release), nie «Latest». Die
     Versionshinweise beginnen in beiden Sprachen mit «Release-Kandidat zum Testen, nicht für den Alltag» und sagen,
     dass ein Gerät daraus auch nach der Endversion im Kanal `vorschau` bleibt (auf `stabil` mit
     `sudo zen kanal wechseln stabil`). Entscheid Zeno vom 06.10.2026, damit der Job «Release» schon vor `v0.1.0`
     läuft und Fehler darin früh auffallen; bis `v0.1.0-rc3` gab es für `-rc` nur Workflow-Artefakte.
   - Andere Tags `v*` (etwa `v0.2.0-beta1`) gehören zu keinem Kanal und scheitern schon bei der Signatur, ohne Release.
   - Wird der Lauf neu gestartet, legt der Job ein Release, das noch Entwurf ist, neu an; ein veröffentlichtes bleibt,
     wie es ist (`image/README.md`, «GitHub Actions»).

## Release-Dateien

| Datei | Inhalt |
|---|---|
| `zenos-<v>-pi5-arm64.img.xz` | das Image |
| `zenos-<v>-pi5-arm64.pakete.txt` | alle Pakete im Image mit Version und Quellpaket |
| `SHA256SUMS` | Prüfsummen von Image, Paketliste und Manifest |
| `zenos-<v>.rpi-imager-manifest` | Manifest für den Raspberry Pi Imager 2.x (siehe «Flashen») |
| `zenos-<v>-quellen-teil<NN>.tar` | Quellcode aller Ubuntu-Pakete im Image, je Teil unter 2 GiB |
| `zenos-<v>-quickshell-<qv>.tar` | Quellcode von Quickshell am gebauten Commit |
| `zenos-<v>-QUELLEN.txt` | welches Quellpaket in welchem Teil liegt und woher es kommt |
| `SHA256SUMS-quellen` | Prüfsummen der Quellen-Dateien |

## Prüfen

- Prüfsummen: `sha256sum -c --ignore-missing SHA256SUMS` (ohne `--ignore-missing` nur, wenn alle drei Dateien da
  sind; dazu `sha256sum -c SHA256SUMS-quellen` für die Quellen). Über das Manifest lädt der Imager das Image selbst
  und prüft es gegen `image_download_sha256` und `extract_sha256` darin; deshalb steht das Manifest mit in
  `SHA256SUMS` und in der Herkunftsbestätigung.
- Herkunft: `gh attestation verify zenos-<v>-pi5-arm64.img.xz --repo <besitzer>/zenOS` bestätigt, dass die Datei aus
  dem Workflow dieses Repos zum Tag stammt (dasselbe für Paketliste und Manifest). Die Bestätigung erzeugt GitHub ohne eigenen
  Schlüssel über Sigstore; dabei landen Metadaten aus der CI (Repo, Workflow, Commit, Prüfsummen) im öffentlichen
  Transparenz-Log von Sigstore. Vom Rechner, auf dem zenOS läuft, geht dabei nichts weg.
- Signatur des Tags: im Repo `image/tag-pruefen.sh vX.Y.Z` (dieselbe Prüfung wie vor dem Bau). Von Hand geht
  `git -c gpg.ssh.allowedSignersFile=system/vertrauen/release -c gpg.ssh.revocationFile=system/vertrauen/widerrufen verify-tag vX.Y.Z`;
  dann zählt nur der Exit-Code, und das Feld `tag` im Objekt (`git cat-file tag vX.Y.Z`) muss dem Namen entsprechen.
  Den Fingerabdruck des Release-Schlüssels nennen die Versionshinweise.

## Signierte Releases

**Stand:** Signieren ist eingerichtet. Der Anker `system/vertrauen/` hat Serie 1 mit je einem öffentlichen Schlüssel
«zenOS Release» (`SHA256:6CAhnfU9qHJz36663u/A/HxmZkKxao0r2QxT3oy+DzI`) und «zenOS Wurzel»
(`SHA256:9xQZHFzUT4CF87GQ2VrCo6oGEC1DimrsHOtEmnB5pDk`), beide am 05.10.2026 mit 1Password abgeglichen. `zen update`
und `zen rollback` laufen über `zenos-kanal` (siehe «Auf dem Gerät»): auf `stabil` und `vorschau` nur gültig
signierte Tags, auf `dev` ein nicht durchgehend signierter Stand nur nach einem getippten «ja». Ein Gerät ohne Anker
(`/etc/zenos/vertrauen`) meldet «Anker fehlt» und installiert über `stabil` und `vorschau` nichts (fail-closed).
Automatische Updates mit einstellbarem Zeitpunkt laufen über `zenos-kanal.timer` («Automatik»). Images entstehen nur
aus gültig signierten Tags, folgen `stabil` bzw. `vorschau` und bringen den Anker mit («Vom Tag zum Image»).

**Installiert per Skript** (`git clone` und `install.sh`, README): Der Kanal ist `dev` (aus `main`: `stabil`), der
Anker bleibt leer, denn `install.sh` übernimmt ihn ausserhalb des Images nie von selbst (`12-vertrauen`). Auf `dev`
installiert `zen update` nur nach «ja», auf `stabil` und `vorschau` gar nichts («Anker fehlt»). Den Anker setzt
`sudo zen kanal anker /opt/zenos/system/vertrauen`: Es fragt den Fingerabdruck der Wurzel und die ersten 8 Zeichen
jedes Release-Schlüssels ab, und die kommen aus einer Quelle ausserhalb des Geräts: beim Besitzer der Schlüssel aus
1Password, sonst die Fingerabdrücke oben (diese Seite auf GitHub; den des Release-Schlüssels nennen auch die
Versionshinweise). Danach wechselt `sudo zen kanal wechseln stabil` (oder `vorschau`) den Kanal.

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
- `serie`: eine Zahl von 1 bis 9999. Serie 1 ist der erste Anker, er kommt mit dem Image oder einmalig von Hand
  (`sudo zen kanal anker /opt/zenos/system/vertrauen`); ein unsignierter Stand füllt ihn nie von selbst.

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
   - Die Prüfung `pruefen.yml` für HEAD ist per `gh` grün. Läuft sie noch (oder ist der Push noch nicht zu sehen),
     wartet das Skript höchstens 25 Minuten; rot oder danach nicht fertig bricht es ab. Ist sie nicht prüfbar (gh
     fehlt, kein Zugriff), geht es nur mit getipptem «ohne Prüfung» weiter.
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

### Vom Tag zum Image

Ein Release von Anfang bis Ende:

1. **Stand:** alles auf `dev` committet und gepusht, `pruefen.yml` für diesen Commit grün.
2. **Signieren** auf dem Mac in einem eigenen Terminal-Tab: `scripts/release-signieren.sh vX.Y.Z` (oder
   `vX.Y.Z-rcN`). Es prüft Stand, CI und Anker, zeigt die Änderungen, signiert mit Touch ID und pusht nur den Tag.
3. **Prüfen auf GitHub:** Der Tag startet `pruefen.yml` (Auslöser `tags: v*`) und `image.yml`. Dort prüft zuerst
   «Tag und Signatur» den Tag gegen `system/vertrauen` im Stand, und dieser Anker muss der sein, den ein Gerät über
   das Netz hätte: Wurzel und Release-Schlüssel von Serie 1 stehen fest in `image/tag-pruefen.sh`, jede spätere Serie
   braucht die ganze Kette `vertrauen/0002` bis `vertrauen/NNNN`, mit der Wurzel signiert. Ein unsignierter, fremd
   signierter, verschobener oder falsch benannter Tag baut nichts, ebenso ein Stand mit fremder Wurzel oder einem
   Release-Schlüssel, der ohne neue Serie dazukam.
4. **Image:** `bauen.sh` prüft noch einmal, baut mit dem Kanal des Tags (`stabil` oder `vorschau`), legt den Anker
   aus `system/vertrauen` nach `/etc/zenos/vertrauen` und den Zustand ab Werk an (`gut.json`, `hoechste`,
   `gesehen.json` aus dem Tag). Danach folgt das Release, wenn auch die Prüfung im selben Lauf grün ist: für `vX.Y.Z`
   als «Latest», für `-rcN` als Vorabversion.
5. **Geräte:** Wer `vorschau` folgt, bekommt `-rcN` ohne Wartezeit, wer `stabil` folgt, `vX.Y.Z` 24 h nach dem ersten
   Sehen, beide zum eingestellten Zeitpunkt. Jedes Gerät prüft den Tag selbst gegen seinen eigenen Anker; der Bau auf
   GitHub ist dafür nicht nötig.

Lokal lässt sich die Prüfung vor dem Bau ohne root nachspielen: `image/bauen.sh --nur-pruefen --ref vX.Y.Z`. Ein
lokaler Testbau ohne gültig signierten Tag geht nur mit `--testbau-ohne-signatur` (Version endet auf `-testbau`) oder
`--nur-mechanik` (`-mechanik`); in GitHub Actions verweigert `bauen.sh` beide.

Auf GitHub schützt Zeno die Tags zusätzlich (ANLEITUNG G): Rulesets für `v*` und `vertrauen/*` (nicht verschieben,
nicht löschen, kein Force-Push, Ausnahme nur für Admins), kein Force-Push und kein Löschen auf `dev` und `main`,
Immutable Releases. Ein veröffentlichtes Release bleibt dann, wie es ist (Dateien und Tag); löschen lässt es sich
weiter, danach den Tag (Notbremse), nur der Name ist dann verbraucht. Das ist nötig, denn `image.yml` und
`tag-pruefen.sh` kommen selbst aus dem Tag: Wer Tags pushen kann, kann auch die Prüfung darin ändern. Der feste Anker
in `tag-pruefen.sh` fängt deshalb vor allem Anker, die in einem echten Release ungewollt mitkamen (etwa ein
zusätzlicher Release-Schlüssel durch eine Prompt-Injection): Er geht nicht ins Image, auch nicht in Serie 1.

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

Was ein Gerät prüft (`zenos-kanal`, siehe «Auf dem Gerät»):

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

### Auf dem Gerät: zenos-kanal

`scripts/bin/zenos-kanal` (Python, nur Standardbibliothek, `python3 -I`) liegt als root-eigene Kopie unter
`/usr/local/libexec/zenos/zenos-kanal` (Modul `14-kanal`). Die Units und `zen update` führen diese Kopie aus, nie
`/opt/zenos`. Installiert wird von Hand (`zen update`, `zen rollback`, die Knöpfe in Einstellungen › System ›
Updates) und automatisch über `zenos-kanal.timer`, aber nur auf stabil und vorschau, nur gültig signiert, ohne
Rückfrage-Pfade, nach der Wartezeit und zum Zeitpunkt, den der Benutzer am Gerät einstellt (siehe «Automatik» unten).

| Befehl | Wer | Was |
|---|---|---|
| `zen update` | Benutzer mit sudo, im Terminal | holen, prüfen und bereitstellen, bei Bedarf «ja», installieren mit Gesundheitsprüfung und Rückweg; danach als Schritt 2 die Pakete der Ubuntu-Basis («Basis-Updates» unten; nur der Kanal: `--nur-zenos`), dann die Benutzerteile |
| `zen rollback <tag>` | ebenso | dasselbe mit einem Tag als Ziel |
| `zen kanal status` | alle | Kanal, Zustand, Anker mit Fingerabdrücken, installierter Stand, `hoechste`, gültige und abgelehnte Tags, letzter Kontakt, letzte Installation, guter Stand, gesperrte Stände |
| `sudo zen kanal pruefen` | root | startet `zenos-kanal-holen.service`, dann `zenos-kanal-pruefen.service`, zeigt danach den Status. Installiert nichts |
| `zen kanal anker` | alle | zeigt den Anker des Geräts |
| `zen kanal zeitpunkt` | alle | zeigt, wann geprüfte Updates automatisch kommen (`/etc/xdg/zenos/kanal-zeitpunkt`, ohne Datei `sperre`) |
| `sudo zen kanal zeitpunkt sperre\|jederzeit\|hand`, `… fenster VON BIS` | root | setzt ihn (dasselbe wie in den Einstellungen; VON und BIS als HH:MM, mindestens eine Stunde, über Mitternacht erlaubt) |
| `zen kanal automatik` | alle | ob die Automatik an ist, nächstes Holen, was sie zuletzt tat, ein Stand, der auf die Bestätigung wartet, eine zurückgestellte Version |
| `sudo zen kanal automatik an\|aus` | root | Notschalter: Timer ein bzw. aus, Vermerk `/etc/xdg/zenos/kanal-automatik-aus` (install.sh hält sich daran). `zen update` geht immer, die Signaturprüfung bleibt |
| `sudo zen kanal wechseln stabil\|vorschau\|dev` | root | setzt den Kanal in `/etc/xdg/zenos/kanal` (atomar, 0644, nur diese drei Wörter, Eintrag im Journal). Installiert nichts; ist der installierte Stand neuer als die neueste Version des neuen Kanals, fragt `zen update` danach nach «ja» (Rückschritt) |
| `sudo zen kanal anker ORDNER` | root, nur im Terminal | setzt den Anker von Hand: den Fingerabdruck der Wurzel und von jedem Release-Schlüssel die ersten 8 Zeichen nach `SHA256:` aus einer vertrauenswürdigen Quelle eintippen (1Password beim Besitzer der Schlüssel, sonst «Signierte Releases» oben). Die Werte aus dem Ordner zeigt es erst danach (auch nach einer falschen Eingabe nicht), damit niemand abtippt, was auf dem Bildschirm steht. Bei gleicher Wurzel nie mit kleinerer Serie, Widerrufe des Geräts bleiben |

Ablauf:

1. **Holen** (`zenos-kanal-holen.service`): als flüchtiger Systembenutzer (DynamicUser) in einer Sandbox, nur mit
   Netz und dem eigenen Ordner `/var/lib/zenos-kanal-holen`. Die Adresse ist origin aus `/opt/zenos/.git/config`,
   nur `https://` ohne Zugangsdaten. `git fetch --no-tags --prune` holt erzwungen nur `refs/tags/v*` (Versionen und
   `vertrauen/NNNN`) nach `refs/kanal/tags/v*` und den Branch `dev` nach `refs/kanal/heads/dev` (ob es ihn gibt, sagt
   vorher `git ls-remote`; ein fehlender Branch in der Liste liesse den Abruf scheitern), mit fsck, Zeitlimit 600 s.
   Ein verschobener oder gelöschter Tag bricht nichts ab. Danach entfernt es andere Refs, packt den Spiegel neu und
   löscht, was nicht mehr erreichbar ist (`repack -a -d`, `prune`); ist er dann grösser als 2 GB, fliegt er weg. So
   füllt ein fremder Branch oder ein wiederholter Push grosser Daten die Platte nicht (Prüfung, Befund 4). Ergebnis:
   `uebergabe.bundle` und `holen.json` (Zeitpunkt, Fehler; nur zur Anzeige).
2. **Prüfen** (`zenos-kanal-pruefen.service`): root, ohne Netz (PrivateNetwork), schreiben nur nach
   `/var/lib/zenos/kanal`, `/etc/zenos/vertrauen` und `/run/zenos-sperre` (RuntimeDirectory, 0700, bleibt stehen). Die
   Sperre `/run/zenos-sperre/kanal.lock` teilt es mit `zen update`, dem Installieren und einem `install.sh` von Hand;
   nur root kommt an sie heran (früher `/run/lock`, wo jeder Benutzer sie halten konnte). Das Bundle wird kopiert
   (ohne Verweisen zu folgen, höchstens 1 GiB) und in ein Repo geholt, das bei jedem Lauf neu entsteht (eigene
   config, keine Hooks). Jedes git läuft mit leerer Umgebung, ohne System- und Benutzer-config, ohne Ersatzobjekte,
   mit `core.hooksPath=/dev/null`, `core.fsmonitor=false`, `protocol.allow=never`,
   `gpg.ssh.program=/usr/bin/ssh-keygen`, OpenPGP und X.509 aus.
3. **Regeln**, in dieser Reihenfolge:
   - Anker: wie oben, root-eigen und für andere nicht schreibbar, auch jeder Ordner darüber. Sonst «Anker fehlt»,
     und nichts gilt als gültig. Die Formprüfung der Tags läuft trotzdem (etwa «unsigniert»).
   - Tag: annotiert; Kopf genau `object`, `type`, `tag`, `tagger`; Feld `tag` gleich dem Ref-Namen; `type commit`;
     genau eine SSH-Signatur am Ende, mit Namespace `git` und Ed25519; keine OpenPGP- oder X.509-Signatur. Der
     Schlüssel in der Signatur darf nicht widerrufen sein und muss zur Rolle passen. Dann `git verify-tag
     <Objekt-ID>` gegen den Anker mit der erwarteten Zeile `Good "git" signature for <prinzipal> with ED25519 key
     <fingerabdruck>`.
   - Viele Tags: Die Tag-Objekte liest es mit drei Aufrufen von `git cat-file --batch` statt zwei je Tag (höchstens
     64 KiB je Objekt). Leichte, unsignierte und fremd signierte Tags kosten so kaum etwas. `git verify-tag` läuft nur
     für Tags mit einem Schlüssel des Ankers, höchstens 2000-mal je Lauf; schon gültige Namen zählen nicht mit und
     kommen zuerst, danach die höchsten Versionen. Die übrigen bleiben ungeprüft (Hinweis), nichts ist deswegen
     «blockiert» (früher blockierten 1001 leichte Tags jedes Gerät, Prüfung, Befund 5). Abgelehnt zeigt es höchstens
     100, den Rest als Zahl.
   - `vertrauen/NNNN` zuerst, aufsteigend, nur mit NNNN über der eigenen Serie (siehe oben). Der neue Anker wird
     Datei für Datei atomar geschrieben: `release`, `widerrufen`, die Serie zuletzt. Bricht es dazwischen ab, ist jeder
     Zwischenstand ein gültiger Anker, und der nächste Lauf vollendet den Wechsel (früher zuerst `widerrufen`: Der
     alte Release-Schlüssel stand dann zugleich in `release` und `widerrufen`, «Anker fehlt» für immer).
   - Hauptbuch `gesehen.json` (nur Namen, die gültig waren: Objekt, Commit, erstmals gesehen mit Uhrzeit und Start,
     beides nur mit synchronisierter Uhr, siehe «Automatik»): Zeigt ein schon
     gültiger Name gültig signiert auf einen anderen Commit, ist der Kanal «blockiert» (ALARM), bis der Name wieder
     auf den alten Commit zeigt. Derselbe Commit in einem anderen Tag-Objekt ist kein Alarm, das Hauptbuch übernimmt
     die neue Objekt-ID: Die Base64-Zeilen der Signatur lassen sich ohne Schlüssel anders umbrechen oder mit einer
     Leerzeile versehen, git nimmt das an (selbst nachgestellt, Prüfung, Befund 1). Ein ungültiges neues Objekt lehnt
     nur diesen Namen ab, ein auf origin gelöschter Tag ist ein Hinweis und kein Ziel mehr (Notbremse).
   - `hoechste` (`/var/lib/zenos/kanal/hoechste`): Jeder gültige Tag, dessen Commit im Verlauf des installierten
     Stands liegt, hebt es an; es sinkt nie. Solange eine Installation unterbrochen ist (`laeuft.json`), hebt es sich
     nicht: `/opt/zenos` steht dann womöglich auf einem Ziel, das nie gesund wurde. Den Verlauf liest es im eigenen Repo oder, für nicht gepushte Commits,
     in `/opt/zenos` (nur lesend, nicht flach). Fehlt `hoechste` und gehört der installierte Stand zu keiner
     signierten Version, ist der Kanal «blockiert», ausser der Stand liegt vor allen gültigen Versionen.
   - Ziel: die höchste gültige Version des Kanals über `hoechste`, ohne Versionen in `/var/lib/zenos/kanal/gesperrt/`.
     `stabil` nimmt nur `vX.Y.Z` und gibt sie erst 24 h nach dem ersten Sehen für die Automatik frei (`frei_ab`,
     `frei`), `vorschau` auch `vX.Y.Z-rcN` sofort. Die nach `zen rollback` verlassene Version liegt nie über
     `hoechste` (das sinkt nicht) und ist deshalb kein Ziel der Prüfung; `zen update` von Hand nimmt sie.
   - Ubuntu-Basis: `system/basis` im Stand nennt die Ubuntu-Version, für die er gebaut ist (eine Zeile wie `26.04`;
     Stände ohne die Datei gelten als 26.04). Passt sie nicht zur `VERSION_ID` des Geräts (mit der Kennung zenOS aus
     `/usr/lib/os-release.ubuntu`), ist der Stand nie ein Ziel: nicht für die Automatik, nicht für `zen update`, auch
     nicht mit «ja», über dev oder `zen rollback`, und `zenos-kanal image` legt mit ihm keinen Zustand ab Werk an.
     Das Ziel ist dann die höchste Version für die eigene Basis; die übrigen stehen in `stand.json` unter
     `basis.fremd` und als Hinweis. Installieren prüft die Basis in der Bereitstellung noch einmal. Ohne diese Grenze
     holte ein Gerät auf 26.04 eine künftige Hauptversion für 28.04 von selbst, weil sie die höchste gültige Version
     ist. Ein Basiswechsel ist eine neue Hauptversion mit neuem Image (siehe «Basiswechsel» unten).
   - `dev`: Neuer Stand von `origin/dev`, ob der installierte Stand darin liegt und ob jeder Commit
     dazwischen gültig mit einem Release-Schlüssel signiert ist (`%G?` gleich `G`; ein unsignierter Commit unter
     einer signierten Spitze zählt). Sonst nur von Hand mit «ja». Automatisch kommt auf dev nie etwas. Ist
     `origin/dev` für eine andere Ubuntu-Basis gebaut, steht das in `dev.basis_problem`, und nichts geht.
   - Rückfrage-Pfade: Trifft der Weg vom installierten Stand zum Ziel Firewall, Netz oder Boot, heisst der Zustand
     `zustimmung`. Die Liste steht fest im Code (`CONSENT_PATHS`, gleich den Gruppen `firewall`, `netz` und `boot`
     in `scripts/lib/sensible-pfade`, ein Test hält beide gleich); die Liste im neuen Stand kann nur Pfade
     dazunehmen. Lässt sich der Weg nicht vergleichen (installierter Stand unbekannt), gilt ebenfalls `zustimmung`.
4. **Stand:** `/var/lib/zenos/kanal/stand.json` (0644, atomar): `kanal`, `zustand`, `grund`, `geprueft`,
   `letzter_kontakt`, `holen_fehler`, `anker` (Serie und Fingerabdrücke), `anker_problem`, `installiert`,
   `hoechste`, `bereit` (Version, Commit, Objekt, `erstmals`, `frei_ab`, `frei`, `rueckfrage`), `dev`, `gueltig`,
   `abgelehnt`, `hinweise`, `uhr_synchron`, `automatik` (`an`), `basis` (`geraet`: Ubuntu-Version des Geräts,
   `fremd`: gültige Versionen für eine andere Basis), `unbestaetigt` (automatisch installierter Stand vor
   der Bestätigung), `zurueckgestellt` (Version nach `zen rollback`), `angehalten` (Stand von Hand: Commit, seit),
   `installation_lage` (wie `zen kanal status --installation`: `schluessel` und `text`, etwa `kaputt` oder
   `unterbrochen`; so zeigt die Oberfläche das auch dann, wenn die Prüfung danach jünger ist als `letzte.json`),
   `wunsch` (Antwort auf `zen update` bzw. `zen rollback`, die Knöpfe oder die Automatik, siehe unten), `installation`
   (Prüfsumme von `letzte.json` und `gut.json`: Weicht sie ab, zeigt `zen kanal status` «veraltet: Seit der letzten
   Prüfung wurde installiert», statt alte Angaben als aktuell auszugeben). Nach jeder Installation prüft `zen update`
   ohne Netz und ohne Wunsch neu.

| Zustand | Exit | Bedeutung |
|---|---|---|
| `aktuell` | 0 | keine neuere gültige Version |
| `bereit` | 0 | eine neuere gültige Version gibt es (`zen update` installiert sie) |
| `zustimmung` | 10 | wie `bereit`, aber der Weg trifft Firewall, Netz oder Boot: nur mit Zustimmung |
| `dev` | 0 | Kanal dev, nur Auskunft |
| `anker_fehlt` | 3 | kein vollständiger Anker: nichts gilt |
| `blockiert` | 3 | ALARM im Hauptbuch, unbekannter Kanal, `hoechste` nicht ableitbar, Bundle unbrauchbar |
| `kein_kontakt` | 10 | noch nie geholt |
| `fehler` | 1 | Prüfung abgebrochen |
| (keiner) | 75 | Sperre belegt (ein `zen update` läuft), `stand.json` bleibt |

#### Wunsch und Bereitstellung (`zen update`, `zen rollback`)

`zen update` startet als root `zenos-kanal update` im Terminal. Läuft gerade ein `install.sh` von Hand (Vermerk
`/run/zenos-sperre/hand`, siehe unten), endet es mit 75. Es schreibt `wunsch.json` (Art, Tag, Kennung, eine Stunde
gültig, gemessen an der Zeit seit dem Start: Stellt NTP die Uhr dazwischen, gilt er weiter), startet holen und prüfen
und liest die Antwort aus `stand.json` (`wunsch`). Das Prüfen bestimmt das Ziel:

- `stabil`, `vorschau`: die höchste gültige Version des Kanals, nicht unter `hoechste` (auch gleich: ein
  `zen update` nach einem Rollback kehrt zurück), ohne gesperrte Versionen, also dieselbe, die die Prüfung und die
  Einstellungen `bereit` nennen. Eine gesperrte Version noch einmal versuchen geht nur bewusst: `zen rollback vX.Y.Z`
  mit «ja». Ohne Anker oder bei «blockiert» nichts.
- `dev`: `origin/dev`. Ohne Frage nur, wenn der installierte Stand im Verlauf liegt und jeder neue Commit gültig
  signiert ist; das prüft das Installieren gegen den Anker von dann noch einmal.
- `rollback <tag>`: der Tag vom zuletzt geholten Stand; gültig signiert ohne Frage, sonst nur mit «ja». Ein
  Vertrauens-Tag ist kein Ziel, ein gültiger Name, der auf origin auf ein anderes Objekt zeigt, wird abgelehnt.

Ein getipptes «ja» braucht es, wenn das Ziel nicht gültig signiert ist (dazu gehört: Anker fehlt, Kanal blockiert,
dev umgeschrieben, nicht jeder neue Commit signiert), wenn es gesperrt ist (scheiterte schon einmal), ein
Rückschritt wäre (Kanalwechsel von dev) oder Firewall, Netz oder Boot trifft. `zen update` zeigt die Gründe und die
neuen Commits (mit `%G?`) und fragt «Genau diesen Stand (…) installieren?». Das «ja» geht mit der gezeigten ID in einen
zweiten Wunsch und gilt nur für genau diese Commit-ID (dev) bzw. dieses Tag-Objekt; ein neuerer Stand braucht ein
neues «ja». Ohne Terminal gibt es keine Zustimmung.

Ist alles erfüllt, stellt das Prüfen das Ziel bereit, ohne Netz und jedes Mal neu:
`/var/lib/zenos/kanal/bereit/<commit>` ist ein eigenes Repo ohne Hooks mit den Objekten aus dem Prüf-Repo, ausgecheckt
(dev auf dem Branch dev, sonst losgelöst), origin wie in `/opt/zenos`. Tags nur geprüfte: der Ziel-Tag, auf dev die
gültig signierten (so kommt kein fremder Tag nach `/opt/zenos` und in `zen version`). Eine ältere Bereitstellung
desselben Commits (etwa von dev, ohne den Tag) wird ersetzt, nicht übernommen. Verlangt werden mindestens 1 GiB frei auf
`bereit/`, `/opt/zenos` und `/var`, HEAD gleich dem Commit und ein sauberer Baum (auch ohne unversionierte oder
ignorierte Dateien). Dann folgt `auftrag.json` (eine Stunde gültig).

#### Installieren

`zenos-kanal-installieren.service` (root, mit Netz, `KillMode=mixed`, `TimeoutStopSec=20min`) endet mit 75, solange
ein `install.sh` von Hand läuft (Vermerk). Sonst liest es `auftrag.json`,
prüft die Bereitstellung noch einmal (Ort, Besitz, Commit, sauber; signiert gegen den Anker von jetzt, dev-Bereich
neu, sonst nur mit «ja») und legt den Rückweg an: den laufenden Stand von `/opt/zenos`, aus `gut.json` oder frisch als
Bereitstellung (Commit ohne Änderungen von Hand). Dann:

1. Sperrdateien von git, die ein Abbruch in `/opt/zenos/.git` liegen liess (`index.lock`, `HEAD.lock`,
   `refs/…/*.lock`), entfernt es (unter der Kanal-Sperre, ohne Lauf von Hand: dann arbeitet dort kein anderes git).
   Wurde dpkg unterbrochen (`/var/lib/dpkg/updates`), läuft `dpkg --configure -a`, sobald kein anderer Paketvorgang
   die Sperren hält. Kam inzwischen ein Stopp (Ausschalten), beginnt kein `install.sh` mehr (`wartet`).
2. `laeuft.json` mit Ziel, Rückweg, Phase und Versuchszähler, `/run/zenos-kanal/uebernahme` und ein Block-Inhibitor
   für Ausschalten und Ruhezustand («zenOS wird aktualisiert»). Jede Oberfläche auf seat0 bekommt Bescheid
   (`zenos-ipc kanal uebernahme beginn`, als ihr Benutzer über `setpriv`): Bis zum Ende (`… ende`) lädt sie geänderte
   Dateien nicht einzeln nach.
3. `<bereit>/scripts/install.sh` als root mit `ZENOS_KANAL_LAUF=1`, ohne Terminal; 10-code übernimmt den Code Datei
   für Datei atomar nach `/opt/zenos`. Ein SIGTERM (Ausschalten durch root) wartet auf das Ende von install.sh.
   Scheitert `install.sh` nur an seiner Sperre (Exit 75, kein «== Beginn» im Ergebnis), zählt der Versuch nicht: keine
   Sperre der Version, kein Rückweg, Ergebnis `wartet` (Exit 75).
4. Gesundheit: Exit 0 und «== Ende … ok» im Ergebnis von `install.sh` (`/var/lib/zenos/kanal/install-ergebnis`,
   root-eigen; ältere Stände ohne dieses Ergebnis: im install.log), `/opt/zenos` auf dem Commit und sauber, `scripts/zen`,
   `install.sh`, `zenos-greeter` und `zenos-sitzung` nicht leer, `bash -n` über `scripts/zen`, `install.sh` und
   `scripts/{zen.d,lib,module,doctor.d}/*.sh`, `zen version` gibt «zenOS …» aus, `quickshell --version` läuft und
   greetd ist nicht ausgefallen (beides nur, wenn es vor `install.sh` noch ging: Ein schon ausgefallenes greetd soll
   das Update, das es repariert, nicht sperren), und der eben installierte zenos-kanal besteht `selbsttest`: Er liest
   den Anker und nimmt den installierten Tag an. Brachte der Stand einen anderen zenos-kanal (und kennt der
   `--probelauf`), macht er dazu einen Probelauf von `status`, `update`, `rollback`, `installieren` und `nachstart` in
   einem Wegwerf-Zustand unter `/var/lib/zenos/kanal/selbsttest` (holen fällt aus, prüfen läuft auf dem letzten
   Bundle, nichts wird bereitgestellt oder installiert). Ein Laufzeitfehler darin gilt als nicht gesund. Beim Rückweg
   prüft der Selbsttest nur den Anker: Der Schlüssel des alten Tags kann inzwischen widerrufen sein, und der alte
   zenos-kanal lief schon. Ein unveränderter zenos-kanal bekommt keinen Probelauf: Er hat eben dieses Update
   ausgeführt, und ein Fehlalarm sperrte sonst jedes weitere Update (im Ende-zu-Ende-Test so passiert, als der
   Probelauf selbst einen Fehler hatte).
5. Gesund: `gut.json`, `hoechste` (nur bei einem Update, nie bei einem Rollback), alte Bereitstellungen weg, Marker
   `angehalten` weg, daemon-reload der Benutzerinstanz einer Sitzung auf seat0; die übrigen Benutzerteile richtet
   `zen update` danach als Benutzer ein (sonst die nächste Anmeldung). Ergebnis `installiert`. Kam der Stand von der
   Automatik, entsteht statt `gut.json` erst `unbestaetigt.json`; die Bereitstellung des guten Stands bleibt (siehe
   «Bestätigung nach dem Start»). Nach `zen rollback` auf eine ältere Version entsteht `zurueckgestellt.json`.
6. Nicht gesund: Die Version kommt nach `gesperrt/` (Grund, Zeit), dann derselbe Lauf mit dem Rückweg. Ist er gesund,
   Ergebnis `zurueck` (Exit 4), sonst `kaputt` (Exit 5, keine weiteren Versuche; die Meldung nennt zuerst den Grund,
   ANLEITUNG F «Kaputt»). Ist das Ziel der laufende Stand selbst, gibt es keinen Rückweg und keine Sperre
   (`gescheitert`, Exit 4).

Ein harter Abbruch (Strom, `kill -9`) hinterlässt `laeuft.json`. `zenos-kanal-nachstart.service` (aktiviert, nur mit
`laeuft.json`, vor greetd, ohne Netz) vollendet beim Start die Übernahme des Codes mit `install.sh --nur-code` aus der
Bereitstellung; kennt deren install.sh die Option nicht (Stände vor diesem Kanal), bleibt das `zen update`. Ein
`zen update` setzt danach zuerst den unterbrochenen Lauf fort. Die Automatik setzt nur fort, was sie selbst begann
(`art: automatik` auf stabil oder vorschau) oder den Weg zurück auf den guten Stand (`art: bestaetigung`); eine
Installation von Hand (auch mit «ja», jede auf dev) setzt nur `zen update` fort. Nach zwei unterbrochenen Versuchen
sperrt schon nachstart die Version und nimmt den Code des Rückwegs. Ein `install.sh` von Hand erledigt einen
unterbrochenen Lauf.
Das Ergebnis jedes Laufs, der eine Installation betraf, steht in `letzte.json` (`ergebnis`, `grund`, `ziel`,
`rueckweg`, `versuche`, `hinweise`); `abgelehnt`, `wartet` und `nichts` überschreiben es nicht, sonst verschwände ein
`kaputt` aus `zen doctor`. `zen doctor` und `zen version` zeigen auch `gescheitert` und `fehler`; ein `angehalten`
löst ein älteres `kaputt` ab und umgekehrt.

Ein `install.sh` von Hand (aus einem Arbeits-Checkout oder aus `/opt/zenos`, nicht der Kanal, nicht das Image, nicht
nur die Benutzerteile) wartet über sudo auf die Kanal-Sperre und trägt darunter seine PID in `/run/zenos-sperre/hand`
ein. Solange dieser Prozess läuft (`/proc/<pid>`, `install.sh`), installiert der Kanal nichts (Exit 75); am Ende
entfernt install.sh den Vermerk. Den Vermerk kann nur root schreiben. Läufe als root (Kanal, `--nur-code`) nehmen die
Sperre `/run/zenos-sperre/install.lock`, Läufe als Benutzer weiter `/run/lock/zenos-install.lock`. Ein Lauf aus einem
Arbeits-Checkout hinterlässt `angehalten` (Commit, Zeit): Bis zum nächsten gelungenen `zen update` (oder «Jetzt
installieren») installiert die Automatik nichts, auch nicht auf vorschau. Wird ein `install.sh` von Hand genau
zwischen Prüfen und Installieren der Automatik fertig, lehnt das Installieren ihren Auftrag ab. `zen update`
installiert den Stand des Kanals dann neu, auch wenn der Commit gleich ist.

| Datei in `/var/lib/zenos/kanal` | Inhalt |
|---|---|
| `wunsch.json` | Wunsch von `zen update`, `zen rollback` oder aus den Einstellungen (`jetzt`, `zustimmen` mit `nur_signiert`; 0600, das Prüfen entfernt ihn) |
| `auftrag.json` | bereitgestelltes Ziel für das Installieren |
| `bereit/<commit>/` | Bereitstellungen: das Ziel und der gute Stand |
| `laeuft.json` | laufende oder unterbrochene Installation |
| `gut.json` | zuletzt gesund installierter Stand (nach einem automatischen Update erst nach der Bestätigung, dann mit `bestaetigt`) |
| `unbestaetigt.json` | automatisch installierter Stand, der auf den Neustart mit Login wartet (Start der Installation, gezählte Starts ohne Login, guter Stand; `zurueck`, wenn der Weg zurück begann) |
| `zurueckgestellt.json` | nach `zen rollback` verlassene Version (für die Anzeige; die Automatik bringt sie wegen `hoechste` ohnehin nicht wieder) |
| `automatik-bereit` | ein bereiter Stand auf stabil oder vorschau: Bedingung für `zenos-kanal-gelegenheit.service` |
| `automatik.json` | letzter Lauf der Automatik (Art, Ergebnis, Grund, Ziel) |
| `letzte.json` | Ergebnis der letzten Installation |
| `gesperrt/<version oder commit>` | gescheiterte Ziele mit Grund |
| `angehalten` | Stand von Hand aus einem Arbeits-Checkout: Die Automatik ruht bis `zen update` |

| Exit | `zen rollback`, Schritt 1 von `zen update` (den Exit von `zen update` mit beiden Schritten zeigt «Basis-Updates» unten) |
|---|---|
| 0 | installiert oder schon aktuell |
| 2 | Aufruf falsch |
| 3 | abgelehnt (etwa Anker fehlt auf stabil, Tag unbekannt, Bereitstellung verändert) |
| 4 | gescheitert, zurück auf dem Stand davor |
| 5 | kaputt: auch der Rückweg scheiterte |
| 10 | wartet: Zustimmung (auch «nein»), Platz, kein Kontakt |
| 75 | ein anderes `zen update`, eine Prüfung, ein `install.sh` von Hand oder eine andere Installation läuft (die Meldung nennt den Prozess) |

Am Gerät nach dem Einrichten (je ein Befehl): `zen kanal status` (Fingerabdrücke mit einer vertrauenswürdigen Quelle vergleichen),
`sudo zen kanal pruefen`. Solange der Anker leer ist, steht dort «Anker fehlt» und `v0.1.0-rc1` bis `rc3` als
«unsigniert»; `zen update` geht dann nur auf dev und nur mit «ja».

Übergang: Das erste `zen update` mit diesem Stand läuft noch über den alten Weg (`git checkout` in `/opt/zenos`,
`install.sh`) und bringt den Kanal; erst das nächste geht darüber. Hat das Gerät `v0.1.0-rc1` vor seiner Verschiebung
auf GitHub geholt, bricht dieser alte Weg mit «git fetch ist fehlgeschlagen» ab; dann einmal der Notweg aus
ANLEITUNG F (holt ohne Tags). Ein `zen rollback` auf einen Stand ohne Kanal (bis `v0.1.0-rc3`) bringt dessen alten
`zen update` zurück; der Kanal-Code und sein Timer bleiben liegen. Auf `dev` stört das nicht. Auf `stabil` und
`vorschau` (jedes Image ab `v0.1.0-rc4`) ist es eine Sackgasse: Der alte `zen update` kennt nur Branches und bricht
mit «Den Kanal «vorschau» gibt es auf origin nicht» ab, und `zen kanal` fehlt. Zurück geht es dann ohne `zen` mit
`sudo /usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal update` (oder `… rollback <tag>`), sonst mit der
nächsten Version über die Automatik. Ziel eines Rollbacks ist deshalb die letzte gültig signierte Version aus
`zen kanal status` («Gültig»), ab `v0.1.0-rc4` also mindestens diese.

Rückweg für diesen Schritt: `zen rollback` auf einen Stand davor; hat das neue Kanal-Programm selbst einen Fehler, die
vorige Fassung zurück (`zenos-kanal.vorher`, ANLEITUNG F); zuletzt der git-Notweg in `ANLEITUNG.md`, Abschnitt F
(signierter Tag gegen den Anker des Geräts geprüft, `dev` nur ohne Anker, ohne `zen` und ohne den Kanal).

Geprüft im Testcontainer mit `test/container/kanal-e2e.sh` (echtes systemd, eigenes origin über https mit
Wegwerf-CA, Wegwerf-Schlüssel): Übergang mit dem alten `zen update`; dev ohne Anker mit «nein» und «ja»; install.sh
zweimal als root aus der Bereitstellung (zweiter Lauf 0 Änderungen); signierter Tag auf vorschau ohne Frage; ein
Modul, das abbricht, und ein leeres `scripts/zen` (Rückweg, gesperrt); ein kleines tmpfs (wartet, Exit 10); ein
Rückfrage-Pfad; SIGKILL mitten im Lauf mit nachgestellter halber Übernahme, Neustart (nachstart vor greetd), Fortsetzen;
zwei Abbrüche (Rückweg schon beim Start); SIGTERM während install.sh (läuft zu Ende); Rollback signiert und unsigniert;
fehlendes zenos-kanal und Notweg (signierter Tag gegen den Anker); Sperren nur für root (ein Benutzer hält die alten
Sperren in `/run/lock`, `zen update` läuft trotzdem; ein `install.sh` von Hand hält den Kanal an); eine
zurückgebliebene `index.lock`.

#### In der Oberfläche (Einstellungen › System › Updates)

`shell/dienste/Kanal.qml` liest ohne Rechte `stand.json`, `letzte.json`, `/etc/xdg/zenos/kanal-zeitpunkt` und
`/run/zenos-kanal/uebernahme` (Logik in `kanal.js`, getestet mit `test/einheiten/kanal.test.mjs`). Die Seite zeigt den
Zustand mit Erklärung, Kanal, installierte und bereite Version, letzte Prüfung, letzten Kontakt mit origin und den Anker
mit Serie und den ersten 8 Zeichen der Fingerabdrücke (wie Zeno sie beim Setzen aus 1Password abtippt). Wurde seit der
letzten Prüfung installiert, sagt sie das, statt alte Angaben zu zeigen. Die Lage der Installation zählt vor dem
Zustand der Prüfung: «Update läuft» (mit Symbol, solange die Übernahme läuft), «Update kaputt» und «Update
unterbrochen» (Warnfarbe, mit dem Weg, bis eine spätere Installation es ablöst), sonst eine Zeile «Letztes Update»
bei gescheitert, zurück oder abgebrochen und «Von Hand» bei einem angehaltenen Stand. Die Zeile «Bereit» sagt, wann das
Update kommt, abgestimmt auf den Zeitpunkt («kommt bei der nächsten Sperre», «frühestens morgen, 10:54, danach
zwischen 02:00 und 05:00», «nur über «Jetzt installieren» oder zen update»). Nach `zen rollback` heisst der Titel
«Zurückgestellt: v0.1.0-rc4 läuft, v0.1.0-rc5 vorhanden».

| Knopf | Helfer (pkexec) | was passiert |
|---|---|---|
| «Jetzt prüfen» | `zenos-kanal-bedienen pruefen` (ohne Passwort) | holen und prüfen wie `sudo zen kanal pruefen`; installiert nichts |
| «Jetzt installieren» (nur bei `bereit`, auf dev bei einem neuen, ganz signierten Stand) | `… installieren ZIEL` (ohne Passwort) | `zenos-kanal-jetzt@ZIEL.service`: `zenos-kanal jetzt ZIEL`, wie `zen update` ohne Terminal, ohne Frage und ohne neues Holen, nur für den angezeigten, schon geprüften Stand (ZIEL: sein Tag-Objekt, auf dev der Commit). Nennt die Prüfung ein anderes Ziel oder bräuchte es ein «ja», bleibt es liegen (Exit 10) |
| «Zustimmen …» (nur bei `zustimmung` auf stabil und vorschau) | `… zustimmen OBJEKT` (Passwort, jedes Mal) | `zenos-kanal-zustimmen@OBJEKT.service`: `zenos-kanal zustimmen OBJEKT`, ohne neues Holen, das «ja» nur für dieses Tag-Objekt und nur für gültig signierte Ziele (`nur_signiert` im Wunsch). Nennt die Prüfung ein anderes Objekt: nichts (Exit 10) |
| Segmente «Bei Sperre · Zeitfenster · Jederzeit · Von Hand», beim Zeitfenster von–bis | `… zeitpunkt …` (ohne Passwort) | `zenos-kanal zeitpunkt` schreibt `/etc/xdg/zenos/kanal-zeitpunkt` (root, 0644, atomar, mit `seit` und `ueber`: pkexec oder sudo mit uid); gilt für das ganze Gerät, weil root-Dienste ihn lesen. Eine ungültige Datei (Hinweis «Datei ungültig» in der Warnfarbe) ersetzt auch die Wahl «Bei Sperre» |

Die Units laufen unabhängig von der Oberfläche: Lädt sie neu (etwa weil das Update QML bringt), endet nur der Helfer.
Den Exit liest der Helfer aus `ExecMainStatus` (ohne `SuccessExitStatus`: eine erfolgreich beendete statische Unit
räumt systemd weg, und es gälte 0) und setzt den Zustand «failed» danach zurück; «wartet» oder «abgelehnt» machen das
System so nicht «degraded». Danach prüft `jetzt` wie `zen update` neu, die Seite zeigt den neuen Stand.

Übernahme in einer offenen Sitzung («Jetzt installieren», «Jederzeit», «Zeitfenster»): Auf das IPC von zenos-kanal
schaltet `Kanal.qml` das Nachladen von Quickshell aus (`watchFiles`), solange die Übernahme läuft; ohne IPC (etwa nach
einem Neustart der Oberfläche mittendrin) genügt `/run/zenos-kanal/uebernahme`. Danach startet es als Benutzer
`systemd-run --user … install.sh --nur-benutzer` (ausserhalb der Oberfläche): Das richtet die Benutzerteile ein und
startet die Oberfläche neu, wenn sich QML geändert hat. Ist gesperrt, folgt das nach dem Entsperren; die Sperre lädt
währenddessen nicht selbst neu. Der Login-Bildschirm zeigt während der Übernahme eine ruhige Zeile «zenOS wird
aktualisiert. Mit der Anmeldung bitte warten, bis das fertig ist.»

Mitteilungen (Absender zenOS, jede nur einmal je Zustand, gemerkt in `~/.local/state/zenos/kanal-meldungen.json`):

| Anlass | Dringlichkeit | Wann wieder |
|---|---|---|
| installiert (`letzte.json`, höchstens 24 h alt) | still (low) | bei der nächsten Installation |
| zurück auf dem Stand davor, gescheitert, abgebrochen (auch älter, etwa nach einem Wochenende) | normal | ebenso |
| kaputt (auch der Rückweg scheiterte; auch älter) | dringend | ebenso |
| blockiert (etwa ALARM) | dringend | wenn der Zustand sicher vorbei war (ein anderer Zustand der Prüfung, nicht nur «kein Kontakt» oder «fehler») oder der Grund ein anderer ist |
| Anker fehlt | normal | ebenso |
| abgelehnt: ein Tag im Kanal über allem, was schon gilt, oder ein auf origin verschobener Tag (stabil und vorschau, mit Anker) | normal | je Tag-Name einmal |
| wartet auf Zustimmung | normal | je Tag-Objekt einmal |
| 14 Tage ohne Kontakt zu origin («Seit N Tagen kein Kontakt zu origin»; geprüft wird weiter, nur der alte Stand) | normal | je Kontaktzeit einmal |
| Update bereit, nur beim Zeitpunkt «Von Hand» | normal | je Tag-Objekt einmal |
| Zeitpunkt geändert, nicht aus den Einstellungen (etwa `sudo zen kanal zeitpunkt` oder pkexec aus einer anderen Anmeldung desselben Benutzers), mit dem Weg aus der Datei | normal | je Änderung einmal |

Im System-Menü steht bei Neustart und Ausschalten «Update läuft», solange `/run/zenos-kanal/uebernahme` oder
`/run/zenos-basis/uebernahme` besteht (install.sh aus dem Kanal bzw. ein Basis-Update mit Block-Inhibitor; systemctl
lehnte dann ab). Ein Klick sagt das als Hinweis, statt still nichts zu tun. Der Login-Bildschirm zeigt dann «zenOS wird
aktualisiert», der Sperrbildschirm nichts davon.

#### Automatik

Entscheide Zeno (Oktober 2026): ab Werk an, Zeitpunkt am Gerät einstellbar (Standard «bei Sperre»), Wartezeit stabil
24 h und vorschau keine, dev nie automatisch, Bestätigung nach dem Neustart. Drei Timer (Modul `14-kanal`):

| Timer | Wann | Unit | Was |
|---|---|---|---|
| `zenos-kanal.timer` | 10–20 Min. nach dem Start, danach alle 6 h (00, 06, 12, 18 Uhr plus bis zu 10 Min. Zufall), `Persistent` holt einen verpassten Lauf gleich beim Start nach (am Login-Bildschirm installiert er trotzdem erst, wenn der seit 5 Min. wartet) | `zenos-kanal-automatik.service` (`zenos-kanal automatik lauf`) | bis 2 Min. auf eine synchronisierte Uhr warten, holen, prüfen, installieren, wenn alles passt |
| `zenos-kanal-gelegenheit.timer` | alle 15 Min. | `zenos-kanal-gelegenheit.service` (`… automatik gelegenheit`), startet nur mit `automatik-bereit` oder `laeuft.json` | dasselbe ohne Holen: So trifft die Automatik die Sperre oder das Zeitfenster, auch wenn der 6-Stunden-Lauf daneben lag |
| `zenos-kanal-bestaetigen.timer` | 2 Min. nach jedem Start (install.sh aktiviert ihn nur; im laufenden Betrieb gestartet, feuerte er sofort) | `zenos-kanal-bestaetigen.service` (`zenos-kanal bestaetigen`), startet nur mit `unbestaetigt.json` | Bestätigung nach dem Start, siehe unten |

Automatisch installiert wird nur, wenn alles zutrifft:

- Kanal `stabil` oder `vorschau`, nie `dev` (dort holt und prüft die Automatik nur, für Status und Oberfläche).
- Ein Stand, den die Prüfung `bereit` nennt: gültig signiert, über `hoechste`, nicht gesperrt, nicht zurückgestellt,
  ohne Rückfrage-Pfade. Trifft er Firewall, Netz oder Boot, bleibt er `zustimmung`; die Oberfläche meldet
  «Update wartet auf deine Zustimmung» (mit Passwort in den Einstellungen oder `zen update`).
- Die Wartezeit ist um (`frei`): stabil 24 h ab dem ersten Sehen, vorschau sofort.
- Der Zeitpunkt passt, einmal vor dem Prüfen und noch einmal unmittelbar vor dem Installieren, dann mit dem Zeitpunkt
  aus der Datei von jetzt (inzwischen entsperrt, das Fenster vorbei oder auf «von Hand» gestellt: Der Auftrag wird
  verworfen).
- Am Netzteil oder mit mindestens 50 % Akku (Statusdatei `/run/zenos/geraet.json` von `zenos-argon`, höchstens 5 Min.
  alt, sonst `/sys/class/power_supply`; unbekannt gilt wie in der Oberfläche als Netzteil). Sonst hiesse ein leerer
  Akku mittendrin (zenos-argon schaltet bei 3 % aus) einen halben Stand. Das gilt auch fürs Fortsetzen.
- Der Stand ist nicht «angehalten» (install.sh von Hand aus einem Arbeitsstand, bis zum nächsten `zen update`).
- Kein automatisch installierter Stand aus einem früheren Start wartet auf die Bestätigung (sonst begänne mit jeder
  neuen Version die Zählung der Starts ohne Login von vorn).
- Kein `install.sh` von Hand läuft, keine andere Bedienung (Sperre `bedienung.lock` wie `zen update`).

| Zeitpunkt (`/etc/xdg/zenos/kanal-zeitpunkt`) | Wann die Automatik installiert |
|---|---|
| `sperre` (Standard, auch ohne Datei) | Jede Sitzung von Menschen auf `seat0` (logind, Klasse `user…`, nicht beim Schliessen) ist seit mindestens 5 Minuten gesperrt: Der Marker der Oberfläche `/run/user/<uid>/zenos/gesperrt` (vor der Sperre angelegt, erst nach dem Entsperren gelöscht, Besitzer der Benutzer, kein Verweis) ist so alt, und die Oberfläche bestätigt es selbst: `zenos-ipc sperre status` als dieser Benutzer (`setpriv`, Argumentliste) antwortet `gesperrt` (ext-session-lock, vom Compositor bestätigt). Antwortet sie nicht, gilt die Sitzung als offen. Liegt der Marker vor dem ersten Abgleich der Uhr (`/run/systemd/timesync/synchronized`), zählt der Abgleich als Beginn. Eine Textkonsole auf `seat0` (logind `Type=tty`, Ctrl+Alt+F3) ist nie gesperrt. Ohne Sitzung auf `seat0` erst, wenn der Login-Bildschirm seit 5 Minuten läuft (Alter seines Prozesses, gemessen an der Zeit seit dem Start; ohne greetd 5 Min. nach dem Start). Ist jemand per SSH angemeldet (logind `Remote=yes`), ist es nie ruhig: Dann arbeitet jemand. Ein tmux-Server ohne Verbindung zählt bewusst nicht (er läuft oft tagelang); was von Hand installiert wurde, schützt «angehalten». Fehlt in der Liste von logind eine Angabe, gilt die Lage als nicht prüfbar. |
| `fenster` (von, bis) | nur zwischen von und bis (Ortszeit, `bis` gehört nicht dazu, über Mitternacht erlaubt, etwa 22:00–04:00) und nur mit synchronisierter Uhr, auch während jemand arbeitet. Das Gerät muss dann laufen: Im Akkubetrieb schaltet zenOS am Login-Bildschirm nach 30 Min. ohne Eingabe aus und, je nach Einstellung, nach langer Sperre (docs/module/energie.md) |
| `jederzeit` | sobald ein Stand bereit ist, auch während jemand arbeitet (die Oberfläche lädt dabei neu, wenn sich QML geändert hat) |
| `hand` | nie. Die Prüfung schreibt `stand.json`, die Oberfläche meldet «Update bereit» einmal je Tag-Objekt; installiert wird über «Jetzt installieren» oder `zen update` |

Uhr: `time-sync.target` wartet nicht (`systemd-time-wait-sync` ist aus), und der Pi hat keine Uhr mit Batterie. Ob die
Uhr synchronisiert ist, sagt `timedatectl` (`NTPSynchronized`, aus dem Kern, auch mit chrony); das Prüfen fragt es
über D-Bus. «Erstmals gesehen» trägt das Prüfen nur mit synchronisierter Uhr ins Hauptbuch ein, mit der Start-ID und der
Zeit seit dem Start (`erstmals_start`); bis dahin heisst es «automatisch erst mit synchronisierter Uhr». Für die 24 h
zählt im selben Start die Zeit seit dem Start (ein Sprung der Uhr durch NTP verkürzt nichts), nach einem Neustart die
Uhr, und die nur, wenn sie synchronisiert ist. Gegen ein NTP, das dauerhaft lügt, hilft das nicht (Restrisiko, NTS).
Damit `zenos-kanal-pruefen.service` die Start-ID lesen kann, hat es kein `ProcSubset=pid` mehr (die übrige Sandbox
bleibt).

Ein Lauf (`automatik lauf` bzw. `gelegenheit`, root, in einer Sandbox ohne Netz: `/run/user` und `/home` nur lesend,
setuid bleibt für den Blick auf die Sperre):

1. Notschalter gesetzt: nichts. Sperre der Bedienung belegt oder `install.sh` von Hand: Exit 75, beim nächsten Mal.
2. Nur `lauf`: bis 2 Min. auf die Uhr warten, dann `zenos-kanal-holen.service` (scheitert es, gilt der letzte Stand).
3. Ist eine Installation unterbrochen (`laeuft.json`), setzt die Automatik sie fort, wenn sie selbst sie begann
   (`art: automatik` auf stabil oder vorschau) oder es der Weg zurück auf den guten Stand ist, und wenn Zeitpunkt und
   Akku passen; ihr Ziel war schon geprüft und bereitgestellt. Eine Installation von Hand (zen update, ein Knopf, ein
   «ja», alles auf dev) setzt nur `zen update` fort: Die Automatik meldet «… von Hand wurde unterbrochen; fortsetzen:
   zen update».
4. Kanal dev, ein angehaltener Stand, ein unbestätigter Stand aus einem früheren Start, der Zeitpunkt oder der Akku
   passt nicht: nichts installieren; nach dem Holen nur prüfen (ohne Wunsch), damit `stand.json` und die Oberfläche
   den neuen Stand kennen. Der Grund steht in `automatik.json`.
5. Sonst `wunsch.json` mit `art: automatik` (nie mit «ja») und prüfen: Das Prüfen stellt genau den Stand bereit, den
   es eben `bereit` nennt, nach der Wartezeit, ohne Grund für ein «ja» (Rückschritt, gesperrt, Firewall, Netz, Boot),
   nie auf dev; `auftrag.json` mit `von_hand: false` (install.sh läuft mit `--ruhig`).
6. Zeitpunkt (neu aus der Datei) und Akku noch einmal, dann `zenos-kanal-installieren.service` (Gesundheit, Rückweg
   wie bei `zen update`), danach prüfen ohne Wunsch.

`automatik.json` hält den letzten Lauf fest (`zen kanal automatik`, `zen kanal status`). Holen und Prüfen enden bei
«Anker fehlt» oder «wartet» mit Exit ungleich 0; die Automatik setzt ihren Zustand «failed» danach zurück (es sind
Zustände des Kanals, keine Ausfälle des Systems). Die Automatik-Units nehmen Exit 10 (wartet) und 75 (belegt) als Erfolg;
4 (zurück) und 5 (kaputt) bleiben «failed» und stehen in `zen doctor`.

**Nach `zen rollback`:** Die verlassene Version kommt automatisch nicht wieder, weil `hoechste` nicht sinkt und die
Prüfung nur Versionen darüber `bereit` nennt. `zurueckgestellt.json` merkt sie sich für die Anzeige («Zurückgestellt:
v0.1.0-rc4 läuft, v0.1.0-rc5 vorhanden»; «… ist zurückgestellt …; zurück dorthin: zen update») und hält sie nur dann
fern, wenn `hoechste` verloren ging. Aufgehoben wird das durch ein gelungenes Update von Hand (`zen update`, «Jetzt
installieren») oder eine neuere Version, die die Automatik installiert.

**Bestätigung nach dem Start:** Ein automatisch installierter Stand gilt erst als gut, wenn nach einem Neustart der
Login kommt: greetd und PAM brechen manchmal erst dann. Bis dahin steht er in `unbestaetigt.json` (mit der Kennung des
Starts der Installation: Start-ID des Kerns und Startzeit von PID 1), `gut.json` bleibt beim guten Stand, und dessen
Bereitstellung bleibt liegen. 2 Minuten nach jedem Start schaut `zenos-kanal-bestaetigen.service` bis zu 3 Minuten:
greetd aktiv und ein Login-Bildschirm (ein Prozess `quickshell` von `_greetd`, seit mindestens 20 s; ein Greeter, den
greetd immer wieder neu startet, zählt so nicht) oder eine grafische Sitzung auf `seat0` (logind `Type` wayland oder
x11). Eine Anmeldung auf der Textkonsole zählt nicht: Genau dorthin weicht man aus, wenn der grafische Login kaputt
ist. War greetd bei der Installation nicht aktiviert, gibt es keinen Login zu prüfen. Läuft beim Start gerade die
Automatik oder ein `zen update` (Sperre der Bedienung), wartet die Bestätigung bis 30 Minuten darauf, statt bis zum
nächsten Start zu verfallen; die Automatik installiert solange nichts Neues.

- Im selben Start wie die Installation: nichts.
- Login da: `gut.json` (mit `bestaetigt`), `unbestaetigt.json` weg.
- Kein Login: Dieser Start zählt (`fehlstarts`, je Start einmal; Exit 10). Beim zweiten: Die Version kommt nach
  `gesperrt/`, der gute Stand wird über `zenos-kanal-installieren.service` wieder installiert (Auftrag `art:
  bestaetigung`, ohne neue Signaturprüfung wie ein Rückweg, und ohne Rückweg auf den Stand ohne Login), `letzte.json`
  sagt `zurueck`, und ist niemand angemeldet, startet greetd neu. `unbestaetigt.json` geht erst weg, wenn das gelingt.
  Scheitert der Weg zurück (etwa install.sh ohne Netz), heisst es `kaputt` (dringende Mitteilung), der gute Stand wird
  nicht gesperrt, und der nächste Start versucht es noch einmal; kommt dann doch der Login, gilt der Stand als gut, und
  seine Sperre fällt weg. Gibt es keinen guten Stand (das allererste Update über den Kanal kam automatisch), heisst es
  `kaputt` (ANLEITUNG F).

Ein Update von Hand gilt sofort als gut (der Mensch sitzt davor); es ersetzt einen unbestätigten Stand. Eine Prüfung
nennt einen unbestätigten Stand «schon installiert», `zen doctor` zeigt ihn als Hinweis.

**Notschalter:** `sudo zen kanal automatik aus` legt `/etc/xdg/zenos/kanal-automatik-aus` an und schaltet
`zenos-kanal.timer` und `zenos-kanal-gelegenheit.timer` aus (`systemctl disable --now`); `install.sh` lässt sie dann
aus, und die Units starten nicht (`ConditionPathExists=!…`). `… an` macht beides rückgängig. Er schaltet nur die
Automatik, nie die Prüfung: Signatur, Anker und Rückfrage gelten bei `zen update` weiter. Die Bestätigung nach dem
Start bleibt an.

**Ausschalten während eines Updates:** Während `install.sh` hält der Kanal einen Block-Hemmer (Ausschalten und
Ruhezustand). Davor und danach (Bereitstellen, Gesundheitsprüfung, Rückweg) nicht, und die Sperren in
`/run/zenos-sperre` sieht kein Benutzer. `zenos-energie` (Ausschalten nach langer Sperre, am Login-Bildschirm) fragt
deshalb zusätzlich systemd: Solange eine Unit `zenos-kanal-*` oder `zenos-basis-*` (Basis-Updates) läuft, schaltet es
nicht aus («Update läuft (…)»).

Geprüft: Einheitentests in `test/einheiten/kanal-automatik.test.py` (Zeitpunkt, Fenster über Mitternacht, Sitzungen
und Sperre mit Attrappen für loginctl, setpriv und zenos-ipc, Uhr und Sprung der Uhr, Wartezeit nach einem Neustart,
lauf und gelegenheit, Notschalter, dev, Zustimmung, unterbrochene Installation, Rückstellung, Bestätigung und der Weg
zurück, auch ohne guten Stand; dazu die Befunde der Prüfung von Teil B: Stand von Hand, auch zwischen Prüfen und
Installieren, Zeitpunkt «von Hand» mitten im Lauf, Login-Bildschirm erst nach 5 Min., SSH-Sitzung, Textkonsole neben
gesperrter Sitzung und als «Login», fehlende Angaben von logind, Sperre vor dem Abgleich der Uhr, Akku aus der
Statusdatei und aus `/sys`, auch fürs Fortsetzen, unterbrochene Installation von Hand auf dev und vorschau,
Bestätigung wartet auf die Sperre der Bedienung, keine neue Version vor der Bestätigung, Weg zurück scheitert und
gelingt beim nächsten Start bzw. der Login kommt doch, Meldung der Übernahme an die Oberfläche) und
`test/einheiten/energie.test.py` (Kanal-Units als Wächter). Die Oberfläche: `test/einheiten/kanal.test.mjs` (Lage
mit «kaputt» nach der Prüfung, «Bereit» je Zeitpunkt, Sätze, Mitteilungen auch nach 24 h, Zeitpunkt geändert) und im
Container das IPC `kanal uebernahme beginn|ende` sowie Bildschirmfotos der Seite in hell und dunkel. Ende-zu-Ende im
Container (`test/container/kanal-e2e.sh automatik`, `nach-automatik`, `nach-automatik-2`, `nach-automatik-3`, mit
echtem systemd): Timer und Notschalter auch über `install.sh`, dev nie, «von Hand» nur bereit, Zeitfenster über die
Gelegenheit ohne Holen, `zenos-energie` als Benutzer sagt während der Installation «Update läuft», «bei Sperre» mit
einer über PAM gestellten Sitzung auf seat0 und der echten Sperre der Oberfläche (eben gesperrt: noch nicht; seit
10 Min.: installiert, aus der Sandbox der Unit heraus gefragt), Rückstellung nach `zen rollback`, Bestätigung durch den
echten Timer nach einem Neustart des Containers, zwei Starts ohne Login mit Rückweg und Neustart von greetd. greetd und
der Login-Bildschirm sind im Container nachgestellt (kein VT).

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
- `git verify-tag` nimmt auch einen Tag mit zwei SSH-Signaturen an. `zenos-kanal` verlangt deshalb genau eine.
- `%G?` ist bei einer gültigen Signatur eines Schlüssels, der nicht im Anker steht, `U`, nicht `G`; bei einem
  widerrufenen `B`. Für dev zählt nur `G`.
- Ein Bundle lässt sich nur mit `protocol.file.allow=always` holen (sonst «transport 'file' not allowed»). Ein
  explizit verlangter Branch, den es auf origin nicht gibt, lässt `git fetch` scheitern; der Holer fragt deshalb
  vorher mit `git ls-remote`, ob es `dev` gibt.
- Eine SSH-Signatur lässt sich ohne Schlüssel neu umbrechen (64 statt 70 Zeichen je Zeile) oder mit einer Leerzeile am
  Ende versehen: `git mktag` legt das Objekt an, `git verify-tag` nimmt es an, die Objekt-ID ist neu. Das Hauptbuch
  vergleicht deshalb den Commit. Eine Pflicht zur Zeilenlänge 70 gibt es nicht: Wie op-ssh-sign von 1Password
  umbricht, ist hier nicht prüfbar, und mit dem Commit-Vergleich spielt die Hülle keine Rolle mehr.
- Die Tests `test/einheiten/kanal.test.py` spielen Holen und Prüfen mit Wegwerf-Schlüsseln durch: unsigniert,
  leichter Tag, fremder Schlüssel, Wurzel statt Release, Tag-Name falsch, Tag auf einen Baum, zwei Signaturen,
  OpenPGP mit importiertem Schlüssel (git nimmt ihn mit gpg an, der Kanal nie), widerrufen, verschoben (gültig:
  ALARM; ungültig: abgelehnt), gelöscht, Downgrade, `hoechste` abgeleitet und nicht ableitbar, `vertrauen/NNNN`
  (Wechsel, mit dem Release-Schlüssel, falsche oder kleinere Serie, andere Wurzel, Widerruf bleibt), leerer Anker
  wie im Repo, fehlende Widerrufsdatei, Rechte, Verweise, fremde git-config und Hooks, dev mit unsigniertem
  Zwischencommit, Sperre, Wartezeit. Dazu die Befunde der Prüfung: neu umbrochene Signatur (kein Alarm), 1001 leichte
  Tags und Kopien echter Signaturen (nicht blockiert, begrenzt), Abbruch nach jeder Datei des Ankers, Spiegel des
  Holers (nur dev und v*, wächst nicht), Sperren nur für root, Uhrsprung, Anker von Hand ohne Abtippen.
  `test/einheiten/kanal-installieren.test.py` spielt dazu durch: Lauf von Hand hält den Kanal an, Sperre von
  install.sh belegt, greetd schon vorher ausgefallen, zurückgebliebene git-Sperren, Stand nach der Installation,
  Probelauf im Selbsttest, Syntaxfehler in zen.d, alte Bereitstellung ohne Tag, nur geprüfte Tags, Rückweg auf einen
  widerrufenen Schlüssel, «gescheitert» bleibt sichtbar, Stopp vor install.sh, belegte Prüfung, kein Netz.
- Vor dem Image-Bau: `test/einheiten/image-signatur.test.py` spielt `image/tag-pruefen.sh` (auch auf dem Mac) und
  `image/bauen.sh --nur-pruefen` (unter Linux) mit Wegwerf-Schlüsseln durch, die Fälle stehen in `image/README.md`,
  «Signatur des Tags». Die Klasse `Image` in `test/einheiten/kanal.test.py` prüft `zenos-kanal image`: Zustand ab
  Werk für rc auf vorschau und final auf stabil, danach «aktuell» beim ersten Lauf, rc nicht auf stabil, nie auf dev,
  unsigniert, fremd und mit der Wurzel signiert, nicht auf dem Tag, nicht sauber, ohne Anker, nur in einem neuen
  Zustand, später verschobener Tag ist ALARM, kein Downgrade unter den Stand ab Werk.
- Ubuntu-Basis (Oktober 2026): Die Klassen `UbuntuBasis` in `test/einheiten/kanal.test.py` und
  `kanal-installieren.test.py` spielen durch: höhere Version für 28.04 neben einer für 26.04 (Ziel ist die für 26.04),
  nur 28.04 (aktuell, nichts für die Automatik), späteres Update für 26.04 nach einer Hauptversion für 28.04,
  ungültige `system/basis` (zwei Zeilen, Text, leer, nur Kommentar, zu gross, Ordner), Gerät ohne `VERSION_ID`, Gerät
  auf 28.04, Kennung zenOS mit `os-release.ubuntu`, dev für 28.04 (kein «Jetzt installieren», auch mit «ja» nicht),
  `zen rollback` signiert und unsigniert mit «ja», Basis wechselt zwischen Prüfen und Installieren, Automatik;
  `Image` dazu einen Tag für 28.04. `BasisImRepo` hält `system/basis` gleich der Regel in `scripts/lib/gemeinsam.sh`.
  Im Container (`kanal-e2e.sh`, Schritte einrichten, dev, signiert, basis, danach kaputt): ein gültig signierter
  `v0.9.0-rc1` für 28.04 bleibt liegen (`zen update` Exit 0, Hinweis, `basis.fremd`), `zen rollback v0.9.0-rc1` mit
  «ja» endet mit Exit 3 ohne Frage, der Drop-in liegt root-eigen, `zen doctor` meldet `Prompt=never`.

### Grenzen

- Eine Signatur bestätigt die Herkunft, nicht den Inhalt. Was signiert ist, läuft später als root auf allen Geräten.
  Dagegen helfen nur die Durchsicht (das Skript zeigt sensible Pfade gesondert), ein eigener Terminal-Tab und danach
  1Password sperren. Auch das Skript selbst ist Teil des Repos und erscheint deshalb unter «Vertrauen und Updates».
- 1Password gibt einen Schlüssel laut Doku pro Anwendung bzw. Terminal-Sitzung frei, bis es sperrt (nicht selbst
  getestet). Ein Programm im selben Terminal könnte danach mitsignieren.
- Die Rückfrage-Pfade fangen indirekte Änderungen nicht, etwa neue Pakete, die initramfs auslösen.
- Ein Rückweg ist kein Schnappschuss: Pakete, Units und Dateien, die ein gescheiterter Stand neu brachte, bleiben
  liegen; zurück kommt der Code und was install.sh des alten Stands einrichtet.
- Ein Abbruch mitten in apt bleibt bis zum nächsten `zen update` halb (dpkg); nachstart vollendet nur den Code.
- Ein Update, das erst nach dem Neustart den Login bricht (greetd-Konfiguration, PAM), fällt der
  Gesundheitsprüfung nicht auf. Nur ein automatisch installierter Stand wartet deshalb auf die Bestätigung nach dem
  Start («Automatik»); ein `zen update` von Hand gilt sofort als gut.
- Das Image vertraut der CI: Workflow, `bauen.sh` und `tag-pruefen.sh` (mit dem festen Anker) kommen aus dem Stand des
  Tags. Wer auf GitHub einen eigenen Tag mit eigenem Workflow pushen kann, kann auch die Prüfung darin ändern; dagegen
  helfen nur die Regeln auf GitHub (ANLEITUNG G). Die Geräte prüfen jeden Tag ohnehin selbst; ein frisch geflashtes
  Gerät übernimmt aber den Anker des Images. Eine eigene Signatur der Image-Dateien (`SHA256SUMS.sig`, mit dem
  Release-Schlüssel auf dem Mac, vor dem Flashen geprüft) gibt es noch nicht; Dritte prüfen die Herkunft über die
  Attestation von GitHub.
- Ein Prozess, der als root läuft, kann den Kanal weiterhin anhalten (Sperre halten). Gegen root schützt nichts.

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
- Der Kanal im Image folgt dem Tag: `vX.Y.Z` → `stabil`, `vX.Y.Z-rcN` → `vorschau` (`--kanal` von `bauen.sh`, nur
  passend zum Tag). Kanäle: `stabil` (nur `vX.Y.Z`), `vorschau` (auch `vX.Y.Z-rcN`), `dev` (nur von Hand, nie im
  Image ausser im Testbau); ein alter Wert `main` gilt als `stabil`.
- Der Anker `/etc/zenos/vertrauen` kommt aus `system/vertrauen` des Tags, `/var/lib/zenos/kanal` hat den Zustand ab
  Werk (`gut.json`, `hoechste`, `gesehen.json`).

## Basis-Updates: Pakete von Ubuntu (zenos-basis)

Paket-Updates innerhalb von Ubuntu 26.04 LTS bringt `scripts/bin/zenos-basis` (Python, nur Standardbibliothek,
`python3 -I`), root-eigene Kopie unter `/usr/local/libexec/zenos/zenos-basis` (Modul `71-basis`). Es installiert, was
`apt full-upgrade` brächte: Fehlerkorrekturen aus `-updates`, Sicherheitsupdates, Pakete der Herstellerquellen (Chrome,
VS Code, 1Password-CLI). Sicherheitsupdates spielt unattended-upgrades weiter täglich selbst ein; daran ändert sich
nichts. Die Arbeit machen zwei statische Units als root mit Netz; sie starten Schritt 2 von `zen update`, die Knöpfe
in Einstellungen › System › Updates und die Automatik.

| Befehl | Wer | Was |
|---|---|---|
| `zenos-basis pruefen` | root, `zenos-basis-pruefen.service` | `apt-get update`, dann `apt-get -s full-upgrade` auswerten; schreibt `stand.json`. Installiert nichts |
| `zenos-basis installieren` | root, `zenos-basis-installieren.service` | installiert die Liste aus `auftrag.json` (Hash, Zustimmung ja/nein, von wem; höchstens eine Stunde alt), mit `--liste HASH [--zustimmung]` ohne Auftrag (Tests, von Hand) |
| `zenos-basis status [--json\|--kurz\|--installation]` | alle | letzte Prüfung, letzte Installation, Neustart nötig, Automatik; `--kurz` für `zen doctor` und die Zeile `Pakete` von `zen version` |
| `zenos-basis update [--ja]` | root, im Terminal (`zen update`) | Schritt 2 von `zen update`, siehe unten |
| `zenos-basis jetzt HASH`, `zenos-basis zustimmen HASH` | root (`zenos-kanal-bedienen` über pkexec) | «Jetzt installieren» bzw. «Mit Passwort installieren» in den Einstellungen |
| `zenos-basis automatik [lauf\|gelegenheit]` | root (Timer); ohne Argument alle | Automatik, siehe unten; ohne Argument: an oder aus, letzter Lauf |

**Prüfen.** Unter der Sperre des Kanals (`/run/zenos-sperre/kanal.lock`, nicht blockierend, sonst Exit 75; ebenso,
solange ein `install.sh` von Hand läuft). Vorher wartet es höchstens 20 Minuten auf einen anderen Paketvorgang
(apt-daily, apt-daily-upgrade mit unattended-upgrades, die Sperren von apt und dpkg; danach Exit 75). Ausgewertet werden
die Zeilen `Inst` und `Remv` von `apt-get -s full-upgrade` (`LC_ALL=C`, ohne autoremove): je Paket Name, alt, neu,
Tasche und Herkunft. Daraus:

- **Sicherheit:** Pakete aus einer Tasche `…-security`.
- **Heikel** (Kernel, Firmware, Bootloader): `linux-raspi`, `linux-image-*`, `linux-modules-*`,
  `linux-headers-*-raspi`, `linux-generic*`, `linux-firmware*`, `flash-kernel`, `piboot-try`, `rpi-eeprom`, `u-boot*`,
  sicherheitshalber `grub*` und `shim*`. Nur mit Zustimmung.
- **Entfernungen:** nur mit Zustimmung. Ist ein geschütztes Paket dabei, gilt «gesperrt», auch mit Zustimmung
  (Exit 3): die feste Liste aus `scripts/lib/aufraeumen.sh` (`_aufraeumen_geschuetzt`, ein Einheitentest hält beide
  gleich), die zenOS-Pakete aus `scripts/pakete/*.txt` und alles, was als manuell installiert gilt.
- **Neustart voraussichtlich:** heikel oder `libc6`, `systemd`, `dbus`, `greetd`. Eine Schätzung; gewiss ist erst
  `/run/reboot-required` danach.
- **Liste:** SHA-256 über die sortierten Einträge, die ersten 40 Zeichen. Installiert wird genau dieser Stand.

Gehaltene Pakete (`apt-mark hold`), der Pin gegen snapd und gestaffelte Updates (Phasing) respektiert apt selbst; sie
stehen nicht in der Liste. Darum laufen beide Units ohne Sandbox mit eigenem Mount-Namensraum (`PrivateTmp`,
`ProtectSystem` …): apt hält das für ein chroot und lässt die Staffelung aus. Im Container geprüft: Mit `PrivateTmp`
zählte die Auswertung 7 Updates, `apt-get full-upgrade` danach 3, und jede Installation endete mit «Liste geändert».

**Installieren.** Dieselbe Sperre, dasselbe Warten. Nicht, solange eine Installation des Kanals unterbrochen ist
(`laeuft.json`) oder der Kanal «kaputt» meldet (Exit 10): `install.sh` aus `/opt/zenos` liefe sonst auf einem halb
übernommenen Stand. Der Hash des Auftrags muss der letzten Prüfung gleichen und einer Auswertung von jetzt (ohne neues
`apt-get update`); sonst Exit 3, und `stand.json` zeigt die neue Liste. Heikle Pakete und Entfernungen ohne Zustimmung:
Exit 10. Dann:

1. Ein unterbrochenes dpkg (`/var/lib/dpkg/updates`) repariert es mit `dpkg --configure -a`; bleibt es unterbrochen,
   Exit 1 ohne apt.
2. Ausgangslage für die Gesundheitsprüfung: `quickshell --version`, greetd ausgefallen, ausgefallene Units (ohne die
   von Kanal und Basis), Fehlerzahl von `zen doctor --kurz` als root.
3. Unter einem Block-Inhibitor für Ausschalten und Ruhezustand («Ubuntu-Basis wird aktualisiert») und mit
   `/run/zenos-basis/uebernahme`: Jede Oberfläche auf seat0 bekommt `zenos-ipc kanal uebernahme beginn|ende` wie beim
   Kanal (lädt währenddessen nicht nach, richtet danach die Benutzerteile ein; System-Menü und Login zeigen «Update
   läuft»).
4. `apt-get -q -y full-upgrade` mit `DEBIAN_FRONTEND=noninteractive`, `NEEDRESTART_MODE=l`, `NEEDRESTART_SUSPEND=1`,
   `--force-confdef`, `--force-confold`, ohne autoremove, `DPkg::Lock::Timeout=300`. Dienste starten wie bei Ubuntu
   neu, nur greetd nicht (ein Neustart beendete die Sitzung): Eine eigene `policy-rc.d` gibt für `greetd` 101 zurück,
   sonst 0; apt setzt sie per `DPkg::Pre-Invoke` vor jedem dpkg-Lauf ein und nimmt sie per `DPkg::Post-Invoke` weg.
   Eine fremde `policy-rc.d` bleibt (Hinweis); einen Rest von zenOS (zenos-basis oder install.sh) entfernen beide.
   Im Container geprüft: `invoke-rc.d: policy-rc.d denied execution of restart` für greetd, cron startete.
5. Nur nach gelungenem apt: `/opt/zenos/scripts/install.sh --ruhig` als root mit `ZENOS_KANAL_LAUF=1` (die Sperre
   hält zenos-basis schon) und eigenem Ergebnis `/var/lib/zenos/basis/install-ergebnis`. Es baut Quickshell neu, wenn
   sich Qt geändert hat, und zieht die Kennung nach.
6. Bringt das Update eine neue greetd-Version, trägt zenos-basis `greetd` in `/run/reboot-required(.pkgs)` ein.
7. Gesundheit: Es zählt nur, was schlechter ist als vorher: dpkg unterbrochen, `install.sh` nicht Exit 0 oder ohne
   «== Ende … ok», `quickshell --version` scheitert, greetd ausgefallen, neu ausgefallene Units, mehr Fehler in
   `zen doctor`. Ergebnis `installiert` (Exit 0), `kaputt` (Exit 5) oder `fehler` (apt scheiterte, Exit 1). Zurückgerollt
   wird nichts; `letzte.json` nennt, was kaputt ist, dazu das Journal (`journalctl -u zenos-basis-installieren`) und
   das Log. Danach wertet es `stand.json` neu aus (ohne Netz).

Ein Stopp (Ausschalten durch root) vor apt beginnt nichts mehr (Exit 10); während apt und `install.sh` laufen beide
zu Ende (`KillMode=mixed`, `TimeoutStopSec=20min`, SIGHUP ignoriert, ein SSH-Abbruch schadet nicht). Ein harter Abbruch
hinterlässt ein unterbrochenes dpkg; das nächste Basis-Update repariert es zuerst. zenos-energie schaltet nicht aus,
solange eine Unit `zenos-basis-*` läuft, zenos-argon nicht, solange `/run/zenos-basis` besteht.

| Datei | Inhalt |
|---|---|
| `/var/lib/zenos/basis/stand.json` | letzte Auswertung: `zeit`, `geprueft` (letztes gelungenes `apt-get update`), `ergebnis` (`aktuell`, `bereit`, `zustimmung`, `gesperrt`, `fehler`), `grund`, `liste`, `anzahl`, `sicherheit`, `heikel`, `entfernen`, `geschuetzt`, `neustart`, `neustart_wegen`, `pakete` (Name, Architektur, alt, neu, Tasche, Herkunft, Sicherheit, heikel) |
| `/var/lib/zenos/basis/letzte.json` | letzte Installation, nur wenn apt lief (eine Ablehnung überschreibt kein `kaputt`): `ergebnis`, `grund`, `liste`, `von`, `zustimmung`, `anzahl`, `geaendert`, `mehr` (was apt über die Liste hinaus änderte), `neustart`, `probleme`, `hinweise` |
| `/var/lib/zenos/basis/auftrag.json` | Auftrag für die Unit (root; das Installieren verbraucht ihn) |
| `/var/log/zenos/basis.log` | root, 0640: je Lauf «== Beginn», Paketstand vorher (dpkg-query), Exit von apt und install.sh, die Änderungen, Probleme, «== Ende». Nur zum Nachsehen, kein Rückweg; über 2 MiB bleiben die letzten 512 KiB |

| Exit | `zenos-basis` |
|---|---|
| 0 | geprüft; installiert und gesund; nichts zu tun |
| 1 | Fehler: `apt-get update` oder `full-upgrade` scheiterte, dpkg bleibt unterbrochen |
| 2 | Aufruf falsch (oder nicht root) |
| 3 | abgelehnt: gesperrt (geschütztes Paket), Liste veraltet, kein oder ungültiger Auftrag |
| 5 | kaputt: nach dem Update schlechter als vorher, nichts zurückgerollt |
| 10 | wartet: Zustimmung nötig, Kanal unterbrochen oder kaputt, Stopp vor apt |
| 75 | läuft schon: Sperre, `install.sh` von Hand, ein anderer Paketvorgang nach 20 Minuten |

Geprüft mit `test/einheiten/basis-updates.test.py` (Fixtures ohne und mit Kernel, Entfernungen, Sicherheit, geschützte
Pakete, Herstellerquelle; Attrappen für apt, dpkg und install.sh) und im Testcontainer über die echten Units:
prüfen (7 bzw. 3 Updates, siehe Staffelung), installieren ohne Zustimmung (3 Pakete, `install.sh` Exit 0, gesund,
danach «aktuell»), Inhibitor und Marker während des Laufs, `policy-rc.d` danach weg.

### `zen update`: zwei Schritte

`zen update` (scripts/zen.d/update.sh) bringt zuerst zenOS über den Kanal (Schritt 1, wie oben, unverändert; sein «ja»
bleibt an die gezeigte ID gebunden und gibt es nur getippt im Terminal), dann die Basis (Schritt 2,
`sudo …/zenos-basis update`). Jeder Schritt meldet am Ende eine Zeile «zenOS-Kanal: gelungen.» bzw. «Ubuntu-Basis:
nicht gelungen – wartet (Exit 10).»; zum Schluss die Benutzerteile (`install.sh --nur-benutzer` als Benutzer), wenn der
Kanal installierte oder zurückging (0, 4) oder der Basis-Schritt gelang.

Der Basis-Schritt hält die Sperre der Bedienung wie der Kanal (`/run/zenos-sperre/bedienung.lock`: `zen update`, die
Automatik und die Knöpfe der Einstellungen laufen nie zugleich), prüft über `zenos-basis-pruefen.service` und zeigt
die Zusammenfassung: Anzahl, davon Sicherheit, Kernel/Firmware/Bootloader (ja/nein mit Namen), Entfernungen,
«Neustart voraussichtlich nötig», Herstellerquellen, den Hash. Ist etwas offen, fragt er «Genau diese Liste (…)
installieren? Tippe «ja»:». Das getippte «ja» ist die Zustimmung für genau diese Liste, auch für Kernel, Firmware,
Bootloader und Entfernungen (dann mit dem Satz, dass danach ein Neustart nötig ist; zenOS startet nie selbst neu).
Danach installiert `zenos-basis-installieren.service` mit dem Auftrag `von: zen update`, das Journal läuft im
Terminal mit; bricht die Verbindung ab, läuft die Unit zu Ende.

| Option | Wirkung |
|---|---|
| `--ja` | Basis ohne Rückfrage, mit Zustimmung. Gilt nur für den Basis-Schritt, nie für das «ja» des Kanals; mit `--nur-zenos` ein Aufruffehler |
| `--nur-zenos` | nur Schritt 1 (so deployt Claude; Paketänderungen der Basis bleiben bei Zeno) |
| `--nur-basis` | nur Schritt 2 |

Der Basis-Schritt läuft auch nach einem Kanal-Ergebnis «nichts neu», «Zustimmung abgelehnt» (10) oder «läuft schon»
(75), aber nicht über einen kaputten Kanal (5) oder eine unterbrochene Installation des Kanals (`laeuft.json`, auch
`letzte.json` «kaputt»: «übersprungen», 10; das prüft zenos-basis selbst noch einmal) und nicht nach Ctrl+C (130).
Ohne Terminal und ohne `--ja` installiert er nichts (10).

| Exit | `zen update` |
|---|---|
| 0 | jeder gelaufene Schritt gelang (aktuell oder installiert) |
| sonst | der Exit des Schritts mit dem schwereren Ergebnis, in dieser Reihenfolge: 5 kaputt, 4 gescheitert und zurück (Kanal), 1 Fehler, 3 abgelehnt oder gesperrt, 10 wartet (auch «nein», ohne Terminal, übersprungen), 75 läuft schon |
| 2 | Aufruf falsch (`--nur-zenos` mit `--nur-basis`, `--ja` mit `--nur-zenos`, ein anderes Wort) |
| 130 | abgebrochen (Ctrl+C; eine laufende Installation läuft zu Ende) |

### In den Einstellungen

Über `pkexec /opt/zenos/scripts/bin/zenos-kanal-bedienen` (polkit-Aktionen in `org.zenos.kanal.policy`, nur in der
aktiven Sitzung am Gerät; `docs/sicherheit.md`):

- `basis-pruefen` (ohne Passwort): `zenos-basis-pruefen.service`, Exit der Unit.
- `basis-installieren HASH` (ohne Passwort): `zenos-basis jetzt HASH` schreibt den Auftrag ohne Zustimmung für genau
  die angezeigte Liste und startet die Unit, ohne neues `apt-get update`. Kernel, Firmware, Bootloader oder
  Entfernungen: Exit 10; Liste nicht mehr aktuell: Exit 3.
- `basis-installieren-zustimmen HASH` (Passwort bei jedem Aufruf): `zenos-basis zustimmen HASH`, dasselbe mit
  Zustimmung.

Ein Auftrag, den die Unit nicht nahm (sie lief nicht), bleibt nicht liegen. Endet die Unit mit 0, 3, 10 oder 75,
setzt zenos-basis ihren Zustand «failed» zurück (das sind Zustände der Basis-Updates); 1 und 5 bleiben sichtbar
(`systemctl --failed`).

Die Oberfläche (`shell/dienste/Basis.qml`, Logik in `basis.js`, getestet mit `test/einheiten/basis.test.mjs`) liest
ohne Rechte `stand.json`, `letzte.json`, `automatik.json`, den Notschalter und `/run/reboot-required(.pkgs)` und zeigt
unter Einstellungen › System › Updates einen eigenen Abschnitt «Updates · Ubuntu-Basis» neben «Updates · zenOS»
(Aussehen: `docs/design.md`). «Jetzt installieren» erscheint nur bei «bereit», «Mit Passwort installieren» nur bei
«zustimmung»; beide übergeben den Hash der angezeigten Liste, bei «gesperrt» gibt es keinen Knopf. Ein Hinweis
(Toast) kommt nur nach dem eigenen Klick; das Ergebnis einer Installation, von wem auch immer, kommt als Mitteilung
(aus `letzte.json`, je einmal, gemerkt in `~/.local/state/zenos/basis-meldungen.json`): «Ubuntu-Basis aktualisiert»
(still, höchstens 24 h alt), «Basis-Update kaputt» (dringend), «Basis-Update gescheitert». Hat die Automatik Kernel,
Firmware, Bootloader oder Entfernungen gesehen (`automatik.json` «zustimmung» für die Liste von `stand.json`), kommt
«Basis-Updates warten auf dich» einmal; wieder erst, wenn sich genau das ändert (ein neuer Kernel, andere
Entfernungen), nicht bei jeder neuen Liste. Bei «gesperrt» ebenso «Basis-Updates gesperrt».

**Neustart nötig.** Quelle ist `/run/reboot-required` (Ubuntu und unattended-upgrades schreiben es, zenos-basis trägt
eine neue greetd-Version ein), abgefragt im Takt der Updates (jede Minute, bei offenen Einstellungen oder Menüs alle
3 s, beim Öffnen des System-Menüs sofort). Die Leiste zeigt dann im System-Knopf das Symbol `neustart` gedämpft,
das System-Menü bei «Neustart» den Wert «nötig» («Update läuft» geht vor), die Einstellungen die Zeile «Neustart».
Leitplanke (`neustartHinweis` in `basis.js`, Code): nur bei voller Leiste, nie während der Bildschirm geteilt wird,
nie bei reduzierter oder ausgeblendeter Leiste, nie auf der Sperre; keine Mitteilung, kein Popup, nie ein Neustart von
selbst. IPC `basis status|neustart|hinweis|pruefen` (`docs/architektur.md`); der Rundgang in `scripts/pruefen.sh`
ruft nur die lesenden.

### Automatik

Entscheid Zeno (Oktober 2026): Basis-Updates dürfen automatisch laufen, ab Werk an, auch auf dem Kanal dev, ohne
Wartezeit (Ubuntu staffelt selbst), nie ein Neustart.

- `zenos-basis-automatik.timer`: 30–40 Minuten nach dem Start, dann alle 6 Stunden (03, 09, 15, 21 Uhr plus bis zu 10
  Minuten Zufall, versetzt zu `zenos-kanal.timer`), `Persistent`. `zenos-basis-automatik.service` (`automatik lauf`)
  prüft über die Unit (`apt-get update`) und installiert, wenn es darf.
- `zenos-basis-gelegenheit.timer`: alle 15 Minuten (7, 22, 37, 52). `zenos-basis-gelegenheit.service`
  (`automatik gelegenheit`) startet nur mit `/var/lib/zenos/basis/automatik-bereit` (es gibt ihn genau dann, wenn
  `stand.json` «bereit» sagt) und installiert die bereite Liste ohne `apt-get update`, wenn es darf. Hat sich die
  Liste inzwischen geändert (etwa durch unattended-upgrades), lehnt die Unit ab, `stand.json` zeigt die neue, die
  nächste Gelegenheit nimmt sie.
- Beide in derselben Sandbox wie die Automatik des Kanals (ohne Netz; apt läuft in den eigenen Units),
  `SuccessExitStatus=10 75`, Sperre der Bedienung (belegt: 75, beim nächsten Mal).

Installiert wird nur:

1. eine Liste ohne Kernel, Firmware, Bootloader und Entfernungen («bereit»). Bei «zustimmung» oder «gesperrt» wartet
   sie auf «ja» von Hand; `automatik.json` hat dann `ergebnis` «zustimmung» bzw. «gesperrt» und die `liste`, die
   Oberfläche meldet daraus «Basis-Updates warten auf dich» höchstens einmal je Liste;
2. wenn `zenos-kanal automatik darf --ohne-ssh --json` ja sagt. Das ist dieselbe Quelle, aus der die Automatik des
   Kanals vor jeder Installation fragt (`automatic_may` in zenos-kanal): Notschalter
   `/etc/xdg/zenos/kanal-automatik-aus`, Zeitpunkt aus `/etc/xdg/zenos/kanal-zeitpunkt` (sperre, fenster,
   jederzeit; hand nie), Akku (Netzteil oder ab 50 %). Strenger als beim Kanal: Bei jedem Zeitpunkt keine
   SSH-Sitzung, nicht nur bei «sperre» (apt startet Dienste neu; wer per SSH arbeitet, merkte das). Antwortet
   zenos-kanal nicht genau so (Exit 0 heisst ja, 10 nein, JSON), heisst das nein;
3. nicht, solange ein `install.sh` von Hand läuft oder der Kanal unterbrochen oder kaputt ist.

Der Notschalter ist gemeinsam: `sudo zen kanal automatik aus` schaltet auch die beiden Timer der Basis aus, und
install.sh (71-basis) lässt sie dann aus. Scheitert `apt-get update` (etwa ohne Netz), endet der Lauf mit 10 (kein
Ausfall der Unit), `automatik.json` und `zen doctor` nennen den Grund.

| Datei | Inhalt |
|---|---|
| `/var/lib/zenos/basis/automatik.json` | letzter Lauf der Automatik: `art` (lauf, gelegenheit), `beginn`, `ende`, `ergebnis` (aus, nichts, aktuell, wartet, zustimmung, gesperrt, installiert, kaputt, fehler), `grund`, `zeitpunkt`, `liste` |
| `/var/lib/zenos/basis/automatik-bereit` | eine Liste ohne Zustimmung installierbar (Hash): Bedingung für `zenos-basis-gelegenheit.service` |

Geprüft mit `test/einheiten/basis-automatik.test.py` (zen update mit «ja», «nein», ohne Terminal, `--ja`, Kernel;
Einstellungen mit und ohne Zustimmung, fremder Hash; Automatik mit und ohne «darf», nie Kernel oder Entfernungen,
Gelegenheit ohne Netz, Liste dazwischen geändert, Notschalter), `test/einheiten/zen-update.test.py` (Schritte,
Optionen, Exit, Benutzerteile), `test/einheiten/kanal-automatik.test.py` («automatik darf», SSH bei jedem Zeitpunkt,
Notschalter auch für die Basis-Timer) und `test/einheiten/kanal-bedienung.test.py` (Helfer und polkit).

## Basiswechsel: neue Hauptversion, neues Image

Ein Stand von zenOS ist für genau eine Ubuntu-Version gebaut; sie steht in `system/basis` (heute `26.04`). Innerhalb
dieser Basis kommt alles als Update: die Stände von zenOS über den Kanal, die Pakete von Ubuntu über
unattended-upgrades (Sicherheit) und die Basis-Updates (oben). Ein Wechsel der Basis (etwa auf 28.04) ist dagegen kein
Update, sondern eine neue zenOS-Hauptversion mit neuem Image (Entscheid Zeno, Oktober 2026). Ein Release-Upgrade
tauscht in einem Lauf fast jedes Paket, auch Kernel, Firmware, Qt (Quickshell muss neu gebaut werden), greetd und PAM,
ohne Schnappschuss und ohne Rückweg. Ein neues Image ist vorher geprüft, und die alte Karte bleibt als Rückweg.

Gesperrt ist der Wechsel an zwei Stellen:

- **Release-Upgrader:** `scripts/module/71-basis.sh` legt `/etc/update-manager/release-upgrades.d/zenos.cfg` mit
  `Prompt=never` ab (aus `system/update-manager/zenos.cfg`). ubuntu-release-upgrader liest nach
  `/etc/update-manager/release-upgrades` jede `*.cfg` in diesem Ordner in Namensreihenfolge, der letzte Wert zählt.
  Die Conffile des Pakets bleibt unberührt, sonst hielte unattended-upgrades bei einem Update des Pakets an. Danach
  lehnt `do-release-upgrade` ab (auch `-d`: «Prompt is set to never so upgrading is not possible», Exit 1), und
  `check-new-release`, die Begrüssung `91-release-upgrade` und `update-notifier-motd.timer` bleiben still, ohne
  changelogs.ubuntu.com zu fragen (im Container mit strace geprüft, siehe `docs/module/kennung.md`). Einen Hinweis auf
  eine neue Version, den die Begrüssung vorher zwischengespeichert hatte, leert das Modul.
- **Kanal:** `zenos-kanal` installiert nie einen Stand, dessen `system/basis` nicht zur `VERSION_ID` des Geräts passt
  (Regel «Ubuntu-Basis» oben). Ein Gerät auf 26.04 bleibt so auf der höchsten Version für 26.04, auch wenn es auf
  origin schon eine Hauptversion für 28.04 gibt.

`zen doctor` warnt, wenn die Basis nicht Ubuntu 26.04 ist (Abschnitt «System») und wenn `Prompt` nicht `never` ist
(Abschnitt «Ubuntu-Basis»). Wer die Paketquellen von Hand auf eine neue Version umstellt, kommt an beiden Sperren
vorbei (root kann alles); danach nimmt der Kanal keinen Stand für 26.04 mehr an.

**Umstieg auf eine neue Hauptversion** (von Hand, wenn es sie gibt):

1. Persönliche Daten sichern, von Hand auf einen eigenen Datenträger, nie auf ein Ziel im Netz (Manifest 0, harte
   Regel 8):
   - `~/.config/zenos/` (Einstellungen, Modi, Zustände, Raster, Bildschirm-Profile, Web-Apps)
   - `~/Ablage/` (dorthin zeigen Schreibtisch, Downloads, Dokumente, Bilder, Musik, Videos)
   - `~/.local/state/zenos/` (Laufzeitzustand, Thema)
   - die Starter der Web-Apps `~/.local/share/applications/zenos-webapp-*.desktop` (sie entstehen aus
     `~/.config/zenos/webapps.json` neu, gesichert ist sicherer)
   - `/etc/xdg/zenos/` (Kanal, Zeitpunkt und Notschalter der Updates, Lüfterkurve, Freigabe des Akkuprofils,
     WLAN-Land; für alle lesbar)
   - nach Wunsch `~/.local/share/zenos/` (Nutzungsstatistik des Befehlsfelds)

   Geheimnisse liegen in 1Password und gehören nicht in diese Sicherung. Ein Werkzeug für das Backup gibt es noch
   nicht.
2. Das Image der neuen Hauptversion auf eine zweite Karte flashen (siehe «Flashen»); die alte Karte bleibt liegen.
3. Erster Start und Einrichtung, dann die Ordner aus Schritt 1 zurückkopieren (`/etc/xdg/zenos/` mit sudo, Datei für
   Datei vergleichen: Die neue Hauptversion kann Werte ändern), danach `zen update`.

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
- Am besten mit dem Raspberry Pi Imager ab 2.0.11 **über die Manifest-Datei** `zenos-<v>.rpi-imager-manifest`: per
  Doppelklick öffnen oder im Imager «App Options › Content Repository › Edit › Use custom file › Apply & Restart»,
  dann zenOS auswählen. Unter
  «Einstellungen» Benutzer, Passwort und optional einen SSH-Schlüssel setzen, dazu Zeitzone und Tastaturbelegung.
  Wählt man das Image dagegen direkt als «eigenes Image» (`.img.xz`), bietet der Imager 2.x keine Einstellungen an,
  weil er nicht weiss, dass das Image cloud-init versteht; erst das Manifest sagt es ihm (`init_format: cloudinit`).
  Die Belegung gilt auch für das Passwortfeld im zenOS-Login, die Zeitzone für Uhr, Bündelung der Mitteilungen und
  Uhrzeit-Auslöser. Die `url` im Manifest zeigt auf die Datei der Release-Seite, bei `-rc` wie bei `vX.Y.Z`; der
  Imager lädt das Image von dort.
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
   zenOS-Login. Per SSH geht das nur mit einem Schlüssel, Passwörter nimmt SSH nicht an. Für `user` fragt sudo immer
   nach dem Passwort. Für einen Benutzer aus den Imager-Einstellungen gilt das nur mit einem Imager ab 2.0.11 und ohne
   «sudo ohne Passwort» (`passwordlessSudo`); sonst schreibt cloud-init `/etc/sudoers.d/90-cloud-init-users` mit
   `NOPASSWD`. zenOS ändert diese Regel nicht, `zen doctor` warnt («sudo geht ohne Passwort»).
   Zeitzone und Tastatur lassen sich dort nachholen: `sudo timedatectl set-timezone <Zone>` und
   `sudo dpkg-reconfigure keyboard-configuration`, danach neu starten.
3. Beim ersten Login kommen die Benutzerteile von zenOS (`zenos-sitzung` ruft `install.sh --nur-benutzer`).
4. Die Einrichtung fragt nach Name, optional Ort, Erscheinungsbild und erstem Modus.
5. Nach Zustimmung werden die proprietären Apps installiert (im Terminal, mit dem sudo-Passwort). Nubix hat noch
   keinen arm64-Build und wird angeboten, sobald es einen gibt.
6. Persönliches wird nur unter `~/.config/zenos/` abgelegt.

## Name und Marke

Geprüft am 04.10.2026 gegen die IPR-Policy von Canonical (Fassung vom 15.07.2015, an dem Tag neu abgerufen und
unverändert, am 06.10.2026 wieder). Für eine veränderte Weitergabe ohne Genehmigung sagt sie vollständig: «Otherwise you
must remove and replace the Trademarks and will need to recompile the source code to create your own binaries.» Gleich
danach: «This does not affect your rights under any open source licence applicable to any of the components of Ubuntu.»
Die Marken (Name, Logo, Systemkennung und Begrüssung) ersetzt zenOS. Bis `v0.1.0-rc2` stimmte das nicht: Das Image
meldete sich als Ubuntu (`ID=ubuntu`, `LOGO=ubuntu-logo`, «Welcome to Ubuntu» bei der Anmeldung, «Ubuntu 26.04.1 LTS» an
der Konsole), und die Ubuntu-Logos lagen als Dateien von base-files im Image. Die Binärpakete von Ubuntu baut zenOS
dagegen nicht neu (unten); dafür liesse sich die Klausel zu den Open-Source-Lizenzen anwenden, wie bei anderen
Ablegern. Ob das genügt oder Canonical schriftlich gefragt wird, entscheidet Zeno vor der ersten Weitergabe
(`docs/baufortschritt.md`, «Offene Punkte für Zeno»).

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
an andere (beides in `docs/baufortschritt.md`, «Offene Punkte für Zeno», und ANLEITUNG G): die schriftliche Anfrage bei
Canonical oder der Entscheid, sich auf die Klausel zu den Open-Source-Lizenzen zu stützen, und eine
Ähnlichkeitsrecherche zum Namen zenOS. Signieren, Prüfung auf den Geräten und Images nur aus signierten Tags sind
eingerichtet («Signierte Releases»); der erste signierte Tag ist `v0.1.0-rc4` (Image-Bau gescheitert), das erste Release `v0.1.0-rc5` als Vorabversion. Weil
auch jedes `-rc` eine öffentliche Release-Seite bekommt, liegt zenOS schon damit für alle sichtbar auf GitHub: Ob
«Name und Marke» davor geklärt wird oder erst vor `v0.1.0`, entscheidet Zeno (ANLEITUNG, «G6 bis G10»).

## Bürorechner

Für x86 kommt später ein eigener Installer-Stick: ein Ubuntu-ISO mit Autoinstall, das nach der Installation `scripts/install.sh` ausführt. Die Verschlüsselung fragt der Installer interaktiv ab. Kein Passwort steht in einer Datei.
