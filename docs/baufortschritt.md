# Baufortschritt

Claude Code führt diese Liste während des Bauauftrags nach. Eine neue Sitzung macht hier weiter.

Status: `offen` · `in Arbeit` · `fertig` · `offener Punkt`

## zenOS 1.0, Vorschau auf der SSD des Argon (Branch `neubau`)

Bauauftrag vom 08.11.2026, erweitert am 10.11.2026 (`BAUAUFTRAG.md`): Die SSD des Argon bekommt zenOS 1.0 direkt,
mit Oberfläche und Updates über `zen update`. Die SSD kommt danach nicht mehr heraus. Konzept: `docs/neubau.md`.

| Schritt | Status | Notiz |
|---|---|---|
| Konzept, Manifest, CLAUDE.md, Bauauftrag | fertig | Bauauftrag am 10.11.2026 auf SSD und Updates erweitert |
| Bauumgebung | fertig | Colima-VM «zenos» (6 Kerne, 6 GB), Kontext `colima-zenos`; `bauen.sh` → `umgebung/bauen-innen.sh` (holt und prüft die Quelle von Quickshell) → mkosi. Arbeits- und Bauordner von mkosi im Volume `zenos-bau-pakete` (Overlay geht nicht auf dem Docker-Overlay). |
| Grundsystem | fertig, Test grün | Debian trixie arm64, Stand 20261108T000000Z; `/` erofs mit dm-verity, `/var` und `/home` auf LUKS2 |
| Quickshell 0.3.1 | fertig | Commit `1a4716c…`, gebaut in `mkosi.build.d/10-quickshell.sh.chroot`; wayland-protocols 1.47 nur fürs Bau-Overlay aus trixie-backports (fürs Image gesperrt, `mkosi.postinst` prüft). `mkosi.finalize` prüft alle Bibliotheken. |
| Oberfläche | fertig, Test grün | Login, Sitzung, Leiste, Befehlsfeld mit Apps, Chromium, kitty, hell und dunkel, System-Menü, Sperre in QEMU geprüft (Bildschirmfotos). Oberfläche von 0.1 für 1.0 angepasst (`shell/`, ohne Kanal, Basis, Firewall, Lüfter, Installer, Einstellungen, Einrichtung, Freigabe, Anzeige); Login `greeter.qml` über `/usr/lib/zenos/greeter`, Sitzung `/usr/lib/zenos/sitzung`, Benutzerdienste `zenos-shell` und `zenos-idle` (swayidle, 5 min), Notfall-Sperre swaylock. Hilfsprogramme unter `/usr/lib/zenos`, `zen` unter `/usr/bin`. |
| Start auf dem CM5, A/B | gebaut, Aufteilung geprüft | Probestart mit tryboot erst auf dem Argon (QEMU hat keinen Bootloader von Raspberry Pi). Schema von Raspberry Pi: Partition 1 `zenos-start` (64 MB, autoboot.txt, Tastatur), 2 `zenos-start_<v>` (Start A), 3 `_empty` (Start B), dann Prüfsummen A (128 MB) und System A (wächst beim ersten Start auf 6 GB), B-Hälfte und Daten beim ersten Start |
| Updates | fertig, Test grün (ohne Probestart) | `zen update` → `zenos-update.service` → `/usr/lib/zenos/update`: lädt `SHA256SUMS` und `SHA256SUMS.sig` (GitHub, `releases/latest/download`), prüft Zenos SSH-Signatur mit Berührung und PIN, dann jede Datei; systemd-sysupdate schreibt nur diese geprüfte Kopie (seit 13.11.2026, vorher GPG in sysupdate), Probestart über `/run/systemd/reboot-param` «0 tryboot», fest über autoboot.txt (Ziffern 2/3 an Ort und Stelle). In QEMU: Update ohne Admin aus der Sitzung in die B-Hälfte, Ablehnung von der seriellen Konsole, Zustand über den Neustart. Erinnerung nach 14 Tagen (`/usr/lib/zenos/erinnerung`, Benutzer-Zeitgeber, Einheitentest). `mkosi/veroeffentlichen.sh` macht die Dateien, `docs/signieren.md` erklärt das Signieren; Releases heissen `zenos-<version>`. |
| Schlüssel für Updates | wartet auf Zeno | Entscheid 13.11.2026: zwei FIDO2-Schlüssel (`ed25519-sk`, OpenSSH), signiert am Mac in Zenos Terminal mit PIN und Berührung (`docs/signieren.md`). `mkosi/schluessel/argon-allowed-signers` (öffentlich); ohne sie baut das Image für den Argon nicht |
| Härtung, Browser | fertig | wie zuvor; Chromium 156 mit Richtlinien |
| Angriffstests | fertig | `mkosi/test/starten.sh`: System und Härtung, Oberfläche (Login wie ein Mensch, Apps, Befehlsfeld, Sperre, Bildschirmfotos unter `mkosi/ausgabe/test/`), Erinnerung, Update-Test (`ZENOS_TEST_NEU=<version>`), `zen notfall`, Hardware-Schlüssel ohne Gerät, Ausschalten nach langer Sperre, fünf Starts (falsches Passwort, Wiederherstellungsschlüssel, echtes Passwort, Notfall-Passwort mit Prüfung der Platte von aussen, danach stimmt nichts mehr). Am 12.11.2026: 88 von 88 grün; am 13.11.2026 mit den drei Angriffen auf den Update-Weg (veränderte Liste, ohne Signatur, ausgetauschtes System) 92 von 92. Einheitentests: `update-einheiten.sh`, `erinnerung-einheiten.sh`, `notfall-einheiten.sh`, `schluessel-einheiten.sh` |
| Deckel | gebaut, Test grün (QEMU 12.11.2026) | Overlay `mkosi/start/zenos-deckel.dts`: GPIO27 des RP1 mit Pull-up als `gpio-keys`-Schalter SW_LID (aktiv tief: Pegel 0 heisst zu), nur im Abschnitt `[cm5]`. logind sperrt beim Zuklappen immer (`HandleLidSwitch*=lock`, `LidSwitchIgnoreInhibited=yes`, keine Schonfrist nach dem Start), über denselben Weg wie die Ein/Aus-Taste (Lock → swayidle → `/usr/lib/zenos/sperren`). `mkosi.finalize` übersetzt das Overlay und wendet es auf den Gerätebaum des CM5 Lite an, sonst bricht der Bau ab; `startpartitionen.sh` prüft es im fertigen Image, `erster-start.py` den Weg über logind in QEMU. Am 11.11.2026 gegen `bcm2712-rpi-cm5l-cm5io.dtb` der Firmware von Raspberry Pi geprüft (fdtoverlay); am 12.11.2026 auf dem Mac gebaut, `startpartitionen.sh` (11 Prüfungen) und QEMU grün. Das Zuklappen selbst prüft erst Zeno am Argon. |
| Browser ohne Spuren | gebaut, Test grün (QEMU 12.11.2026) | Chromium-Richtlinien: kein Verlauf, Cookies nur für die Sitzung, beim Beenden Cookies, Website-Daten, Cache, Formulardaten, Anmeldedaten und Download-Verlauf löschen, keine Wiederherstellung der Sitzung. Downloads nur im Arbeitsspeicher (`~/Downloads` → `$XDG_RUNTIME_DIR/zenos/downloads`, `sitzung`). Lesezeichen, Einstellungen pro Website und Erweiterungsdaten bleiben. QEMU-Test prüft den tmpfs (45 von 45 Prüfungen grün am 12.11.2026). |
| Notfall-Passwort | gebaut, Test grün | Bauauftrag 2 vom 11.11.2026 (`BAUAUFTRAG.md`): eigene Partition `zenos-notfall` (32 MB, Nr. 8; Daten jetzt Nr. 9), eigene Passwortabfrage `zenos-entsperren` statt systemd-cryptsetup, Löschen der Schlüssel (`luksErase`), Attrappe im Arbeitsspeicher (zram, sonst Loop-Gerät auf tmpfs) mit angemeldetem leerem Konto, `zen notfall` über `zenos-notfall.socket` (varlinkctl, PID/UID von systemd, strenges Muster statt JSON-Parser). Einheitentests `notfall-einheiten.sh` (32), QEMU: erster Start, `zen notfall`, falsches Passwort, Wiederherstellungsschlüssel, Attrappe, Platte von aussen, danach stimmt nichts mehr. Audit des Kernels aus (`audit=0`): Es schrieb jeden Start von `zenos-notfall@` ins Journal. |
| Ausschalten nach langer Sperre | gebaut, Test grün | Bauauftrag 3 vom 11.11.2026: `zenos-ausschalten.service` (festes Systemkonto ohne root, polkit nur fürs Ausschalten, auch gegen Inhibitoren; kein DynamicUser, dessen Laufzeitverzeichnis unter `/run/private` für die Sperre nicht lesbar wäre) zählt über logind die Zeit ohne entsperrte Sitzung an seat0, mit `/proc/uptime`; fest 30 Minuten, im QEMU-Image 5 (`ausschalten-test-nach`, im Argon-Image verboten). Die Sperre und swaylock melden LockedHint über `/usr/lib/zenos/gesperrt-melden` an die grafische Sitzung des Kontos (`session/auto` findet für Dienste der Benutzerinstanz keine). «Schaltet in 1 Minute aus» auf der Sperre (Bildschirmfoto `10-ausschalten-hinweis`). QEMU: gesperrt mit Inhibitor aus nach der Testzeit, Entsperren setzt zurück, am Login ohne Anmeldung aus. |
| Hardware-Schlüssel (FIDO2) | gebaut, ohne Gerät getestet | Bauauftrag 4 vom 11.11.2026: Passphrase pro Schlüsselplatz aus Passwort und hmac-secret (`schluessel-gemeinsam`, Token `zenos-fido2`), kein Platz mit dem Passwort allein; erster Start mit Schlüssel 1 (Pflicht) und 2; `pam_u2f` für greetd, Sperre und swaylock (`/etc/pam.d/zenos-schluessel`, Liste unter `/var/lib/zenos/schluessel`); Notweg nach dem Wiederherstellungsschlüssel; `zen schluessel`. Die Sperre weicht jetzt auf `greetd` statt `login` aus (dort ohne Schlüssel). Einheitentests `schluessel-einheiten.sh` (35) mit Attrappen der FIDO2-Werkzeuge; QEMU ohne Gerät (Test-Image: Platz mit Passwort, `nouserok`), die echte Prüfung macht Zeno am Argon mit seinen Schlüsseln. |
| Abnahme auf dem Argon ONE UP | offen | Zeno schreibt das Image auf die SSD (Befehle in `mkosi/README.md`) |

**Plan für Bauauftrag 2 und 4 (12.11.2026, zusammen geplant, 2 zuerst):**

- **Partition:** `40-zenos-notfall.conf` (32 MB, `linux-generic`, Label `zenos-notfall`) entsteht beim ersten Start vor
  `zenos-daten`. `daten-anlegen` nullt sie sofort: Auf der SSD liegen alte Daten von 0.1, ein alter LUKS-Kopf darin sähe
  sonst wie ein Notfall-Container aus. Die Datenpartition wird damit Nummer 9.
- **`zenos-entsperren.service`** ersetzt den Eintrag in `/etc/crypttab`: auf der Konsole wie `daten-schuetzen`
  (`tty-force`), `TimeoutStartSec=infinity`; `/etc/fstab` verlangt den Dienst (`x-systemd.requires=`,
  `x-systemd.device-timeout=0`). Ablauf: Eingabe mit `systemd-ask-password`; sieht sie aus wie ein
  Wiederherstellungsschlüssel, normalisieren (klein, Bindestriche). Dann die Daten öffnen (`cryptsetup open
  --key-file=-`, Passwort per `printf` über eine Pipe). Erst wenn das scheitert und `zenos-notfall` LUKS ist:
  `--test-passphrase` dagegen. Mit Bauauftrag 4 öffnen die Daten nur noch Plätze aus Passwort und Schlüssel (unten);
  ist kein Schlüssel eingesteckt, kann die Eingabe die echten Daten gar nicht öffnen, dann wird gleich das
  Notfall-Passwort geprüft, und sonst kommt «Schlüssel einstecken und berühren».
- **Notfall:** Namen lesen und Container schliessen, `luksErase` der Daten, Notfall-Partition nullen, `luksDump`
  prüfen (scheitert etwas: trotzdem weiter). Attrappe: zram, darauf `cryptsetup open --type plain` mit Zufallsschlüssel
  unter dem Namen `daten`, ext4 mit `home`. Marker `/run/zenos/attrappe` (Name), Notfall-Passwort mit `keyctl padd` in
  den Schlüsselbund von root (Zeitlimit 5 Min.). `zenos-attrappe.service` (nach homed, vor greetd) legt das Konto an
  (`directory`), aktiviert es und schreibt eine Konfiguration von greetd mit `[initial_session]` nach `/run`;
  `/usr/lib/zenos/greetd-starten` nimmt sie nur, wenn es sie gibt. Im Notfall-Zustand: kein `zen update`, keine
  Erinnerung.
- **Erster Start** (`daten-schuetzen`): Tastatur, Kontoname (für den Notfall-Container und `zenos-konto`), Passwort,
  [4: Schlüssel 1 und 2], Wiederherstellungsschlüssel, Notfall-Passwort (Enter = keins, zweimal; abgelehnt, wenn es
  die Daten öffnet). `zenos-konto` legt das Konto unter diesem Namen an.
- **`zen notfall`:** `zenos-notfall.socket` (`Accept=yes`) mit `zenos-notfall@.service` als root. systemd gibt im
  Namen der Instanz PID und UID des Aufrufers mit (SO_PEERCRED); angenommen wird nur eine aktive, lokale grafische
  Sitzung dieser UID (wie polkit bei `zen update`). Der Aufrufer ist `varlinkctl`, die Parameter kommen über stdin
  (geprüft am 12.11.2026), die Passwörter hex-kodiert; der Dienst prüft die Anfrage mit einem strengen Muster statt
  eines JSON-Parsers.
- **Bauauftrag 4:** Pro Schlüssel ein LUKS-Platz mit der Passphrase aus dem hmac-secret des Schlüssels, Salz =
  SHA-256 aus festem Präfix, Zufallssalz des Platzes und Passwort; Credential und Salz als LUKS-Token
  `zenos-fido2`. Kein Platz mit dem Passwort allein; der Wiederherstellungsschlüssel bleibt der einzige Weg ohne
  Schlüssel. Anmelden und Sperre: Passwort (homed) und `pam_u2f` mit einer Liste unter `/var/lib/zenos`, die nur root
  schreibt. In der Attrappe nimmt die Sperre die Berührung eines beliebigen FIDO2-Schlüssels an. Test in QEMU mit
  einem nachgebauten FIDO2-Schlüssel (Python in der Bauumgebung über uhid an `u2f-passthru` von QEMU; Debians QEMU hat
  keinen canokey).
- **Pakete:** `cryptsetup-bin` (luksFormat, luksErase, Test der Passwörter), `keyutils` (Übergabe an die Attrappe), mit
  Bauauftrag 4 `fido2-tools`, `libpam-u2f`, `pamu2fcfg`. zram ist im Kernel von Raspberry Pi (Modul), brd fest mit 4 MB
  (zu klein).

**Hier geht es weiter:** Die Bauaufträge 2 bis 4 sind gebaut und in QEMU geprüft, soweit es ohne Hardware geht. Seit
13.11.2026 signiert Zeno Updates mit seinen zwei FIDO2-Schlüsseln (OpenSSH, `docs/signieren.md`). Reihenfolge:
1. Zeno richtet die Keys ein (`docs/signieren.md`, Abschnitte 1 bis 3), einen Befehl nach dem anderen.
2. Nach dem Setzen der PIN prüft Claude lesend, ob die Keys neue Einträge ohne PIN erlauben (`makeCredUvNotRqd`);
   sonst fragt der erste Start des Argon (Bauauftrag 4) nach einer PIN, die er nicht kennt.
3. Probe mit beiden Keys (`mkosi/ausgabe/signatur-probe/`, `mkosi/signatur-pruefen.sh probe`).
4. Image für den Argon bauen (Fingerabdrücke mit Zenos Papier vergleichen, in `MANIFEST.md` eintragen),
   `startpartitionen.sh`, und die Befehle zum Schreiben der SSD, einer nach dem anderen.
Für den ersten Start braucht Zeno beide Hardware-Schlüssel (ohne Schlüssel 1 geht er nicht weiter).

**Abnahme am Argon** (Zeno, nach dem Schreiben der SSD):

1. Erster Start mit beiden Schlüsseln; beim Start Passwort und Berührung, ohne Schlüssel «Schlüssel einstecken».
2. Login und Sperre: Passwort, dann «Schlüssel berühren»; ohne Schlüssel kein Einlass. Passkey in Chromium (etwa auf
   webauthn.io) mit dem Schlüssel.
3. Deckel zu: sperrt sofort. 30 Minuten gesperrt: «Schaltet in 1 Minute aus», dann aus.
4. `zen schluessel status`, `zen notfall status`.
5. Das Notfall-Passwort selbst nur ausprobieren, solange noch nichts Wichtiges auf der SSD liegt: Danach geht es nur
   mit einem neuen Image weiter.
6. Wie bisher: der Probestart mit tryboot beim ersten echten Update, und ob beim Öffnen des Befehlsfelds Spuren der
   Gleit-Animation in der Leiste stehen bleiben (in QEMU einmal, in den Läufen danach nicht mehr).

Bekannte, harmlose Meldungen der Oberfläche im Journal: `zenos-konfig` und `zenos-energie` aus 0.1 fehlen (Modi,
Zustände, Raster und Energie kommen später); labwc kann ext-idle-notify nur in Version 1.

Offene Fragen an Zeno: Gibt es einen Test-Pi 5 für den signierten Start? Welche Hardware-Wallet (Trezor oder Ledger)?
(Geklärt am 13.11.2026: kein Signierrechner; signiert wird mit den zwei Security Keys über OpenSSH, Vorschlag von Zeno.)

Gefunden auf der SSD von 0.1 (nur gelesen): Ubuntu nutzte auf diesem Argon schon `autoboot.txt` mit `tryboot_a_b=1`
und ein initramfs von 70 MB vom NVMe. Der Bootloader des CM5 kann also tryboot, autoboot.txt und grosse Dateien.

**Offener Punkt:** Die machine-id ist bei jedem Start neu (schreibgeschütztes `/etc`). systemd-homed meldet beim
zweiten Start «Failed to allocate new home object» und «Fixation failed: Required key not available»; die
Anmeldung geht trotzdem. Vor Vorschau 2 muss die machine-id dauerhaft werden (Vorschlag: Daten im initrd
entsperren und `/etc/machine-id` auf `/var` zeigen lassen).

**Befunde vom 13.11.2026 (Updates mit FIDO2-Schlüsseln statt GPG), behoben:**

- systemd-sysupdate prüft nur GPG (`SHA256SUMS.gpg`). `/usr/lib/zenos/update` prüft jetzt selbst und gibt sysupdate
  nur eine geprüfte lokale Kopie (`Type=regular-file`, `/var/lib/zenos/update/quelle`). Vorher in der Bauumgebung mit
  einer Loop-Platte geprüft: Inhalt Byte für Byte gleich, UUID und Bezeichnung gesetzt. systemd-pull und gpg sind aus
  dem Image; `mkosi.finalize` lässt keine Quelle aus dem Netz zu.
- `ssh-keygen -Y verify` prüft bei FIDO-Signaturen die Flags nicht (Berührung, PIN). zenOS liest sie selbst aus der
  Signatur (PROTOCOL.sshsig, PROTOCOL.u2f). Einheitentest mit nachgebauten Signaturen, am Mac mit Zenos echten Keys
  geprüft (Probe A und B: «Berührung und PIN: ja», Gegenprobe mit verändertem Inhalt abgelehnt).
- openssh-client bringt `ssh-agent` (setgid, startet als Benutzerdienst mit jeder Sitzung) und `ssh-keysign` (setuid
  root). Im Image bleibt nur `ssh-keygen`; die Probe läuft ohne `/usr/lib/openssh`, wie auf dem Argon.
- mkosi trennt `--environment` an Leerzeichen: Der Wegwerf-Schlüssel des Tests kam als `ssh-ed25519` allein an. Jetzt
  nur der Base64-Teil.
- Die Security Keys (Firmware 5.8) haben eine PIN; der erste Start des Argon legt seine Einträge ohne PIN an. Beide
  Keys melden `makeCredUvNotRqd: true` und `alwaysUv: false` (mit ykman/python-fido2 gelesen), das geht also.
- Das `ssh-keygen` von macOS kann keine FIDO-Keys («No FIDO SecurityKeyProvider specified»): Zeno nimmt
  `/opt/homebrew/bin/ssh-keygen` mit vollem Pfad.

**Befunde vom 12.11.2026 (Bauaufträge 2 bis 4), behoben:**

- Der Kernel schrieb zu jedem Start und Ende eines Dienstes einen Audit-Eintrag ins Journal, auch für `zenos-notfall@`.
  `Audit=no` in journald half nicht (journald hängt nicht am Audit); jetzt `audit=0` auf der Befehlszeile.
- `cryptsetup luksKillSlot --batch-mode` liest stdin trotzdem: Steht dort etwas, gilt es als Passwort, und der Platz
  bleibt. Im Dienst hinter dem Socket ist stdin die Verbindung zu `zen`; alle Aufrufe bekommen `</dev/null`.
- Die Oberfläche läuft als Dienst der Benutzerinstanz und gehört zu keiner Sitzung: `session/auto` fand keine, und
  `onLockStateChanged` kommt beim eigenen Sperren nicht. LockedHint meldet jetzt `sperren()`/`_entsperren()` über
  `gesperrt-melden`, an die grafische Sitzung des Kontos.
- `update` legte `/var/lib/zenos` mit 0700 an: Die Sperre (als Konto) hätte die Liste der Schlüssel nicht lesen können
  und sich am Argon nie mehr entsperren lassen. Jetzt 0755, nur `update/` bleibt privat.
- Im Notweg liess sich das Notfall-Passwort als neues Passwort setzen; ein Start ohne Schlüssel hätte dann die Daten
  gelöscht. Jetzt abgelehnt (Einheitentest).
- Die Sperre wich bei einem PAM-Fehler auf `login` aus, das den Schlüssel nicht verlangt; jetzt auf `greetd`. swaylock
  band nur `login` ein; jetzt mit Schlüssel.
- Mit `DynamicUser=yes` liegt das Laufzeitverzeichnis unter `/run/private` (nur root): Der Zeitpunkt für «Schaltet in
  1 Minute aus» war für die Sperre nicht lesbar. Jetzt ein festes Systemkonto `zenos-ausschalten` (sysusers.d). Das
  Ausschalten selbst kam in QEMU pünktlich (306 s nach dem Sperren bei 300 s Grenze).
- `pam_exec` meldete den Normalfall (keine Attrappe) bei jedem Entsperren als Fehler; jetzt `quiet_log`.
- Das Konto des Wächters entstand nie: `systemd-sysusers` verwarf die Zeile (Doppelpunkt in der Beschreibung), und beim
  Start kann es in das schreibgeschützte `/etc` ohnehin nichts schreiben. `mkosi.finalize` legt Systemkonten aus
  `/usr/lib/sysusers.d/zenos.conf` jetzt im Bau an und prüft sie.
- Im Test wartete pexpect einmal nur 293 statt 420 Sekunden aufs Ausschalten: Es misst mit der Uhrzeit, und die Uhr der
  Bau-VM sprang. Der Test wartet jetzt in kurzen Schritten mit der monotonen Uhr. Der Wächter selbst zählt mit
  `/proc/uptime` und war pünktlich.

**Befunde vom 10.11.2026 (Oberfläche und Updates), behoben:**

- labwc aus Debian ist mit Xwayland gebaut und beendet sich, wenn es kein Xwayland findet. Davon war auch Vorschau 1a
  betroffen (der Test prüfte die grafische Sitzung damals nicht). zenOS bleibt ohne X-Server: `WLR_XWAYLAND` zeigt auf
  `/usr/lib/zenos/kein-xwayland`, das jede X11-Anfrage ablehnt.
- greetd gab nach fünf schnellen Fehlstarts auf (schwarzer Bildschirm). Jetzt nie (`greetd.service.d/zenos.conf`), und
  nach zwei schnell gescheiterten grafischen Logins kommt der Text-Login von greetd mit fish als Notausgang (WLAN mit
  nmtui, `zen update`).
- mkosi: Das Overlay für die Bau-Pakete lässt sich nicht auf das Overlay-Dateisystem von Docker legen (EINVAL), und
  Quellen lassen sich nicht ineinander in das nur lesbar eingehängte Repo hängen. Arbeitsordner im Volume, Quellen
  nebeneinander unter `$SRCDIR`.
- Quickshell 0.3.1 braucht ext-background-effect (wayland-protocols ab 1.45, Debian 13 hat 1.44): nur fürs Bau-Overlay
  aus trixie-backports. Quickshell braucht libQt6Widgets (Prüfung in `mkosi.finalize` hat es gefunden).
- Versionen ohne «~»: GitHub benennt Dateien mit Sonderzeichen um, systemd-sysupdate fände sie dann nicht. Vorschau =
  0.9.x.
- Login: Die Kontoliste kommt einen Moment nach dem Start (getent). Bis dahin stand der Fokus im Namensfeld, das mit der
  Liste verschwand; das getippte Passwort landete im unsichtbaren Feld. Jetzt fokussiert der Login neu, sobald die Liste
  da ist (Bildschirmfotos vor und nach Enter im Test).
- systemd-sysupdate liegt in Debian unter `/usr/lib/systemd/` (Paket systemd-container), nicht im Suchpfad: voller Pfad.
- Quickshell unter Qt 6.8 lädt keine ES-Module (`.mjs`) über `qs:`-Pfade, das Befehlsfeld blieb leer. Die Hilfsdateien
  der Oberfläche sind jetzt JavaScript-Bibliotheken (`.js` mit `.pragma library`).
- `RectangularShadow` gibt es erst ab Qt 6.9 (Debian 13 hat 6.8): Das Befehlsfeld hat keinen Schatten mehr, und
  QtQuick.Effects ist aus dem Image.
- Nach dem Schreiben eines Updates stimmen die Verweise unter `/dev/disk/by-partlabel` einen Moment lang nicht; die
  Kontrolle danach meldete fälschlich «nicht vollständig geschrieben». Das Update liest die Bezeichnungen jetzt mit
  lsblk direkt von der Platte, nachdem udev sie neu eingelesen hat.
- Releases von 1.0 heissen `zenos-<version>`, nie `v…`: Auf signierte Tags `v1.2.3` reagiert `zen update` von 0.1, auf
  Tags `v*` der Image-Workflow von 0.1.
- Geprüft: `zen update` geht ohne Admin nur aus einer Sitzung am Gerät (polkit: lokal und aktiv); von der seriellen
  Konsole lehnt polkit ab. Seit dem 11.11. sofort (`systemctl --no-ask-password`), statt nach einem Root-Passwort zu
  fragen, das es nicht gibt.

**Befunde aus den QEMU-Tests (08.11.2026), alle behoben:**

- systemd-resolved startete nicht: `PrivateTmp=disconnected` braucht `/var/tmp` als Einhängepunkt, bevor die
  Daten entsperrt sind. Das System behält jetzt die leeren Grundverzeichnisse von `/var`.
- `tastatur-laden` endete mit `[ -n "$variante" ] && …` und damit mit Fehlercode 1 bei Belegungen ohne Variante;
  daran scheiterte die Einrichtung. `loadkeys` ist auf seriellen Konsolen kein Fehler mehr.
- Das Paket `login` fehlte (Debian 13 zählt es nicht mehr zur Grundausstattung); ohne `/etc/pam.d/login` brach
  greetd ab. `agreety` liegt unter `/usr/sbin`, ausserhalb des Suchpfads von `_greetd`.
- `systemd-homed-firstboot` läuft nur beim allerersten Start (ConditionFirstBoot); mit schreibgeschütztem `/etc`
  wäre das nie. Eigener Dienst `zenos-konto`.
- Die B-Hälfte entsteht erst beim ersten Start: Das Image schrumpfte von 7,8 auf 1,7 GB.
- AppArmor fand `/var/cache/apparmor` nicht (tmpfiles legt es an).
- mkosi 25.3 mit `Incremental=yes` scheitert am Entfernen von dpkg im wiederverwendeten initrd (aus).
- `ManifestFormat=changelog` holte Änderungslisten aus dem Netz und scheiterte an Sicherheitsupdates (nur json).
- Der Archivschlüssel von Raspberry Pi von der Webseite hat Bindungen mit SHA-1; `sqv` lehnt ihn ab. Erneuerter
  Schlüssel aus `raspberrypi-archive-keyring`, über InRelease → Packages.gz → .deb geprüft.

## zenOS 0.1 (eingefroren)

| Modul | Status | Notiz |
|---|---|---|
| M1 · Installer und zen-Werkzeug | fertig | install.sh (idempotent, Module, Log), gemeinsam.sh, zen (update, rollback, doctor, version, benutzer, hilfe), pruefen.sh, Testumgebung `test/container/`. Details: `docs/module/m1.md` |
| M2 · Basis und Sitzung | fertig | Pakete, Quickshell v0.3.1 aus dem Quellcode (Neubau nur bei anderem Commit/Qt), Schriften, greetd mit Quickshell-Greeter (kein Autologin), Sitzung als systemd-Target. Details: `docs/module/m2.md` |
| M3 · Design-Tokens und Theme | fertig | Theme-Singleton aus tokens.json (neue Tokens: linie2, trennlinie, eingabeRand, tasteRand, abgesetzt, schatten), Dienste, Komponenten, shell.qml mit isoliert geladenen Oberflächen, zenos-thema (GTK, Qt über Portal, kitty, labwc, VS Code). Details: `docs/module/m3.md` |
| M4 · Leiste | fertig | Leiste nach Entwurf 2, System-Menü, Hintergrund «Heute». Details: `docs/module/m4.md` |
| M5 · Befehlsfeld | fertig | Apps, Web-Apps, Rechnen (eigener Parser), Dateien, Modi/Zustände, Aktionen; Bildschirmfoto und Pipette. Details: `docs/module/m5.md` |
| M6 · Mitteilungen | fertig | NotificationServer, Bündelung nach Zustand, Zentrale, Leitplanke bei Freigabe. Details: `docs/module/m6.md` |
| M7 · Sperrbildschirm | fertig | ext-session-lock + PAM, swayidle, zen lock (auch per SSH), Marker nach Absturz, Notfall-Sperre mit swaylock, 1Password. Details: `docs/module/m7.md` |
| M8 · Modi und Zustände | fertig | Schemas, zenos-konfig, Modi/Zustände/Leitplanken, Freigabe über xdg-desktop-portal-wlr, Einstellungen mit «Modi & Zustände». Details: `docs/module/m8.md` |
| M9 · Raster und Bildschirme | fertig | zenos-labwc (Regionen, Kürzel, Theme-Teil), zenos-kanshi, Raster-Vorlagen. Details: `docs/module/m9.md` |
| M10 · Terminal | fertig | kitty (Ctrl+C/V, Super-Kürzel), fish mit Statuszeile, «?» offline, Warnung bei gefährlichen Befehlen. Details: `docs/module/m10.md` |
| M11 · Sicherheit | fertig | unattended-upgrades, Chrome-Richtlinien, gitleaks-Hook + CI, ufw (seit `v0.1.0-rc3` standardmässig an). Details: `docs/module/m11.md` |
| M12 · Erster Start | fertig | Einrichtung nach Entwurf 2, Zustimmung, zen apps (Chrome, VS Code, 1Password, CLI, coremail), Web-Apps. Nubix: kein ARM-Build. Details: `docs/module/m12.md` |
| M13 · Argon ONE | fertig | zenos-argon (Lüfterkurve, Power-Button, Abschaltsignal beim Ausschalten), Temperatur in der Leiste. Details: `docs/module/m13.md` |
| M14 · Image-Workflow | fertig | image.yml + image/bauen.sh; Release für jeden gültigen Tag, -rc als Vorabversion (bis rc3 nur Artefakt). Details: `docs/module/m14.md` |
| M15 · Abschluss | fertig | Integration (frische Installation von GitHub, `zen update`, voller Image-Bau, drei Abnahme-Touren, drei Reviews mit Gegenprüfung, 36 Befunde behoben), Doku, ANLEITUNG, CHANGELOG, Tag `v0.1.0-rc1` |
| Bildmarke «Zwei Steine» | fertig | nach Zenos Spezifikation: Dateien in `assets/zeichen/` (erzeugt von `erzeugen.py`), Pfade in tokens.json, `ZenZeichen` statt `Zeichen` in Leiste, Login, Sperre, Befehlsfeld und Erstem Start, Wasserzeichen und Token `wasserzeichen` entfernt, App-Icon `zenos` (45-thema). Details: `docs/bildmarke.md` |
| Bootsplash (Plymouth) | fertig, nicht aktiv | Theme `system/plymouth/zenos/` (Gleiten, Überblenden, atmender Spalt, Passwortfeld, 1x/2x), Modul 42-bootsplash legt es ab, `zen bootsplash` schaltet nach Rückfrage ein, `zen doctor` meldet den Stand. Details: `docs/module/bootsplash.md` |
| Docks und Bildschirm über USB | fertig | direkt auf dem Pi (Argon ONE UP) gebaut: zenos-dock, udev-Regel 73-zenos-dock (nur Markierung für systemd), Benutzerdienst zenos-dock.service, Modul 84-dock, Abschnitt in zen doctor. Befund und Mitteilung am Gerät mit dem i-tec-Dock geprüft; der Weg über udev nach install.sh. Details: `docs/module/dock.md` |
| Bluetooth im System-Menü | fertig | direkt auf dem Pi gebaut: BluetoothQuelle (Quickshell.Bluetooth), BluetoothAbschnitt und bluetooth.js, Symbole, Paket bluez mit Modul 36-bluetooth, zen doctor. Headless hell und dunkel angesehen, Start-Test ohne Befund; Koppeln mit einem echten Gerät steht aus. Details: `docs/module/bluetooth.md` |
| x86-Rechner: Installations-ISO mit Calamares | in Arbeit, ungetestet | Entscheid Zeno vom 18.10.2026: grafischer Installer, einfache Installation, nichts von Ubuntu Desktop, «Ubuntu» nirgends sichtbar. `image/x86/bauen.sh` baut ein eigenes ISO (System-Schicht mit zenOS, Live-Schicht mit Calamares), ersetzt den Stick aus Ubuntu Desktop (`image/x86-stick.sh`, wird entfernt). Noch nie gebaut. Stand und nächste Schritte: unten «Stand», 18. Oktober 2026 |
| Öffentlicher Bildschirm (Geräteprofil `anzeige`) | fertig, nicht abgenommen | Zenos Auftrag vom 15.10.2026: MANIFEST (Grundsatz 0, Leitplanke «Ausnahme Anzeigegerät»), `zenos-anzeige`, `zen anzeige`, Anzeige-Konto ohne Rechte, greetd `[initial_session]` nur mit Profil, eigene labwc-Sitzung, Ersatzbild, polkit-Regel, Firewall-Regeln wie SSH, Modul und doctor `77-anzeige`, Updates «ruhig». Einheitentests grün; `test/container/anzeige-e2e.sh` geschrieben, nicht gelaufen (kein Docker auf dem Bau-Rechner). Details: `docs/module/anzeige.md` |

## Wo gebaut wird

Der Bau lief nicht auf dem Pi, sondern auf dem Mac: Claude Code wurde dort gestartet. Linux-Tests laufen in einem
Docker-Container mit Ubuntu 26.04 arm64 (gleiche Architektur wie der Pi, mit systemd, headless labwc und Quickshell),
siehe `test/container/`. Was nur auf echter Hardware prüfbar ist (Grafik über den Pi-Treiber, greetd auf dem VT,
I2C/GPIO des Argon ONE, Tastatur), ist pro Modul unter «am Pi prüfen» notiert.

## Stand

**18. Oktober 2026: Installations-ISO für x86 (in Arbeit, hier weitermachen).** Entscheid Zeno: Für x86 einen
grafischen Installer und eine einfache Installation, bei der nichts von Ubuntu Desktop mitkommt und «Ubuntu» nirgends
zu sehen ist; Ubuntu bleibt vorerst der Unterbau. Grund: Der Stick aus dem ISO von Ubuntu Desktop installierte auch in
der kleinsten Auswahl 1550 Pakete und 13 Snaps (GNOME, Firefox-Snap, App Center, whoopsie, ubuntu-report,
ubuntu-insights), und sein Installer sagt «Ubuntu». Einen eigenen Branch für x86 gibt es nicht und braucht es nicht
(gleicher Code, Unterschiede zur Laufzeit).

Geschrieben (auf `dev`, noch nie gebaut):
- `image/x86/bauen.sh`: debootstrap `resolute`, `ubuntu-server` wie auf dem Pi, Kernel, Firmware, GRUB und shim
  (signiert), dann `install.sh --image` und dieselben Prüfungen wie `image/bauen.sh`. System-Schicht
  `casper/zenos.squashfs` (kommt auf die Platte), Live-Schicht `casper/zenos.live.squashfs` (overlayfs: casper,
  Calamares, Installer-Sitzung), ISO nur UEFI mit shim und `gcdx64.efi` von Ubuntu. Testbau auch in GitHub Actions
  (Ausnahme zur Regel beim Pi-Image, weil amd64 auf dem Pi nicht geht).
- `image/x86/calamares/`: Ablauf und Module nach Lubuntu 26.04, Branding mit Platzhaltern aus `tokens.json`, Folien;
  `geoip` aus, `uploadServer: none`, LUKS2 vorgewählt mit unverschlüsselter `/boot`, Starteintrag «zenOS».
- `image/x86/live/`: Installer-Sitzung (labwc als root auf tty1, nur Calamares), Abgleich der Tastaturbelegung,
  `abschluss` (Starteintrag «zenOS», Rückfallpfad EFI/BOOT mit shim, `grub2/update_nvram` false, SSH-Schlüssel),
  `protokoll`.
- `image/x86/iso/`: Startmenü des ISO. `test/x86/qemu-test.py`: Start in QEMU mit Secure Boot, Bildschirmfotos,
  erfolgreich, wenn Calamares erscheint. `system/grub/zenos-distributor.cfg`: Startmenü «zenOS», EFI-Ordner bleibt
  `ubuntu` (signierter GRUB sucht fest dort).

Nächste Schritte, in dieser Reihenfolge:
1. **Workflow an seinen Platz:** Der GitHub-Zugang auf dem Pi hat das Recht `workflow` nicht, der Push von
   `.github/workflows/x86.yml` wurde abgelehnt. Die Datei liegt deshalb vorübergehend unter
   `image/x86/x86-workflow.yml`. Am Rechner mit dem Recht (oder nach `gh auth refresh -h github.com -s workflow`):
   `git mv image/x86/x86-workflow.yml .github/workflows/x86.yml`, die drei Kopfzeilen «VORÜBERGEHEND HIER» löschen,
   committen, pushen. Dann startet der Testbau (etwa eine Stunde).
2. **shellcheck rot:** SC2016 in `image/x86/bauen.sh` bei `info "Kernel …"` (`-f='${Version}'` ist das Format von
   dpkg-query). Hinweis `# shellcheck disable=SC2016` davor, wie in `image/bauen.sh`. Bis dahin ist die Prüfung auf
   `dev` rot; sonst war sie grün.
3. **Testbau auswerten:** Artefakt `x86-testbau-bilder` (Bildschirmfotos, `seriell.log`, `install.log`), Fehler
   beheben, bis Calamares mit Secure Boot erscheint.
4. **Vollständige Installation in QEMU** (Tasten über QMP `send-key`), danach Start von der Platte mit Passphrase;
   prüfen, dass `/var/log/zenos/installer-calamares.log` keine Passwörter enthält.
5. **Altes Verfahren entfernen:** `image/x86-stick.sh`, `image/x86/README`, `autoinstall.yaml`, `einrichten.sh`,
   `installer/`, `test/einheiten/x86-stick.test.py`, Eintrag in `scripts/lib/sensible-pfade`; Texte anpassen in
   `.github/workflows/image.yml` (Versionshinweise), `README.md`, `ROADMAP.md` (GNOME als Rückfall-Sitzung entfällt),
   `docs/funktionen.md`, `docs/sicherheit.md`, `docs/architektur.md`, `docs/module/kennung.md`, `image/README.md`,
   `docs/image-und-releases.md` («Bürorechner (x86)» neu), `ANLEITUNG.md` H, `CHANGELOG.md`,
   `scripts/doctor.d/74-pc.sh` (Hinweis auf den Stick).
6. **Hosting und Releases:** Das ISO wird grösser als 2 GiB (GitHub-Grenze für Release-Dateien). Zeno will es auf
   zenos-linux.com anbieten; die Prüfsumme bleibt auf der Release-Seite. Offen: Darf die Domain ins Repo (Regel 1
   nennt Hostnamen), Upload von Hand oder aus GitHub Actions, Bau aus signierten Tags in `image.yml`, Quellcode der
   Pakete des ISO (`image/quellen.sh` kennt nur die Paketliste des Pi).
7. **Abnahme am EliteDesk:** Installation, Passphrase mit Startbild, Login von zenOS, Starteintrag «zenOS» in der
   Firmware (HP: `F9`), `zen doctor` Abschnitt «PC». Rechner vom alten Stick neu installieren.

Ungeklärt: Verschlüsselung nur vorgewählt oder erzwingen (`docs/sicherheit.md` nennt sie auf dem Bürorechner Pflicht;
Calamares kann sie nicht erzwingen, nur die Installation abbrechen, wenn sie fehlt). pollinate aus `ubuntu-server`
geht beim ersten Start zu entropy.ubuntu.com (auch auf dem Pi) – prüfen und entscheiden. Den Tag `v0.1.0-rc8` gibt es
nicht, obwohl CHANGELOG und Doku ihn nennen. Auf dem Pi ist keine Git-Identität eingetragen; die Commits liefen mit
`git -c user.name=Zeno -c user.email=34447646+Zenovs@users.noreply.github.com`.

**13. Oktober 2026:** Nach `v0.1.0-rc2` kamen der signierte Update-Kanal, Energie, die Systemkennung zenOS, das Image
als eigenständige Distribution (Release-Seite, Quellcode) und die Fensterübersicht mit Wischen dazu. `v0.1.0-rc4` ist
der erste signierte Release-Kandidat (Image-Bau scheiterte, behoben), `v0.1.0-rc6` (rc5 übersprungen) das erste Release
mit Image, `v0.1.0-rc7` bringt den zen Installer. `v0.1.0-rc8` bringt den Installer-Stick für x86-Rechner, Bluetooth
und Docks; den Tag signiert Zeno (`scripts/release-signieren.sh`). Danach die Abnahme auf echter Hardware (Argon ONE UP
und ein x86-Rechner) und `v0.1.0` (`ROADMAP.md`). Rund 1600 Einheitentests. Der Rest dieses Abschnitts beschreibt den
Stand von rc1/rc2.

Alle Module sind gebaut und im Container getestet (Ubuntu 26.04 arm64 mit systemd, headless labwc, echte
PAM-/logind-Sitzungen). Die Abnahme auf dem Pi steht aus: `ANLEITUNG.md`, Abschnitte C bis E. Pro Modul steht unter
«Am Pi prüfen» in `docs/module/<modul>.md`, was nur echte Hardware zeigt.

Gemessen im Container (nicht auf dem Pi):
- Frische Installation von GitHub auf nacktem Ubuntu Server 26.04: Exit 0, keine Warnung; zweiter Lauf «0 Änderungen».
  SSH, Netz und Konten unverändert, greetd aktiviert, aber erst nach dem Neustart gestartet.
- `zen update` von GitHub auf ein installiertes System: 5 Änderungen, zweiter Lauf 0; `zen doctor` 0 Fehler.
- Image: `install.sh --image` im Ubuntu-Pi-Image, 1481 MiB mit `xz -9` (72 % der 2-GiB-Grenze), ohne
  SSH-Hostschlüssel, ohne proprietäre Apps, ohne Benutzerdaten. Auf GitHub (Tag `v0.1.0-rc1`) gebaut in 15:29 Minuten,
  1484 MiB, als Workflow-Artefakt (kein Release).
- `scripts/pruefen.sh`: shellcheck, JSON-Schemas, Hex- und sh-c-Regel, damals rund 300 Einheitentests, qmllint,
  gitleaks, Start-Test der Oberfläche – sauber, auch in der CI auf GitHub.

Abnahme in einer echten VM (lima/Apple Virtualization, Ubuntu 26.04 arm64, virtio-gpu mit Mesa, statt des Pi):
- Installation genau nach ANLEITUNG B–D, Neustart, echter greetd-Login auf VT 7, Einrichtung, echte Installation von
  Chrome 154, VS Code, 1Password, 1Password-CLI und coremail, drei Touren durch die Testliste E.
- 21 bestätigte Befunde, darunter einer hoch (Leitplanke beim Teilen in Chrome kurz aus), alle behoben und in der VM
  nachgeprüft: `zen update` von GitHub (92 Änderungen, zweiter Lauf 0), Freigabe in 1663 empfangenen Bildern aus
  10 Chrome-Sitzungen ohne Mitteilungsinhalt, neue Bildmarke an allen Stellen mit echter Grafik.
- Tag `v0.1.0-rc2` mit Bildmarke und Behebungen; `v0.1.0-rc1` bleibt der Stand des Bauauftrags.

## Entscheidungen während des Baus

- **Gebaut auf dem Mac statt auf dem Pi**, getestet in Docker (`test/container/`). Deshalb führt Zeno `install.sh` auf
  dem Pi selbst aus (ANLEITUNG C); die sudo-Regel aus B12 braucht es nur noch für Nacharbeit mit Claude Code auf dem Pi.
- **Quickshell** fehlt in den Ubuntu-26.04-Paketquellen → Quellbau v0.3.1 (Commit `1a4716c`), fest eingetragen; neu
  gebaut nur bei anderem Commit oder anderer Qt-Version (private Qt-APIs).
- **Schriften** liegen im Repo unter `assets/fonts/` (Geist v1.7.2, Instrument Serif `65c0ef2`, OFL), Quellen und
  Prüfsummen in `assets/fonts/QUELLEN.md`.
- **Git-Identität** im Repo: GitHub-noreply-Adresse, damit keine persönliche E-Mail in öffentliche Commits gelangt.
- **Ubuntu 26.04 hat uutils coreutils und sudo-rs:** `install -D` ersetzt Symlinks im Zielpfad durch Ordner, deshalb
  legt zenOS Elternordner selbst an. Die Testumgebung nutzt sudo-rs wie Ubuntu Server.
- **Dienste starten bei der Paketinstallation nicht** (temporäre policy-rc.d, nur während des eigenen dpkg); greetd
  läuft erst nach dem Neustart, SSH bleibt unberührt. `dbus reload` bleibt erlaubt (polkit).
- **systemd-Benutzereinheiten unter `/etc/systemd/user`**: systemd 259 durchsucht `/etc/xdg/systemd/user` ohne
  `XDG_CONFIG_DIRS` nicht.
- **Logik für Modi und Zustände läuft in Quickshell** (C5-Frage), Anbindung nach aussen über kleine Hilfsprogramme.
- **Notfall-Sperre mit swaylock**, falls die Oberfläche nicht antwortet: Die automatische Sperre darf nie ausfallen.
- **Mitteilungen ohne Zustand gesammelt zur vollen Stunde** (`gebuendelt-60`, «Ruhe ist der Normalzustand»).
- **Tastenkürzel:** Super+Links/Rechts für Hälften, Super+Oben/Unten bleiben für kitty (Entwurf 2: «Super+↑↓ zwischen
  Befehlen»); Super+Enter maximiert.
- **Freigabe:** xdg-desktop-portal-wlr teilt ganze Bildschirme; Label «Dieser Bildschirm wird geteilt».
- **Apps aus der Oberfläche in eigenen systemd-Einheiten**, damit sie einen Neustart der Oberfläche überleben.
- **Ubuntu motd-news und apt-news aus**, VS Code mit `TelemetryLevel` off (Leitplanke «keine Telemetrie»); umkehrbar,
  siehe `docs/sicherheit.md`.
- **Argon-Abschaltsignal** als system-shutdown-Hook wie im Original-Skript (nur bei poweroff/halt, nur mit Argon).
- **Kanal:** Pi und Image folgen `dev`, solange `main` nur den Start-Commit trägt. Überholt: Seit dem signierten
  Kanal folgt das Image dem Kanal seines Tags (`stabil` bzw. `vorschau`), siehe `docs/image-und-releases.md`, «Name,
  Version und Kanal».
- **Tags `v0.1.0-rc1` und `v0.1.0-rc2`** gesetzt, obwohl die Abnahme auf dem Pi aussteht: Die Testliste braucht
  einen Tag für `zen rollback`, und der Workflow baut damit das Image nur als Artefakt, ohne Release. rc2 enthält die
  neue Bildmarke und die Behebungen aus der VM-Abnahme.
- **Neue Bildmarke «Zwei Steine»** nach Zenos Spezifikation (`docs/bildmarke.md`); die Bogen-Wasserzeichen der
  alten Marke sind entfallen. Bootsplash gebaut, aber nicht eingeschaltet (Boot-Kommandozeile = Rückfrage).
- **Login-Bildschirm dunkel nach 1 Minute** (Zenos Entscheid vom 06.10.2026, war ein offener Punkt): am Netzteil wie
  am Akku, die erste Taste, der erste Klick oder die erste Berührung weckt nur und wird verworfen. Gebaut in
  `shell/greeter/Bildschirm.qml` mit wlopm direkt aus dem Login; in der Sitzung bleibt «dunkel heisst gesperrt».
  Ausfallsicher: Was scheitert, lässt den Bildschirm an. Im Container mit `test/container/login-e2e.sh` geprüft, am
  Gerät abzunehmen (`docs/module/energie.md`, «Bildschirm aus am Login-Bildschirm»).
- **Ein/Aus-Taste am Login-Bildschirm weckt nur** (Zenos Entscheid vom 08.10.2026, war ein offener Punkt): Die
  Oberfläche des Logins hält einen logind-Hemmer «handle-power-key», solange sie läuft (`zenos-energie hemmer-login`,
  `shell/greeter/EinAusTaste.qml`); polkit erlaubt ihn der Sitzung des Logins ohne eigene Regel. Dunkel weckt ein
  kurzer Druck, hell bewirkt er nichts; ausgeschaltet wird über «Ausschalten» oder langes Drücken. Ausfallsicher:
  Ohne Hemmer schaltet logind wie bisher aus, der Notfall-Login nimmt keinen. Im Container mit
  `test/container/einaus-e2e.sh` geprüft (ohne echtes `KEY_POWER`), am Gerät abzunehmen (`docs/module/energie.md`,
  «Ein/Aus-Taste am Login-Bildschirm»).
- **Leerer Akku: kontrolliert ausschalten auch während SSH und tmux** (Zenos Bestätigung vom 08.10.2026): Bei 3 %
  wartet `zenos-argon` auf Updates höchstens 5 Min. und warnt alle Terminals über `wall` (`docs/module/energie.md`,
  «Entscheidungen»).

- **x86 über einen Stick zum Selbstbauen** (Zenos Auftrag vom 13.10.2026: «auf x86-Rechnern installieren», dazu
  `v0.1.0-rc8`): Das Ubuntu-ISO ist für eine Release-Datei zu gross (rund 6,5 GB), deshalb baut `image/x86-stick.sh` den
  Stick aus dem offiziellen ISO, statt ein verändertes Ubuntu-ISO zu verteilen. Die Einrichtung im Installer folgt dem
  Bau des Pi-Images (`install.sh --image` im chroot). Zeitzone über geoip des Installers, weil kein fester Ort ins
  Repo darf. Alle Erweiterungen aus dev bleiben (Zenos Entscheid vom 13.10.2026), dazu nur der GRUB-Schutz.
- **Installer im Look von zenOS** (Zeno, 15.10.2026: «sieht genau so aus wie Ubuntu, soll angepasst für zenOS sein»):
  über die offizielle Anpassung des Installers (`whitelabel.yaml`, eigene Schicht im Live-System), nicht mit einem
  eigenen Installer (Grundsatz 1, «Der Rest kommt von Ubuntu»). Dazu der Produktname «zenOS» über `/.disk/info` und
  eine dunkle Live-Sitzung. Texte mit dem Namen des Flavors («Willkommen bei Ubuntu») und das Startlogo bleiben. Dazu
  Downloads vom Hauptspiegel mit Wiederholungen, nachdem die erste Installation am EliteDesk beim Kernel abbrach.
- **Öffentlicher Bildschirm** (Zenos Ja vom 15.10.2026, ohne Antwort auf die drei Entscheide, deshalb die
  Vorschläge): Ausschalten, Neustart und Standby aus der Anzeige-Sitzung gesperrt; Ausweg `Strg + Alt + Shift +
  Rücktaste`; Updates automatisch (die Anzeige-Sitzung gilt als ruhig). Bildschirmzeiten über `wlopm` statt
  `wlr-randr` (schon installiert, schaltet nur die Anzeige). Fenster maximiert ohne Rahmen statt einer Vollbild-Regel.
- **Stick mit dem grafischen Installer von Ubuntu Desktop** (Zenos Entscheid vom 14.10.2026, nach dem ersten Test: «die
  Installation grafisch wie Ubuntu Desktop»): Grundlage ist das Desktop-ISO, zenOS kommt auf Ubuntu Desktop. GNOME
  bleibt installiert, gdm wird beim Einrichten deaktiviert (greetd übernimmt), die Netzumstellung beim ersten Start
  entfällt, weil NetworkManager das Netz schon verwaltet. GNOME im Login von zenOS wählbar zu machen, ist offen.

## Offene Punkte für Zeno

- **Bildmarke:** App-Icon mit zwei flacheren Kachelecken in der Referenz (Absicht?), Farbe der Mono-Zeile im
  Vorschaubild (`#8C887F` ist kein Token), Einrichtung 44 px zeigt mit dem Qt-CurveRenderer an den Übergängen Bogen →
  Gerade einzelne harte Pixel (48 px wären glatt), Bootsplash einschalten (`zen bootsplash aktivieren`), Avatar und
  Vorschaubild auf GitHub hochladen.
- **coremail** (eigenes Repo): legt beim ersten Start einen zweiten Starter an; die nötige Änderung steht in
  `docs/module/m12.md`. zenOS entfernt ihn bis dahin.
- **Abnahme auf dem Pi** nach `ANLEITUNG.md` (C bis E). Danach `CHANGELOG.md` ergänzen und `v0.1.0` taggen (G).
- **`v0.1.0-rc8` signieren** am Mac mit `scripts/release-signieren.sh v0.1.0-rc8` (Touch ID); erst dann baut GitHub das
  Release. Das Update auf rc8 fragt auf den Geräten nach Zustimmung (neuer Rückfrage-Pfad `system/grub/`).
- **Öffentlicher Bildschirm abnehmen** nach ANLEITUNG I, auf dem EliteDesk und dem Pi, mit SlateDesk;
  `test/container/anzeige-e2e.sh` im Testcontainer laufen lassen (auf dem Bau-Rechner fehlt Docker).
- **Abnahme auf einem x86-Rechner** mit dem Stick (ANLEITUNG H): Secure Boot an, LUKS gewählt, Login, Einrichtung,
  `zen doctor` Abschnitt «PC», Testliste E ohne Argon. GNOME als Rückfall-Sitzung fehlt noch.
- **`zen update` auf dev aus Claude Code:** `CLAUDE.md` nennt `zen update --nur-zenos` für den Weg über `dev`. Die Commits
  auf `dev` sind unsigniert, `zen update` verlangt dafür ein getipptes «ja» an einem Terminal; aus Claude Code (ohne
  Terminal) geht das nicht. Was geht: `./scripts/install.sh` aus `~/zenOS`. `CLAUDE.md` anpassen oder den Weg ändern
  ist Zenos Entscheid.
- **Temporäre sudo-Regel** `/etc/sudoers.d/zenos-bau` nach der Testphase löschen (G1), falls angelegt.
- **Safe Browsing Stufe 2 oder 1** in Chrome (Zielkonflikt Sicherheit ↔ «keine Telemetrie», `docs/sicherheit.md`).
- **Firewall:** entschieden (Oktober 2026), standardmässig an; Ausschalten nur über den Schalter in den
  Einstellungen mit Passwort oder `zen firewall deaktivieren` (`docs/module/m11.md`). Am Gerät prüfen.
- **Bootsplash einschalten** mit `zen bootsplash aktivieren` (Boot-Kommandozeile, Pakete, initramfs; der Pi startet
  danach zweimal). Bis dahin zeigt `zen doctor` «Bootsplash vorbereitet, nicht aktiv». Prüfliste in
  `docs/module/bootsplash.md`.
- **WLAN-Menü einschalten** mit `zen netzwerk umstellen` und `sudo reboot` am Gerät (NetworkManager statt netplan
  mit systemd-networkd, WPA3 im WLAN-Treiber aus). Rückweg `zen netzwerk zurueck`. Prüfliste in
  `docs/module/netzwerk.md`.
- **Akku messen (Argon ONE UP)** mit `zen akku freigeben`: Erst dann weckt zenos-argon den Akku-Messchip und
  schreibt Argons Akkuprofil (Register und Risiko in `docs/sicherheit.md`). Bis dahin «nicht freigegeben».
- **Akku im Sperrbildschirm:** Die Sperre zeigt heute keinen Akku. Ein kleines Symbol mit Prozent wäre kein Inhalt
  im Sinn der Leitplanke, berührt aber die Sperre (sicherheitskritisch); eigener Schritt nach Zenos Entscheid.
- **GitHub-Avatar und Vorschaubild** von Hand hochladen: `assets/zeichen/png/github-avatar-500.png` und
  `github-social-preview-1280x640.png` (`docs/bildmarke.md`, Abschnitt «GitHub»).
- **`main`** auf `v0.1.0` vorspulen, damit `git clone` ohne `git switch dev` funktioniert (ANLEITUNG G11–G14); danach
  entscheiden, ob Image und neue Installationen `main` folgen.
- **fish als Login-Shell** (`chsh -s /usr/bin/fish`), damit auch SSH-Sitzungen Eingabezeile, `?` und die Warnung haben.
- **Nubix** hat bis v4.4.4 keinen arm64-Build; ein arm64-`.deb` in der Release reicht, `zen apps` bietet es dann an.
- **Widgets** (Zustandswert `widgets`): was sie zeigen sollen, ist offen.
- **Chrome `AutofillCreditCardEnabled`** ist ab Chrome 156 veraltet. Erledigt am 08.10.2026: Die Richtlinie setzt
  zusätzlich den Nachfolger `AutofillSettings` (Kreditkarten auf allen Seiten gesperrt, der Ersatz laut Googles
  Richtlinienliste); die alte bleibt, solange Google sie auswertet. Belege in `docs/sicherheit.md`,
  «Chrome-Richtlinien». Am Gerät prüfen: Chrome-Punkt in ANLEITUNG E (`chrome://policy`, 14 Richtlinien).
- **`esm-cache` von ubuntu-pro-client** fragt bei `apt update` `contracts.canonical.com` ab; abschalten oder lassen.
- **GitHub:** 2FA im Konto prüfen. Erledigt am 08.10.2026 (per `gh`, mit Zenos Ja): Issues aus, Rulesets
  «Release-Tags» (`v*`, `vertrauen/*`: nicht verschieben, nicht löschen, Ausnahme Admin) und «dev und main» (nicht
  löschen, kein Force-Push), unveränderliche Releases an (ANLEITUNG G2 bis G5).
- **Festplattenverschlüsselung und Backups** auf dem Pi sind Ziel, in 0.1 nicht umgesetzt.
- **Name und Marke vor der ersten Weitergabe:** die Markenrecherche zu «zenOS» und bei Canonical schriftlich anfragen
  oder sich auf die Klausel der IPR-Policy zu den Open-Source-Lizenzen stützen (`docs/image-und-releases.md`, «Name
  und Marke»). Seit auch jedes `-rc` eine öffentliche Release-Seite bekommt (Entscheid vom 06.10.2026), ist das schon
  `v0.1.0-rc4`. Entscheid vom 07.10.2026: die Release-Kandidaten erscheinen so, Name und Marke werden vor
  `v0.1.0` geklärt.
- **sudo ohne Passwort von cloud-init:** Hat der Imager den Benutzer angelegt (bis 2.0.10 oder mit
  «passwordlessSudo») oder kam der Benutzer `ubuntu` aus Ubuntus Vorgabe, gibt es eine Regel ohne Passwort
  (`/etc/sudoers.d/90-cloud-init-users`). `zen doctor` warnt dann («sudo geht ohne Passwort»); zenOS ändert sie nicht.
  Entfernen oder lassen.
