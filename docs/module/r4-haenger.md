# R4 · Hänger bei «thema wechseln» im Start-Test

## Befund

In Containern aus `zenos-test:installiert` brach `scripts/pruefen.sh start` reproduzierbar beim ersten
IPC-Aufruf des Rundgangs ab («IPC «thema wechseln»: keine Antwort nach 15 s»), auch mit älteren Ständen. In
Containern aus `zenos-test:basis` lief der Test sauber.

## Ursache

Nicht zenOS-Code, sondern ein hängender rtkit im Container, der die Testshell über PipeWire blockiert:

1. `install.sh` installiert seit der Behebung von M2 rtkit (`scripts/pakete/basis.txt`). Im Basis-Image fehlt
   er, deshalb lief der Test dort.
2. rtkit begrenzt sich auf 3 Prozesse seiner UID (`RLIMIT_NPROC`, `/proc/<pid>/limits`: «Max processes 3»).
   Der Kernel zählt diese Grenze über alle Container der colima-VM, und Container desselben Images haben
   dieselbe UID für rtkit (hier 986). Läuft rtkit schon in einem anderen Container, scheitert im nächsten
   `pthread_create` (Journal: «pthread_create failed: Resource temporarily unavailable»). Der Dienst hält
   dann den Namen `org.freedesktop.RealtimeKit1` auf dem System-Bus, beantwortet aber keine Anfrage
   (`busctl … MaxRealtimePriority` → nach 25 s «Connection timed out»; im Container lief nur dieser eine
   rtkit-Prozess).
3. Der PipeWire-Client lädt `libpipewire-module-rt` (`/usr/share/pipewire/client.conf`). Das Modul fragt
   rtkit in einem eigenen Thread «module-rt» nach drei Werten, synchron mit je 25 s Zeitlimit.
4. Die Testshell erreicht ohne laufende Benutzerinstanz kein PipeWire (Errno 112). Quickshell baut den
   Kontext dann sofort wieder ab (`PwCore::start` → `shutdown` → `pw_context_destroy`), und der Abbau wartet
   im Hauptthread auf den Thread «module-rt» (`pw_thread_loop_stop`, Stack mit gdb). Das dauert bis zu 75 s.
   In dieser Zeit beantwortet die Shell auch kein IPC. Der erste Zugriff auf `Pipewire` fällt zeitlich
   mit dem ersten Aufruf des Rundgangs zusammen.

Nachgestellt mit einer kleinen QML-Probe: Der erste Zugriff auf `Pipewire.defaultAudioSink` dauerte 75 088 ms,
ein IPC-Aufruf in dieser Zeit 60 s ohne Antwort. Mit `module.rt = false` dauerte der Zugriff 4 ms.

## Behebung

- **`scripts/pruefen.sh` (Teil start):** Die Testsitzung legt in ihrem eigenen `XDG_CONFIG_HOME`
  `pipewire/client.conf.d/90-zenos-pruefen.conf` mit `context.properties = { module.rt = false }` an. Die
  Testshell braucht keine Echtzeit, der Test hängt damit nicht mehr vom Zustand von rtkit ab. Dazu kommen
  `PIPEWIRE_REMOTE` und `PIPEWIRE_CONFIG_DIR/NAME/PREFIX` nicht mehr aus der aufrufenden Umgebung mit, damit
  die Einstellung sicher greift und die Prüfung auf `pipewire-0` stimmt.
- **`test/container` (Dockerfile, `starten.sh`, README):** Im Testcontainer läuft rtkit ohne diese Grenze
  (Drop-in `/etc/systemd/system/rtkit-daemon.service.d/zenos-test.conf`, `--no-limit-resources`). Das
  Dockerfile bringt ihn in neue Basis-Images mit. `starten.sh` legt ihn in jedem Container an, auch aus
  älteren Images (`ZENOS_TESTBILD=zenos-test:installiert`), und beendet einen schon hängenden rtkit; der
  nächste Aufruf startet ihn über D-Bus neu. Für Container aus `docker run` stehen die Befehle in der README.
  Damit bekommen auch PipeWire, WirePlumber und die Sitzung im Container wieder Antwort von rtkit.

## Echte Sitzung

Nicht betroffen:

- Auf dem Pi gibt es nur einen rtkit. Seine 3 Threads (Hauptthread, Canary, Watchdog) liegen genau in
  seiner Grenze; so ist rtkit gebaut. Die Grenze reisst nur, wenn fremde Prozesse dieselbe UID haben, wie
  hier Container desselben Images auf einem Kernel.
- Die Shell der Sitzung erreicht PipeWire immer (Socket-Aktivierung durch `pipewire.socket`), baut den
  Kontext also nicht ab und wartet nicht auf «module-rt». Gemessen im Container mit hängendem rtkit
  (Anmeldung wie greetd, `PAMName=greetd`): `zenos-ipc thema status` 9 s nach dem Start in 32–58 ms, obwohl
  pipewire, wireplumber und pipewire-pulse zugleich «RTKit error: NoReply» meldeten. Mit funktionierendem
  rtkit: `zenos-ipc thema wechseln` viermal in 30–35 ms, `gsettings color-scheme` und
  `einstellungen.json` folgen jedes Mal. Der Hell/Dunkel-Schalter der Leiste ruft dieselbe Funktion.

## Nebenbefund: Signale aus der Testshell an die echte Sitzung

`zenos-thema` schickte SIGHUP an jedes labwc und SIGUSR1 an jede kitty des Benutzers. Aus der Testshell
(eigenes HOME, frische Dateien) liess das das labwc der echten Sitzung je Lauf dreimal seine Konfiguration
neu lesen (strace: signalfd, danach `rc.xml` und `themerc-override`) und die kitty der Sitzung neu laden.
Harmlos, aber gegen die Abschottung des Tests. Jetzt: SIGHUP an das labwc aus `LABWC_PID` (labwc gibt die
Variable an seine Kindprozesse weiter, `system/labwc/autostart` auch an die Benutzerdienste), ohne gültige
Angabe wie bisher an alle eigenen (z. B. `install.sh` per SSH); SIGUSR1 nur an kitty mit demselben `HOME`
(Umgebung nicht lesbar: zählt mit).

## Getestet (Container Ubuntu 26.04 arm64 aus `zenos-test:installiert`)

- Nachgestellt: `docker run` ohne `starten.sh`, Arbeitsstand, `install.sh` (installiert rtkit), dann
  `pruefen.sh start`: «keine Antwort nach 15 s». Vor `install.sh` (ohne rtkit) sauber.
- Mit hängendem rtkit und ohne erreichbares PipeWire: alte Fassung von `pruefen.sh` dreimal Abbruch bei
  «thema wechseln», neue dreimal ohne Befund; mit PipeWire der Sitzung ebenfalls ohne Befund. Die Testshell
  hat danach keinen Thread «module-rt» mehr.
- `starten.sh` am laufenden Container: Drop-in angelegt, hängender rtkit beendet, `MaxRealtimePriority` in
  24 ms (`i 20`), «Max processes unlimited»; zweiter Aufruf ändert nichts. Gegenprobe ohne Drop-in: rtkit
  hängt sofort wieder, obwohl im Container kein anderer rtkit läuft. Drop-in vor der Installation von
  rtkit (wie im Basis-Image): greift. Die Datei aus dem Dockerfile ist byte-gleich mit der von `starten.sh`.
- `zenos-thema`, Zielauswahl mit echten Prozessen (echtes und zweites labwc, kitty der Sitzung): wie die
  Shell → nur das echte labwc, kitty; wie die Testshell → nur das Test-labwc, keine kitty; ohne, mit
  veralteter oder unsinniger `LABWC_PID` → alle labwc, kitty. In der Sitzung: Hell/Dunkel lädt labwc einmal
  neu, ein neuer Akzent labwc einmal und kitty einmal (SIGUSR1 über ihr signalfd), derselbe Akzent schickt
  kein SIGUSR1. Während `pruefen.sh start`: labwc und kitty der Sitzung unberührt (vorher las labwc je Lauf
  dreimal neu; die alte Fassung mit fremdem HOME schickte der kitty der Sitzung ein SIGUSR1).
- `scripts/pruefen.sh` komplett: alles sauber (shellcheck 60, python 10, json, hex, shc, namen, einheiten
  node 66 · python 90 · fish 136, qmllint, gitleaks, start mit 25 IPC-Aufrufen).
- Beobachtung am Rand: Startet der Test in den ein, zwei Sekunden, in denen `systemctl stop user@1000`
  die Benutzerinstanz abbaut, liegt `pipewire-0` noch ohne Dienst in `/run/user/1000`. Der Test hält
  PipeWire dann für erreichbar und meldet «Failed to connect pipewire context» als Befund. Nur so im
  Container nachgestellt; solange die Benutzerinstanz läuft, hält `pipewire.socket` den Socket.

## Am Pi prüfen

- Nach der Installation und einem Neustart: `journalctl -b | grep -i rtkit` ohne «pthread_create failed»
  und ohne «NoReply»; `busctl --system get-property org.freedesktop.RealtimeKit1 /org/freedesktop/RealtimeKit1
  org.freedesktop.RealtimeKit1 MaxRealtimePriority` antwortet sofort.
- `scripts/pruefen.sh` per SSH nach der Installation: alles sauber, auch der Start-Test.
- Dasselbe, während die Sitzung läuft: Fensterrahmen und kitty flackern nicht, keine Neuladung sichtbar.
- Hell/Dunkel in der Leiste und im Befehlsfeld: sofort, labwc-Rahmen und kitty folgen; neuer Modus mit
  anderem Akzent färbt kitty um.
