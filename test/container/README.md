# Testumgebung auf dem Mac

zenOS läuft auf dem Pi, gebaut und getestet wird aber auch auf dem Mac: in einem Docker-Container mit
Ubuntu 26.04 arm64 (gleiche Architektur wie der Pi 5), systemd als PID 1, einem Benutzer `tester` und
einer Oberfläche ohne Bildschirm (labwc headless, Quickshell im Software-Backend).

Der Container ersetzt den Test auf echter Hardware nicht: Es gibt keine GPU-Beschleunigung, kein VT
(greetd lässt sich nicht wirklich anmelden), kein I2C/GPIO (Argon ONE) und keine echte Tastatur.

## Bestandteile

| Datei | Läuft auf | Zweck |
|---|---|---|
| `Dockerfile` | Mac | Basis-Image `zenos-test:basis`: Ubuntu 26.04, systemd, sudo, alle Laufzeitpakete, Prüfwerkzeuge (shellcheck, gitleaks, qmllint), Quickshell v0.3.1 vorgebaut |
| `starten.sh <name>` | Mac | Container starten (oder auffrischen) und den Arbeitsstand nach `/home/tester/zenOS` bringen |
| `arbeitsstand.sh` | Container | überträgt den Stand von `/repo` nach `~/zenOS` (von `starten.sh` aufgerufen) |
| `oberflaeche.sh` | Container | labwc + Quickshell ohne Bildschirm, Bildschirmfotos, IPC, hell/dunkel |
| `holen.sh <container> <ordner>` | Mac | Bildschirmfotos aus dem Container holen |

## Basis-Image bauen

Quickshell wird nicht im Dockerfile gebaut, sondern liegt als `cache/usr-local.tar` daneben (gitignoriert).
Das Archiv enthält `/usr/local` eines Containers, in dem Quickshell v0.3.1 gebaut wurde (Pfade `local/…`:
`bin/quickshell`, `lib/qt6/qml/Quickshell`, `share/zenos/quickshell.version`). Neu erzeugen: in einem
Container aus diesem Dockerfile ohne die `ADD`-Zeile `scripts/module/25-quickshell.sh` laufen lassen und
danach `tar -C /usr -cf /srv/usr-local.tar local` herauskopieren.

```
docker build -t zenos-test:basis test/container
```

colima hat nur 2 CPUs und 4 GB: Container schlank halten und nach dem Test entfernen.

## Container starten

```
test/container/starten.sh zenos-m1-test
```

Der Name muss mit `zenos-` beginnen. Das Repo ist unter `/repo` nur lesbar eingehängt; `~/zenOS` ist ein
eigener Git-Checkout mit gleichem Branch und Commit, dazu alle nicht committeten und neuen Dateien, so wie
auf dem Pi nach `git clone`. Nochmals `starten.sh` mit demselben Namen frischt `~/zenOS` auf (Änderungen,
die nur im Container gemacht wurden, gehen dabei verloren).

Als `tester` arbeiten (Passwort `tester`, sudo über `/etc/sudoers.d/zenos-bau` wie beim Bau auf dem Pi):

```
docker exec -it -u tester -w /home/tester/zenOS zenos-m1-test bash
```

Im Container:

```
./scripts/install.sh        # zweimal: der zweite Lauf meldet «0 Änderungen»
./scripts/pruefen.sh        # shellcheck, JSON-Schemas, Hex-Regel, qmllint, gitleaks …
zen doctor
```

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
- `starte kitty` startet ein Programm in der Sitzung (Protokoll in `/srv/oberflaeche/`).
- Im Software-Backend fehlen `MultiEffect` und `RectangularShadow` (brauchen RHI). Schatten dort nicht
  beurteilen. `Shape` mit `preferredRendererType: Shape.CurveRenderer` rendert sauber.

Bilder auf den Mac holen und ansehen:

```
test/container/holen.sh zenos-m1-test ~/Desktop/zenos-bilder
```

Jede Oberfläche in hell und dunkel prüfen und mit Entwurf 2 vergleichen.

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
