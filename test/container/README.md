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
| `kanal-e2e.sh <schritt>` | Container (root) | Ende-zu-Ende-Test des signierten Kanals: eigenes origin über https mit Wegwerf-CA und Wegwerf-Schlüsseln, `zen update`, `zen rollback`, Rückweg, Abbruch mit Neustart, Notweg, Automatik (Timer, Zeitpunkt, gestellte Sitzung auf seat0 mit echter Sperre, Bestätigung nach Neustarts; Schritte im Kopf der Datei) |

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
