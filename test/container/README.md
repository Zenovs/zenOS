# Testumgebung auf dem Mac

zenOS läuft auf dem Pi, gebaut und getestet wird aber auch auf dem Mac: in einem Docker-Container mit
Ubuntu 26.04 arm64 (gleiche Architektur wie der Pi 5), systemd als PID 1, einem Benutzer `tester` und
einer Oberfläche ohne Bildschirm (labwc headless, Quickshell im Software-Backend).

Der Container ersetzt den Test auf echter Hardware nicht: Es gibt keine GPU-Beschleunigung, kein VT
(greetd lässt sich nicht wirklich anmelden), kein I2C/GPIO (Argon ONE) und keine echte Tastatur. Die
systemd-Benutzerinstanz von `tester` läuft dauernd (linger), weil `docker exec` keine logind-Sitzung
erzeugt; auf dem Pi läuft sie nur während einer Anmeldung (Login oder SSH).

## Bestandteile

| Datei | Läuft auf | Zweck |
|---|---|---|
| `Dockerfile` | Mac | Basis-Image `zenos-test:basis`: Ubuntu 26.04, systemd, sudo-rs (wie Ubuntu Server 26.04), ohne die Docker-eigene `policy-rc.d`, Man-Seiten (auch Deutsch), alle Laufzeitpakete, Prüfwerkzeuge (shellcheck, gitleaks, qmllint, nodejs), Testwerkzeuge (expect, tmux, wtype, foot), Quickshell v0.3.1 vorgebaut, rtkit ohne Prozessgrenze |
| `starten.sh <name>` | Mac | Container starten (oder auffrischen), rtkit einrichten und den Arbeitsstand nach `/home/tester/zenOS` bringen |
| `arbeitsstand.sh` | Container | überträgt den Stand von `/repo` nach `~/zenOS` (von `starten.sh` aufgerufen) |
| `oberflaeche.sh` | Container | labwc + Quickshell ohne Bildschirm (direkt oder als Sitzung wie auf dem Pi), Bildschirmfotos, IPC, hell/dunkel, Tastatureingaben |
| `holen.sh <container> <ordner>` | Mac | Bildschirmfotos aus dem Container holen |
| `gesten-e2e.sh [schritt …]` | Container (root) | Ende-zu-Ende-Test des Wischens mit drei Fingern: virtuelles Touchpad, Tastatur und Touchpad mit Tasten über uinput (`gesten/touchpad_uinput.py`, python3-libevdev), udev von Hand, `install.sh` zweimal, Rechte der Knoten, Dienst `zenos-gesten` (Socket, Erkennung, Hotplug), labwc über logind in einer Sitzung auf seat0 (`gesten/beobachter.qml`), die Oberfläche (Übersicht auf und zu, polkit-Dialog und Menü der Leiste gehen vor, Sperre) und der Rückweg über den Notschalter (auch mit laufendem Messmodus); Schritte im Kopf der Datei |
| `login-e2e.sh [schritt …]` | Container (tester) | Ende-zu-Ende-Test des Bildschirms am Login-Bildschirm: labwc ohne Bildschirm mit `shell/greeter.qml`, Attrappe von greetd (`login/greetd_attrappe.py`), wtype und wlrctl; eine Minute ohne Eingabe, Tippen beginnt sie neu, die erste Taste und der erste Klick wecken nur, eine gehaltene Wecktaste wiederholt sich nicht ins Feld, auch nicht mit Shift, Alt, AltGr oder Super dazu, Fehler von wlopm lassen den Bildschirm an (Schritte im Kopf der Datei) |
| `sperre-e2e.sh [schritt …]` | Container (tester) | Ende-zu-Ende-Test der Wecktaste der Sperre: labwc ohne Bildschirm mit der Oberfläche aus `~/zenOS`, echte Sperre (ext-session-lock) und PAM (Passwort `tester`), dunkel über `zenos-bildschirm aus`, wtype; die erste Taste weckt nur, eine gehaltene Wecktaste (auch Return) wiederholt sich nicht ins Feld, auch nicht mit Shift, Alt, AltGr oder Super dazu, eine andere Taste kommt an, hell wird nichts verworfen. Fehlversuche zählt das Journal (pam_unix); Schritte im Kopf der Datei |
| `einaus-e2e.sh [schritt …]` | Container (root) | Ende-zu-Ende-Beleg der Ein/Aus-Taste am Login-Bildschirm: der Login als `_greetd` über `zenos-greeter` in einer über PAM (`greetd-greeter`) gestellten Sitzung der Klasse `greeter` auf seat0, Attrappe von greetd; Hemmer «handle-power-key» bei logind ohne eigene polkit-Regel (Gegenprobe ohne Sitzung), `XF86PowerOff` über wtype weckt nur, nach Anmeldung und Absturz kein Hemmer, Notfall-Login ohne Hemmer. Bewusst ohne `KEY_POWER` über uinput (logind der colima-VM sähe das Gerät); Schritte im Kopf der Datei |
| `kanal-e2e.sh <schritt>` | Container (root) | Ende-zu-Ende-Test des signierten Kanals: eigenes origin über https mit Wegwerf-CA und Wegwerf-Schlüsseln, der Übergang von `v0.1.0-rc3` mit dessen altem `zen update` (in einem frischen Container aus `zenos-test:installiert`, ohne `install.sh` aus `~/zenOS`), `zen update`, `zen rollback`, Rückweg, Abbruch mit Neustart, Notweg, Automatik (Timer, Zeitpunkt, gestellte Sitzung auf seat0 mit echter Sperre, Bestätigung nach Neustarts; Schritte im Kopf der Datei) |
| `basis-e2e.sh <schritt>…` | Container (root) | Ende-zu-Ende-Test der Basis-Updates (`zenos-basis`): lokale Paketquelle mit Attrappen-Paketen, Automatik, `zen update --nur-basis`, Kernel-Attrappe, geschütztes Paket, Abbruch mitten in dpkg, Stopp der Prüfung mitten in `dpkg --configure -a`, Sperren gegen Kanal und `install.sh`, greetd startet nicht neu (siehe «Basis-Updates Ende zu Ende») |
| `installer-e2e.sh <schritt>…` | Container (root) | Ende-zu-Ende-Test des zen Installers (`zenos-installer`): selbst gebautes Test-Paket mit Dienst, Standard für .deb (gio, xdg-mime), ansehen als tester, Installieren und Entfernen über `sudo zenos-installer-bedienen` mit den echten Units, geänderte Datei und anderer Plan werden abgelehnt (Schritte im Kopf der Datei) |

## Basis-Image bauen

Quickshell wird nicht im Dockerfile gebaut, sondern liegt als `cache/usr-local.tar` daneben (gitignoriert).
Das Archiv enthält `/usr/local` eines Containers, in dem Quickshell v0.3.1 gebaut wurde (Pfade `local/…`:
`bin/quickshell`, `lib/qt6/qml/Quickshell`, `share/zenos/quickshell.version`). Neu erzeugen: in einem
Container aus diesem Dockerfile ohne die `ADD`-Zeile `scripts/module/25-quickshell.sh` laufen lassen und
danach `tar -C /usr -cf /srv/usr-local.tar local` herauskopieren.

```
docker build -t zenos-test:basis test/container
```

Ein neues Image mit demselben Namen ändert laufende Container nicht; sie laufen mit dem alten Image weiter,
bis sie neu gestartet werden. Sicherer ist, unter einem anderen Namen zu bauen, einen Container daraus zu
prüfen und erst dann umzubenennen (`docker tag … zenos-test:basis`).

Wie auf dem Pi: `/usr/bin/sudo` ist sudo-rs (das Paket `sudo` empfiehlt es nur; mit
`--no-install-recommends` fehlte es bisher, deshalb steht es ausdrücklich in der Liste). Die Docker-eigene
`/usr/sbin/policy-rc.d` («exit 101») entfernt der letzte Schritt. Bis dahin verhindert sie Dienststarts beim
Bau; danach setzt `pakete_sicherstellen` wie auf dem Pi die zenOS-Richtlinie (greetd startet nicht,
`dbus reload` bleibt erlaubt). Ein `apt-get install` von Hand startet Dienste im Container jetzt wie auf dem Pi.

Das Ubuntu-Image für Container ist «minimiert» (keine Man-Seiten). Das Dockerfile hebt das nur für die
Man-Seiten auf (wie `unminimize`): Ausschlüsse von dpkg entfernen, die Pakete des Basis-Images mit
Man-Seiten neu installieren, den Platzhalter für `/usr/bin/man` entfernen. So ist es wie auf dem Pi
(Ubuntu Server ist nicht minimiert), und `?` im Terminal findet die Optionen in `man`.

colima hat nur 2 CPUs und 4 GB: Container schlank halten und nach dem Test entfernen.

## Container starten

```
test/container/starten.sh zenos-m1-test
```

Der Name muss mit `zenos-` beginnen. Das Repo ist unter `/repo` nur lesbar eingehängt; `~/zenOS` ist ein
eigener Git-Checkout mit gleichem Branch und Commit, dazu alle nicht committeten und neuen Dateien, so wie
auf dem Pi nach `git clone`. Nochmals `starten.sh` mit demselben Namen frischt `~/zenOS` auf (Änderungen,
die nur im Container gemacht wurden, gehen dabei verloren). Ein anderes Image, etwa ein schon installiertes
System: `ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-m1-test`. `starten.sh` richtet
dabei auch rtkit für den Container ein (siehe «rtkit in Testcontainern»).

Als `tester` arbeiten (Passwort `tester`, sudo über `/etc/sudoers.d/zenos-bau` wie beim Bau auf dem Pi):

```
docker exec -it -u tester -w /home/tester/zenOS zenos-m1-test bash
```

Im Container:

```
./scripts/install.sh        # zweimal: der zweite Lauf meldet «0 Änderungen»
./scripts/pruefen.sh        # shellcheck, JSON-Schemas, Hex-Regel, Einheitentests, qmllint, gitleaks, Start-Test …
zen doctor
```

## Start-Test

```
scripts/pruefen.sh start                 # nur der Start-Test (rund 30 s)
scripts/pruefen.sh --ausfuehrlich start  # dazu alle Warnungen von Qt/Quickshell
```

Startet `shell/shell.qml`, `shell/greeter.qml` und den Notfall-Login (jede kleingeschriebene `.qml`-Datei
unter `shell/` mit `ShellRoot`) nacheinander in labwc ohne Bildschirm, wartet auf «Configuration Loaded»
und wertet das Quickshell-Protokoll aus. In `shell.qml` folgt ein Rundgang über IPC (Thema hin und zurück,
Befehlsfeld mit Apps-Ansicht, Zentrale, Umschalter, jede Einstellungen-Seite, App-Leiste, Fensterübersicht,
Schreibtisch, Einrichtung, Hinweis, Bildschirmfreigabe, zuletzt die Sperre).
Gemeldet werden die gefundenen Zeilen: Ladefehler («Type … unavailable», «is not a type»),
ReferenceError/TypeError, «Cannot assign», «Binding loop», jede Warnung aus einer Datei unter `shell/`,
`console.warn`/`console.error`, gescheiterte IPC-Aufrufe und eine Sperre, die nicht «gesperrt» meldet.
Bekannte harmlose Meldungen stehen mit Begründung in `START_BEKANNT` (pruefen.sh). Hängt ein Einstieg
beim Laden, bricht der Test ihn nach 90 s ab und räumt die Testsitzung samt Kindprozessen weg.

Die Testsitzung ist abgeschottet (eigenes HOME, eigene XDG-Ordner und eigener Sitzungsbus im Temp-Ordner,
HTTP(S) ins Leere, PipeWire-Client ohne `module-rt`, also ohne Anfragen an rtkit) und beginnt wie ein
erster Start. Sie läuft unabhängig von `oberflaeche.sh` und darf auch in einer echten Sitzung auf dem Pi
laufen. Ohne labwc oder Quickshell (z. B. in CI) wird der Teil übersprungen.

Wichtig: `/tmp` ist im Container ein tmpfs. `docker cp` nach `/tmp` landet unsichtbar darunter; für
Dateien, die hinein oder heraus sollen, `/srv/<modul>/` verwenden. Bind-Mounts aus `/private/tmp` des Macs
funktionieren mit colima nicht.

## Oberfläche ohne Bildschirm

Im Container als `tester`:

```
test/container/oberflaeche.sh start                    # ~/zenOS/shell/shell.qml, 1440×900
test/container/oberflaeche.sh thema hell
test/container/oberflaeche.sh bild leiste-hell         # → /srv/bilder/leiste-hell.png
test/container/oberflaeche.sh thema dunkel
test/container/oberflaeche.sh bild leiste-dunkel
test/container/oberflaeche.sh ipc befehlsfeld oeffnen
test/container/oberflaeche.sh bild befehlsfeld "0,0 1440x400"   # nur ein Ausschnitt
test/container/oberflaeche.sh log                      # Ende des Quickshell-Protokolls
test/container/oberflaeche.sh stopp
```

- `start --shell <pfad>` startet eine andere QML-Datei, `start --greeter` die Login-Oberfläche
  (`shell/greeter.qml`, mit `system/greeter/labwc` als labwc-Konfiguration, falls vorhanden),
  `--groesse 1920x1080` eine andere Auflösung.
- Läuft die Shell aus `~/zenOS`, ist `ZENOS_CODE=~/zenOS` gesetzt; die Oberfläche nimmt dann Skripte
  und Vorlagen aus dem Arbeitsstand statt aus `/opt/zenos`.
- Die Schriften aus `assets/fonts` werden nach `~/.local/share/fonts/zenos-test` kopiert, solange sie nicht
  systemweit installiert sind (Modul 30).
- `thema` ruft `thema.setzen` per IPC auf; ohne laufende Shell schreibt es `erscheinungsbild` in
  `~/.config/zenos/einstellungen.json`.
- `ipc` meldet Fehler (unbekanntes Ziel, falsche Argumente) mit Exit 1. Quickshell v0.3.1 selbst beendet
  `quickshell ipc call` in diesen Fällen mit Exit 0 und schreibt die Meldung auf stdout.
- `log` zeigt das Protokoll ohne Farbcodes. Eine Auswertung wie im Start-Test macht `scripts/pruefen.sh start`.
- `starte kitty` startet ein Programm in der Sitzung (Protokoll in `/srv/oberflaeche/`).
- `tippe tester` und `taste Return` geben Text und Tasten über wtype ein (z. B. das Passwort in die Sperre).
  wtype kennt kein `--`; Text, der mit `-` beginnt, lehnt `tippe` ab. Tastenkombinationen schreibt man mit `+`,
  z. B. `taste super+l` oder `taste ctrl+alt+t` (Modifikatoren: super, ctrl, alt, shift).
- Der erste virtuelle Tastendruck nach dem Start von labwc geht verloren. `tippe`/`taste` senden deshalb einmal
  pro Sitzung vorab ein harmloses `Shift_L`.
- Im Software-Backend fehlen `MultiEffect` und `RectangularShadow` (brauchen RHI). Schatten dort nicht
  beurteilen. `Shape` mit `preferredRendererType: Shape.CurveRenderer` rendert sauber.
- GTK3-Apps mit Symbolen (Thunar, GTK-Dateiauswahl) brechen im Container ab: gdk-pixbuf 2.44 lädt jedes Bild über
  glycin in einer bwrap-Sandbox, und bwrap kann im Container kein Loopback im eigenen Netz-Namespace einrichten
  («RTM_NEWADDR: Operation not permitted»). Auf dem Pi ist die Sandbox vorgesehen (AppArmor-Profile für glycin im
  Paket apparmor); dort am Gerät prüfen.
  Prüfbar bleibt, dass sie gestartet werden (Journal: `app-zenos-oeffnen-….scope`, Befehlszeile der App).
  Thunar liest vor dem Abbruch noch `~/.config/Thunar/uca.xml` (fehlt einer Aktion die `unique-id`, schreibt es die
  Datei neu); so lässt sich prüfen, ob es die Datei annimmt. Thunar dabei nicht aus `~/zenOS` starten: Der Abbruch
  legt `core.*` im Arbeitsordner ab, und `install.sh` kopiert sie sonst nach `/opt/zenos`.
- Mausklicks: `wlrctl pointer move -3000 -3000`, dann `wlrctl pointer move X Y` und `wlrctl pointer click left`
  (Paket wlrctl, im Basis-Image nicht enthalten).

## Sitzung wie auf dem Pi

```
./scripts/install.sh                                   # Einheiten, /opt/zenos, ~/.config/labwc …
test/container/oberflaeche.sh start --sitzung          # labwc → autostart → zenos-sitzung.target
test/container/oberflaeche.sh status                   # Target und Dienste (shell, idle, kanshi)
zen lock                                               # wie per SSH, auch aus einem anderen docker exec
test/container/oberflaeche.sh ipc sperre status        # gesperrt
test/container/oberflaeche.sh tippe tester
test/container/oberflaeche.sh taste Return             # entsperrt
test/container/oberflaeche.sh log 40                   # Journal von zenos-shell.service seit dem Start
test/container/oberflaeche.sh stopp                    # stoppt das Target, labwc und die Umgebung
```

- labwc bekommt einen eigenen Konfigurationsordner (`/srv/oberflaeche/labwc-sitzung`) mit Verweisen auf
  alles aus `~/.config/labwc` ausser `autostart`. Das eigene autostart setzt die Auflösung und
  `QT_QUICK_BACKEND=software` für die systemd-Benutzerdienste (kein GPU im Container) und ruft dann das echte
  `~/.config/labwc/autostart` (`system/labwc/autostart`), das `zenos-sitzung.target` startet.
- Die Oberfläche läuft als `zenos-shell.service` aus `~/.config/quickshell` → `/opt/zenos/shell`, nicht aus
  `~/zenOS`. Änderungen erst mit `./scripts/install.sh` übernehmen (install.sh startet die Oberfläche danach neu;
  gesperrt lädt sie nach dem Entsperren neu).
- `ipc`, `thema`, `bild` und `status` finden die Oberfläche auch nach einem Neustart durch systemd
  (`kill` der Quickshell: `Restart=always`, neue PID aus `systemctl --user show -p MainPID`).
- Wie `zenos-sitzung` löscht der Start den Marker `$XDG_RUNTIME_DIR/zenos/gesperrt`.

Bilder auf den Mac holen und ansehen:

```
test/container/holen.sh zenos-m1-test ~/Desktop/zenos-bilder
```

Jede Oberfläche in hell und dunkel prüfen und mit Entwurf 2 vergleichen.

## rtkit in Testcontainern

`install.sh` installiert rtkit (PipeWire bekommt darüber Echtzeitpriorität). rtkit begrenzt sich auf 3
Prozesse seiner UID (`RLIMIT_NPROC`). Der Kernel zählt diese Grenze über alle Container der colima-VM, und
Container desselben Images teilen sich die UID von rtkit. Läuft rtkit schon in einem anderen Container,
scheitert im nächsten `pthread_create` (Journal: «pthread_create failed: Resource temporarily unavailable»),
und rtkit nimmt Anfragen an, ohne sie je zu beantworten. Jeder PipeWire-Client wartet dann je Wert 25 s
(«RTKit error: org.freedesktop.DBus.Error.NoReply»). Kommt dabei keine Verbindung zu PipeWire zustande,
wartet Quickshell im Hauptthread und antwortet bis zu 75 s auf nichts, auch nicht auf IPC. So scheiterte
der Start-Test in Containern aus `zenos-test:installiert` am ersten IPC-Aufruf («thema wechseln»). Auf dem
Pi gibt es nur einen rtkit, dort tritt das nicht auf.

Im Testcontainer läuft rtkit deshalb ohne diese Grenze: Drop-in
`/etc/systemd/system/rtkit-daemon.service.d/zenos-test.conf` mit `--no-limit-resources`. Neue Basis-Images
bringen ihn aus dem Dockerfile mit; `starten.sh` legt ihn in jedem Container an (auch aus älteren Images)
und beendet einen schon hängenden rtkit. Für einen Container, der mit `docker run` entstand:

```
docker exec <container> mkdir -p /etc/systemd/system/rtkit-daemon.service.d
printf '[Service]\nExecStart=\nExecStart=/usr/libexec/rtkit-daemon --no-limit-resources\n' |
  docker exec -i <container> tee /etc/systemd/system/rtkit-daemon.service.d/zenos-test.conf
docker exec <container> systemctl daemon-reload
docker exec <container> systemctl kill --signal=KILL rtkit-daemon.service   # nur, wenn er schon läuft
```

Prüfen: `busctl --system get-property org.freedesktop.RealtimeKit1 /org/freedesktop/RealtimeKit1
org.freedesktop.RealtimeKit1 MaxRealtimePriority` antwortet sofort mit `i 20`; ein hängender rtkit meldet
nach 25 s «Connection timed out». Der Start-Test von `pruefen.sh` hängt davon nicht mehr ab (PipeWire-Client
ohne `module-rt`).

## Basis-Updates Ende zu Ende

`basis-e2e.sh` prüft `zenos-basis` mit echtem apt, dpkg, systemd, `zen`, `zenos-kanal` und `install.sh`, aber ohne die
Paketquellen von Ubuntu: Die Pakete kommen aus einer eigenen Quelle im Container, und jeder Lauf ist ohne Netz gleich.

```
ZENOS_TESTBILD=zenos-test:installiert test/container/starten.sh zenos-basis-e2e
docker exec -u tester -w /home/tester/zenOS zenos-basis-e2e ./scripts/install.sh   # Arbeitsstand nach /opt/zenos
docker exec zenos-basis-e2e bash /repo/test/container/basis-e2e.sh alle               # rund 2 Minuten
docker rm -f zenos-basis-e2e
```

Einzelne Schritte gehen auch (`einrichten` zuerst, danach in beliebiger Reihenfolge und wiederholbar: Jeder Schritt
bietet neue Versionen an). Langes `docker exec` am besten im Hintergrund starten und das Protokoll lesen.

- **Paketquelle:** `file:/srv/basis-e2e/repo` mit den Taschen `e2e` und `e2e-security` (Release-Dateien wie bei
  Ubuntu, Herkunft `zenos-e2e`, gebaut mit `dpkg-scanpackages`). Sie ist nicht signiert: `Trusted: yes` steht nur in
  `/etc/apt/sources.list.d/zenos-e2e.sources` dieses Wegwerf-Containers, nie im Repo-Code für Geräte. Die Quellen von
  Ubuntu liegen während des Tests unter `/srv/basis-e2e/beiseite`; `aufraeumen` legt sie zurück (die Listen holt erst
  ein `apt-get update` mit Netz wieder). Solange sie fehlen, meldet `72-kennung` in `install.sh` «Sicherheitsquelle
  nicht prüfbar»; das ist der Test, nicht das Gerät.
- **Attrappen** (Architektur `all`, mit `dpkg-deb` gebaut): `zenos-e2e-auto`, `-werkzeug`, `-sicher` (kommt aus
  `e2e-security`), `-dienst` (ein Dienst, den das postinst wie `dh_installsystemd` über `deb-systemd-invoke` neu
  startet), `linux-image-e2e-raspi` (heikel; das postinst schreibt `/run/reboot-required` wie
  `notify-reboot-required`), `zenos-e2e-halten` (das postinst wartet, solange `/srv/basis-e2e/halten` besteht: so
  steht dpkg fest mitten im Lauf), `zenos-e2e-konflikt` und `zenos-e2e-frei`. Dazu `lxd-installer` als Attrappe
  (automatisch installiert): Der Name steht auf der Schutzliste (`_aufraeumen_geschuetzt`), das Paket fehlt im Testbild.
  Ein echtes `lxd-installer` lässt der Test in Ruhe und bricht ab.
- **greetd:** das echte Paket aus `/var/cache/apt/archives` mit neuer Version `…+e2eN` (gleicher Inhalt, echte
  Maintainer-Skripte). Es bleibt nach `aufraeumen` in dieser Version installiert.
- **Timer:** Laufzeit-Drop-ins in `/run/systemd/system/<timer>.d/e2e.conf` halten die Timer von Basis, Kanal und
  apt-daily an; der Test startet die Units selbst. Zeitpunkt «jederzeit», ohne Notschalter (beides vorher gesichert).

Was die Schritte zeigen:

| Schritt | Ergebnis |
|---|---|
| `automatik` | Zeitpunkt «von Hand»: `automatik.json` «wartet», Liste «bereit», Marker `automatik-bereit`. «jederzeit»: `zenos-basis-gelegenheit.service` installiert die drei Pakete. greetd behält InvocationID und Zustand, im Journal steht `invoke-rc.d: policy-rc.d denied execution of restart`, der Dienst der Attrappe startet neu; `greetd` in `/run/reboot-required.pkgs` |
| `zen-update` | `zen update --nur-basis --ja`: Zusammenfassung «Updates: 2, davon Sicherheit: 1», keine Rückfrage, «Ubuntu-Basis: gelungen.»; ohne Updates «aktuell»; danach `install.sh` zweimal als root mit 0 Änderungen |
| `kernel` | Automatik: «zustimmung», nichts installiert, kein Marker; «Jetzt installieren» ohne Passwort Exit 10; `zen update` fragt, «nein» Exit 10, «ja» installiert; `zenos-basis status` und `zen version` sagen «Neustart nötig» |
| `schutz` | full-upgrade würde `lxd-installer` entfernen: «gesperrt», `zen update --ja` Exit 3, `zenos-basis zustimmen` und `installieren --zustimmung` Exit 3, Automatik «gesperrt», nichts geändert. Danach eine Entfernung von `zenos-e2e-frei`: Automatik wartet, ohne Passwort Exit 10, mit «ja» entfernt |
| `abbruch` | `systemctl kill --signal=KILL` der Unit, während dpkg im postinst steht (vorher: Marker, Inhibitor, `policy-rc.d` der Basis da, `apt-get update` scheitert an der Sperre der Paketlisten): dpkg unterbrochen, `policy-rc.d` bleibt liegen, Marker weg, Sperre frei. `apt-get -s` zeigt dann nur `Conf …` (hiesse «aktuell»); das nächste `zen update` holt in der Prüfung `dpkg --configure -a` nach, danach `dpkg --audit` leer, keine `policy-rc.d` |
| `stopp` | dpkg unterbrochen (apt-get im postinst hart beendet), dann `zenos-basis-pruefen.service` gestartet und mitten in `dpkg --configure -a` gestoppt: Die Unit bleibt «deactivating», dpkg läuft weiter (`KillMode=mixed`) und nach dem Loslassen zu Ende; danach Exit 10, kein `apt-get update`, `stand.json` unverändert, keine `policy-rc.d` |
| `sperre` | Während eine Basis-Installation läuft: `zenos-kanal pruefen`, `zen update --nur-zenos` und ein zweites `zenos-basis installieren` Exit 75; ein `install.sh` von Hand (als tester) wartet und beginnt erst danach (sein Vermerk taucht nie während der Basis auf). `flock` auf `kanal.lock` wie ein Lauf des Kanals: Basis Exit 75. Der Vermerk eines `install.sh` von Hand (Attrappe namens `install.sh`, die wartet): Exit 75 mit «install.sh von Hand läuft gerade» |

Grenzen: greetd läuft im Container nicht (kein VT); geprüft wird, dass es nicht gestartet wird und die
`policy-rc.d` den Neustart ablehnt. Der Kanal hält seine Sperre im Test über `flock` auf dieselbe Datei, nicht mit
einem echten Lauf. Ein `install.sh` von Hand **als root** (`sudo -i`) während eines Laufs von Kanal oder Basis wartet
bis zu 15 Minuten und endet dann mit Exit 75: Es nimmt zuerst `/run/zenos-sperre/install.lock` und wartet dann auf
`kanal.lock`, das `install.sh` des Laufs wartet umgekehrt (im Test gesehen; ein Lauf als Benutzer, wie dokumentiert,
nimmt eine andere Sperre und wartet nur auf `kanal.lock`). Ein harter Abbruch hinterlässt keine `letzte.json`; die Oberfläche zeigt bis zum nächsten Lauf das
vorige Ergebnis.

## Bootsplash ansehen

`system/plymouth/zenos/vorschau.sh` (als root) startet plymouthd mit dem x11-Renderer unter Xvfb und macht
Bildschirmfotos des Ablaufs, dazu Passwort- und Fragefeld (Einzelheiten in `docs/module/bootsplash.md`). Es braucht
`plymouth plymouth-label plymouth-x11 xvfb x11-apps xdotool imagemagick`, und die nur in einem Wegwerf-Container:
`plymouth` stösst bei der Installation `update-initramfs` an. Ein privilegierter Container (wie aus `starten.sh`)
sieht die Konsole der colima-VM (`/dev/tty1`); `vorschau.sh` startet plymouthd deshalb ohne Konsolen.

## Image-Modus testen (ohne systemd, wie im chroot)

```
docker run --rm -it -v "$PWD":/repo:ro zenos-test:basis bash
# im Container als root:
bash /repo/test/container/arbeitsstand.sh /repo /opt/zenos
chown -R root:root /opt/zenos
/opt/zenos/scripts/install.sh --image
```

## Aufräumen

```
docker rm -f zenos-m1-test
```

Fremde Container und die colima-VM nie anfassen.
