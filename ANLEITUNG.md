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
Start-Commit, `dev` zenOS 0.1 mit dem Tag `v0.1.0-rc2`. Die früheren Schritte A1 bis A14 fallen weg.

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
- Bricht sie mit «apt-get install ist fehlgeschlagen» oder «Failed to fetch» ab, war meist das Netz oder der
  Paketserver kurz weg. Dann `./scripts/install.sh` einfach noch einmal starten, Erledigtes bleibt. Den Rat von apt
  («apt update», «--fix-missing») braucht es nicht.
- Die SSH-Verbindung bleibt bestehen. Der Bildschirm am Pi bleibt bis zum Neustart bei der Textkonsole.
- Gegen Ende schaltet es die Firewall ein («Firewall eingeschaltet»): Herein kommt dann nur noch SSH aus lokalen
  Netzen. Vorher prüft es, ob deine SSH-Verbindung erlaubt bleibt; kommt sie aus einem anderen Netz (etwa über ein
  VPN), bleibt die Firewall aus und eine Warnung nennt den Grund.
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

Erwartet wird `0 Fehler`. Hinweise sind normal, zum Beispiel «greetd läuft noch nicht», «Bootsplash vorbereitet,
nicht aktiv» und die noch nicht installierten Apps. Eine Warnung gibt es nur, wenn du die sudo-Regel aus B12 angelegt
hast, oder wenn die Firewall aus ist. Sie ist ab jetzt an («Firewall an»); bleibt sie aus, steht der Grund in der
Ausgabe von C2 (zum Beispiel eine SSH-Verbindung aus einem anderen Netz).

**C5.** WLAN-Menü einschalten. Bis hier läuft das Netz wie bei Ubuntu Server über netplan; ein neues WLAN müsstest
du von Hand in eine netplan-Datei schreiben. Mit diesem Befehl verwaltet NetworkManager das Netz, und du wählst WLANs
oben rechts im System-Menü. Der Befehl zeigt vorher, was passiert: welche WLANs er übernimmt (je ein eigenes
Profil, die Passwörter bleiben), wo er die alten Dateien sichert, und dass er auf dem Raspberry Pi WPA3 im
WLAN-Treiber abschaltet (Mischnetze verbinden dann über WPA2, reine WPA3-Netze gehen mit diesem WLAN-Chip ohnehin
nicht). Erst wenn du «umstellen» eintippst, stellt er um. Wirksam wird es mit dem Neustart in D1, bis dahin bleibt
das Netz, wie es ist:

```
zen netzwerk umstellen
```

Mach den Neustart am Gerät, dort, wo ein bekanntes WLAN oder ein Kabel da ist. Geht danach kein Netz, am Gerät in
kitty `zen netzwerk zurueck` und `sudo reboot` (siehe F). Auf einem schon installierten zenOS gilt dasselbe: nach
`zen update` einmal `zen netzwerk umstellen`, dann `sudo reboot`.

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
- [ ] Nach dem Neustart erscheint der zenOS-Login: dunkel, grosse Uhrzeit, dein Benutzer vorausgewählt, unten mittig
  die Bildmarke (zwei Steine, der untere salbeigrün). Niemand wird automatisch angemeldet.
- [ ] Ein falsches Passwort zeigt «Das Passwort stimmt nicht. Bitte noch einmal.», das Feld ist danach leer, nichts
  springt. Das richtige Passwort meldet an, auch mit Sonderzeichen deiner Tastatur.
- [ ] «Neustart» und «Ausschalten» im Login führen erst beim zweiten Klick aus.
- [ ] Die Einrichtung fragt nach Name, Ort (optional), Erscheinungsbild und erstem Modus. Nach «Einrichten» ist der
  Modus aktiv: Seine Akzentfarbe steht in der Leiste und in «Heute».
- [ ] Solange die Einrichtung offen ist, bewirken `Super + Leertaste`, `Super + M`, `Super + Z` und `Super + Komma`
  nichts, die Tastatur bleibt im Formular. Bekannte Ausnahme: `Ctrl + Alt + T` öffnet kitty unsichtbar dahinter.
- [ ] Danach listet die Einrichtung Chrome, VS Code, 1Password, 1Password-CLI und coremail mit Herkunft; Nubix steht
  mit «noch kein ARM-Build» da. Der Fokusrahmen liegt auf «Installieren», Enter genügt. Es öffnet ein Terminal, zeigt
  Quellen, Schlüssel und Dateien, fragt einmal nach und dann nach dem sudo-Passwort. Passt die Übersicht nicht ins
  Fenster, steht vor der Frage ein Hinweis; mit dem Mausrad oder `Ctrl + Shift + Bild↑` siehst du den Anfang.
  «Später» (oder `Esc`) führt zu Einstellungen → Apps.
- [ ] Chrome, VS Code, 1Password und coremail starten danach aus dem Befehlsfeld. coremail steht dort genau einmal,
  auch nach seinem ersten Start. Die Symbole von VS Code, 1Password und coremail erscheinen erst nach dem nächsten
  Anmelden, bis dahin steht der Anfangsbuchstabe da. `op --version` zeigt die 1Password-CLI.
- [ ] Chrome zeigt in einem neuen Profil keine Leiste «Google Chrome isn't your default browser», und Links aus
  anderen Apps öffnen in Chrome.
- [ ] Abmelden (System-Menü → Abmelden) führt zurück zum Login. Nach dem nächsten Anmelden erscheint die Einrichtung
  nicht mehr.

**Leiste, «Heute» und Erscheinungsbild**
- [ ] Die Leiste zeigt links Zeichen, Modus und Raster («4er»), in der Mitte Datum und Uhrzeit in deiner Ortszeit,
  rechts Glocke, Hell/Dunkel und den System-Knopf mit Temperatur. Sie sieht aus wie Entwurf 2.
- [ ] Der Ordner rechts neben «4er» öffnet `~/Ablage` in Thunar (mit Symbolen, eine Titelzeile, hell und dunkel);
  ein Download aus Chrome landet dort, Rechtsklick → «Terminal hier öffnen» startet kitty.
- [ ] «Heute» zeigt Wochentag, Tageszahl, einen Gruss mit deinem Namen und unten die Tastenkappen für Super +
  Leertaste, Super + M und Super + Z.
- [ ] Der Hell/Dunkel-Schalter wechselt ohne Flackern: Leiste, «Heute», Fensterrahmen, kitty, Chrome und VS Code (nach
  seinem ersten Start). Ein laufendes Chrome wechselt in beide Richtungen, auch von dunkel zurück auf hell.
- [ ] Das System-Menü zeigt Netz, Lautstärke mit Regler, 1Password, Temperatur und Lüfter, dazu Sperren,
  Einstellungen, Abmelden, Neustart und Ausschalten. Abmelden, Neustart und Ausschalten fragen einmal nach.

**WLAN (oben rechts, nach C5)**
- [ ] `zen netzwerk status` zeigt «Netz: NetworkManager», «NetworkManager: aktiviert · läuft», die übernommenen
  WLANs und das WLAN-Land mit «gesetzt». `zen doctor` zeigt im Abschnitt «Netz» keine Warnung.
- [ ] Die Leiste zeigt im System-Knopf das WLAN-Symbol mit Signalstufe (ein bis drei Bögen, die fehlenden blass).
- [ ] Das System-Menü zeigt «WLAN» mit Schalter und das verbundene Netz mit Haken. «Netze in Reichweite» klappt
  die Liste auf: Netze mit Signal und Schloss, das verbundene oben, dann die bekannten.
- [ ] Ein neues Netz mit Passwort: Klick darauf, das Passwortfeld erscheint (Punkte statt Zeichen), Enter verbindet.
  Danach steht es oben mit Haken.
- [ ] Ein falsches Passwort zeigt ruhig «Passwort falsch?» unter dem Feld, das Feld ist leer. Esc bricht ab;
  danach liegt für dieses Netz kein Profil herum (`ls /etc/netplan` zeigt keine neue Datei).
- [ ] Ein bekanntes Netz verbindet mit einem Klick, ohne Passwort.
- [ ] «x» bei einem gespeicherten Netz fragt «… vergessen?», der zweite Klick vergisst es; unter `/etc/netplan`
  verschwindet genau eine Datei.
- [ ] Der Schalter schaltet WLAN aus und wieder ein; danach verbindet es sich von selbst wieder. Ein Klick auf das
  Wort «WLAN» schaltet nichts.
- [ ] Ein offenes Netz (ohne Schloss) verbindet mit einem Klick. Danach zeigt
  `nmcli -g connection.autoconnect connection show <Name>` «no»: Es verbindet sich später nur auf Klick.
- [ ] Mit mehr als fünf Netzen in Reichweite ist die unterste Zeile angeschnitten, und die Liste scrollt.
- [ ] Mit der Tastatur: Pfeile wandern durch die Netze, Enter wählt, im Passwortfeld bricht Esc ab, sonst schliesst
  Esc das Menü.
- [ ] Beim Teilen des Bildschirms zeigt das Menü keine Netznamen («Netzname verborgen»).
- [ ] Das Büro-WLAN: Erst nachsehen, was es anbietet: `nmcli -f SSID,SECURITY dev wifi | grep -i <Name>`.
  «WPA2 WPA3» heisst Mischnetz, es verbindet jetzt über WPA2. Steht nur «WPA3», ist es reines WPA3 und geht mit
  diesem WLAN-Chip nicht (im Menü dann z. B. «Anmeldung dauerte zu lange. Bietet das Netz nur WPA3 an, geht es mit
  diesem WLAN-Chip nicht.»); dann vergessen. Der Menütext allein unterscheidet die beiden nicht.

**Befehlsfeld**
- [ ] `Super + Leertaste` öffnet es, `Esc` oder nochmals `Super + Leertaste` schliesst es.
- [ ] Ein Klick auf das Zeichen oben links öffnet es mit allen installierten Apps als Raster: Die Karte gleitet ruhig
  vom Zeichen her auf, ohne Ruckeln. Pfeiltasten wählen (mit Fokusrahmen), Enter oder ein Klick startet, Tippen
  sucht; ein zweiter Klick auf das Zeichen schliesst. Auch in hell und dunkel prüfen.
- [ ] `1440 / 16` zeigt `90`, Enter kopiert den Wert («90 kopiert»).
- [ ] Apps starten, Dateien im Home-Ordner finden und öffnen.
- [ ] Mit `Tab` zu den Werkzeugen: Das Bildschirmfoto eines Bereichs landet in der Zwischenablage und in
  `~/Bilder/Screenshots`. Dasselbe mit `Print` und `Super + Shift + S`.
- [ ] Die Pipette (`Super + Shift + C`) kopiert per Klick einen Farbwert wie `#A7B89F`.
- [ ] Aktionen wie «Hell/Dunkel», «Sperren» und «Einstellungen» funktionieren auch von hier.
- [ ] Sind die Apps installiert, zeigt die Suche «chrome» Chrome ohne die Zeile «Apps installieren». «apps» zeigt
  «Apps verwalten», Enter öffnet Einstellungen → Apps.

**Mitteilungen**
- [ ] Ohne Zustand wartet `notify-send "Test" "Hallo"`: Die Leiste zeigt «1 · HH:00» mit der nächsten vollen Stunde,
  dann erscheint oben rechts eine ruhige Sammelkarte.
- [ ] `notify-send -u critical "Test" "Dringend"` erscheint sofort als Karte.
- [ ] Mit dieser Karte oben rechts das System-Menü öffnen: Die Karte tritt zurück, das Menü lässt sich ganz bedienen.
  Nach dem Schliessen des Menüs ist die Karte wieder da.
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
  Wechsel ändert den Akzent in Leiste, Fensterrahmen und kitty. Im Zeichen links in der Leiste blendet nur der untere
  Stein weich zur neuen Farbe über; bei hell/dunkel wechseln beide Steine im selben Moment.
- [ ] Mit Chrome-Profil im Modus (das Profil vorher in Chrome anlegen) und «Beim Wechsel öffnen: Chrome» öffnet
  Chrome beim Wechsel im Profil des neuen Modus, auch wenn Chrome schon offen ist (dann ein neues Fenster in diesem
  Profil; ist dort schon eines offen, keins).
- [ ] Fokus starten: Die Leiste zeigt «Fokus» mit Restzeit, Raster-Knopf und Hell/Dunkel treten zurück, «Heute»
  blendet seinen Inhalt aus.
- [ ] Sitzung: Zuerst eine dringende Mitteilung anzeigen lassen, sie bleibt oben rechts stehen:
  `notify-send -u critical Test Geheim`. Dann in Chrome den Bildschirm teilen, etwa auf einer Testseite für
  Bildschirmfreigabe oder in einem Videocall: den Bildschirm anklicken, den du teilen willst, dann in Chromes Dialog
  mit Vorschau «Teilen» («Share»). Die Sitzung startet von selbst: Rahmen und «Dieser Bildschirm wird geteilt», in der
  Leiste «Sitzung», auf der Karte nur «Inhalt verborgen, Bildschirm wird geteilt». Beim Klick auf «Teilen» endet
  «Sitzung» nicht kurz, und die ersten Bilder beim Empfänger (Vorschau der Testseite, zweites Gerät) zeigen keinen
  Inhalt der Mitteilung. Weitere Mitteilungen zeigt die Leiste als «N zurückgehalten».
- [ ] Danach «Freigabe beenden» («Stop sharing») und sofort neu teilen: wieder ohne Unterbrechung. Rund 5 s nach dem
  Ende der Freigabe endet die Sitzung, und Zurückgehaltenes wird zugestellt. Diese kurze Nachlaufzeit ist Absicht.

**Raster**
- [ ] `Super + 1` bis `Super + 4` setzen das aktive Fenster in die Viertel (4er-Grid, der Standard).
- [ ] `Super + Links` und `Super + Rechts` setzen es in die linke und rechte Hälfte.
- [ ] `Super + Enter` maximiert und stellt wieder her.
- [ ] Raster-Knopf in der Leiste → «3 Spalten»: `Super + 1` bis `Super + 3` setzen in die drei Spalten.
- [ ] Mit der Maus: Fenster an der Titelzeile ziehen und Super halten, die Bereiche erscheinen, Loslassen rastet ein.
- [ ] Mit zweitem Bildschirm: `Super + Shift + Links` bzw. `Rechts` schiebt das Fenster hinüber; Leiste und «Heute»
  sind auf beiden.
- [ ] Fensterrahmen: Titelzeile in Geist Mono, oben runde Ecken (unten eckig, das ist eine Grenze von labwc). Das gilt
  für Fenster mit zenOS-Rahmen wie kitty; Chrome zeichnet seinen eigenen (siehe «Offene Entscheidungen» in G).
- [ ] Scrollen: Der Inhalt folgt den Fingern (natürlich). Einstellungen → Allgemein → «Scroll-Tempo»: «Langsam» bzw.
  «Sehr schnell» scrollt in Chrome und kitty sofort halb bzw. doppelt so weit, mit Touchpad und Mausrad, ohne
  Abmelden. Zum Schluss die Stufe wählen, die sich richtig anfühlt.

**Fenster wechseln**
- [ ] `Alt + Tab` (Alt halten): Die Liste ist breit, jede Zeile beginnt mit einem grossen App-Symbol, daneben Name und
  Fenstertitel. Hell und dunkel prüfen; nichts ruckelt beim ersten Tastendruck.
- [ ] Mehrere Apps offen (z. B. Chrome, Mail, kitty): Mit der Maus rechts in der Mitte an den Rand fahren und kurz
  ruhen. Rechts gleitet eine schmale Karte mit einem Symbol pro App herein, die aktive App hat einen kleinen Punkt,
  beim Zeigen steht der Name daneben. Oben oder unten am Rand und beim blossen Vorbeifahren erscheint nichts, sonst
  ist am Rand nichts zu sehen.
- [ ] Chrome im Vollbild (`F11`): rechts mittig an den Rand, Klick auf das Mail-Symbol → die Mail ist vorne. Über
  die Leiste zurück zu Chrome. Die Karte verschwindet nach dem Klick und kurz nach dem Wegfahren.
- [ ] App mit zwei Fenstern (z. B. zwei kitty): Die Karte zeigt «2» am Symbol, ein Klick auf die schon aktive App
  wechselt zum anderen Fenster. Ein minimiertes Fenster kommt per Klick zurück.

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
  wie «Bootsplash vorbereitet, nicht aktiv».
- [ ] `zen update` meldet «Schon aktuell» oder alt → neu und endet mit `installiert · N Änderungen`. Die Oberfläche ist
  danach vollständig da.
- [ ] `zen rollback v0.1.0-rc2` geht auf den Tag zurück, `zen version` zeigt ihn. `zen update` bringt dich wieder auf
  `dev`.
- [ ] Die Temperatur steht in der Leiste, der Lüfter im System-Menü (Argon ONE). Unter Last (in kitty viermal
  `yes > /dev/null &`, danach `pkill yes`) wird der Lüfter hörbar schneller und später wieder leiser.
- [ ] Argon-Knopf: Doppeltipp startet neu, drei Sekunden halten schaltet aus, einmal kurz drücken tut nichts.
  (Nur Argon ONE V3 am Pi 5.)

**Argon ONE UP (Laptop mit Compute Module 5)**
- [ ] Vor der Freigabe: Im System-Menü steht «Akku · nicht freigegeben», `zen akku status` zeigt «Akkuprofil
  schreiben: nicht freigegeben». Der Messchip bleibt unberührt.
- [ ] In kitty `zen akku freigeben`: Die Erklärung nennt die Register und das Risiko, erst «freigeben» legt die
  Freigabe an. Innerhalb von 15 Sekunden steht der Ladestand in der Leiste.
- [ ] Oben rechts im System-Knopf steht der Akku mit Prozent, etwa «87 %». Am Netzteil zeigt das Symbol einen
  Blitz. Netzteil aus- und wieder einstecken: Der Blitz verschwindet bzw. erscheint nach 10 bis 25 Sekunden, ohne
  Flackern.
- [ ] Das System-Menü zeigt nach 1Password: Akku («87 % · lädt», am Netz voll «100 % · Netzteil»), Lüfter («aus»
  oder «Stufe 2 von 4 · 3120 U/min») und CPU-Temperatur. Unter Last (viermal `yes > /dev/null &`, danach
  `pkill yes`) steigen Temperatur und Lüfterstufe, danach sinken sie wieder.
- [ ] Der Prozentwert ist plausibel: voll geladen nahe 100 %, nach einer Stunde Arbeit spürbar weniger. Direkt nach
  dem ersten Start braucht der Akku-Messchip etwas Zeit, bis die Werte stimmen.
- [ ] Im Akkubetrieb bei 10 % und darunter: Akku in Gelb (Warnfarbe), nichts blinkt. Eine ruhige Mitteilung «Akku
  bei N %» kommt (ohne Zustand gebündelt zur nächsten vollen Stunde, Glocke «1 · HH:00»). Bei 5 % ersetzt sie eine
  dringende Karte, die sofort erscheint, ohne Ton. Es steht immer nur eine Akku-Mitteilung da. zenOS fährt nicht
  selbst herunter. Nach dem Einstecken verschwindet die Akku-Mitteilung, und es beginnt von vorn.
- [ ] Per SSH, nur lesend: `sudo /opt/zenos/scripts/bin/zenos-argon --pruefen` zeigt «Messchip aktiv, Argons
  Akkuprofil ist geladen» und den Ladestand. `zen doctor` zeigt im Abschnitt «Argon ONE» den Akku.
- [ ] In Chrome zeigt `chrome://policy` 13 zenOS-Richtlinien ohne Fehler. Die 1Password-Erweiterung ist fest
  installiert, andere Erweiterungen sind gesperrt.
- [ ] In VS Code steht die Einstellung `telemetry.telemetryLevel` auf `off` und ist von der Organisation verwaltet.
- [ ] `zen firewall status` zeigt «an» und die fünf SSH-Regeln für die lokalen Netze (`LIMIT IN`). Von einem
  zweiten Gerät im selben Netz geht `ssh` weiterhin; die laufende SSH-Sitzung riss beim Einschalten nicht ab.
- [ ] Einstellungen → System: Der Schalter «Firewall» steht auf «An». Ausschalten: Es erscheint mittig der Dialog
  «Firewall ausschalten» mit «Passwort von <dein Benutzername>», das Feld hat sofort den Fokus. Ein falsches
  Passwort: «Das Passwort stimmt nicht.», der Dialog bleibt offen. Esc: Der Dialog schliesst, der Schalter springt
  auf «An» zurück. Mit dem richtigen Passwort: «Aus», im System-Menü steht «Firewall · aus», `zen doctor` warnt.
- [ ] `zen update` lässt die ausgeschaltete Firewall aus («Firewall bleibt aus: bewusst ausgeschaltet»).
- [ ] Wieder einschalten mit dem Schalter: ohne Passwort, sofort «An». Danach nochmals ausschalten, den Dialog offen
  lassen und mit `Super + L` sperren: Nach dem Entsperren ist kein Dialog da, die Firewall ist noch an.
- [ ] `journalctl -t zenos-firewall` zeigt jeden Wechsel mit Weg (Einstellungen über pkexec, sudo, install.sh).
- [ ] 1Password-SSH-Agent: in 1Password → Einstellungen → Entwickler einschalten, ab- und wieder anmelden. Dann meldet
  `ssh -T git@github.com` dich über 1Password an (1Password fragt nach der Freigabe; dein SSH-Schlüssel liegt in
  1Password und ist bei GitHub eingetragen).
- [ ] Direkt nach der Installation meldet `zen doctor` «unattended-upgrades ist noch nie gelaufen». Am Tag danach
  (der Lauf ist gegen 6 Uhr, war der Pi da aus, kurz nach dem Start) steht dort «Letzter erfolgreicher Lauf von
  unattended-upgrades: …».
- [ ] Bootsplash: `zen doctor` zeigt «Bootsplash vorbereitet, nicht aktiv», beim Start erscheint noch keiner. Er bleibt
  aus, bis du entscheidest (siehe G).

**Flüssigkeit**
- [ ] Befehlsfeld, Hell/Dunkel, Fensterwechsel (`Alt + Tab` und App-Leiste) und Einrasten laufen flüssig (60 fps).
  Nichts ruckelt, nichts blinkt.

---

## F · Wenn etwas nicht geht

**Häufige Fälle**

Der Pi zeigt nach dem Flashen nichts an, nur die LEDs leuchten: meist ist der Bootloader zu alt (siehe «Vorab» in B).

`install.sh` oder `zen update` bricht mit «apt-get install ist fehlgeschlagen» oder «Failed to fetch» ab: Das Netz
oder der Paketserver war kurz weg. Denselben Befehl noch einmal starten, Erledigtes bleibt.

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

Statt des zenOS-Logins erscheint ein schlichter Login mit «Der Login konnte nicht vollständig geladen werden»:
Anmelden geht trotzdem. Danach meldet `zen doctor` «Login lief im Notfall-Modus …». Alle Zeilen des Logins zeigt per
SSH dieser Befehl (zeigt er nichts, mit `sudo` davor):

```
journalctl -b -t zenos-greeter
```

Der Login meldet «Das Passwort muss zuerst geändert werden»: mit `Ctrl + Alt + F2` zur Textkonsole, dort anmelden, ein
neues Passwort setzen, mit `exit` abmelden und mit `Ctrl + Alt + F7` zurück zum zenOS-Login.

Die Oberfläche hängt oder fehlt: per SSH neu starten. Ist die Sitzung gesperrt, sperrt sie danach sofort wieder.

```
systemctl --user restart zenos-shell.service
```

Nach `zen netzwerk umstellen` und dem Neustart kein Netz: am Gerät in kitty zurück auf netplan, danach neu
starten (geht ohne Netz):

```
zen netzwerk zurueck
```

Nach einem Update geht etwas nicht mehr: zurück zum letzten guten Stand.

```
zen rollback v0.1.0-rc2
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

**G1.** Die temporäre sudo-Regel löschen, falls du B12 gemacht hast. Danach zeigt `zen doctor` dazu keine Warnung
mehr:

```
sudo rm /etc/sudoers.d/zenos-bau
```

**G2.** Final taggen, auf dem Mac. Der Tag startet auf GitHub den Bau des Images. Lass vorher in `CHANGELOG.md` einen
Abschnitt «0.1.0» mit Datum ergänzen (was sich seit `v0.1.0-rc2` geändert hat). In den Ordner wechseln:

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
- Firewall: Sie ist jetzt standardmässig an (eingehend gesperrt, SSH nur aus lokalen Netzen, je Adresse höchstens
  fünf neue Verbindungen in 30 s). Wer SSH über ein VPN (z. B. Tailscale) braucht, sagt es; dafür fehlt heute
  eine Regel. Verbindet sich dein Mac über eine öffentliche IPv6-Adresse des Geräts (möglich, wenn das Heimnetz
  IPv6 hat und der Name auch zu einer IPv6-Adresse auflöst), hängt ein neues `ssh` bei eingeschalteter Firewall
  rund eine Minute, bevor es über IPv4 geht; siehe «Offen» in `docs/module/m11.md`.
- Safe Browsing in Chrome: Stufe 2 (erweitert, heute gesetzt) oder Stufe 1, siehe `docs/sicherheit.md`.
- Sicheres DNS in Chrome: heute aus, weil Chrome es mit Richtlinien von selbst abschaltet. Eine Richtlinie könnte es
  festlegen, der Schalter bliebe gesperrt, siehe `docs/sicherheit.md`.
- Rahmen von Chrome: Chrome zeichnet heute seinen eigenen, ohne zenOS-Titelzeile und Akzentrand, und eingerastet ragt
  sein Schatten in die Lücke. Den zenOS-Rahmen bekommt es in Chrome unter «Darstellung» mit Titelleiste und Rahmen
  des Systems (pro Chrome-Profil). Ob zenOS das vorgibt, siehe `docs/module/m9.md`, «Apps mit eigenem Rahmen».
- Kanal des Images: Es folgt heute `dev`. Trägt `main` Releases, kann es auf `main` wechseln (Option `--kanal` von
  `image/bauen.sh` im Workflow).
- fish als Login-Shell, damit auch SSH-Sitzungen Eingabezeile, `?` und die Warnung haben: `chsh -s /usr/bin/fish`.
- Bootsplash einschalten: per SSH `zen bootsplash aktivieren`. Es zeigt jeden Schritt vorher (Pakete, Standard-Theme,
  «quiet splash» in der Boot-Kommandozeile, neues initramfs) und fragt nach. Danach startet der Pi zweimal. Zurück mit
  `zen bootsplash deaktivieren`. Was du danach prüfst: `docs/module/bootsplash.md`, «Am Pi prüfen».
