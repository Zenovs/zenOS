# Bauaufträge für zenOS 1.0

Vier Aufträge sind offen. Bauauftrag 2, 3 und 4 sind gebaut und in QEMU geprüft (12.11.2026), soweit es ohne
Hardware geht; sie warten auf die Abnahme am Argon (Liste in `docs/baufortschritt.md`). Bauauftrag 1 wartet auf Zenos
Signaturschlüssel (seit 13.11.2026 seine zwei FIDO2-Schlüssel, `docs/signieren.md`) und die Abnahme am Argon. Der Rahmen von Bauauftrag 1 (Mac, Colima, Freigaben, Rückfragen) gilt für
alle.

## Bauauftrag 2: Notfall-Passwort (gebaut, Abnahme am Argon offen)

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

## Bauauftrag 3: Ausschalten nach langer Sperre (gebaut, Abnahme am Argon offen)

Erteilt von Zeno am 11.11.2026 im Chat mit Claude («Ausschalten nach langer Sperre nimm das auch noch rein»).

### Ziel

Solange zenOS läuft, liegt der Schlüssel der Daten im Arbeitsspeicher, auch hinter der Sperre und am Login. Erst ein
ausgeschaltetes Gerät ist wirklich zu. Deshalb schaltet zenOS aus, wenn es 30 Minuten lang ohne entsperrte Sitzung
war: gesperrt (auch über den Deckel) oder am Login nach dem Entsperren der Daten. Das ist eine Leitplanke, nicht
abschaltbar. Verloren geht dabei nichts, was bleiben soll: Downloads und Browserdaten sind ohnehin flüchtig.

### Aufbau

- Ein Dienst des Systems (nicht der Sitzung, damit ein Absturz der Oberfläche ihn nicht stoppt) zählt die Zeit ohne
  entsperrte Sitzung, über logind (Sitzungen, `LockedHint`). Die Sperre setzt dafür `LockedHint` beim Sperren und
  löscht ihn beim Entsperren; die Notfall-Sperre mit swaylock ebenso. Ist logind unklar (keine Antwort), gilt das als
  gesperrt.
- Nach 30 Minuten: ausschalten (`poweroff`), ohne dass ein Programm es mit einem Inhibitor verhindern kann. Eine
  Minute vorher zeigt die Sperre einen ruhigen Hinweis «Schaltet in 1 Minute aus» (kein Inhalt, Leitplanke der Sperre
  bleibt). Entsperren setzt die Zeit zurück.
- Gilt genauso im Notfall-Zustand aus Bauauftrag 2.
- Fest 30 Minuten im Image für den Argon. Nur das QEMU-Profil darf eine kürzere Zeit haben (für den Test), nie das
  Argon-Image; `mkosi.finalize` prüft das.

### Tests (QEMU)

- Mit kurzer Zeit im QEMU-Profil: gesperrt → Hinweis → ausgeschaltet. Entsperren vor Ablauf setzt zurück.
- Am Login nach dem Entsperren der Daten ohne Anmeldung → ausgeschaltet.
- Eine Sitzung, die einen Inhibitor hält, verhindert das Ausschalten nicht.
- Die bisherigen Tests bleiben grün.

### Fertig heisst

Image baut, Tests grün, gitleaks und shellcheck sauber; `docs/neubau.md` (Leitplanke und Grund), `mkosi/README.md` und
`docs/baufortschritt.md` nachgeführt; kurzer Bericht an Zeno.

---

## Bauauftrag 4: Hardware-Schlüssel (FIDO2) beim Start, beim Anmelden und beim Entsperren (gebaut, Abnahme am Argon offen)

Erteilt von Zeno am 11.11.2026 im Chat mit Claude («ja nimm das auch rein»; vorher gefragt, ob man «schon beim
anmelden den key physisch braucht»). Zeno bestellt zwei Schlüssel der Security-Key-Reihe von Yubico (FIDO2, USB-C,
NFC); beide werden eingetragen, einer liegt als Ersatz an einem sicheren Ort.

### Ziel

Ohne einen der beiden Schlüssel kommt niemand an die Daten und ins Konto, auch nicht mit dem Passwort und auch nicht
mit einer Kopie der SSD. Das ersetzt den Sicherheitschip, den der CM5 nicht hat. Der Schlüssel gehört an den
Schlüsselbund, nicht in den Laptop; die Doku sagt das deutlich.

### Aufbau

1. **Start (Daten):** Öffnen nur mit Passwort UND Schlüssel (Berührung). LUKS-Schlüsselplätze gelten einzeln (oder),
   deshalb leitet sich die Passphrase je Schlüssel aus beidem ab, zum Beispiel aus dem Passwort und dem hmac-secret
   des Schlüssels (`fido2-assert`, libfido2). Ein Platz pro Schlüssel, dazu der Wiederherstellungsschlüssel als
   einziger Weg ohne Schlüssel. Kein Platz mit dem Passwort allein. Das Ableitungsverfahren steht offen in der Doku,
   damit es nachprüfbar ist.
2. **Zusammen mit Bauauftrag 2:** Eine Eingabe für das Passwort, wie gehabt; dazu «Schlüssel einstecken und berühren».
   Reihenfolge bleibt: zuerst die echten Daten (Passwort plus Schlüssel), dann das Notfall-Passwort. Das
   Notfall-Passwort wirkt auch ohne eingesteckten Schlüssel. Die Attrappe fragt beim Entsperren ebenfalls nach dem
   Schlüssel und nimmt das Notfall-Passwort mit der Berührung eines beliebigen FIDO2-Schlüssels an, damit sie gleich
   aussieht.
3. **Anmelden und Entsperren:** Kontopasswort UND Schlüssel, über PAM (Login von greetd und `zenos-sperre`), zum
   Beispiel mit pam_u2f oder den FIDO2-Fähigkeiten von systemd-homed. Die Liste der erlaubten Schlüssel liegt so, dass
   das Konto selbst sie nicht ändern kann (nicht unter `~`).
4. **Einrichten beim ersten Start:** nach dem Passwort der Daten beide Schlüssel nacheinander eintragen (für Daten und
   Konto); mit nur einem geht es weiter, mit einem deutlichen Hinweis, den zweiten nachzutragen.
5. **Später: `zen schluessel status|hinzufuegen|entfernen`** über denselben Socket-Dienst wie `zen notfall` (nicht
   noch einen Weg zu root). Verlangt das Passwort der Daten und die Berührung eines schon eingetragenen Schlüssels. Der
   letzte Schlüssel lässt sich nicht entfernen.
6. **Notweg:** Wurden die Daten mit dem Wiederherstellungsschlüssel geöffnet, bietet der Start an, neue Schlüssel für
   Daten und Konto einzutragen. Sonst gibt es keinen Weg am Schlüssel vorbei.
7. **Passkeys im Browser:** Chromium spricht den Schlüssel über USB an (udev, `uaccess`); im Image prüfen, dass das
   ohne weitere Rechte geht.

### Freigegeben

Wie in Bauauftrag 1 und 2, dazu die Pakete für FIDO2 (libfido2 und Werkzeuge, pam_u2f falls nötig), mit Grund in der
Paketliste.

### Nur nach Rückfrage bei Zeno

Wie in Bauauftrag 1 und 2, dazu: jeder Weg, der ohne Schlüssel an Daten oder Konto führt (ausser dem
Wiederherstellungsschlüssel), und eine PIN auf dem Schlüssel als Pflicht für den Start.

### Tests

- In QEMU mit einem emulierten FIDO2-Schlüssel, falls die Bauumgebung einen hat (zum Beispiel canokey), sonst so viel
  wie ohne geht; was nur mit echter Hardware geht, steht im Bericht für die Abnahme am Argon.
- Start: Passwort ohne Schlüssel scheitert, Passwort mit Schlüssel öffnet, Wiederherstellungsschlüssel öffnet und
  bietet das Neueintragen an, Notfall-Passwort wirkt mit und ohne Schlüssel.
- Anmelden und Sperre: ohne Schlüssel abgelehnt, mit Schlüssel angenommen.
- `zen schluessel`: hinzufügen, entfernen, letzter Schlüssel bleibt; ohne Passwort der Daten abgelehnt.
- Die bisherigen Tests bleiben grün.

### Fertig heisst

Image baut, Tests grün, gitleaks und shellcheck sauber; `docs/neubau.md` (Bedrohungsmodell: Dieb mit Kopie der SSD,
Ableitung der Passphrase, Regel «Schlüssel an den Schlüsselbund»), `mkosi/README.md` (erster Start, `zen schluessel`,
Notweg) und `docs/baufortschritt.md` nachgeführt; kurzer Bericht an Zeno mit der Liste für die Abnahme am Argon.

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
- Updates: `zen update` lädt den neuen Stand (GitHub), prüft die Signatur von Zenos Schlüssel und alle Prüfsummen,
  schreibt mit systemd-sysupdate in die freie Hälfte (System, Prüfsummen, Startpartition) und startet ihn einmal zur Probe
  (tryboot, autoboot.txt). Läuft er, wird er fest; sonst startet wieder der alte.

### Nicht im Umfang

Signierter Start und eigener Kernel (1.0), alle übrigen Funktionen von 0.1 (Einstellungen, Modi, Bluetooth, Akku …).

### Fertig heisst

- Das Image baut, die Angriffstests in QEMU sind grün (auch Oberfläche und Update), gitleaks ist sauber.
- Zenos öffentliche Schlüssel sind im Image; ohne sie baut das Image für den Argon nicht. (Entscheid Zeno vom
  13.11.2026: zwei FIDO2-Schlüssel mit OpenSSH statt GPG im Live-System, `docs/signieren.md`.)
- `docs/baufortschritt.md` ist nachgeführt, `mkosi/README.md` erklärt Bau, Schreiben auf die SSD und Updates,
  `docs/signieren.md` das Signieren.
- Zeno bekommt einen kurzen Schlussbericht und den ersten Befehl, um das Image auf die SSD zu schreiben.
