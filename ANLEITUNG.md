# Anleitung: zenOS installieren und testen

Von Ubuntu Server auf dem Pi bis zum getesteten zenOS. Führe die Befehle einzeln aus und schau nach jedem, ob er ohne
Fehler durchlief.

**Voraussetzungen:**
- Raspberry Pi 5 mit mindestens 4 GB RAM
- Bootloader (EEPROM) des Pi 5 vom 11.02.2025 oder neuer, sonst startet Ubuntu 26.04 nicht (siehe «Vorab» in B)
- SD-Karte oder NVMe mit mindestens 32 GB
- Bildschirm, Tastatur und Maus am Pi
- Netzwerkkabel, empfohlen
- Mac mit Terminal für SSH
- Optional: Argon ONE V3 als Gehäuse (Lüfter und Power-Button)
- Optional: Claude-Abo mit Claude Code, nur für Nacharbeiten (Abschnitt F)

---

## A · Repo auf GitHub (erledigt)

Der Bau lief nicht auf dem Pi, sondern auf dem Mac: Claude Code hat dort gebaut und in Docker-Containern mit Ubuntu
26.04 arm64 getestet, also mit derselben Architektur wie der Pi. Das Repo liegt auf GitHub: `main` enthält den
Start-Commit, `dev` zenOS 0.1 mit dem Tag `v0.1.0-rc1`. Die früheren Schritte A1 bis A14 fallen weg.

---

## B · Pi vorbereiten

**Vorab · Bootloader.** Ubuntu 26.04 startet auf dem Pi 5 nur mit einem Bootloader vom 11.02.2025 oder neuer (so
steht es in den Versionshinweisen von Ubuntu 26.04). Weisst du nicht, wie alt deiner ist, aktualisiere ihn vorher mit
dem Raspberry Pi Imager: Gerät Raspberry Pi 5, System «Misc utility images» → «Bootloader (Pi 5 family)» → die
Boot-Reihenfolge wählen (SD-Karte oder NVMe/USB), auf eine freie SD-Karte schreiben. Den Pi mit dieser Karte
starten und warten, bis die grüne LED gleichmässig blinkt und der Bildschirm grün wird. Dann ausschalten und die
Karte entfernen. Läuft auf dem Pi schon Raspberry Pi OS oder Ubuntu ab 24.04, geht es auch dort mit
`sudo rpi-eeprom-update -a` und einem Neustart. zenOS selbst fasst den Bootloader nie an.

**B1.** Mit dem Raspberry Pi Imager auf dem Mac installieren:

- **Gerät:** Raspberry Pi 5
- **System:** Other general-purpose OS → Ubuntu → **Ubuntu Server 26.04 LTS (64-bit)**
- **Einstellungen**, falls der Imager sie anbietet:
  - Hostname `zenos-pi`
  - Lokalisierung: Zeitzone und Tastaturbelegung. Die Belegung gilt auch für das Passwortfeld im zenOS-Login und
    auf dem Sperrbildschirm.
  - Benutzer und Passwort
  - SSH mit deinem öffentlichen Schlüssel
  - WLAN, falls kein Kabel

Bietet der Imager keine Einstellungen an, meldest du dich beim ersten Start an der Textkonsole des Pi mit `ubuntu` /
`ubuntu` an und vergibst ein neues Passwort. Zeitzone und Tastatur stellst du dann nach B6 ein.

**B2.** Pi starten, zwei Minuten warten. Die IP-Adresse steht im Router, oder am Pi mit `hostname -I`.

**B3.** Vom Mac aus verbinden, dein Benutzername statt `<benutzer>`:

```
ssh <benutzer>@zenos-pi.local
```

Klappt `zenos-pi.local` nicht, nimm die IP-Adresse.

**B4.**

```
sudo apt update
```

**B5.**

```
sudo apt full-upgrade -y
```

**B6.** Neu starten, danach wie in B3 wieder verbinden:

```
sudo reboot
```

Zur Kontrolle zeigt `sudo rpi-eeprom-update` unter «CURRENT» das Datum des Bootloaders.

**Nur ohne Imager-Einstellungen:** Zeitzone und Tastatur jetzt einstellen, sonst weiter mit B7. Ohne sie läuft die
Uhr in UTC (Leiste, Sperre, gesammelte Mitteilungen liegen daneben), und im zenOS-Login gilt die US-Belegung.
Zuerst die Zeitzone, deine statt `<Zone>` (die Liste zeigt `timedatectl list-timezones`):

```
sudo timedatectl set-timezone <Zone>
```

Dann die Tastaturbelegung:

```
sudo dpkg-reconfigure keyboard-configuration
```

Prüfen kannst du beides mit `timedatectl` und `cat /etc/default/keyboard`.

**B7.**

```
sudo apt install -y git gh tmux curl
```

**B8.** Optional: bei GitHub anmelden. Nötig nur, wenn du vom Pi aus pushen willst (Claude Code in F); das Repo ist
öffentlich, B9 geht auch ohne. Wähle GitHub.com, HTTPS und die Anmeldung im Browser, den Code gibst du auf dem Mac
ein:

```
gh auth login
```

**B9.**

```
git clone https://github.com/Zenovs/zenOS.git ~/zenOS
```

**B10.**

```
cd ~/zenOS
```

**B11.** zenOS 0.1 liegt auf `dev`, solange `main` nur den Start-Commit enthält (bis G3):

```
git switch dev
```

**B12 bis B16 brauchst du nur, wenn Claude Code auf dem Pi nacharbeiten soll (Abschnitt F).** Sonst weiter mit C1.
Du kannst sie auch später nachholen.

**B12.** Eine temporäre sudo-Regel anlegen. Claude Code kann keine Passwörter eintippen. **Sie wird in G1 wieder
gelöscht**; bis dahin warnt `zen doctor`.

```
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/zenos-bau
```

**B13.**

```
sudo chmod 0440 /etc/sudoers.d/zenos-bau
```

**B14.** Prüfen, ob die sudo-Konfiguration gültig ist. Erwartet wird «parsed OK»:

```
sudo visudo -c
```

**B15.** Claude Code mit dem offiziellen Installer installieren:

```
curl -fsSL https://claude.ai/install.sh | bash
```

**B16.** Prüfen:

```
claude --version
```

Wird `claude` nicht gefunden, zuerst `exec bash -l` ausführen und B16 wiederholen.

---

## C · Installieren (Pi, per SSH)

Du bist per SSH verbunden und in `~/zenOS` auf dem Branch `dev`.

**C1.** Eine Sitzung starten, die weiterläuft, auch wenn die SSH-Verbindung abbricht:

```
tmux new -s zenos
```

**C2.** zenOS installieren:

```
./scripts/install.sh
```

- Das Skript fragt einmal nach deinem sudo-Passwort («zenOS braucht sudo für die Systemteile.»). Mit der sudo-Regel
  aus B12 fragt es nicht.
- Dauer, geschätzt: 15 bis 30 Minuten. Das meiste davon ist der Bau von Quickshell; auf dem Pi gemessen ist es noch
  nicht.
- Erscheint «Warte auf einen anderen Paketvorgang …», laufen gerade die automatischen Updates von Ubuntu. Die
  Installation wartet und macht danach weiter.
- Die SSH-Verbindung bleibt bestehen. Der Bildschirm am Pi bleibt bis zum Neustart bei der Textkonsole.
- Am Ende steht `zenOS … installiert · N Änderungen`. Das Protokoll liegt unter `/var/log/zenos/install.log`.

Bricht die Verbindung ab: wie in B3 wieder verbinden, dann `tmux attach -t zenos`.

**C3.** Noch einmal, zur Kontrolle. Das geht schnell, fragt eventuell noch einmal nach dem Passwort und meldet
`installiert · 0 Änderungen`, ohne Warnung:

```
./scripts/install.sh
```

**C4.** Den Prüfbericht ansehen:

```
zen doctor
```

Erwartet wird `0 Fehler`. Hinweise sind normal, zum Beispiel «greetd läuft noch nicht», «Firewall vorbereitet, aber
nicht aktiv» und die noch nicht installierten Apps. Eine Warnung gibt es nur, wenn du die sudo-Regel aus B12
angelegt hast.

---

## D · Neustart

**D1.**

```
sudo reboot
```

Nach etwa einer Minute erscheint am Bildschirm der zenOS-Login. Die tmux-Sitzung endet mit dem Neustart.

---

## E · Testen (am Pi)

Hake ab, was funktioniert. Notiere, was nicht geht, am besten mit Uhrzeit. Die Befehle gibst du in kitty ein
(`Ctrl + Alt + T`) oder per SSH, wo es dabeisteht. Mehr Prüfpunkte pro Modul stehen in `docs/module/<modul>.md`
unter «Am Pi prüfen».

**Login und Einrichtung**
- [ ] Nach dem Neustart erscheint der zenOS-Login: dunkel, grosse Uhrzeit, dein Benutzer vorausgewählt. Niemand wird
  automatisch angemeldet.
- [ ] Ein falsches Passwort zeigt «Das Passwort stimmt nicht. Bitte noch einmal.», das Feld ist danach leer, nichts
  springt. Das richtige Passwort meldet an, auch mit Sonderzeichen deiner Tastatur.
- [ ] «Neustart» und «Ausschalten» im Login führen erst beim zweiten Klick aus.
- [ ] Die Einrichtung fragt nach Name, Ort (optional), Erscheinungsbild und erstem Modus. Nach «Einrichten» ist der
  Modus aktiv: Seine Akzentfarbe steht in der Leiste und in «Heute».
- [ ] Danach listet sie Chrome, VS Code, 1Password, 1Password-CLI und coremail mit Herkunft; Nubix steht mit «noch
  kein ARM-Build» da. «Installieren» öffnet ein Terminal, zeigt Quellen, Schlüssel und Dateien, fragt einmal nach und
  dann nach dem sudo-Passwort. «Später» führt zu Einstellungen → Apps.
- [ ] Chrome, VS Code, 1Password und coremail starten danach aus dem Befehlsfeld. `op --version` zeigt die
  1Password-CLI.
- [ ] Abmelden (System-Menü → Abmelden) führt zurück zum Login. Nach dem nächsten Anmelden erscheint die Einrichtung
  nicht mehr.

**Leiste, «Heute» und Erscheinungsbild**
- [ ] Die Leiste zeigt links Zeichen, Modus und Raster («4er»), in der Mitte Datum und Uhrzeit in deiner Ortszeit,
  rechts Glocke, Hell/Dunkel und den System-Knopf mit Temperatur. Sie sieht aus wie Entwurf 2.
- [ ] «Heute» zeigt Wochentag, Tageszahl, einen Gruss mit deinem Namen und unten die Tastenkappen für Super +
  Leertaste, Super + M und Super + Z.
- [ ] Der Hell/Dunkel-Schalter wechselt ohne Flackern: Leiste, «Heute», Fensterrahmen, kitty, Chrome und VS Code (nach
  seinem ersten Start).
- [ ] Das System-Menü zeigt Netz, Lautstärke mit Regler, 1Password, Temperatur und Lüfter, dazu Sperren,
  Einstellungen, Abmelden, Neustart und Ausschalten. Abmelden, Neustart und Ausschalten fragen einmal nach.

**Befehlsfeld**
- [ ] `Super + Leertaste` öffnet es, `Esc` oder nochmals `Super + Leertaste` schliesst es.
- [ ] `1440 / 16` zeigt `90`, Enter kopiert den Wert («90 kopiert»).
- [ ] Apps starten, Dateien im Home-Ordner finden und öffnen.
- [ ] Mit `Tab` zu den Werkzeugen: Das Bildschirmfoto eines Bereichs landet in der Zwischenablage und in
  `~/Bilder/Screenshots`. Dasselbe mit `Print` und `Super + Shift + S`.
- [ ] Die Pipette (`Super + Shift + C`) kopiert per Klick einen Farbwert wie `#A7B89F`.
- [ ] Aktionen wie «Hell/Dunkel», «Sperren» und «Einstellungen» funktionieren auch von hier.

**Mitteilungen**
- [ ] Ohne Zustand wartet `notify-send "Test" "Hallo"`: Die Leiste zeigt «1 · HH:00» mit der nächsten vollen Stunde,
  dann erscheint oben rechts eine ruhige Sammelkarte.
- [ ] `notify-send -u critical "Test" "Dringend"` erscheint sofort als Karte.
- [ ] Ein Klick auf die Glocke öffnet die Zentrale: «Jetzt zustellen» holt Wartendes, Einträge lassen sich verwerfen.
- [ ] Im Zustand Fokus warten normale Mitteilungen («1 warten»), dringende kommen sofort. Endet Fokus, kommt alles
  Wartende.

**Sperrbildschirm**
- [ ] `Super + L` sperrt: Uhrzeit, Datum, «N Mitteilungen · Inhalte erst nach dem Entsperren», keine Inhalte.
  Entsperren geht mit dem Passwort, ein falsches zeigt «Das Passwort stimmt nicht.».
- [ ] Nach 5 Minuten ohne Eingabe sperrt zenOS von selbst. Einstellbar sind 1 bis 15 Minuten (Einstellungen →
  Allgemein), abschalten lässt es sich nicht.
- [ ] War beim Sperren das Befehlsfeld offen, ist es nach dem Entsperren zu, und das Fenster darunter nimmt Tippen
  sofort an.
- [ ] `zen lock` per SSH sperrt die laufende Sitzung («Gesperrt.»).
- [ ] Absturztest: im gesperrten Zustand per SSH `pkill -9 -x quickshell`. Der Bildschirm bleibt gesperrt, nach etwa
  einer bis zwei Sekunden ist der Sperrbildschirm wieder da. Entsperren geht normal.
- [ ] Mit 1Password: Unten steht «zenOS gesperrt · 1Password gesperrt», und nach dem Entsperren ist 1Password
  gesperrt.

**Notfall-Sperre (optional, per SSH).** Antwortet die Oberfläche nicht, sperrt `zen lock` mit swaylock. Zum Testen
schaltest du die Oberfläche kurz ab. Wichtig: Die Schritte bis zum Schluss durchgehen, sonst fehlt die Oberfläche
auch nach dem nächsten Anmelden.

Die Oberfläche sperren, damit sie nicht neu startet:

```
systemctl --user mask zenos-shell.service
```

Die Oberfläche beenden:

```
systemctl --user stop zenos-shell.service
```

Sperren. Erwartet wird «Gesperrt (Notfall-Sperre mit swaylock …)», am Bildschirm ein dunkler Grund mit einem Ring:

```
zen lock
```

Am Pi das Passwort eintippen und Enter drücken, die Notfall-Sperre ist weg. Dann per SSH die Oberfläche wieder
freigeben:

```
systemctl --user unmask zenos-shell.service
```

Und starten. Sie sperrt dabei einmal, entsperren mit dem Passwort:

```
systemctl --user start zenos-shell.service
```

- [ ] Die Notfall-Sperre sperrt und lässt sich mit dem Passwort entsperren, danach ist die Oberfläche wieder da.

**Modi und Zustände**
- [ ] `Super + M` öffnet die Modus-Wahl, `Super + Z` die Zustand-Wahl. Ein Klick auf den Chip in der Leiste öffnet sie
  direkt darunter.
- [ ] In den Einstellungen (`Super + Komma`) → «Neuer Modus» einen zweiten Modus mit anderer Akzentfarbe anlegen. Der
  Wechsel ändert den Akzent in Leiste, Fensterrahmen und kitty.
- [ ] Mit Chrome-Profil im Modus (das Profil vorher in Chrome anlegen) und «Beim Wechsel öffnen: Chrome» öffnet
  Chrome beim Wechsel im Profil des neuen Modus.
- [ ] Fokus starten: Die Leiste zeigt «Fokus» mit Restzeit, Raster-Knopf und Hell/Dunkel treten zurück, «Heute»
  blendet seinen Inhalt aus.
- [ ] Sitzung: In Chrome den Bildschirm teilen, etwa auf einer Testseite für Bildschirmfreigabe oder in einem
  Videocall. Zuerst den Bildschirm anklicken, den du teilen willst. Die Sitzung startet von selbst: Rahmen und «Dieser
  Bildschirm wird geteilt», in der Leiste «N zurückgehalten», im geteilten Bild keine Inhalte von Mitteilungen. Mit
  dem Ende der Freigabe endet die Sitzung, und Zurückgehaltenes wird zugestellt.

**Raster**
- [ ] `Super + 1` bis `Super + 4` setzen das aktive Fenster in die Viertel (4er-Grid, der Standard).
- [ ] `Super + Links` und `Super + Rechts` setzen es in die linke und rechte Hälfte.
- [ ] `Super + Enter` maximiert und stellt wieder her.
- [ ] Raster-Knopf in der Leiste → «3 Spalten»: `Super + 1` bis `Super + 3` setzen in die drei Spalten.
- [ ] Mit der Maus: Fenster an der Titelzeile ziehen und Super halten, die Bereiche erscheinen, Loslassen rastet ein.
- [ ] Mit zweitem Bildschirm: `Super + Shift + Links` bzw. `Rechts` schiebt das Fenster hinüber; Leiste und «Heute»
  sind auf beiden.
- [ ] Fensterrahmen: Titelzeile in Geist Mono, oben runde Ecken (unten eckig, das ist eine Grenze von labwc).

**Terminal**
- [ ] `Ctrl + Alt + T` öffnet kitty mit fish und der zenOS-Eingabezeile.
- [ ] Text markieren, dann `Ctrl + C`: Der Text ist kopiert. Ohne Markierung bricht `Ctrl + C` ein laufendes
  `sleep 100` ab. `Ctrl + V` fügt ein.
- [ ] Nach jedem Befehl steht eine Statuszeile, etwa `✓ 0,1 s` oder `✗ Fehler 1 · …`.
- [ ] `? rsync` erklärt den Befehl als Karte, unten «lokal · offline».
- [ ] Ein Tippfehler im Befehl, etwa `lss`, wird rot.
- [ ] Bei `sudo rm -rf /var/log/test` kommt eine Warnung mit gelbem Rahmen. «Abbrechen» ist vorausgewählt, Enter
  bricht ab, der Befehl bleibt zum Ändern stehen.
- [ ] `Super + T` öffnet einen neuen Tab, `Super + Pfeil hoch/runter` springt zwischen den Befehlen.

**System**
- [ ] `zen doctor` meldet `0 Fehler`. Eine Warnung höchstens zur temporären sudo-Regel (nur mit B12), sonst Hinweise
  wie «Firewall vorbereitet, aber nicht aktiv».
- [ ] `zen update` meldet «Schon aktuell» oder alt → neu und endet mit `installiert · N Änderungen`. Die Oberfläche ist
  danach vollständig da.
- [ ] `zen rollback v0.1.0-rc1` geht auf den Tag zurück, `zen version` zeigt ihn. `zen update` bringt dich wieder auf
  `dev`.
- [ ] Die Temperatur steht in der Leiste, der Lüfter im System-Menü (Argon ONE). Unter Last (in kitty viermal
  `yes > /dev/null &`, danach `pkill yes`) wird der Lüfter hörbar schneller und später wieder leiser.
- [ ] Argon-Knopf: Doppeltipp startet neu, drei Sekunden halten schaltet aus, einmal kurz drücken tut nichts.
- [ ] In Chrome zeigt `chrome://policy` 13 zenOS-Richtlinien ohne Fehler. Die 1Password-Erweiterung ist fest
  installiert, andere Erweiterungen sind gesperrt.
- [ ] In VS Code steht die Einstellung `telemetry.telemetryLevel` auf `off` und ist von der Organisation verwaltet.
- [ ] `zen firewall status` zeigt «vorbereitet, nicht aktiv» und die fünf SSH-Regeln für die lokalen Netze. Die
  Firewall bleibt aus, bis du entscheidest (siehe G).
- [ ] 1Password-SSH-Agent: in 1Password → Einstellungen → Entwickler einschalten, ab- und wieder anmelden. Dann meldet
  `ssh -T git@github.com` dich über 1Password an (1Password fragt nach der Freigabe; dein SSH-Schlüssel liegt in
  1Password und ist bei GitHub eingetragen).
- [ ] Nach einem Tag zeigt `zen doctor` den letzten Lauf von unattended-upgrades.

**Flüssigkeit**
- [ ] Befehlsfeld, Hell/Dunkel, Fensterwechsel (`Alt + Tab`) und Einrasten laufen flüssig (60 fps). Nichts ruckelt,
  nichts blinkt.

---

## F · Wenn etwas nicht geht

**Häufige Fälle**

Der Pi zeigt nach dem Flashen nichts an, nur die LEDs leuchten: meist ist der Bootloader zu alt (siehe «Vorab» in B).

Das Passwort wird im zenOS-Login abgelehnt, per SSH geht es: Die Tastaturbelegung stimmt nicht. Per SSH neu wählen,
danach neu starten:

```
sudo dpkg-reconfigure keyboard-configuration
```

Die Uhrzeit in Leiste und Login liegt eine oder zwei Stunden daneben: Die Zeitzone fehlt. Per SSH setzen, danach ab-
und wieder anmelden:

```
sudo timedatectl set-timezone <Zone>
```

Der Login meldet «Das Passwort muss zuerst geändert werden»: mit `Ctrl + Alt + F2` zur Textkonsole, dort anmelden, ein
neues Passwort setzen, mit `exit` abmelden und mit `Ctrl + Alt + F7` zurück zum zenOS-Login.

Die Oberfläche hängt oder fehlt: per SSH neu starten. Ist die Sitzung gesperrt, sperrt sie danach sofort wieder.

```
systemctl --user restart zenos-shell.service
```

Nach einem Update geht etwas nicht mehr: zurück zum letzten guten Stand.

```
zen rollback v0.1.0-rc1
```

Die Textkonsole erreichst du immer mit `Ctrl + Alt + F2`, zurück zum zenOS-Login mit `Ctrl + Alt + F7`. Solange SSH
geht, ist alles reparierbar.

**Bericht und Nacharbeit**

**F1.** Per SSH den Prüfbericht speichern. Er enthält keine Geheimnisse und nichts Persönliches:

```
zen doctor > ~/doctor.txt
```

**F2.** Nacharbeit auf dem Mac (so wurde zenOS gebaut). Den Bericht auf dem Mac holen, dein Benutzername statt
`<benutzer>`:

```
scp <benutzer>@zenos-pi.local:doctor.txt ~/Downloads/zenos-doctor.txt
```

Dann in `~/Documents/github/zenOS` Claude Code starten und schreiben: «Lies CLAUDE.md, ~/Downloads/zenos-doctor.txt und
meine Notizen aus dem Test (unten). Behebe die Fehler, teste im Container, committe und pushe auf dev.» Danach auf dem
Pi per SSH:

```
zen update
```

Wiederhole dann die Punkte aus E, die nicht gingen.

**F3.** Nacharbeit direkt auf dem Pi, wenn es die echte Hardware braucht (Grafik, Tastatur, Argon ONE). Dafür braucht
es B8 und B12 bis B16. Per SSH in die tmux-Sitzung:

```
tmux new -A -s zenos
```

In `~/zenOS` Claude Code starten:

```
claude
```

Und schreiben: «Lies CLAUDE.md, docs/baufortschritt.md, ~/doctor.txt und meine Notizen aus dem Test (unten). Behebe
die Fehler, committe und pushe auf dev.» Danach wiederholst du D und die Punkte aus E, die nicht gingen.

---

## G · Abschluss

**G1.** Die temporäre sudo-Regel löschen, falls du B12 gemacht hast. Danach meldet `zen doctor` dazu nichts mehr:

```
sudo rm /etc/sudoers.d/zenos-bau
```

**G2.** Final taggen, auf dem Mac. Der Tag startet auf GitHub den Bau des Images. Lass vorher in `CHANGELOG.md` einen
Eintrag «0.1.0» ergänzen (was sich seit `v0.1.0-rc1` geändert hat). In den Ordner wechseln:

```
cd ~/Documents/github/zenOS
```

**G3.**

```
git switch dev
```

**G4.**

```
git pull
```

**G5.**

```
git tag -a v0.1.0 -m "zenOS 0.1.0"
```

**G6.**

```
git push origin v0.1.0
```

Nach dem Bau liegen `zenos-0.1.0-pi5-arm64.img.xz` und `SHA256SUMS` unter Releases auf GitHub. Den Stand des Baus
zeigt GitHub unter Actions.

**G7 bis G10: `main` auf den Stand bringen** (deine Entscheidung). Solange `main` nur den Start-Commit enthält,
braucht jede Installation `git switch dev`. Vorschlag: `main` auf `v0.1.0` vorspulen. Dann funktionieren
`git clone … ~/zenOS` und `./scripts/install.sh` ohne `git switch dev`, und neue Installationen folgen dem Kanal
`main`. Der Pi bleibt auf dem Kanal `dev` (steht in `/etc/xdg/zenos/kanal`).

**G7.**

```
git switch main
```

**G8.**

```
git merge --ff-only v0.1.0
```

**G9.**

```
git push origin main
```

**G10.**

```
git switch dev
```

**Offene Entscheidungen für dich**
- Firewall einschalten: per SSH aus dem eigenen Netz `zen firewall aktivieren`, danach von einem zweiten Gerät neu
  per SSH verbinden. Zurück mit `sudo ufw disable`.
- Safe Browsing in Chrome: Stufe 2 (erweitert, heute gesetzt) oder Stufe 1, siehe `docs/sicherheit.md`.
- Kanal des Images: Es folgt heute `dev`. Trägt `main` Releases, kann es auf `main` wechseln (Option `--kanal` von
  `image/bauen.sh` im Workflow).
- fish als Login-Shell, damit auch SSH-Sitzungen Eingabezeile, `?` und die Warnung haben: `chsh -s /usr/bin/fish`.
