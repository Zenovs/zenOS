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
Start-Commit, `dev` zenOS 0.1 mit den Release-Kandidaten `v0.1.0-rc1` bis `v0.1.0-rc3` (unsigniert, nur als
Workflow-Artefakt). `v0.1.0-rc4` ist der erste signierte (G); sein Image-Bau scheiterte, die erste Release-Seite, als
Vorabversion markiert, kommt mit `v0.1.0-rc5`. Die früheren Schritte A1 bis A14 fallen weg.

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

**B11.** zenOS 0.1 liegt auf `dev`, solange `main` nur den Start-Commit enthält (bis G11):

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

Erwartet wird `0 Fehler`. Hinweise sind normal, zum Beispiel «greetd läuft noch nicht», «Bootsplash vorbereitet, nicht
aktiv» und die noch nicht installierten Apps. Eine Warnung gibt es nur, wenn du die sudo-Regel aus B12 angelegt hast
(ohne sie: wenn sudo sonst ohne Passwort geht, siehe G1), oder wenn die Firewall aus ist. Sie ist ab jetzt an («Firewall
an»); bleibt sie aus, steht der Grund in der Ausgabe von C2 (zum Beispiel eine SSH-Verbindung aus einem anderen Netz).

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
  Bildschirm aus, Einstellungen, Abmelden, Neustart und Ausschalten. Abmelden, Neustart und Ausschalten fragen einmal
  nach.

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
  `~/Ablage/Screenshots`. Dasselbe mit `Print` und `Super + Shift + S`.
- [ ] Die Pipette (`Super + Shift + C`) kopiert per Klick einen Farbwert wie `#A7B89F`.
- [ ] Aktionen wie «Hell/Dunkel», «Sperren», «Bildschirm aus» und «Einstellungen» funktionieren auch von hier.
  «Energie» öffnet Einstellungen → Energie.
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

**Energie** (Einzelheiten in `docs/module/energie.md`)
- [ ] Einstellungen → Energie zeigt «Ohne Eingabe: Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min. · Aus nach
  65 Min. im Akkubetrieb», hell und dunkel. «Bereitschaft» sagt «Auf diesem Gerät nicht verfügbar …».
- [ ] `Super + Shift + L` sperrt und macht den Bildschirm dunkel, wirklich dunkel (auch das Hintergrundlicht).
  Dasselbe mit «Bildschirm aus» im System-Menü. Shift, eine Buchstabentaste oder das Touchpad wecken ihn, die Sperre
  bleibt, im Passwortfeld steht kein Punkt, und das Passwort klappt beim ersten Versuch.
- [ ] Ohne Eingabe: nach 5 Minuten gesperrt, eine Minute später dunkel. Eine Eingabe weckt, nach einer Minute ohne
  Eingabe wird es wieder dunkel.
- [ ] Ein Video in Chrome (Vollbild, ohne Eingabe): zenOS sperrt nicht nach 5 Minuten, aber spätestens nach
  60 Minuten. Mit dem Video im Hintergrund-Tab oder minimiert: sperrt es nach 5 Minuten? Gesperrt geht der Bildschirm
  auch mit laufendem Video nach einer Minute aus.
- [ ] Die Ein/Aus-Taste kurz drücken: zenOS sperrt und macht dunkel, das Gerät bleibt an. Nochmals kurz: hell.
  `systemd-inhibit --list` zeigt «zenOS» mit handle-power-key. Am Login-Bildschirm schaltet ein kurzer Druck aus.
  Mit Ctrl+Alt+F3 auf eine Textkonsole wechseln (die Sitzung läuft weiter) und kurz drücken: Was passiert? Notieren
  und melden (zurück mit Ctrl+Alt+F7).
- [ ] Ausschalten: Einstellungen → Energie → «Immer», «Nach 30 Min.». Sperren und 30 Minuten warten (ohne SSH,
  ohne tmux). Der Bildschirm geht an, die Sperre zeigt «zenOS schaltet um HH:MM aus · Eine Taste bricht ab». Eine
  Taste bricht ab, es bleibt gesperrt. Nochmals 30 Minuten warten, dann schaltet das Gerät nach 60 s aus. Nach dem
  Einschalten und Anmelden kommt einmal die Mitteilung «zenOS hat ausgeschaltet».
- [ ] Mit offener SSH-Sitzung oder laufendem tmux schaltet es nicht aus. `journalctl -t zenos-energie` nennt den
  Grund, Einstellungen → Energie zeigt «Zurzeit nicht: SSH-Sitzung offen». Danach wieder «Im Akkubetrieb» und
  «60 Min.» einstellen.
- [ ] Während der Vorwarnung (`zenos-ipc energie vorwarnung`, gesperrt) direkt das Passwort tippen und Enter: Es
  entsperrt beim ersten Versuch.
- [ ] Login-Bildschirm, Bildschirm aus: Abmelden und eine Minute nichts tun. Der Bildschirm wird dunkel (auch das
  Hintergrundlicht). Tippen in Abständen unter einer Minute hält ihn an.
- [ ] Wecken am Login-Bildschirm, je nach einer dunklen Minute: eine Buchstabentaste, ein Klick auf «Anmelden», ein
  Tipp auf dem Touchpad, eine Berührung des Bildschirms (falls er das kann). Jedes Mal wird er hell, im Passwortfeld
  steht kein Punkt, und nichts wird ausgelöst (kein «Anmelden», kein «Jetzt neu starten»).
- [ ] Am Login-Bildschirm drei Zeichen des Passworts tippen, eine Minute warten (dunkel), mit einer Taste wecken, den
  Rest tippen und Enter: Die Anmeldung klappt beim ersten Versuch, danach ist der Bildschirm an.
- [ ] Dasselbe, aber die Taste zum Wecken 2 s halten, bis der Bildschirm hell ist: kein Punkt dazu, die Anmeldung
  klappt beim ersten Versuch. Mit gehaltenem Enter wecken: Es meldet nicht an.
- [ ] Dasselbe am Netzteil und am Akku (Argon ONE UP). Mit Deckel: zuklappen, eine Minute warten, aufklappen. Der
  Bildschirm wird von selbst hell, das erste Zeichen landet im Feld. Kurz nach einer Eingabe zuklappen und nach
  50 s aufklappen: Er bleibt danach eine Minute hell.
- [ ] Am dunklen Login den Monitor aus- und wieder anstecken: Er wird hell, das erste Zeichen landet im Feld.
- [ ] `journalctl -b -t zenos-greeter` zeigt «Bildschirm aus» und «Wecktaste verworfen», keine Zeile «gescheitert».
- [ ] Login-Bildschirm im Akkubetrieb (nur Argon ONE UP): Abmelden, Netzteil ab, 30 Minuten nichts tun. Die Zeile
  «zenOS schaltet um HH:MM aus · Eine Taste bricht ab» erscheint, eine Taste bricht ab. Ohne Eingabe schaltet das
  Gerät 60 s später aus.
- [ ] `zen energie` zeigt die Zeiten, was das Ausschalten gerade aufhält, die Ein/Aus-Taste, «Bildschirm jetzt an»
  und die Bereitschaft. `zen doctor` zeigt den Abschnitt «Energie» ohne Fehler.

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

**Fensterübersicht, Schreibtisch und Wischen** (Einzelheiten in `docs/design.md` und `docs/module/m9.md`, Rechte in
`docs/sicherheit.md`, «Gesten»). Am 06.10.2026 schon lesend geprüft: Das Touchpad meldet drei bis fünf Finger.
- [ ] `zen doctor`, Abschnitt «Gesten»: «Touchpad eventN: nur für zenos-gesten lesbar (0640)», «… meldet drei Finger
  (BTN_TOOL_TRIPLETAP)», «Diese Sitzung hat keine Rechte an /dev/input», der Dienst läuft als zenos-gesten, «Oberfläche
  liest die Gesten», ohne Fehler. Steht dort «hat auch Tasten», liegt das Touchpad auf einem Knoten mit
  Tastatur-Tasten: Dann bleibt es für den Dienst gesperrt, das Wischen fällt weg (Super+Tab geht weiter). Melden.
- [ ] Touchpad, Zeiger, Tippen und Scrollen gehen nach der udev-Regel wie vorher. `id` zeigt weder `input` noch
  `zenos-gesten`, und `test -r /dev/input/eventN && echo lesbar || echo gesperrt` (N aus `zen doctor`) zeigt
  «gesperrt».
- [ ] `systemd-analyze security zenos-gesten.service` zeigt höchstens 0.8. `/opt/zenos/scripts/install.sh` läuft
  zweimal hintereinander ohne Fehler, der zweite Lauf meldet `0 Änderungen`.
- [ ] Display des Argon ONE UP: `wlr-randr` zeigt Auflösung und Skalierung. Notieren und melden (der Entwurf nahm
  1920 × 1200 an, ungeprüft). Daraus folgen die Spalten der Übersicht (bei 1920 px höchstens 7) und wie viele Zeilen
  ohne Scrollen passen.
- [ ] `Super + Tab` mit 10 oder mehr echten Fenstern (Chrome, VS Code, kitty, Firefox), hell und dunkel: Die
  Übersicht ist sofort da, die Kacheln blenden ruhig ein, nichts ruckelt. Der Hintergrund deckt die Fenster ruhig zu,
  Name und Titel sind gut lesbar. Das aktive Fenster hat den Punkt, vorgewählt ist das vorige: `Enter` führt dorthin
  zurück.
- [ ] In der Übersicht: Pfeile, `Tab` und `Shift + Tab` wählen (mit Fokusrahmen), Tippen filtert («chr» lässt nur
  Chrome stehen), `Enter` wechselt, `Esc` oder nochmals `Super + Tab` schliesst. Mit der Maus wählt Zeigen, ein Klick
  wechselt, ein Klick daneben schliesst. Ein minimiertes Fenster («minimiert») kommt per Klick zurück, ein Fenster
  wechselt auch aus einem Video im Vollbild.
- [ ] Wie schnell? Per SSH `time /opt/zenos/scripts/bin/zenos-ipc uebersicht umschalten` (zweimal, das zweite Mal
  schliesst es). Im Container dauerte der Aufruf 16 bis 20 ms; am Pi die Zeit «real» notieren und melden.
- [ ] `Super + Tab` und `Super + H` in kitty, Chrome, Firefox und VS Code: Sie lösen aus, ohne dass die App selbst
  reagiert. In kitty schliesst `Super + W` weiter einen Tab, und `Super + D` teilt weiter.
- [ ] Schreibtisch mit drei Fenstern, ein viertes vorher von Hand minimiert: `Super + H` räumt alle weg, «Heute» zeigt
  rechts «Super H · Fenster zurück» (hell und dunkel). Nochmals `Super + H`: Die drei kommen zurück, das von Hand
  minimierte bleibt unten, das vorher aktive ist wieder aktiv. Liegen die Fenster wieder brauchbar übereinander?
  Dasselbe mit einem Video im Vollbild in Chrome.
- [ ] Nach `Super + H` ein Fenster über die App-Leiste holen: Die Tastenkappe «Super H · Fenster zurück»
  verschwindet, und das nächste `Super + H` räumt wieder alles weg.
- [ ] Sperre: Übersicht offen, dann `Super + L`. Nach dem Entsperren ist sie zu. Gesperrt bewirken `Super + Tab`,
  `Super + H` und das Wischen nichts.
- [ ] Einstellungen (`Super + Komma`) öffnen, ein anderes Fenster darüber holen, `Super + Tab`, dann `Super + Komma`:
  Die Übersicht geht zu, die Einstellungen kommen nach vorn. Ein Klick auf die Lupe der Filterzeile lässt die
  Übersicht offen.
- [ ] Mit einem zweiten Bildschirm (HDMI): Übersicht offen, Kabel abziehen oder anstecken. Die Übersicht geht zu, und
  was du danach tippst, landet sichtbar im aktiven Fenster.
- [ ] Passwortfragen gehen vor: In den Einstellungen die Firewall ausschalten, der polkit-Dialog fragt nach dem
  Passwort. Jetzt mit drei Fingern nach oben wischen und `Super + Tab` drücken: Die Übersicht öffnet nicht, was du
  tippst, landet als Punkte im Passwortfeld. Dann `Abbrechen`. Ebenso: System-Menü der Leiste mit WLAN-Liste offen,
  dann wischen: Das Menü geht zu, die Übersicht öffnet.
- [ ] Bildschirm teilen (etwa in Chrome): Die Übersicht zeigt «Titel verborgen».
- [ ] Wischen mit drei Fingern: nach oben öffnet die Übersicht, nach unten schliesst sie. Scrollen mit zwei Fingern,
  Wischen zur Seite, Tippen mit drei Fingern (Mittelklick) und Schreiben mit aufliegendem Handballen lösen nie aus.
- [ ] Schwelle einmessen, wenn das Wischen zu früh oder zu spät auslöst. Per SSH (Ende mit `Ctrl + C`):
  `sudo -u zenos-gesten /usr/bin/python3 -I /opt/zenos/scripts/bin/zenos-gesten --messen`. Am Gerät ein paar Mal
  bewusst mit drei Fingern hoch und runter wischen und ein paar Mal nur leicht: Je Geste kommt eine Zeile mit
  Fingerzahl und Weg («senkrecht +85 (Schwelle 60) · löst aus: unten»). Die Zeilen melden; die Schwelle passt Claude
  dann im Code an.
- [ ] Reagieren Chrome, Firefox, VS Code oder kitty selbst auf das Wischen mit drei Fingern (labwc reicht es ihnen
  zusätzlich weiter), etwa mit Vor und Zurück im Browser? Melden.
- [ ] Last des Dienstes: per SSH `systemctl show zenos-gesten -p CPUUsageNSec -p MemoryCurrent`, dann eine Minute
  lang das Touchpad benutzen, dann noch einmal. Im Container war es gut 1 % eines Kerns und rund 15 MB. Beide Zeilen
  melden.
- [ ] Deckel zu und wieder auf: Die Geste geht danach weiter. Kommt das Touchpad dabei neu, steht in
  `journalctl -u zenos-gesten` «Touchpad eventN dazu».
- [ ] Hat die Tastatur eine Mission-Control-, Launchpad- oder F3-Taste mit Fenster-Symbol? Wenn ja, melden. Dann
  bestimmt Claude ihr Keysym (dafür braucht es das Paket `wev`, nur nach deinem Ja) und legt die Übersicht darauf.
- [ ] Rückweg ausprobieren (optional, per SSH): `sudo touch /etc/xdg/zenos/gesten-aus`, dann
  `/opt/zenos/scripts/install.sh`. `zen doctor` sagt «Gesten aus» und «Regel, Dienst und Benutzer sind entfernt»,
  Touchpad und `Super + Tab` gehen weiter. Wieder an: `sudo rm /etc/xdg/zenos/gesten-aus`, dann noch einmal
  `/opt/zenos/scripts/install.sh`.

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
- [ ] Das erste `zen update` nach dem Wechsel auf den Kanal läuft noch auf dem alten Weg und bringt den neuen Code
  (endet mit `installiert · N Änderungen`). Endet es mit «git fetch ist fehlgeschlagen» (der Pi kennt `v0.1.0-rc1` noch
  vom alten Ort): einmal den Notweg aus F über `dev` (Anker fehlt), danach weiter hier.
- [ ] Das nächste `zen update` geht über den Kanal: «Hole von origin», «Prüfe (ohne Netz)». Solange der Anker leer
  ist, zeigt es «Anker fehlt», die neuen Commits und fragt nach «ja» für genau diesen Commit. Mit «nein» ändert sich
  nichts; mit «ja» folgen das Journal von `zenos-kanal-installieren.service`, «Installiert: … installiert und gesund»
  und die Benutzerteile. Ein weiteres `zen update` meldet «Schon installiert». Die Oberfläche ist danach vollständig
  da.
- [ ] `zen version` zeigt in der Zeile «Update» den eben installierten Stand.
- [ ] `zen doctor` zeigt unter «Signierter Kanal» die Installation und keinen Fehler.
- [ ] `zen rollback v0.1.0-rc3` fragt (unsigniert) nach «ja» für das Tag-Objekt, geht danach auf den Tag zurück, und
  `zen version` zeigt ihn. `zen update` bringt dich wieder auf `dev` (aus `v0.1.0-rc3` noch auf dem alten Weg).
- [ ] Signierter Kanal: `zen kanal status` zeigt «Anker fehlt» mit dem Weg von Hand. Die Schlüssel sind im Repo
  (Serie 1), `install.sh` und `zen update` übernehmen sie aber nie von selbst (ein ungeprüfter Stand könnte sonst
  einen fremden Anker bringen); nur das Image bringt den Anker mit. Den Anker setzt du von Hand und tippst dabei den Fingerabdruck von
  «zenOS Wurzel» und die ersten 8 Zeichen von «zenOS Release» aus 1Password ab (nicht vom Bildschirm, dort stehen sie
  erst danach): `sudo zen kanal anker /opt/zenos/system/vertrauen`. Danach zeigt `zen kanal status` die
  Fingerabdrücke.
  `sudo zen kanal pruefen` holt von GitHub und listet `v0.1.0-rc1` bis `rc3` als «unsigniert». An `/opt/zenos`
  ändert sich dabei nichts (`zen version` zeigt danach denselben Commit).
- [ ] Einstellungen › System › Updates, in hell und dunkel: Die Lage («Anker fehlt», «Kanal dev, nur von Hand» oder
  «Aktuell») mit einem ruhigen Satz, darunter Kanal, Installiert, Geprüft, Kontakt und der Anker mit den ersten 8
  Zeichen der Fingerabdrücke (mit 1Password vergleichen). «Jetzt prüfen» fragt nach keinem Passwort, zeigt
  «Prüft …» und danach «Updates geprüft»; «Geprüft» steht dann auf «heute, …». Ein abgebrochener Dialog bleibt still.
- [ ] «Automatisch installieren»: «Bei Sperre» ist gewählt. «Von Hand» setzt ohne Passwort, `zen kanal zeitpunkt`
  zeigt es; «Zeitfenster» zeigt 02:00 bis 05:00, ein Fenster unter einer Stunde (etwa 03:00 bis 03:30) steht rot
  darunter und wird nicht gesetzt. Der Satz darunter sagt je Wahl, wann es kommt (beim Zeitfenster «auch wenn du
  gerade arbeitest. Das Gerät muss dann laufen.»). Ist die Datei ungültig (zum Probieren: `echo zeitpunkt=x | sudo tee
  /etc/xdg/zenos/kanal-zeitpunkt`), steht «Datei ungültig» in der Warnfarbe, und ein Klick auf «Bei Sperre» repariert
  sie. Zum Schluss wieder «Bei Sperre».
- [ ] Mitteilungen: Nach dem ersten Start mit dieser Oberfläche kommt «Updates: Anker fehlt» einmal (solange der
  Anker fehlt), nach einem Neustart nicht noch einmal. Nach einem `zen update` mit Installation kommt «zenOS
  aktualisiert» still in die Zentrale.
- [ ] Während `zen update` installiert (im System-Menü schauen, solange «install.sh aus …» läuft): Bei Neustart und
  Ausschalten steht «Update läuft»; ein Klick schliesst das Menü und sagt, dass es erst danach geht. Danach ist der
  Wert wieder weg. Gesperrt zeigt der Sperrbildschirm nichts davon.
- [ ] Automatik: `systemctl list-timers 'zenos-kanal*'` zeigt `zenos-kanal.timer` (nächstes Holen in höchstens 6 h),
  `zenos-kanal-gelegenheit.timer` (alle 15 Min.) und `zenos-kanal-bestaetigen.timer`. `zen kanal automatik` sagt «an»
  und was sie zuletzt tat; auf dem Kanal `dev` steht dort «Kanal dev: Automatisch kommt nie etwas».
- [ ] Erst wenn der Pi auf `vorschau` ist (`sudo zen kanal wechseln vorschau`, nach G10) und ein neues signiertes rc
  bereit steht (`zen kanal status`: «neue Version
  bereit»): sperren (Super+L) und mindestens 20 Minuten warten. Danach kommt still «zenOS aktualisiert» in die
  Zentrale, und `zen kanal status` sagt unter «Update» «… automatisch installiert …, gilt als gut nach einem Neustart
  mit Login». Neustart; nach etwa 5 Minuten steht unter «Update» der neue Stand als gut (`journalctl -u
  zenos-kanal-bestaetigen.service`: «Bestätigt»).
- [ ] Ausschalten nach langer Sperre wartet auf ein laufendes Update: Solange `zenos-kanal-installieren.service` läuft,
  sagt `/opt/zenos/scripts/bin/zenos-energie status` «nein: Update läuft (zenos-kanal-…)».
- [ ] Notschalter: `sudo zen kanal automatik aus`, dann `systemctl list-timers 'zenos-kanal*'`: nur noch die
  Bestätigung. `zen doctor` nennt «Automatik aus». Wieder an: `sudo zen kanal automatik an`.
- [ ] Stand von Hand: Nach einem `install.sh` aus `~/zenOS` sagt `zen kanal automatik` bei «zuletzt» «Von Hand
  angehalten …», und die Einstellungen zeigen die Zeile «Von Hand · … · Automatik ruht bis zen update». Auch gesperrt
  kommt dann kein automatisches Update. Ein `zen update` hebt das auf.
- [ ] Per SSH angemeldet (etwa Claude in tmux) und am Gerät gesperrt oder am Login-Bildschirm: `zen kanal automatik`
  sagt «Nicht jetzt: … ist per SSH angemeldet». Nach dem Abmelden von SSH geht es wieder.
- [ ] Nach einem Neustart steht der Login-Bildschirm keine 5 Minuten: Ein Lauf der Automatik sagt «der
  Login-Bildschirm läuft erst seit Kurzem». Läuft ein Update, während der Login-Bildschirm da ist, steht dort «zenOS
  wird aktualisiert. Mit der Anmeldung bitte warten, bis das fertig ist.»
- [ ] Argon ONE UP im Akkubetrieb unter 50 %, gesperrt, ein Update bereit: `zen kanal automatik` sagt «Nicht jetzt:
  im Akkubetrieb mit … %». Mit Netzteil kommt es beim nächsten Lauf.
- [ ] «Jetzt installieren» mit offener Sitzung, wenn das Update QML ändert: Während der Übernahme steht oben «Update
  läuft»; die Oberfläche lädt nicht stückweise nach, sondern startet danach einmal neu (Leiste und Mitteilungen sind
  da). Der Knopf heisst währenddessen «Wird installiert …».
- [ ] Einstellungen › System › Updates nach einem gescheiterten Update (`zen kanal status`: «Gescheitert, zurück …»):
  Die Zeile «Letztes Update» nennt es mit Zeit und Version, auch nach «Jetzt prüfen». Nach einer kaputten Installation
  heisst der Titel «Update kaputt» (Warnfarbe), bis ein späteres `zen update` gelingt.
- [ ] `sudo zen kanal zeitpunkt hand` per SSH: In der Sitzung kommt «Zeitpunkt für Updates geändert · Jetzt: Von Hand
  (gesetzt über sudo, uid …)». Aus den Einstellungen gesetzt kommt keine Mitteilung. Zum Schluss wieder «Bei Sperre».
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
  dringende Karte, die sofort erscheint, ohne Ton. Es steht immer nur eine Akku-Mitteilung da. Nach dem Einstecken
  verschwindet die Akku-Mitteilung, und es beginnt von vorn.
- [ ] Bei 3 % im Akkubetrieb: Die dringende Karte «Akku fast leer · zenOS schaltet um HH:MM aus» erscheint, auf der
  Sperre steht dieselbe Uhrzeit. Netzteil einstecken bricht ab (Karte weg). Ohne Netzteil schaltet das Gerät nach
  60 s sauber aus; `journalctl -b -1 -u zenos-argon` zeigt danach «schalte kontrolliert aus».
- [ ] Deckel: `sudo systemctl stop zenos-argon`, dann `sudo /opt/zenos/scripts/bin/zenos-argon --pruefen` einmal
  offen («Pegel 1 = offen») und einmal zugeklappt («Pegel 0 = zu»), danach `sudo systemctl start zenos-argon`.
  Zuklappen sperrt innerhalb von 2 s und macht dunkel, Aufklappen schaltet den Bildschirm an, die Sperre steht.
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

**Lüfter einstellen (Argon ONE UP, auch Argon ONE V3)**
- [ ] System-Menü: Die Zeile «Lüfter» zeigt z. B. «aus · Auto» und rechts einen Pfeil. Ein Klick klappt darunter
  «Auto · 1 · 2 · 3 · 4» auf, «Auto» ist hervorgehoben, darunter «Folgt der Temperatur.». Hell und dunkel ruhig, nichts
  blinkt.
- [ ] «2» antippen: kein Passwort. «Wird eingestellt …», nach höchstens 2 Sekunden «… · mind. 2» in der Zeile, der
  Lüfter läuft hörbar an. Per SSH: `cat /sys/class/thermal/thermal_zone0/policy` zeigt `user_space`, `zen luefter`
  zeigt «Mindeststufe 2», `journalctl -u zenos-argon` «Lüfter: Mindeststufe 2, zenos-argon regelt (…)».
- [ ] Tastatur: Menü öffnen, mit Pfeil runter bis zur Wahl, links/rechts zeigt der Fokusrahmen das Segment, Enter
  wählt.
- [ ] Unter Last (viermal `yes > /dev/null &`) steigt die Stufe über 2 hinaus, wie sie es automatisch täte (ab
  60 / 67,5 / 75 °C Stufe 2 / 3 / 4). Nach `pkill yes` sinkt sie wieder, aber nie unter 2.
- [ ] «Auto» antippen: Nach höchstens 2 Sekunden «… · Auto», `policy` wieder `step_wise`, die Stufe wie vorher
  automatisch. Hast du die Stufe unter Last gewählt, steht der Lüfter kurz auf der Stufe von damals und wird dann
  mit der Temperatur leiser.
- [ ] Neustart mit Mindeststufe 1: Danach gilt sie wieder (`zen luefter`, System-Menü).
- [ ] Per SSH mit Mindeststufe 2: `sudo kill -9 $(systemctl show -p MainPID --value zenos-argon)`. Gleich danach zeigt
  `policy` wieder `step_wise` (Sicherung beim Beenden), nach 10 Sekunden läuft der Dienst neu und hält wieder
  Stufe 2. `journalctl -u zenos-argon` nennt beides.
- [ ] Per SSH mit Mindeststufe 2, der Dienst hängt:
  `sudo kill -STOP $(systemctl show -p MainPID --value zenos-argon)`. Nach etwa 30 Sekunden zeigt
  `journalctl -u zenos-argon` «Watchdog timeout», `policy` steht wieder auf `step_wise`, 10 Sekunden später hält
  der neue Lauf wieder Stufe 2.
- [ ] `zen luefter 3` (mit sudo) und `zen luefter auto` wirken wie das Menü. `zen doctor` zeigt im Abschnitt «Argon
  ONE» den Lüfterwunsch und den Regler ohne Warnung.

**Flüssigkeit**
- [ ] Befehlsfeld, Hell/Dunkel, Fensterwechsel (`Alt + Tab`, App-Leiste und Fensterübersicht) und Einrasten laufen
  flüssig (60 fps). Nichts ruckelt, nichts blinkt.

---

## F · Wenn etwas nicht geht

**Häufige Fälle**

Der Pi zeigt nach dem Flashen nichts an, nur die LEDs leuchten: meist ist der Bootloader zu alt (siehe «Vorab» in B).

`install.sh` oder `zen update` bricht mit «apt-get install ist fehlgeschlagen» oder «Failed to fetch» ab: Das Netz
oder der Paketserver war kurz weg. Denselben Befehl noch einmal starten, Erledigtes bleibt. Steht dabei, dass dpkg
«mittendrin unterbrochen» wurde (oder meldet `zen doctor` das), zuerst reparieren, danach noch einmal:

```
sudo dpkg --configure -a
```

`zen doctor` meldet «Letzte Installation … ist nicht zu Ende gelaufen» oder «Installation von … unterbrochen» (Strom
weg oder Absturz während einer Installation): `zen update` noch einmal laufen lassen. Es setzt die unterbrochene
Installation fort; beim Start hat `zenos-kanal-nachstart.service` den Code schon vor dem Login vollendet. Nach zwei
Abbrüchen derselben Version geht es von selbst auf den Stand davor zurück.

`zen update` endet mit «Gescheitert, zurück auf dem Stand davor»: Die neue Version war nicht gesund (Grund in der
Meldung und in `zen kanal status`), der alte Stand läuft wieder, die Version ist gesperrt. Ein späteres `zen update`
lässt sie aus; noch einmal versuchen geht bewusst mit `zen rollback <version>` und «ja». Schick Claude die Meldung.

`zen update` fragt nach «ja», obwohl alles signiert ist: Die Änderung betrifft Firewall, Netz oder Boot (die Pfade
stehen dabei). Das ist gewollt; mit «nein» bleibt alles, wie es ist.

`zen update` meldet auf `stabil` oder `vorschau` «Anker fehlt»: Ohne Schlüssel im Anker kommt dort nichts. Von Hand
geht es auf `dev` weiter:

```
sudo zen kanal wechseln dev
```

`zen update` meldet «läuft gerade»: Ein anderes `zen update`, eine Prüfung oder ein `install.sh` von Hand läuft
noch; die Meldung nennt den Prozess (vergessene tmux-Sitzung? `tmux ls`). Wer die Sperren hält, zeigt auch:

```
sudo fuser -v /run/zenos-sperre/kanal.lock /run/zenos-sperre/install.lock /run/lock/zenos-install.lock
```

Was ein `zen update` gerade tut, zeigt auch nach einem Abbruch der SSH-Verbindung:

```
journalctl -fu zenos-kanal-installieren.service
```

**Kaputt.** `zen update` endet mit «Kaputt»: Auch der Rückweg scheiterte. Zuerst den Grund in der Meldung lesen
(`zen kanal status` zeigt ihn noch einmal) und ihn beheben, dann `zen update` noch einmal:

- «MB frei» oder «No space left»: Platz schaffen (`df -h /var /opt`).
- «Failed to fetch» oder «apt-get»: Das Netz war weg; einfach noch einmal.
- «läuft gerade» oder «Sperre»: siehe oben.
- git meldet «index.lock: File exists» (Strom weg mitten in einem Update; `zen update` räumt das selbst weg, der
  Notweg unten nicht):

```
sudo rm -f /opt/zenos/.git/index.lock
```

Danach geht es zurück auf einen guten Stand: die letzte gültig signierte Version aus `zen kanal status` («Gültig»),
ab dem ersten signierten Release-Kandidaten etwa `zen rollback v0.1.0-rc4`.

**Fehler im Kanal selbst.** `zen update` bricht mit einem Python-Fehler («Traceback») ab: Das neue Kanal-Programm hat
einen Fehler, den sein Selbsttest nicht fand. Die vorige Fassung liegt daneben; zurückholen:

```
sudo cp /usr/local/libexec/zenos/zenos-kanal.vorher /usr/local/libexec/zenos/zenos-kanal
```

Danach `zen rollback` auf den Stand davor (oder `zen update`, sobald ein Fix da ist). Startet `zen` selbst nicht mehr,
geht dasselbe ohne `zen`, den Tag statt `<tag>`:

```
sudo /usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal rollback <tag>
```

**Notweg ohne `zen` und ohne den Kanal** (per SSH), wenn das alles nicht hilft, `zenos-kanal` fehlt oder `zen update`
auf dem alten Weg mit «git fetch ist fehlgeschlagen» abbricht (bis `v0.1.0-rc3`, wenn auf GitHub ein Tag verschoben
wurde, so bei `v0.1.0-rc1`). Er prüft die Signatur selbst gegen den Anker des Geräts. Nimm einen gültigen Tag aus
`zen kanal status` («Gültig»), zum Beispiel `v0.1.1`. Erst den Tag holen:

```
sudo git -C /opt/zenos fetch --no-tags origin +refs/tags/v0.1.1:refs/tags/v0.1.1
```

Dann prüfen. In der Ausgabe muss `tag v0.1.1` stehen (derselbe Name) und `Good "git" signature for zenos-release`;
fehlt eins davon, hier aufhören:

```
sudo git -C /opt/zenos -c gpg.ssh.allowedSignersFile=/etc/zenos/vertrauen/release -c gpg.ssh.revocationFile=/etc/zenos/vertrauen/widerrufen verify-tag -v v0.1.1
```

Dann `/opt/zenos` darauf umstellen:

```
sudo git -C /opt/zenos checkout --force v0.1.1
```

Dann installieren (fragt nach dem sudo-Passwort):

```
/opt/zenos/scripts/install.sh
```

Nur solange der Anker fehlt (`zen kanal status`: «Anker fehlt»), gibt es nichts zu prüfen; dann geht der Notweg über
`dev`, und du liest selbst, was kommt. Erst holen (ohne Tags):

```
sudo git -C /opt/zenos fetch --no-tags origin dev
```

Dann die neuen Commits ansehen. Stammt einer nicht von dir oder Claude, hier aufhören und nachfragen:

```
sudo git -C /opt/zenos log --format='%h %an %s' HEAD..origin/dev
```

Dann umstellen und installieren wie oben, mit `sudo git -C /opt/zenos checkout --force -B dev origin/dev`.

Danach geht `zen update` wieder; eine unterbrochene Installation des Kanals gilt nach diesem `install.sh` als
erledigt.

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

Nach einem Update geht etwas nicht mehr: zurück zum letzten guten Stand, der letzten gültig signierten Version aus
`zen kanal status` («Gültig»), zum Beispiel `v0.1.0-rc4`. Ein Tag, den es nicht gibt, zeigt die vorhandenen. Ein
unsignierter Tag geht nur nach «ja» für genau dieses Tag-Objekt. Auf `vorschau` und `stabil` nie auf einen Stand ohne
Kanal (bis `v0.1.0-rc3`): Dessen altes `zen update` kennt diese Kanäle nicht («Den Kanal … gibt es auf origin nicht»),
und `zen kanal` fehlt. Kam es doch so, holt `sudo /usr/bin/python3 -I /usr/local/libexec/zenos/zenos-kanal update`
den neusten gültigen Stand zurück.

```
zen rollback v0.1.0-rc4
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
mehr. Meldet es stattdessen «sudo geht ohne Passwort», stammt die Regel von cloud-init (Imager-Einstellungen, Imager
bis 2.0.10 oder Benutzer `ubuntu`); ob sie bleibt, entscheidest du (`docs/baufortschritt.md`, «Offene Punkte»):

```
sudo rm /etc/sudoers.d/zenos-bau
```

**G2 bis G5: GitHub absichern** (einmalig, im Browser; das kannst nur du einstellen). Tags `v*` und `vertrauen/*`
lassen sich danach nicht mehr verschieben oder löschen, ausser von dir als Admin, auf `dev` und `main` gibt es keinen
Force-Push mehr, und ein veröffentlichtes Release bleibt, wie es ist. Die Geräte prüfen die Signatur ohnehin selbst;
das hier ist die zweite Schicht (`docs/sicherheit.md`, «Repo und Releases»).

**G2.** Regeln für die Tags. Auf GitHub im Repo zenOS: Settings › Rules › Rulesets › «New ruleset» › «New tag
ruleset»:
- Ruleset Name: `Release-Tags`, Enforcement status: «Active».
- Bypass list: «Add bypass» › «Repository admin», «Always allow». Sonst niemand.
- Target tags: «Add target» › «Include by pattern» › `v*`, dann noch einmal mit `vertrauen/*`.
- Rules: «Restrict updates», «Restrict deletions» und «Block force pushes» anhaken, sonst nichts.
- «Create».

**G3.** Regeln für `dev` und `main`. Wieder «New ruleset», diesmal «New branch ruleset»:
- Ruleset Name: `dev und main`, Enforcement status: «Active».
- Bypass list: leer lassen.
- Target branches: «Add target» › «Include by pattern» › `dev`, dann noch einmal mit `main`.
- Rules: nur «Restrict deletions» und «Block force pushes» (meist schon angehakt). Keine weiteren Regeln, sonst gehen
  normale Pushes auf `dev` nicht mehr.
- «Create».

**G4.** Unveränderliche Releases: Settings › General › Abschnitt «Releases» › «Enable release immutability»
anhaken. Das gilt für Releases, die danach erscheinen, auch für die Vorabversionen der `-rc`. Ein Release lässt sich
weiter löschen (Notbremse), nur sein Name ist danach verbraucht. Startest du einen Lauf «Image» neu, bleibt ein schon
veröffentlichtes Release, wie es ist; nur ein Entwurf eines abgebrochenen Laufs wird neu angelegt.

**G5.** Prüfen, auf dem Mac, dein GitHub-Konto statt `<konto>` (ausserhalb des Repo-Ordners findet `gh` es sonst
nicht). Es zeigt beide Rulesets als aktiv:

```
gh ruleset list --repo <konto>/zenOS
```

**G6 bis G10: Final signieren.** Der signierte Tag startet auf GitHub den Bau des Images. Lass vorher in
`CHANGELOG.md` einen Abschnitt mit Version und Datum ergänzen (was sich seit dem letzten Tag geändert hat; fehlt einem
früheren Tag sein Abschnitt, etwa `v0.1.0-rc3`, zuerst diesen), committen und pushen. Die Prüfung `pruefen.yml` für
diesen Stand muss grün sein: Läuft sie noch, wartet das Skript in G9 auf sie; ist sie rot oder fehlt sie, bricht es
ab. Für jedes `-rc` gehst du genauso vor, nur mit dessen Namen (etwa `v0.1.0-rc4`). Seit dem 06.10.2026 bekommt auch
jedes `-rc` eine öffentliche Release-Seite, als Vorabversion markiert. Damit liegt schon ein Release-Kandidat für alle
sichtbar auf GitHub. Entschieden am 07.10.2026: Die Release-Kandidaten erscheinen so, «Name und Marke» (unten) wird vor `v0.1.0`
geklärt.

**G6.** Öffne einen eigenen Terminal-Tab, in dem Claude Code nicht läuft, und wechsle in den Ordner:

```
cd ~/Documents/github/zenOS
```

**G7.**

```
git switch dev
```

**G8.**

```
git pull
```

**G9.** Signieren. Das Skript zeigt die Commits seit dem letzten Release, gesondert die sensiblen Pfade und die
Fingerabdrücke des Ankers; vergleiche den Release-Schlüssel mit «zenOS Release» in 1Password. Das erste «ja»
signiert (Touch ID), das zweite pusht nur den Tag. Danach 1Password sperren.

```
scripts/release-signieren.sh v0.1.0
```

**G10.** Auf GitHub unter Actions den Lauf «Image» für `v0.1.0` ansehen: «Tag und Signatur» ist grün, und seine
Zusammenfassung nennt Kanal `stabil`, `Release: «Latest»` und den Release-Schlüssel `SHA256:6CAhnfU9…`. Bei einem
`-rc` steht dort Kanal `vorschau` und `Release: Vorabversion`. Ist er rot, wird nichts gebaut; der Grund steht im Lauf.
«Prüfung» muss ebenfalls grün sein, sonst gibt es kein Release.

Nach dem Bau liegen unter Releases auf GitHub: `zenos-0.1.0-pi5-arm64.img.xz`, die Paketliste, `SHA256SUMS`, das
Manifest für den Raspberry Pi Imager und der Quellcode aller Pakete (`docs/image-und-releases.md`, «Release-Dateien»).
Ein `-rc` hat dieselben Dateien, ist als «Pre-release» markiert und wird nie «Latest»; seine Versionshinweise beginnen
mit «Release-Kandidat zum Testen, nicht für den Alltag». Das Manifest zeigt in beiden Fällen auf die Datei der
Release-Seite, du musst darin nichts ändern.
Den Stand des Baus zeigt GitHub unter Actions; der Quellcode-Job braucht je nach Netz bis zu einigen Stunden. Ein
Image aus `v0.1.0` folgt dem Kanal `stabil`, eines aus einem `-rc` dem Kanal `vorschau`; beide bringen den Anker mit
und aktualisieren sich danach selbst.

**Kanal wechseln.** Nach dem ersten signierten `-rc` stellst du den Pi von `dev` auf `vorschau` (danach `zen update`).
`vorschau` bekommt auch die Endversionen wie `v0.1.0`. Steht der Pi auf einem neueren `dev`-Stand als das `-rc`,
fragt `zen update` «Rückschritt: Der installierte Stand ist neuer als …» nach «ja»; mit «nein» bleibt er, bis eine
neuere Version kommt. Ein Gerät aus einem `-rc`-Image wechselt nach `v0.1.0` genauso auf `stabil`
(`sudo zen kanal wechseln stabil`).

```
sudo zen kanal wechseln vorschau
```

**G11 bis G14: `main` auf den Stand bringen** (deine Entscheidung). Solange `main` nur den Start-Commit enthält, braucht
jede Installation `git switch dev`. Vorschlag: `main` auf `v0.1.0` vorspulen. Dann funktionieren `git clone … ~/zenOS`
und `./scripts/install.sh` ohne `git switch dev`, und neue Installationen folgen dem Kanal `stabil` (aus `main`). Etwas
bekommen sie dort erst mit dem Anker, den nur das Image mitbringt: von Hand `sudo zen kanal anker
/opt/zenos/system/vertrauen`, die Fingerabdrücke aus `docs/image-und-releases.md` («Signierte Releases») bzw. den
Versionshinweisen; sonst meldet `zen update` «Anker fehlt». Dein Pi bleibt auf seinem Kanal (steht in
`/etc/xdg/zenos/kanal`). Ein Push auf `main` ist mit den Regeln aus G3 nur vorwärts möglich, ohne Force-Push.

**G11.**

```
git switch main
```

**G12.**

```
git merge --ff-only v0.1.0
```

**G13.**

```
git push origin main
```

**G14.**

```
git switch dev
```

**Offene Entscheidungen für dich**
- Name und Marke vor `v0.1.0` (entschieden am 07.10.2026: die Release-Kandidaten erscheinen schon vorher
  öffentlich als Vorabversion, G6 bis G10): die Markenrecherche zu «zenOS» und bei Canonical schriftlich anfragen oder
  dich auf die Klausel der IPR-Policy zu den Open-Source-Lizenzen stützen (`docs/image-und-releases.md`, «Name und
  Marke»).
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
- Prüfsummen der Images selbst signieren (`SHA256SUMS.sig` mit `ssh-keygen -Y sign`, ein Touch-ID-Schritt mehr je
  Release): Für Dritte wäre das die einzige Bindung der Image-Dateien an dich, die Attestation von GitHub bestätigt
  nur den Bau. Heute gibt es sie nicht.
- fish als Login-Shell, damit auch SSH-Sitzungen Eingabezeile, `?` und die Warnung haben: `chsh -s /usr/bin/fish`.
- Bootsplash einschalten: per SSH `zen bootsplash aktivieren`. Es zeigt jeden Schritt vorher (Pakete, Standard-Theme,
  «quiet splash» in der Boot-Kommandozeile, neues initramfs) und fragt nach. Danach startet der Pi zweimal. Zurück mit
  `zen bootsplash deaktivieren`. Was du danach prüfst: `docs/module/bootsplash.md`, «Am Pi prüfen».
