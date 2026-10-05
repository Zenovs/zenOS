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

**Stand:** Signieren ist eingerichtet. Der Anker `system/vertrauen/` hat Serie 1 mit je einem öffentlichen Schlüssel
«zenOS Release» (`SHA256:6CAhnfU9qHJz36663u/A/HxmZkKxao0r2QxT3oy+DzI`) und «zenOS Wurzel»
(`SHA256:9xQZHFzUT4CF87GQ2VrCo6oGEC1DimrsHOtEmnB5pDk`), beide am 05.10.2026 mit 1Password abgeglichen. `zen update`
und `zen rollback` laufen über `zenos-kanal` (siehe «Auf dem Gerät»): auf `stabil` und `vorschau` nur gültig
signierte Tags, auf `dev` ein nicht durchgehend signierter Stand nur nach einem getippten «ja». Ein Gerät ohne Anker
(`/etc/zenos/vertrauen`) meldet «Anker fehlt» und installiert über `stabil` und `vorschau` nichts (fail-closed).
Automatische Updates mit einstellbarem Zeitpunkt kommen in einem zweiten Teil.

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
`/opt/zenos`. Automatisch installiert diese Fassung nichts: nur `zen update`, `zen rollback` und die Knöpfe in
Einstellungen › System › Updates (die Automatik folgt; ihren Zeitpunkt stellt der Benutzer am Gerät schon ein).

| Befehl | Wer | Was |
|---|---|---|
| `zen update` | Benutzer mit sudo, im Terminal | holen, prüfen und bereitstellen, bei Bedarf «ja», installieren mit Gesundheitsprüfung und Rückweg, dann die Benutzerteile |
| `zen rollback <tag>` | ebenso | dasselbe mit einem Tag als Ziel |
| `zen kanal status` | alle | Kanal, Zustand, Anker mit Fingerabdrücken, installierter Stand, `hoechste`, gültige und abgelehnte Tags, letzter Kontakt, letzte Installation, guter Stand, gesperrte Stände |
| `sudo zen kanal pruefen` | root | startet `zenos-kanal-holen.service`, dann `zenos-kanal-pruefen.service`, zeigt danach den Status. Installiert nichts |
| `zen kanal anker` | alle | zeigt den Anker des Geräts |
| `zen kanal zeitpunkt` | alle | zeigt, wann geprüfte Updates automatisch kommen (`/etc/xdg/zenos/kanal-zeitpunkt`, ohne Datei `sperre`) |
| `sudo zen kanal zeitpunkt sperre\|jederzeit\|hand`, `… fenster VON BIS` | root | setzt ihn (dasselbe wie in den Einstellungen; VON und BIS als HH:MM, mindestens eine Stunde, über Mitternacht erlaubt) |
| `sudo zen kanal anker ORDNER` | root, nur im Terminal | setzt den Anker von Hand: den Fingerabdruck der Wurzel und von jedem Release-Schlüssel die ersten 8 Zeichen nach `SHA256:` aus 1Password eintippen. Die Werte aus dem Ordner zeigt es erst danach (auch nach einer falschen Eingabe nicht), damit niemand abtippt, was auf dem Bildschirm steht. Bei gleicher Wurzel nie mit kleinerer Serie, Widerrufe des Geräts bleiben |

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
   - Hauptbuch `gesehen.json` (nur Namen, die gültig waren: Objekt, Commit, erstmals gesehen): Zeigt ein schon
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
     `stabil` nimmt nur `vX.Y.Z` und gibt sie erst 24 h nach dem ersten Sehen für die Automatik frei (`frei_ab`),
     `vorschau` auch `vX.Y.Z-rcN` sofort.
   - `dev`: Neuer Stand von `origin/dev`, ob der installierte Stand darin liegt und ob jeder Commit
     dazwischen gültig mit einem Release-Schlüssel signiert ist (`%G?` gleich `G`; ein unsignierter Commit unter
     einer signierten Spitze zählt). Sonst nur von Hand mit «ja». Automatisch kommt auf dev nie etwas.
   - Rückfrage-Pfade: Trifft der Weg vom installierten Stand zum Ziel Firewall, Netz oder Boot, heisst der Zustand
     `zustimmung`. Die Liste steht fest im Code (`CONSENT_PATHS`, gleich den Gruppen `firewall`, `netz` und `boot`
     in `scripts/lib/sensible-pfade`, ein Test hält beide gleich); die Liste im neuen Stand kann nur Pfade
     dazunehmen. Lässt sich der Weg nicht vergleichen (installierter Stand unbekannt), gilt ebenfalls `zustimmung`.
4. **Stand:** `/var/lib/zenos/kanal/stand.json` (0644, atomar): `kanal`, `zustand`, `grund`, `geprueft`,
   `letzter_kontakt`, `holen_fehler`, `anker` (Serie und Fingerabdrücke), `anker_problem`, `installiert`,
   `hoechste`, `bereit` (Version, Commit, Objekt, `erstmals`, `frei_ab`, `rueckfrage`), `dev`, `gueltig`,
   `abgelehnt`, `hinweise`, `wunsch` (Antwort auf `zen update` bzw. `zen rollback`, siehe unten), `installation`
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
  `zen update` nach einem Rollback kehrt zurück). Ohne Anker oder bei «blockiert» nichts.
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
   für Ausschalten und Ruhezustand («zenOS wird aktualisiert»).
3. `<bereit>/scripts/install.sh` als root mit `ZENOS_KANAL_LAUF=1`, ohne Terminal; 10-code übernimmt den Code Datei
   für Datei atomar nach `/opt/zenos`. Ein SIGTERM (Ausschalten durch root) wartet auf das Ende von install.sh.
   Scheitert `install.sh` nur an seiner Sperre (Exit 75, kein «== Beginn» im Log), zählt der Versuch nicht: keine
   Sperre der Version, kein Rückweg, Ergebnis `wartet` (Exit 75).
4. Gesundheit: Exit 0 und «== Ende … ok» im install.log, `/opt/zenos` auf dem Commit und sauber, `scripts/zen`,
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
   `zen update` danach als Benutzer ein (sonst die nächste Anmeldung). Ergebnis `installiert`.
6. Nicht gesund: Die Version kommt nach `gesperrt/` (Grund, Zeit), dann derselbe Lauf mit dem Rückweg. Ist er gesund,
   Ergebnis `zurueck` (Exit 4), sonst `kaputt` (Exit 5, keine weiteren Versuche; die Meldung nennt zuerst den Grund,
   ANLEITUNG F «Kaputt»). Ist das Ziel der laufende Stand selbst, gibt es keinen Rückweg und keine Sperre
   (`gescheitert`, Exit 4).

Ein harter Abbruch (Strom, `kill -9`) hinterlässt `laeuft.json`. `zenos-kanal-nachstart.service` (aktiviert, nur mit
`laeuft.json`, vor greetd, ohne Netz) vollendet beim Start die Übernahme des Codes mit `install.sh --nur-code` aus der
Bereitstellung; kennt deren install.sh die Option nicht (Stände vor diesem Kanal), bleibt das `zen update`. Ein
`zen update` setzt danach zuerst den unterbrochenen Lauf fort. Nach zwei unterbrochenen Versuchen sperrt schon
nachstart die Version und nimmt den Code des Rückwegs. Ein `install.sh` von Hand erledigt einen unterbrochenen Lauf.
Das Ergebnis jedes Laufs, der eine Installation betraf, steht in `letzte.json` (`ergebnis`, `grund`, `ziel`,
`rueckweg`, `versuche`, `hinweise`); `abgelehnt`, `wartet` und `nichts` überschreiben es nicht, sonst verschwände ein
`kaputt` aus `zen doctor`. `zen doctor` und `zen version` zeigen auch `gescheitert` und `fehler`; ein `angehalten`
löst ein älteres `kaputt` ab und umgekehrt.

Ein `install.sh` von Hand (aus einem Arbeits-Checkout oder aus `/opt/zenos`, nicht der Kanal, nicht das Image, nicht
nur die Benutzerteile) wartet über sudo auf die Kanal-Sperre und trägt darunter seine PID in `/run/zenos-sperre/hand`
ein. Solange dieser Prozess läuft (`/proc/<pid>`, `install.sh`), installiert der Kanal nichts (Exit 75); am Ende
entfernt install.sh den Vermerk. Den Vermerk kann nur root schreiben. Läufe als root (Kanal, `--nur-code`) nehmen die
Sperre `/run/zenos-sperre/install.lock`, Läufe als Benutzer weiter `/run/lock/zenos-install.lock`. Ein Lauf aus einem
Arbeits-Checkout hinterlässt `angehalten` (Commit, Zeit): `zen update` installiert den Stand des Kanals dann neu, auch
wenn der Commit gleich ist.

| Datei in `/var/lib/zenos/kanal` | Inhalt |
|---|---|
| `wunsch.json` | Wunsch von `zen update`, `zen rollback` oder aus den Einstellungen (`jetzt`, `zustimmen` mit `nur_signiert`; 0600, das Prüfen entfernt ihn) |
| `auftrag.json` | bereitgestelltes Ziel für das Installieren |
| `bereit/<commit>/` | Bereitstellungen: das Ziel und der gute Stand |
| `laeuft.json` | laufende oder unterbrochene Installation |
| `gut.json` | zuletzt gesund installierter Stand |
| `letzte.json` | Ergebnis der letzten Installation |
| `gesperrt/<version oder commit>` | gescheiterte Ziele mit Grund |
| `angehalten` | Stand von Hand aus einem Arbeits-Checkout |

| Exit | `zen update`, `zen rollback` |
|---|---|
| 0 | installiert oder schon aktuell |
| 2 | Aufruf falsch |
| 3 | abgelehnt (etwa Anker fehlt auf stabil, Tag unbekannt, Bereitstellung verändert) |
| 4 | gescheitert, zurück auf dem Stand davor |
| 5 | kaputt: auch der Rückweg scheiterte |
| 10 | wartet: Zustimmung (auch «nein»), Platz, kein Kontakt |
| 75 | ein anderes `zen update`, eine Prüfung, ein `install.sh` von Hand oder eine andere Installation läuft (die Meldung nennt den Prozess) |

Am Gerät nach dem Einrichten (je ein Befehl): `zen kanal status` (Fingerabdrücke mit 1Password vergleichen),
`sudo zen kanal pruefen`. Solange der Anker leer ist, steht dort «Anker fehlt» und `v0.1.0-rc1` bis `rc3` als
«unsigniert»; `zen update` geht dann nur auf dev und nur mit «ja».

Übergang: Das erste `zen update` mit diesem Stand läuft noch über den alten Weg (`git checkout` in `/opt/zenos`,
`install.sh`) und bringt den Kanal; erst das nächste geht darüber. Hat das Gerät `v0.1.0-rc1` vor seiner Verschiebung
auf GitHub geholt, bricht dieser alte Weg mit «git fetch ist fehlgeschlagen» ab; dann einmal der Notweg aus
ANLEITUNG F (holt ohne Tags). Ein `zen rollback` auf einen älteren Stand (etwa
`v0.1.0-rc3`) bringt dessen alten `zen update` zurück, der Kanal-Code bleibt liegen und stört nicht.

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
letzten Prüfung installiert, sagt sie das, statt alte Angaben zu zeigen.

| Knopf | Helfer (pkexec) | was passiert |
|---|---|---|
| «Jetzt prüfen» | `zenos-kanal-bedienen pruefen` (ohne Passwort) | holen und prüfen wie `sudo zen kanal pruefen`; installiert nichts |
| «Jetzt installieren» (nur bei `bereit`, auf dev bei einem neuen, ganz signierten Stand) | `… installieren` (ohne Passwort) | `zenos-kanal-jetzt.service`: `zenos-kanal jetzt`, wie `zen update` ohne Terminal und ohne Frage; was ein «ja» bräuchte, bleibt liegen (Exit 10) |
| «Zustimmen …» (nur bei `zustimmung` auf stabil und vorschau) | `… zustimmen OBJEKT` (Passwort, jedes Mal) | `zenos-kanal-zustimmen@OBJEKT.service`: `zenos-kanal zustimmen OBJEKT`, ohne neues Holen, das «ja» nur für dieses Tag-Objekt und nur für gültig signierte Ziele (`nur_signiert` im Wunsch). Nennt die Prüfung ein anderes Objekt: nichts (Exit 10) |
| Segmente «Bei Sperre · Zeitfenster · Jederzeit · Von Hand», beim Zeitfenster von–bis | `… zeitpunkt …` (ohne Passwort) | `zenos-kanal zeitpunkt` schreibt `/etc/xdg/zenos/kanal-zeitpunkt` (root, 0644, atomar); gilt für das ganze Gerät, weil root-Dienste ihn lesen |

Die Units laufen unabhängig von der Oberfläche: Lädt sie neu (etwa weil das Update QML bringt), endet nur der Helfer.
Exit 3, 10 und 75 sind für die Units Zustände, keine Fehler (`SuccessExitStatus`). Danach prüft `jetzt` wie
`zen update` neu, die Seite zeigt den neuen Stand.

Mitteilungen (Absender zenOS, jede nur einmal je Zustand, gemerkt in `~/.local/state/zenos/kanal-meldungen.json`):

| Anlass | Dringlichkeit | Wann wieder |
|---|---|---|
| installiert (`letzte.json`, höchstens 24 h alt) | still (low) | bei der nächsten Installation |
| zurück auf dem Stand davor, gescheitert, abgebrochen | normal | ebenso |
| kaputt (auch der Rückweg scheiterte; auch älter) | dringend | ebenso |
| blockiert (etwa ALARM) | dringend | wenn der Zustand sicher vorbei war (ein anderer Zustand der Prüfung, nicht nur «kein Kontakt» oder «fehler») oder der Grund ein anderer ist |
| Anker fehlt | normal | ebenso |
| abgelehnt: ein Tag im Kanal über allem, was schon gilt, oder ein auf origin verschobener Tag (stabil und vorschau, mit Anker) | normal | je Tag-Name einmal |
| wartet auf Zustimmung | normal | je Tag-Objekt einmal |
| 14 Tage ohne Kontakt zu origin | normal | je Kontaktzeit einmal |
| Update bereit, nur beim Zeitpunkt «Von Hand» | normal | je Tag-Objekt einmal |

Im System-Menü steht bei Neustart und Ausschalten «Update läuft», solange `/run/zenos-kanal/uebernahme` besteht
(install.sh aus dem Kanal mit Block-Inhibitor; systemctl lehnte dann ab). Ein Klick sagt das als Hinweis, statt
still nichts zu tun. Der Sperrbildschirm zeigt nichts davon.

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
- Die Bestätigung einige Minuten nach dem Start (läuft der Login?) kommt erst mit der Automatik (Teil B): Ein
  Update, das erst nach dem Neustart den Login bricht (greetd-Konfiguration, PAM), gilt bis dahin als gesund.
- Offen für Teil B (Automatik): «erstmals» in `gesehen.json` entsteht mit der Uhr beim ersten Sehen, auch wenn sie
  noch nicht synchronisiert ist (die 24 h auf stabil verschieben sich dann); ein `zen rollback` sperrt die Version,
  von der er wegführt, nicht, und die Automatik brächte sie wieder.
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
- Der Kanal für `zen update` ist im Image `dev`, wie auf dem Pi, bis es signierte Releases gibt (dann `stabil`).
  Kanäle: `stabil` (nur `vX.Y.Z`), `vorschau` (auch `vX.Y.Z-rcN`), `dev`; ein alter Wert `main` gilt als `stabil`.

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
