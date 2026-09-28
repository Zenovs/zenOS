# Bootsplash (Plymouth)

Grundlage: [`docs/bildmarke.md`](../bildmarke.md), Abschnitt «Bootsplash (Plymouth)». Das Theme wird mit gebaut,
eingeschaltet ist es nicht: Dafür braucht es `splash` in der Boot-Kommandozeile und ein neues initramfs, und das ist
laut Bauauftrag Bootloader-Gebiet, nur nach Rückfrage bei Zeno.

## Was gebaut ist

- **Theme** `system/plymouth/zenos/` (Plymouth-Modul `script`): `zenos.plymouth`, `zenos.script` und die Bilder in
  `bilder/`. Hintergrund `grund` (dunkel), in der Mitte das Zeichen mit 64 px, 48 px darunter eine Fortschrittslinie
  (96 × 2 px, Spur `linie`, Füllung `gedaempft`).
  - **Ablauf:** Die zwei Steine gleiten in 300 ms aus 8 Einheiten mehr Abstand zusammen, bis der Spalt 6 breit ist
    (`OutCubic`, dabei von unsichtbar zu voll deckend). Danach blendet der untere Stein in 200 ms von `text` zu
    `salbei`. Dann atmet der Spalt: 6 ± 1 Einheit als Sinus, 3,2 s pro Atemzug, bis Plymouth endet (Login).
  - **Unterpixel:** 1 Einheit sind bei 64 px nur 0,35 px je Achse und Stein. Die Sprites stehen immer auf ganzen
    Pixeln; die Bruchteile stecken in fertigen Bildern (8 Lagen je Stein im Achtelpixel, dazu 9 Farbstufen für das
    Überblenden). So bleibt das Atmen weich, ohne dass Plymouth etwas skalieren muss.
  - **Zeit:** gezählt in Bildern (50 pro Sekunde). Kommen die Bilder langsamer, holt die Zeit zur Uhr aus dem
    Fortschritt von Plymouth auf; Gleiten und Atmen behalten ihr Tempo.
  - **Fortschritt:** die Schätzung von Plymouth (`/var/lib/plymouth/boot-duration`), weich nachgeführt und nie
    rückwärts. Beim Herunterfahren und Neustarten keine Linie, nur das atmende Zeichen.
  - **Passwort** (etwa für eine spätere Verschlüsselung): Statt der Linie erscheint in 120 ms das Feld wie in
    Sperre und Login (`Eingabe.qml`): Beschriftung «Passwort» (`gedaempft`, 13 px), Feld 320 × 44 px, Radius 10,
    Fläche `flaeche`, Rahmen im Akzent (fokussiert), Punkte «•» in Geist 15 px und `text`, ein stehender
    Textcursor. Bei Feststelltaste darunter «Feststelltaste ist aktiv». Die Aufforderung von cryptsetup (englisch)
    erscheint nicht. Fragen mit sichtbarer Antwort zeigen ihren Text und die Antwort in Geist (über das
    Label-Plugin), Meldungen von Plymouth erscheinen klein unter der Linie.
  - **HiDPI:** Bilder in `bilder/1x` und `bilder/2x`. Das Theme nimmt 2x, wenn Plymouth ihm mindestens
    2880 × 1620 Pixel meldet. Ubuntu lässt Plymouth ab dieser Grösse selbst verdoppeln (Gerätefaktor 2, dann
    vergrössert es die 1x-Bilder und die Kanten werden weich); `zen bootsplash aktivieren` setzt deshalb
    `DeviceScale=1`, dann zeichnet Plymouth in Bildschirmpixeln und das Theme scharf in 2x.
- **`erzeugen.py`** (im Theme-Ordner, wird nicht installiert): rendert die Bilder mit rsvg-convert, die Schrift als
  Pfade (Schrift-Klasse aus `assets/zeichen/erzeugen.py`), schreibt `zenos.plymouth` und den Werte-Block in
  `zenos.script`. Farben, Schrift, Pfade der Bildmarke, Radius, Abstände und Bewegung kommen aus
  `shell/theme/tokens.json`, der Spalt aus `assets/zeichen/geometrie.json`; nichts ist von Hand abgeschrieben.
  Neu erzeugen im Container (braucht `librsvg2-bin`, `python3-fonttools`): `python3 system/plymouth/zenos/erzeugen.py`.
  Ein zweiter Lauf schreibt nichts.
- **`vorschau.sh`** (Testcontainer, als root): plymouthd mit dem x11-Renderer unter Xvfb, Bildschirmfotos zu festen
  Zeitpunkten, Passwort- und Fragefeld. Das Theme kommt über `/run/plymouth/themes` aus dem Arbeitsstand; es wird
  nichts eingeschaltet. Braucht `plymouth plymouth-label plymouth-x11 xvfb x11-apps xdotool imagemagick`.
- **`scripts/module/42-bootsplash.sh`**: kopiert `*.plymouth`, `*.script` und `bilder/**/*.png` nach
  `/usr/share/plymouth/themes/zenos/` (0644, Ordner 0755, root) und entfernt dort, was nicht mehr zum Theme
  gehört. Auch im Image. Es installiert keine Pakete, setzt kein Standard-Theme, baut kein initramfs und fasst die
  Boot-Kommandozeile nicht an. Hinweis im Log, wenn sich etwas geändert hat.
- **`scripts/pakete/bootsplash.txt`**: bewusst ohne Pakete (Begründung in der Datei und unten).
- **`zen bootsplash [status|aktivieren|deaktivieren]`** (`scripts/zen.d/bootsplash.sh`):
  - `status` (Standard): vorbereitet, aktiv oder teilweise, dazu Theme, Pakete, Standard-Theme, DeviceScale,
    Kommandozeile (Datei und laufender Start), ob das initramfs älter ist als das Theme, und auf dem Pi, ob neue
    Startdateien in `/boot/firmware/new` warten.
  - `aktivieren`: nur in einem Terminal. Zeigt jeden Schritt samt Kommandozeile vorher/nachher und verlangt die
    Eingabe «aktivieren». Dann, in dieser Reihenfolge: Kommandozeile nach `/var/backups/zenos/` sichern und die
    fehlenden Wörter aus «quiet splash» anhängen (sonst nichts, der Rest bleibt Zeichen für Zeichen); fehlende
    Pakete `plymouth plymouth-label` installieren; Standard-Theme `default.plymouth` → zenos
    (`update-alternatives --install` und `--set`); `DeviceScale=1` zwischen Markierungen in
    `/etc/plymouth/plymouthd.conf`; `update-initramfs -u`. Auf dem Pi kopiert flash-kernel die Kommandozeile dabei
    nach `/boot/firmware/new/`; zur Sicherheit gleicht `aktivieren` sie dort noch an. Welche Wörter es gesetzt hat,
    steht in `/var/lib/zenos/bootsplash`. Ist schon alles eingeschaltet und nur das initramfs älter als das Theme
    (etwa nach `zen update`), bietet es nur den Neubau an.
  - `deaktivieren`: nimmt genau das zurück (Eingabe «deaktivieren»): nur die Wörter, die `aktivieren` gesetzt hat,
    den Block in `plymouthd.conf`, das Standard-Theme, danach `update-initramfs -u`. Die Pakete und das Theme
    bleiben.
  - Boot über GRUB (Bürorechner): `aktivieren` bricht ohne Änderung ab, das kommt mit dem Bürorechner.
- **`scripts/doctor.d/42-bootsplash.sh`**: Theme installiert und gleich wie in `/opt/zenos` (sonst Warnung). Nicht
  eingeschaltet ist ein Hinweis: «Bootsplash vorbereitet, nicht aktiv (zen bootsplash aktivieren nach Rückfrage)».
  Eingeschaltet: ok, dazu ein Hinweis, wenn das initramfs älter ist als das Theme.

## Warum nicht aktiv

- **Boot-Kommandozeile:** Ubuntu zeigt Plymouth nur mit `splash` (Ubuntu-Patch `ubuntu-add-splash-option`,
  `ConditionKernelCommandLine=splash`). Das Server-Image für den Pi hat kein `splash`:
  `console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4
  panic=10 rootwait fixrtc` (aus `ubuntu-26.04.1-preinstalled-server-arm64+raspi.img.xz` gelesen).
- **Wo sie steht:** Ubuntu 26.04 auf dem Pi startet mit piboot-try: `config.txt` hat `os_prefix=current/`, die
  Kommandozeile ist `/boot/firmware/current/cmdline.txt` (nicht `/boot/firmware/cmdline.txt`). Jedes
  `update-initramfs` ruft über `/etc/initramfs/post-update.d/flash-kernel` flash-kernel auf; das schreibt Kernel,
  initramfs und eine Kopie von `current/cmdline.txt` nach `/boot/firmware/new/`. Beim nächsten Start bootet der Pi
  normal, `piboot-try-reboot` startet sofort neu in den Testmodus mit `new/`, und `piboot-try-validate` macht
  daraus `current/`. Scheitert der Test, bleibt `current/`. Der Start nach dem Einschalten läuft also zweimal.
- **Pakete:** Das Server-Image bringt `plymouth` (mit dem Modul `script`) und `plymouth-theme-ubuntu-text` mit, aber
  kein Standard-Theme (`default.plymouth` fehlt) und kein Label-Plugin. `plymouth` stösst in seinem postinst
  `update-initramfs` an (dpkg-Trigger, dracut baut neu, danach flash-kernel wie oben). Deshalb steht es nicht in
  `scripts/pakete/`: 20-pakete installiert jede Liste dort, auch auf einem System ohne plymouth.
- **Label-Plugin nötig:** Plymouth 24.004.60 (Ubuntu 26.04) stürzt mit dem Modul `script` ohne Label-Plugin beim
  ersten Bild ab (`ply_console_viewer_hide` mit NULL in `script_lib_sprite_refresh`), auch mit dem Beispiel-Theme
  von Plymouth, im Container nachgestellt. `plymouth-label` (label-pango, zieht pango, cairo und fonts-ubuntu)
  gehört deshalb zum Einschalten. `plymouth-populate-initrd` nimmt es ins initramfs mit, dazu Geist (Eintrag
  `Font=` in `zenos.plymouth`) für Fragen und Meldungen.
- **Standard-Theme:** Ubuntu wählt das Theme über `update-alternatives` (`default.plymouth`), nicht über
  `plymouthd.conf`. Ein neues Alternativ setzt sich im Modus «auto» selbst, wenn es das einzige ist; deshalb
  registriert install.sh das Theme nicht, sondern legt nur die Dateien ab.

## Einschalten

Nur nach Rückfrage bei Zeno, am besten per SSH und mit Zeit für zwei Neustarts:

```
zen bootsplash                # Stand ansehen
zen bootsplash aktivieren     # zeigt alles, verlangt «aktivieren»
sudo reboot                   # nach Absprache; der Pi startet zweimal
```

Zurück: `zen bootsplash deaktivieren` (verlangt «deaktivieren»), danach wieder zwei Starts. Von Hand, falls nötig:
die Sicherung aus `/var/backups/zenos/boot-firmware-current-cmdline.txt.<zeit>` nach
`/boot/firmware/current/cmdline.txt` kopieren, `sudo update-alternatives --remove default.plymouth
/usr/share/plymouth/themes/zenos/zenos.plymouth`, den Block zwischen den Markierungen «zenOS-Bootsplash» aus
`/etc/plymouth/plymouthd.conf` löschen, `sudo update-initramfs -u`. Notfalls `sudo piboot-try --restore-old`.

## Entscheidungen

- **Aus leichtem Abstand:** 8 Einheiten mehr Spalt am Anfang (Spalt 14 → 6), dazu die Deckkraft von 0 auf 1 im
  selben Zug, damit das erste Bild nicht springt. Farbe zuerst `text` für beide Steine («einfarbig»), dann `salbei`.
- **Atmen:** Spalt 5 bis 7 Einheiten, Sinus, Periode 3,2 s (ein Atemzug = auf und zu). Beginnt nach dem
  Überblenden, läuft auch während der Passwortabfrage (sie wartet, der Start läuft noch).
- **Linie:** 96 × 2 px, 48 px unter dem Zeichen (`abstand` a6), Füllung `gedaempft` statt Akzent: Die Farbe bleibt
  dem unteren Stein vorbehalten, die Linie soll nur leise da sein.
- **Beschriftung:** fest «Passwort» als Bild in Geist, nicht die englische Aufforderung von cryptsetup und
  systemd; genau ein Benutzer, genau eine Platte.
- **Punkte:** Glyphe «•» aus Geist 15 px mit ihrer Breite als Schritt (5 px bei 1x), wie das Passwortfeld in Sperre
  und Login.
- **DeviceScale=1 beim Einschalten:** sonst verdoppelt Plymouth auf 4K-Bildschirmen die 1x-Bilder (weich, im
  Container verglichen). Nur zwischen Markierungen, ein vorhandenes `DeviceScale` von Hand bleibt.
- **Theme-Ordner nur mit Theme-Dateien:** `plymouth-populate-initrd` kopiert den ganzen Ordner des Themes ins
  initramfs; `erzeugen.py` und `vorschau.sh` bleiben im Repo.
- **Pfad `/usr/share/plymouth/themes/zenos`:** fest in `plymouth-populate-initrd` (Name aus `default.plymouth`, Ordner
  darunter). Er steht nicht in der Liste der freigegebenen Pfade des Bauauftrags; die Spezifikation verlangt ihn.

## Im Container geprüft

- `install.sh` zweimal: erster Lauf legt 79 Dateien und 4 Ordner an, zweiter Lauf «0 Änderungen». Zwei fremde
  Dateien, ein fremder Ordner mit leerem Unterordner und ein veränderter Punkt im Zielordner: fünf Änderungen,
  danach wieder 0. plymouth wurde dabei nicht installiert, `default.plymouth` blieb leer.
- `erzeugen.py` zweimal: zweiter Lauf «0 geschrieben».
- `vorschau.sh` bei 1920 × 1080, 3840 × 2160 (Plymouth verdoppelt) und 3840 × 2160 mit `--skala 1` (2x-Bilder):
  Theme lädt ohne Fehler im Protokoll, Ablauf, Passwort (14 Punkte), Hinweis Feststelltaste, Frage mit Text.
- `plymouthd.conf` mit dem Block von `aktivieren`: Plymouth meldet «Device scale is set to 1».
- `zen bootsplash aktivieren/deaktivieren` im Wegwerf-Container mit `/boot/firmware/current/cmdline.txt` aus dem
  Ubuntu-Image und einem Test-`update-initramfs`, das wie flash-kernel nach `new/` kopiert: ohne Terminal Exit 2,
  andere Eingabe bricht ohne Änderung ab; aktivieren setzt «quiet splash», installiert plymouth-label, setzt das
  Standard-Theme und DeviceScale, `new/cmdline.txt` stimmt; zweites aktivieren: «schon eingeschaltet»; nach einer
  Theme-Änderung nur der Neubau; deaktivieren stellt `cmdline.txt` und `plymouthd.conf` byte-genau wieder her
  (md5). Dazu `/boot/firmware/cmdline.txt` ohne Zeilenumbruch am Ende und mit zweiter Zeile, «splash» schon
  vorhanden (nur «quiet» dazu und wieder weg), `plymouthd.conf` mit eigenem `[Daemon]`, und GRUB (Abbruch ohne
  Änderung).

## Am Pi prüfen

Vorher: `zen doctor` zeigt «Bootsplash vorbereitet, nicht aktiv». Nach der Rückfrage und `zen bootsplash
aktivieren`, dann `sudo reboot`:

- Der Pi startet zweimal; beim ersten Start erscheint höchstens der Text-Splash von Ubuntu (altes initramfs), beim
  zweiten das Zeichen. Danach `cat /boot/firmware/current/state` → `good`, `/boot/firmware/new` ist weg.
- Erscheint das Zeichen überhaupt, oder nur Text? `grep -i plymouth /proc/cmdline`, `journalctl -b -u
  plymouth-start` und `plymouth --ping` direkt nach dem Login. Der Pi 5 braucht dafür früh einen DRM-Treiber im
  initramfs (simpledrm vom Firmware-Framebuffer oder vc4); ohne zeigt Plymouth nur Text.
- Ablauf ruhig und flüssig: Zusammengleiten, Überblenden, Atmen; keine Sprünge. Auf 4K scharfe Kanten
  (DeviceScale=1). Die Fortschrittslinie bewegt sich; sie wird ab dem zweiten Start genauer.
- Übergang zum Login (greetd): kein Flackern, keine Textkonsole dazwischen.
- Herunterfahren und Neustart: Zeichen ohne Linie.
- `zen bootsplash` → aktiv, `zen doctor` → ok. `zen bootsplash deaktivieren` und zweimal neu starten: wieder wie
  vorher.
