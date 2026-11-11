# Bauaufträge für zenOS 1.0

Zwei Aufträge sind offen. Bauauftrag 2 ist der aktive; Bauauftrag 1 wartet nur noch auf Zenos Schlüssel und die
Abnahme am Argon. Der Rahmen von Bauauftrag 1 (Mac, Colima, Freigaben, Rückfragen) gilt für beide.

## Bauauftrag 2: Notfall-Passwort (aktiv)

Erteilt von Zeno am 11.11.2026 im Chat mit Claude («das mit dem nuke passwort will ich»; Entscheide: nach dem
Notfall-Passwort «soll zenos schreibtisch anzeigen aber es ist nichts mehr da, aber aussehen wie ich mich eingelogt
hätte»; das Notfall-Passwort ist «auch später änderbar»; Plan bestätigt mit «ja schreibe das so»).

### Ziel

Gibt Zeno beim Start statt des Passworts für die Daten sein Notfall-Passwort ein, sind die Daten in Sekunden endgültig
unlesbar, auch für den Wiederherstellungsschlüssel. Danach sieht alles normal aus: zenOS startet bis zum Schreibtisch,
angemeldet mit einem leeren Konto unter seinem Namen. Nichts davon landet auf der SSD. Das Notfall-Passwort legt Zeno
beim ersten Start fest (optional) und kann es später mit `zen notfall` setzen, ändern oder entfernen.

Schützt gegen: jemanden, der den Laptop selbst startet und Zeno zwingt, das Passwort einzutippen. Schützt nicht gegen:
eine Kopie der SSD, die jemand vorher zieht und ohne den Startcode von zenOS untersucht. Die Täuschung hält bis zum
Ausschalten; danach ist jedes Passwort «falsch», und wer den LUKS-Kopf ansieht, sieht, dass die Schlüssel fehlen.
Beides gehört so in die Doku.

### Aufbau

1. **Eigene Partition `zenos-notfall`** (`/usr/lib/repart.d/40-zenos-notfall.conf`, 32 MB, `linux-generic`, ohne
   Dateisystem), beim ersten Start vor der Datenpartition angelegt. Mit Notfall-Passwort ist sie ein LUKS2-Container
   (Argon2id) mit nur diesem einen Schlüsselplatz; im geöffneten Container stehen nur der Kontoname (eine Zeile, ohne
   Dateisystem). Ohne Notfall-Passwort ist sie leer (kein LUKS). Kein Hash, nichts im Klartext.
2. **Eigene Passwortabfrage statt systemd-cryptsetup** für `daten`: `/usr/lib/zenos/entsperren` in
   `zenos-entsperren.service` (vor `cryptsetup.target`, nach Tastatur und erstem Start). Der Eintrag in `/etc/crypttab`
   entfällt, `/etc/fstab` verlangt den neuen Dienst. Ablauf pro Eingabe:
   1. Passwort über `systemd-ask-password` (gleiche Anzeige wie bisher, Belegung aus `zenos-tastatur`).
   2. Zuerst die Daten öffnen (`cryptsetup open --key-file=-`). Klappt das, fertig. Der Wiederherstellungsschlüssel
      geht hier ebenso.
   3. Sonst, nur wenn `zenos-notfall` ein LUKS-Container ist: `--test-passphrase` dagegen. Passt es: Notfall (4.).
   4. Sonst «Das Passwort stimmt nicht. Bitte noch einmal.» und von vorn, ohne Grenze.
   Das echte Passwort öffnet also immer zuerst; ein Tippfehler löst nie den Notfall aus.
3. **Regel für Passwörter in diesen Skripten** (Ausnahme von «zenOS fasst nie selbst ein Passwort an», nur hier):
   nur im Arbeitsspeicher, über Pipes an cryptsetup (`printf` als eingebauter Befehl, nie in argv), nie in einer Datei,
   nie im Journal, sofort danach `unset`. Weitergabe an einen späteren Dienst nur über den Schlüsselbund des Kernels
   (`systemd-ask-password --keyname=… --accept-cached`), nicht über `/run`.
4. **Notfall:**
   1. Kontonamen aus dem Notfall-Container lesen, Container schliessen.
   2. `cryptsetup luksErase -q` auf die Datenpartition (alle Schlüsselplätze, auch der Wiederherstellungsschlüssel),
      dann den Notfall-Container löschen und die Partition nullen. Prüfen, dass `luksDump` keine Schlüsselplätze mehr
      zeigt; scheitert das Löschen, trotzdem weiter wie unten (nie zurück zur echten Anmeldung).
   3. Attrappe: `/var` auf einem Datenträger im Arbeitsspeicher, unter demselben Namen `/dev/mapper/daten` (zum
      Beispiel zram mit dm-linear), ext4 mit `/home`. Die SSD wird danach nicht mehr beschrieben.
   4. Ein Dienst nach systemd-homed legt das Konto unter dem gelesenen Namen an (Speicher `directory`, Passwort =
      Notfall-Passwort aus dem Schlüsselbund), aktiviert es, und greetd meldet es einmal automatisch an (Konfiguration
      zur Laufzeit unter `/run`, über einen Drop-in für greetd). Die Sperre entsperrt mit dem Notfall-Passwort.
   5. Im Notfall-Zustand kein `zen update` und keine Erinnerung; sonst verhält sich alles wie gewohnt (hell, Leiste,
      Apps, Chromium).
   6. Nach einem Neustart: Daten ohne Schlüssel, Notfall-Partition leer, also «stimmt nicht» für jedes Passwort. Zurück
      nur mit neuem Image.
5. **Setzen beim ersten Start** (`daten-schuetzen`): nach dem Wiederherstellungsschlüssel ein optionaler Schritt
   «Notfall-Passwort (Enter = keins)», zweimal eingeben. Abgelehnt wird es, wenn es die Daten öffnet (gleich wie das
   echte Passwort oder der Wiederherstellungsschlüssel). Der Text sagt in zwei Sätzen, was es tut und dass es nicht
   rückgängig zu machen ist.
6. **Später: `zen notfall status|setzen|aendern|entfernen`.** Ohne Admin und ohne pkexec: ein Dienst mit root hinter
   einem Socket, der nur eine aktive lokale Sitzung annimmt (Peer-Credentials). Jede Änderung verlangt das Passwort der
   Daten (geprüft mit `--test-passphrase` gegen die Datenpartition); das neue Notfall-Passwort zweimal, abgelehnt wie
   in 5. Die Passwörter gehen nur über den Socket, nie in argv, Dateien oder Journal. Sonst kann der Dienst nichts.

### Freigegeben

Wie in Bauauftrag 1, dazu: eine neue Partition im Layout des ersten Starts, die eigene Passwortabfrage anstelle von
systemd-cryptsetup, zram oder brd als Kernel-Modul, ein Socket-Dienst mit root nur für `zen notfall`.

### Nur nach Rückfrage bei Zeno

Wie in Bauauftrag 1, dazu: jede Abweichung von «echtes Passwort zuerst», jede Speicherung eines Passworts ausserhalb
des Arbeitsspeichers und jeder weitere Weg zu root.

### Tests (QEMU, alle grün, bevor es auf den Argon kommt)

- Erster Start mit Notfall-Passwort; ein Notfall-Passwort gleich dem echten wird abgelehnt.
- Zweiter Start mit dem echten Passwort und mit dem Wiederherstellungsschlüssel: Daten da, kein Notfall.
- Falsches Passwort: «stimmt nicht», nichts gelöscht.
- `zen notfall`: setzen, ändern, entfernen; falsches Passwort der Daten wird abgelehnt; aus einer Sitzung ohne
  Bildschirm (serielle Konsole) abgelehnt; nichts davon im Journal.
- Zuletzt, weil es die Maschine zerstört: Start mit dem Notfall-Passwort. Erwartet: Schreibtisch mit angemeldetem
  leerem Konto unter dem Namen, `/var` im Arbeitsspeicher, `luksDump` ohne Schlüsselplätze, Notfall-Partition genullt,
  Sperre entsperrt mit dem Notfall-Passwort, Bildschirmfoto. Danach Neustart: echtes Passwort und Notfall-Passwort
  beide «stimmt nicht».
- Die bisherigen Angriffstests bleiben grün.

### Fertig heisst

- Image baut, alle Tests grün, gitleaks sauber, `shellcheck` sauber.
- `docs/neubau.md` (Bedrohungsmodell: neue Zeile «Jemand zwingt dich», Abschnitt Notfall-Passwort mit den Grenzen von
  oben), `mkosi/README.md` (erster Start, `zen notfall`) und `docs/baufortschritt.md` sind nachgeführt.
- Zeno bekommt einen kurzen Bericht: was getestet ist und was erst am Argon geprüft werden kann.

---

## Bauauftrag 1: Vorschau auf der SSD des Argon (08.11.2026, offen: Schlüssel und Abnahme am Argon)

Erteilt von Zeno am 08.11.2026 («ja, lege los, auf diesem Mac»; die Entscheide in `docs/neubau.md` sind für ihn so in
Ordnung). Der Bauauftrag für 0.1 ist abgeschlossen; er steht im Branch `dev`.

### Ziel

Erweitert am 10.11.2026 auf Zenos Wunsch («die ssd kann gelöscht werden, darauf komplett das neue zenOS
installieren … nach dem einbau, können nur noch update über das terminal online gezogen und installiert werden»):

Ein Image, das Zeno selbst auf die SSD des Argon ONE UP (Compute Module 5 Lite) schreibt. Nach dem Einbau muss alles
funktionieren, bis zur Oberfläche und den Apps; die SSD kommt danach nicht mehr heraus. Neue Stände kommen nur noch
online über das Terminal (`zen update`), signiert mit Zenos Schlüssel, A/B mit Probestart. Der Argon wird danach Zenos
Gerät für Zahlungen und Trading. Das umfasst Vorschau 1 und die Updates aus Vorschau 2 (`docs/neubau.md`, Abschnitt 6).

Auf dem Gerät ist nur, was gebraucht wird. Keine überflüssige Software, und als Browser der sicherste, der sich auf
diesem Gerät pflegen lässt (Chromium aus Debian, gehärtet über Richtlinien).

### Rahmen

- Gebaut wird auf Zenos Mac: Docker über Colima, mkosi in einem Debian-Container, Tests in QEMU. Branch `neubau`.
- `MANIFEST.md` und `CLAUDE.md` gelten. Bei einem Widerspruch gewinnt das Manifest.
- Arbeite selbstständig durch. Frag Zeno nur bei den Punkten unter «Nur nach Rückfrage» oder bei einem echten Blocker.
- Halte den Fortschritt in `docs/baufortschritt.md` (Abschnitt «zenOS 1.0») fest. Endet eine Sitzung, muss eine neue
  dort nahtlos weitermachen können.
- Committe thematisch auf `neubau` und pushe danach.

### Freigegeben

- Die Colima-VM auf mehr Kerne und RAM stellen und dafür neu starten.
- Container und Images bauen, Pakete im Container installieren, Caches unter `mkosi/` anlegen (nicht im Repo).
- Pushen auf `neubau`.

### Nur nach Rückfrage bei Zeno

- Alles, was auf einen physischen Datenträger, das EEPROM oder das OTP schreibt. Das macht Zeno selbst.
- Software auf dem Mac ausserhalb von Docker installieren.
- Tags, Releases, GitHub-Einstellungen und Secrets.
- Änderungen am Branch `dev`.
- Signaturschlüssel: Claude erzeugt, sieht und benutzt nie welche.

### Umfang Vorschau 1

- Debian 13 arm64 als Image mit mkosi, aus einem eingefrorenen Paketstand von `snapshot.debian.org`.
- Kernel und Firmware von Raspberry Pi, Bootpartition für das CM5 (mit dem USB-Overlay für Tastatur und Touchpad).
- `/` schreibgeschützt mit dm-verity. `/var` und `/home` auf LUKS2 mit Argon2id, beim ersten Start eingerichtet. Platz
  für die B-Hälfte.
- Kein SSH, kein sudo und su, kein apt, keine Compiler. nftables verwirft Eingehendes, chrony mit NTS, resolved ohne
  mDNS und LLMNR, NetworkManager.
- Kernel-Härtung über sysctl und Befehlszeile.
- Chromium mit Richtlinien, udev-Regeln für Trezor und Ledger.
- Oberfläche: Login, Leiste, Apps starten, Sperre, WLAN.
- Angriffstests in QEMU.
- Updates: `zen update` lädt den neuen Stand (systemd-sysupdate, GitHub), prüft die Signatur von Zenos Schlüssel und
  alle Prüfsummen, schreibt in die freie Hälfte (System, Prüfsummen, Startpartition) und startet ihn einmal zur Probe
  (tryboot, autoboot.txt). Läuft er, wird er fest; sonst startet wieder der alte.

### Nicht im Umfang

Signierter Start und eigener Kernel (1.0), alle übrigen Funktionen von 0.1 (Einstellungen, Modi, Bluetooth, Akku …).

### Fertig heisst

- Das Image baut, die Angriffstests in QEMU sind grün (auch Oberfläche und Update), gitleaks ist sauber.
- Zenos öffentlicher Schlüssel ist im Image; ohne ihn baut das Image für den Argon nicht.
- `docs/baufortschritt.md` ist nachgeführt, `mkosi/README.md` erklärt Bau, Schreiben auf die SSD und Updates,
  `docs/signieren.md` das Signieren.
- Zeno bekommt einen kurzen Schlussbericht und den ersten Befehl, um das Image auf die SSD zu schreiben.
