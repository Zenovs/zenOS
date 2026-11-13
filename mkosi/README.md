# zenOS 1.0: Bau des Images

Hier entsteht zenOS 1.0 als unveränderliches Image aus Debian 13 «trixie» (Konzept: `docs/neubau.md`). Stand:
**Vorschau für die SSD des Argon ONE UP**, mit der Oberfläche von zenOS und Updates über `zen update`. Signierter Start
und eigener Kernel kommen mit 1.0.

## Was hier liegt

| Pfad | Inhalt |
|---|---|
| `mkosi.conf` | gemeinsame Einstellungen, Paketliste mit Gründen, Härtung der Kernel-Befehlszeile |
| `mkosi.sandbox/` | Paketquellen: ein fester Stand von snapshot.debian.org (Backports nur für den Bau von Quickshell) |
| `mkosi.profiles/argon/` | Argon ONE UP (CM5) und Pi 5: Kernel und Firmware von Raspberry Pi, Startpartitionen, Updates |
| `mkosi.profiles/qemu/` | virtuelle Maschine für die Tests: Kernel von Debian, Start über UEFI mit UKI, Updates vom Testserver, signiert mit dem Wegwerf-Schlüssel des Tests |
| `repart/gemeinsam/` | System A (erofs, dm-verity) und seine Prüfsummen |
| `mkosi.build.d/` | Quickshell 0.3.1 aus dem Quellcode; Oberfläche (`shell/`) und Schriften ins Image |
| `mkosi.extra/` | Dateien im System: Login, Sitzung, Sperre, `zen`, Updates, Firewall, Zeit, Netz, Härtung, Chromium |
| `mkosi.postinst` | löscht Dateien von Paketen, die nur als Abhängigkeit kommen; nichts aus den Backports |
| `mkosi.finalize` | /var vorbereiten; setuid, Verbotenes, Quickshell und Signaturprüfung prüfen; Schlüssel und Paketstand ins Image; Overlay des Deckels übersetzen und am Gerätebaum des CM5 prüfen |
| `mkosi.postoutput` | schreibt autoboot.txt (Partition 1) und Kernel, initrd, Gerätebäume, `config.txt`, `cmdline.txt` (Startpartition A) |
| `schluessel/` | Zenos öffentliche Schlüssel für Updates (`argon-allowed-signers`, zwei FIDO2-Schlüssel); ohne sie baut das Image für den Argon nicht |
| `start/config.txt` | Start auf dem CM5 und dem Pi 5 |
| `start/zenos-deckel.dts` | Overlay für den Deckel des Argon ONE UP: GPIO27 als Schalter SW_LID, Zuklappen sperrt (logind) |
| `umgebung/` | Bauumgebung: Debian-Container mit mkosi und QEMU; `bauen-innen.sh` holt und prüft die Quelle von Quickshell |
| `veroeffentlichen.sh` | macht aus einem gebauten Image die Dateien für ein Update und `SHA256SUMS` zum Signieren |
| `signatur-pruefen.sh` | prüft Zenos Signatur eines Stands (oder der Probe) mit dem Code des Argon; signiert nie |
| `test/` | Angriffs- und Starttests in QEMU mit Oberfläche, Update, Notfall-Passwort und Ausschalten nach langer Sperre, Einheitentests des Updates, der Erinnerung, des Notfall-Passworts und des Hardware-Schlüssels, Prüfung der Startpartitionen des Argon-Images |

## Aufteilung der SSD

| Nr. | Bezeichnung | Inhalt |
|---|---|---|
| 1 | `zenos-start` | 64 MB FAT: `autoboot.txt` (welche Startpartition startet) und die Tastaturbelegung |
| 2 | `zenos-start_<version>` | 256 MB FAT: Startpartition A (Kernel, initrd, Gerätebäume, `config.txt`, `cmdline.txt`) |
| 3 | `_empty` | 256 MB FAT: Startpartition B, frei für das nächste Update |
| 4 | `zenos_<version>_verity` | 128 MB: Prüfsummen (dm-verity) von System A |
| 5 | `zenos_<version>` | System A (erofs), beim ersten Start auf 6 GB vergrössert |
| 6, 7 | `_empty` | System und Prüfsummen B, beim ersten Start angelegt |
| 8 | `zenos-notfall` | 32 MB ohne Dateisystem: Nullen, oder mit Notfall-Passwort ein LUKS2-Container, darin nur der Kontoname; beim ersten Start angelegt |
| 9 | `zenos-daten` | `/var` und `/home`, LUKS2, beim ersten Start angelegt, der ganze Rest der SSD |

Der Bootloader liest `autoboot.txt`: Startpartition 2 startet; nach einem Update startet 3 einmal zur Probe
(`tryboot`). Läuft der neue Stand, tauscht `/usr/lib/zenos/update` die beiden Ziffern; sonst startet beim nächsten
Einschalten wieder der alte Stand.

## Bauen

Auf dem Mac, mit Docker über Colima, in einer eigenen Colima-VM «zenos» (einmalig:
`colima start zenos --cpu 6 --memory 6 --disk 80 --vm-type vz`, danach `docker context use colima`).

```
mkosi/bauen.sh argon     # Image für das Argon ONE UP → mkosi/ausgabe/argon/zenos_<version>.raw
mkosi/bauen.sh qemu      # Image für die Tests        → mkosi/ausgabe/qemu/zenos_<version>.raw
mkosi/test/starten.sh    # erster und zweiter Start in QEMU mit Oberfläche und Prüfungen
mkosi/test/update-einheiten.sh
mkosi/test/erinnerung-einheiten.sh
mkosi/test/notfall-einheiten.sh   # Passwortabfrage beim Start und Notfall-Passwort, mit echtem cryptsetup
mkosi/test/schluessel-einheiten.sh   # Hardware-Schlüssel (Attrappen der FIDO2-Werkzeuge, echtes cryptsetup)
mkosi/test/startpartitionen.sh   # Startpartitionen des Argon-Images, vor dem Schreiben auf die SSD
```

Update-Test: einen zweiten Stand bauen und vorbereiten, dann den Test damit starten:

```
ZENOS_AUSGABE=qemu-neu mkosi/bauen.sh qemu --image-version=0.9.2
ZENOS_AUSGABE=qemu-neu ZENOS_VERSION=0.9.2 mkosi/veroeffentlichen.sh qemu
ZENOS_TEST_NEU=0.9.2 mkosi/test/starten.sh
```

Ohne `schluessel/argon-allowed-signers` bricht `bauen.sh argon` ab. Nur für einen Entwicklungsbau, der nie auf ein
Gerät kommt: `mkosi/bauen.sh argon --environment=ZENOS_SCHLUESSEL_FEHLT_OK=1` (dieses Image nimmt keine Updates an).

Das Test-Image traut nur einem Wegwerf-Schlüssel: `bauen.sh qemu` legt ihn beim ersten Mal unter
`mkosi/ausgabe/test-schluessel/` an (nicht im Repo), `veroeffentlichen.sh qemu` signiert damit. Kein Gerät kennt ihn;
`mkosi.finalize` lässt im Argon-Image nur FIDO2-Schlüssel zu.

## Auf die SSD schreiben (Zeno, auf dem Mac)

Vorher prüft Claude das fertige Image: `mkosi/test/startpartitionen.sh` muss «Alle Prüfungen bestanden» melden, und der
Bau muss «Updates nur mit Zenos FIDO2-Schlüsseln» mit zwei Fingerabdrücken gemeldet haben, denselben wie auf Zenos
Papier. Beide Keys haben vorher die Probe bestanden (`docs/signieren.md`, Abschnitt 4).

Die SSD des Argon hängt in einem USB-Gehäuse am Mac. **Alles auf ihr wird gelöscht.** Die Nummer (`/dev/diskN`) muss
genau stimmen: Mit einer falschen Nummer überschreibt `dd` eine andere Platte. Einen Befehl nach dem anderen:

```
diskutil list external physical
diskutil unmountDisk /dev/diskN
sudo dd if=mkosi/ausgabe/argon/zenos_<version>.raw of=/dev/rdiskN bs=4m status=progress
diskutil eject /dev/diskN
```

Danach die SSD in den Argon einbauen. Die Boot-Reihenfolge im EEPROM bleibt, wie sie ist: Der Argon startet schon heute
von der SSD.

## Erster Start

Beide Hardware-Schlüssel bereithalten (unten); ohne Schlüssel 1 geht der erste Start nicht weiter.

Zuerst bereitet zenOS den Speicher vor: Es legt die verschlüsselte Datenpartition an und verwirft dabei die alten Daten
auf der SSD. Auf dem Bildschirm steht «Der Speicher wird vorbereitet …»; das dauert einige Minuten (in QEMU mit
500 GB gut vier), danach kommt die erste Frage. Nicht ausschalten: Bricht der erste Start ab, bevor das Passwort gesetzt
ist, lässt sich die Datenpartition nicht mehr öffnen, und die SSD muss neu geschrieben werden.

1. Tastaturbelegung wählen (sie gilt ab dann immer, auch für das Passwort beim Start).
2. Passwort für die verschlüsselten Daten setzen: lang, zum Beispiel sechs zufällige Wörter.
3. Schlüssel 1 einstecken und zweimal berühren, wenn er blinkt; dann Schlüssel 2 genauso (Enter: später).
4. Den Wiederherstellungsschlüssel auf Papier schreiben und getrennt vom Laptop aufbewahren.
5. Wenn gewünscht ein Notfall-Passwort (unten), zweimal; Enter überspringt es.
6. Das Passwort eingeben und den Schlüssel berühren, um die Daten zu öffnen.
7. Ein Konto anlegen (Name und Passwort).
8. Beide Schlüssel für die Anmeldung eintragen (je einmal berühren).
9. Am Login von zenOS anmelden: Passwort, dann den Schlüssel berühren. WLAN über das System-Menü oben rechts.

## Hardware-Schlüssel

Ohne einen der beiden Schlüssel öffnen sich die Daten nicht und das Konto nicht, auch nicht mit dem Passwort. Beim
Start, beim Login und in der Sperre nach dem Passwort den Schlüssel berühren. Der Schlüssel gehört an den
Schlüsselbund, nicht in den Laptop; der zweite liegt als Ersatz an einem sicheren Ort.

```
zen schluessel status               # wie viele für die Daten und für die Anmeldung
zen schluessel hinzufuegen          # Passwort der Daten, eingetragenen Schlüssel berühren, dann den neuen
zen schluessel entfernen <nummer>   # Passwort der Daten, einen anderen eingetragenen berühren; nie den letzten
```

**Notweg:** Ist ein Schlüssel verloren, öffnet der Wiederherstellungsschlüssel die Daten beim Start. Danach fragt der
Start, ob er ein neues Passwort und neue Schlüssel eintragen soll; die alten Plätze werden dabei gelöscht, und die
neuen Schlüssel gelten auch für die Anmeldung. Wie die Passphrase aus Passwort und Schlüssel entsteht, steht in
`docs/neubau.md`, Abschnitt 4.9.

## Notfall-Passwort

Für den Fall, dass dich jemand zwingt, den Laptop zu starten und das Passwort einzutippen. Tippst du beim Start statt
deines Passworts das Notfall-Passwort, löscht zenOS in Sekunden alle Schlüssel deiner Daten, auch den
Wiederherstellungsschlüssel. Danach startet zenOS wie immer bis zum Schreibtisch, angemeldet unter deinem Namen, aber
leer: Alles liegt nur noch im Arbeitsspeicher, die SSD wird nicht mehr beschrieben. Die Sperre entsperrt mit dem
Notfall-Passwort. **Das lässt sich nicht rückgängig machen.** Nach dem Ausschalten stimmt kein Passwort mehr; zurück
geht es nur mit einem neuen Image.

Das echte Passwort öffnet immer zuerst. Ein Tippfehler löst den Notfall nie aus, und ein Notfall-Passwort, das die Daten
öffnet, nimmt zenOS gar nicht an.

```
zen notfall status       # gesetzt oder nicht
zen notfall setzen       # Passwort der Daten, dann zweimal das neue Notfall-Passwort
zen notfall aendern
zen notfall entfernen    # Passwort der Daten
```

`zen notfall` geht nur in deiner Sitzung am Gerät und verlangt für jede Änderung das Passwort der Daten. Grenzen: Gegen
eine Kopie der SSD, die jemand vorher zieht und ohne den Startcode von zenOS untersucht, hilft es nicht. Die Täuschung
hält bis zum Ausschalten. Wer danach den LUKS-Kopf ansieht, sieht, dass die Schlüssel fehlen, und ein LUKS-Kopf auf
`zenos-notfall` verrät, dass es ein Notfall-Passwort gibt.

## Ausschalten nach langer Sperre

War zenOS 30 Minuten lang ohne entsperrte Sitzung, schaltet es aus: gesperrt (auch über den Deckel) oder am Login nach
dem Entsperren der Daten. Eine Minute vorher zeigt die Sperre «Schaltet in 1 Minute aus»; Entsperren setzt die Zeit
zurück. Kein Programm kann es aufhalten. Erst ausgeschaltet ist der Schlüssel der Daten aus dem Arbeitsspeicher.
Downloads und Browserdaten sind ohnehin flüchtig. Im Test-Image für QEMU sind es 5 Minuten.

## Notausgang

Scheitert der grafische Login zweimal schnell hintereinander (etwa ein Problem mit der Grafik), kommt stattdessen der
Text-Login von greetd. Dort mit Name und Passwort des Kontos anmelden; es startet fish. WLAN mit `nmtui`, dann
`zen update` für eine Korrektur. Nach dem Abmelden (`exit`) versucht es der grafische Login wieder.

## Updates

Im Terminal (Ctrl+Alt+T): `zen update`. Es lädt die Liste des neuesten Stands von GitHub, prüft Zenos Signatur (einer
der zwei FIDO2-Schlüssel, mit PIN und Berührung), lädt dann die Dateien, prüft jede gegen ihre Prüfsumme und schreibt
erst diese geprüfte Kopie in die freie Hälfte. Danach `zen neustart`: Der neue Stand startet einmal zur
Probe. Läuft er bis zum Login, wird er fest. Hängt er, die Ein/Aus-Taste lange drücken und wieder einschalten: Dann
startet der alte Stand, und `zen status` sagt, was war. Ein gescheiterter Stand wird nicht nochmals angeboten.

Erinnerung: Sind die Pakete des laufenden Stands 14 Tage alt (gezählt ab dem festen Stand von snapshot.debian.org),
kommt einmal am Tag eine Mitteilung. Gezählt wird nur mit einer Uhr, die chrony über NTS gestellt hat; ins Netz geht
dafür nichts. `zen status` zeigt das Alter der Pakete.

Veröffentlichen (Claude, nach Zenos Ja): `mkosi/bauen.sh argon`, `mkosi/veroeffentlichen.sh`, Zeno signiert
`SHA256SUMS` in seinem Terminal (`docs/signieren.md`), `mkosi/signatur-pruefen.sh <version>`, dann ein Release auf
GitHub mit den Dateien, `SHA256SUMS` und `SHA256SUMS.sig`.
Das Release heisst `zenos-<version>` (Tag ebenso, zum Beispiel `zenos-0.9.2`) und ist keine Vorabversion, sonst zeigt
`releases/latest` nicht darauf. Nie ein Tag `v…`: Darauf reagieren `zen update` von 0.1 (signierte Tags `v1.2.3`) und
der Image-Workflow von 0.1.

## Was noch fehlt

- **Kein signierter Start.** Wer root hat, könnte die Startpartitionen ändern. Das schliesst 1.0 (OTP).
- Bluetooth und Akku-Anzeige des Argon sind noch nicht eingerichtet; Einstellungen, Modi und Raster aus 0.1 kommen
  später mit Updates.
- **Deckel:** Zuklappen sperrt (Overlay `zenos-deckel`, logind `HandleLidSwitch=lock`, immer, auch am Netzteil und mit
  einem zweiten Bildschirm). Der Bildschirm unter dem Deckel geht wie bei jeder Sperre erst nach der eingestellten Zeit
  ohne Eingabe aus. Auf dem Argon noch nicht geprüft: Zuklappen muss sofort sperren, Aufklappen zeigt die Sperre.
- Die machine-id ist bei jedem Start neu (schreibgeschütztes `/etc`); systemd-homed meldet dazu Fehler im Journal, die
  Anmeldung geht.
