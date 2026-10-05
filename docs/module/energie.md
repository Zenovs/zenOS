# Energie · Bildschirm aus, Ausschalten, Ein/Aus-Taste

zenOS spart Strom, ohne die Sperre aufzuweichen. Alles hängt an der Sperre: Ohne Eingabe sperrt zenOS wie bisher
nach 1–15 Minuten, erst danach geht der Bildschirm aus, und auf Wunsch schaltet zenOS nach langer Sperre ganz aus.
**Dunkel heisst gesperrt**, und nichts auf diesem Weg verzögert die automatische Sperre. Bereitschaft (Suspend) gibt
es auf dem Raspberry Pi 5 und dem Compute Module 5 nicht (Abschnitt «Ehrlich nicht möglich»); Ausschalten ist der
Ersatz.

## Zeitleiste ab der letzten Eingabe

| Wann | Was | Wer |
|---|---|---|
| nach S Min. (`sperreNachMinuten`, 1–15, Standard 5) | gesperrt | `zenos-idle` (swayidle, `zen lock`) |
| spätestens nach 60 Min., auch wenn ein Programm den Leerlauf hemmt (Video) | gesperrt | `shell/dienste/Energie.qml` |
| S + B Min. (`bildschirmAusNachSperre`, 1–10, Standard 1) | Bildschirm aus, die Sperre bleibt | Sperre (`Sperre.qml`), dazu `zenos-idle` als Rückfallebene |
| S + M Min. (`ausschaltenNachMinuten`, 30–240, Standard 60), nur bei `ausschalten` `akku` (Standard, sicher im Akkubetrieb) oder `immer` | 60 s Vorwarnung, dann aus | `Energie.qml` und `zenos-energie` |

Mit den Standardwerten im Akkubetrieb: gesperrt nach 5, dunkel nach 6, aus nach 65 Minuten. Gezählt wird ab der
Sperre (auch nach Super+L), nicht ab dem Zeitpunkt, an dem der Bildschirm ausging. Dazu kommen drei Auslöser, die
nicht warten:

- **Sofort:** «Bildschirm aus» im System-Menü und im Befehlsfeld, Super+Shift+L, `zen energie aus` und IPC
  `energie aus` sperren und schalten den Bildschirm aus. Eine Eingabe weckt ihn, die Sperre bleibt.
- **Zuklappen** (Argon ONE UP): sperrt sofort und schaltet den Bildschirm aus, Aufklappen schaltet ihn an
  (`docs/module/m13.md`).
- **Leerer Akku** (Argon ONE UP): Bei 3 % im Akkubetrieb schaltet `zenos-argon` nach 60 s Vorwarnung kontrolliert
  aus, unabhängig von `ausschalten` und auch am Login-Bildschirm (`docs/module/m13.md`).

## Was gebaut ist

- **Leitplanken und Logik:** `shell/modi/zustandslogik.js` hält die Grenzen eingefroren in `LEITPLANKEN`
  (`sperreTrotzHemmerMinuten` 60, `bildschirmNurGesperrt`, `bildschirmAusNachSperre…` 1–10 / 1,
  `ausschaltenMinuten…` 30–240 / 60, `vorwarnungSekunden` 60, `akkuAusschaltenProzent` 3). Die vier neuen Schlüssel
  stehen in `GESPERRT`: Ein Zustand kann sie nicht setzen, sie gelten nur aus `einstellungen.json`.
  `shell/dienste/energie.js` rechnet die wirksamen Werte, die Zeitleiste, die Vorwarnung als Zustandsautomat
  (`aus`, `laeuft`, `warten`) und die Wecktaste. `Leitplanken.qml` reicht die Werte an die Oberfläche weiter.
  Schlüssel in `Einstellungen.qml`, im Schema und im neutralen Beispiel `config/beispiele/einstellungen.energie.json`.
- **`scripts/bin/zenos-bildschirm aus|an|status`:** schaltet alle Bildschirme mit `wlopm --off|--on '*'` (Paket
  wlopm, Protokoll wlr-output-power-management, bietet labwc 0.9 an). `aus` ruft immer zuerst `zen lock` auf und
  schaltet nur ab, wenn die Sperre bestätigt ist; sonst bleibt der Bildschirm an, und der Grund steht im Journal
  (`journalctl -t zenos-bildschirm`). wlopm endet auch bei Fehlern mit 0, deshalb wertet der Helfer die
  JSON-Ausgabe aus. Er meldet der Sperre `sperre bildschirm aus|an` (ohne darauf zu warten).
- **`scripts/bin/zenos-idle`** startet swayidle mit
  `timeout (S+B)·60 "<bin>/zenos-bildschirm aus" resume "<bin>/zenos-bildschirm an"`, dann `before-sleep` und `lock`,
  zuletzt `timeout S·60 "zen lock"`. swayidle stellt jeden Timeout vorne in seine Liste; so löst SIGUSR1 zuerst die
  Sperre aus. zenos-idle reicht SIGUSR1 an swayidle weiter (Sofort-Aktion), schaltet den Bildschirm beim Start immer
  an (nach SIGKILL oder einem Absturz bliebe er sonst dunkel) und startet swayidle nur neu, wenn sich Sperr- oder
  Bildschirmzeit ändern. Ausschalten und Ein/Aus-Taste starten es nie neu. Neu: `zenos-idle energie` (alle wirksamen
  Werte, je Zeile `<name> <wert> <art>`); `zenos-idle pruefen` behält sein Format.
- **Sperre** (`shell/sperre/Sperre.qml`): Ein IdleMonitor ab der Sperre (ohne Rücksicht auf Idle-Hemmer) schaltet
  den Bildschirm B Min. nach der Sperre aus, auch nach Super+L und hinter einem Video. Jede Eingabe weckt ihn. Die
  Sperre verwirft die Taste, die weckt (`Eingabe.vorTaste`): genau eine Taste, solange es dunkel ist oder bis 1 s
  nach dem Wecken, nie mehr (sonst könnte ein hängender Zustand die Passworteingabe blockieren). Während der
  Vorwarnung zeigt sie eine ruhige Zeile mit der Uhrzeit (Abschnitt «Ausschalten nach langer Sperre»). IPC
  `sperre bildschirm aus|an` und `sperre taste`.
- **Dienst `shell/dienste/Energie.qml`:** `aus()` (Sofort-Aktion über `zen energie aus`), `bildschirm(aus|an)` mit
  Argumentliste (immer nur ein Aufruf, der letzte Wunsch gilt), die Höchstdauer der Sperre trotz Idle-Hemmer, das
  Ausschalten nach langer Sperre, der Deckel und die Mitteilung nach einem automatischen Aus. IPC `energie aus`,
  `energie status` (Zeitleiste) und `energie vorwarnung` (Probe, schaltet nie aus, nur gesperrt).
- **`scripts/bin/zenos-energie`** (als Benutzer, nie als root): `darf-ausschalten` («ja» oder «nein: Grund», mit
  Journal), `status` (dasselbe ohne Journal), `ausschalten`, `taste` (Ein/Aus-Taste) und `meldung` (Mitteilung nach
  dem nächsten Start).
- **Sofort-Aktion:** System-Menü «Bildschirm aus» unter «Sperren» (ohne Rückfrage), Befehlsfeld «Bildschirm aus»
  und «Energie» (öffnet die Seite), Super+Shift+L (`system/labwc/rc.xml.in`), `zen energie aus`. Läuft zenos-idle,
  geht die Aktion über SIGUSR1 (die nächste Eingabe weckt über `resume`), sonst über `zen lock` und
  `zenos-bildschirm aus` (geweckt wird dann über die Sperre). Zwischen Sperre und Abschalten wartet `zen energie aus`
  1 s, sonst weckt das Loslassen von Super+Shift+L den Bildschirm gleich wieder.
- **Einstellungen → «Energie»** (`shell/einstellungen/SeiteEnergie.qml`, zwischen «Allgemein» und «System»):
  Zeitleiste, «Bildschirm aus», «Ausschalten, wenn gesperrt», «Ein/Aus-Taste», «Zuklappen», «Bereitschaft» und der
  Leitplankenhinweis. Unter «Allgemein» → «Automatische Sperre nach» führt ein Verweis dorthin. Aussehen:
  `docs/design.md`, «Einstellungen».
- **`zen energie [status|aus]`** (`scripts/zen.d/energie.sh`, ohne sudo): `status` zeigt die wirksamen Zeiten mit
  Herkunft (Standard, Einstellung, begrenzt, ungültig), was das Ausschalten gerade aufhält, die Ein/Aus-Taste, den
  Bildschirm in der laufenden Sitzung und ob der Kernel Bereitschaft anbietet. `aus` sperrt und schaltet ab, auch
  per SSH.
- **`zen doctor`**, Abschnitt «Energie» (`scripts/doctor.d/66-energie.sh`, nur lesend): wlopm und
  `zenos-bildschirm`, wirksame Zeiten, Bildschirm in der Sitzung erreichbar, Stand von zenos-idle, Ausschalten
  (Einstellung und was im Weg ist), Hemmer und Tastenkürzel der Ein/Aus-Taste, Bereitschaft (nur Hinweis).
- **Installation:** wlopm steht in `scripts/pakete/sperre.txt`. `65-oberflaeche` startet zenos-idle nach einem
  Update nur neu, wenn die Sitzung gesperrt ist: Ein Neustart beginnt die Leerlaufzeit von vorn und schöbe die
  Sperre sonst hinaus. Ungesperrt übernimmt zenos-idle den neuen Stand selbst bei der nächsten Sperre, solange der
  Bildschirm an ist.

### Ausschalten nach langer Sperre

1. `Energie.qml` zählt ab der Sperre ohne Eingabe (IdleMonitor ohne Rücksicht auf Hemmer). Bei `akku` nur sicher im
   Akkubetrieb: Messwert «ok» und sicher «lädt nicht». Ein unbekannter Akku gilt als Netzteil.
2. Ist die Zeit um, fragt es `zenos-energie darf-ausschalten`. Die Wächter, der erste Grund gilt:
   - Einstellung und Akkubetrieb,
   - keine Fern-Sitzung (logind `Remote=yes`) und keine SSH-Verbindung (`sshd-session`),
   - kein tmux- und kein screen-Server,
   - keine Installation (Sperre `/run/lock/zenos-install.lock` von `install.sh`, nur lesend und kurz geteilt
     gesperrt; `zen update`, `zen rollback`),
   - kein apt, apt-get, aptitude oder dpkg, kein laufendes `unattended-upgrade` (nicht der ständige
     `-shutdown`-Prozess), kein aktives `apt-daily(-upgrade).service`,
   - kein logind-Hemmer «shutdown» im Modus block (`busctl … ListInhibitors`).

   Was sich nicht prüfen lässt, gilt als blockiert. Ist etwas im Weg, bleibt es dunkel, und der Dienst versucht es
   alle 5 Minuten erneut.
3. **Vorwarnung:** Der Bildschirm geht an, die Sperre zeigt «zenOS schaltet um 22:41 aus · Eine Taste bricht ab»
   (ohne Sekunden), der Marker `$XDG_RUNTIME_DIR/zenos/vorwarnung` entsteht. Jede Eingabe, das Entsperren und bei
   `akku` das Netzteil brechen ab; die Taste, die abbricht, landet nicht im Passwortfeld.
4. Nach 60 s prüft `zenos-energie ausschalten` alles erneut, dazu: Marker vorhanden, eigene Datei, 60 s bis 5 Min.
   alt, gilt einmal; die Sitzung ist gesperrt. Dann schreibt es `~/.local/state/zenos/energie.json` und ruft nur
   `systemctl --no-ask-password poweroff --check-inhibitors=yes` auf. Jeder Entscheid steht mit Grund im Journal
   (`journalctl -t zenos-energie`).
5. Beim nächsten Start zeigt die Sitzung einmal die ruhige Mitteilung «zenOS hat ausgeschaltet · Am 5.10. um 22:41,
   nach 60 Min. gesperrt im Akkubetrieb.» und löscht die Datei.

### Ein/Aus-Taste

`einAusTaste`: `sperren` (Standard), `menue` oder `ausschalten`. Ausser bei `ausschalten` hält zenos-idle den
logind-Hemmer «handle-power-key»
(`systemd-inhibit --what=handle-power-key --mode=block --who=zenOS … tail --pid=<zenos-idle> -f /dev/null`). Er endet
mit zenos-idle, auch nach SIGKILL (`tail --pid`). labwc gibt `XF86PowerOff` (`allowWhenLocked`) an
`zenos-energie taste`:

- ungesperrt bei `sperren`: sperren und Bildschirm aus (wie Super+Shift+L), bei `menue`: das System-Menü,
- gesperrt: Bildschirm an, solange er dunkel ist oder bis 2 s nach dem Wecken, sonst aus,
- bei `ausschalten`: nichts, logind schaltet aus wie bisher.

Am Login-Bildschirm und an der Konsole gilt weiter logind: Ein kurzer Druck schaltet aus. Gedrückt halten schaltet
immer hart aus (Hardware).

### Dateien

| Was | Wo |
|---|---|
| Einstellungen | `~/.config/zenos/einstellungen.json` (`bildschirmAusNachSperre`, `ausschalten`, `ausschaltenNachMinuten`, `einAusTaste`) |
| Vorwarnung läuft | `$XDG_RUNTIME_DIR/zenos/vorwarnung` (Marker, gilt einmal) |
| Nach einem automatischen Aus | `~/.local/state/zenos/energie.json` (Zeit, Start-ID, Minuten, Art; gelöscht nach der Mitteilung) |
| Deckel und leerer Akku | `/run/zenos/geraet.json` (`deckel`, `akku.ausschaltenUm`, von `zenos-argon`) |

## Entscheidungen

- **Zenos Entscheid zum Ausschalten (Antwort b):** Standard `ausschalten: akku` nach 60 Min. gesperrt, dazu das
  kontrollierte Ausschalten bei 3 % Akku. Immer 60 s Vorwarnung, nie während SSH, tmux oder Updates. Ohne
  Bereitschaft braucht ein gesperrter Laptop im Rucksack rund 3,3 W, bis der Akku leer ist und hart abschaltet;
  ausgeschaltet laut Raspberry Pi rund 0,01 W (nicht selbst gemessen). «Nie» bleibt als Wahl.
- **Zenos Entscheid zu Video und Sperre (Antwort b):** Ein Idle-Hemmer (z. B. ein Video im Browser) hält die
  automatische Sperre höchstens 60 Min. ohne Eingabe auf, dann sperrt zenOS trotzdem (IdleMonitor mit
  `respectInhibitors: false`). Fest im Code, nicht abschaltbar. Vorher hielt ein vergessener Tab das Gerät
  unbegrenzt offen und hell, denn labwc prüft nicht, ob das Fenster sichtbar ist. Ein Film am Stück bleibt möglich.
- **Kein CPU-Profil:** Nicht gebaut. Der Takt liegt im Leerlauf schon rund 92 % der Zeit auf dem Minimum von 1,5 GHz
  (`time_in_state`), powersave kostet bis 37,5 % Spitzenleistung, und den Nutzen kann zenOS nicht messen (der
  Strom-Rohwert des CW2217 ist nicht kalibriert). Der Regler bleibt ondemand wie bei Ubuntu.
- **Bildschirm aus nur gesperrt, ohne «nie»:** Ein leuchtender Sperrbildschirm nützt niemandem, der Bildschirm ist
  der grösste Verbraucher (laut Geerling rund 8 W mit, 3,3 W ohne, nicht selbst gemessen). Einen dunklen, offenen
  Bildschirm gibt es bewusst nicht.
- **wlopm statt `wlr-randr --off`:** wlr-randr nimmt den Ausgang aus dem Layout, Fenster wandern, die Oberfläche
  verliert ihn, und beim Einschalten ist labwc im Container abgestürzt. wlopm schaltet nur die Ausgabe ab; Ausgang,
  Fenster und Sperrflächen bleiben.
- **Zwei Wege für «Bildschirm aus»:** Die Sperre zählt ab der Sperre und ohne Rücksicht auf Hemmer (ein Video hinter
  der Sperre sieht niemand) und kennt die Wecktaste. swayidle in zenos-idle schaltet zusätzlich nach S + B ab, als
  Rückfallebene ohne Oberfläche (dann zählt es ab der letzten Eingabe, wie die Sperre selbst).
- **Ausschalten frühestens 30 Min. nach der Sperre:** So liegt es immer nach Sperre und Bildschirm aus (zusammen
  höchstens 25 Min.), und eine kurze Pause endet nie mit offenen Fenstern im Aus.
- **Ausschalten in der Sitzung, nicht im Systemdienst:** Die Oberfläche kennt Sperre, Eingabe und Vorwarnung. Stürzt
  sie ab, schaltet nichts aus (sichere Richtung); Sperre und Bildschirm aus laufen über swayidle weiter. polkit
  erlaubt `power-off` in der aktiven Sitzung ohne Passwort; Hemmer übergehen (`-i`, `--force`) bräuchte
  `auth_admin_keep` und kommt nicht vor. Anders beim leeren Akku: Das entscheidet `zenos-argon` als Systemdienst,
  damit es auch am Login-Bildschirm gilt, und SSH oder tmux halten es nicht auf, weil das harte Aus schlimmer wäre.
- **Ein/Aus-Taste über einen Hemmer statt `logind.conf`:** Ein Drop-in `HandlePowerKey=` wäre ein Eingriff ins System
  und gälte auch am Login-Bildschirm. Der Hemmer gilt nur in der eigenen, aktiven Sitzung (polkit
  `inhibit-handle-power-key`: `allow_active yes`) und verschwindet mit ihr.
- **Deckel über GPIO27 statt logind:** logind kennt keinen Deckel (kein `SW_LID`-Gerät) und zählt HDMI als externen
  Bildschirm («Docked»). Argons Software liest den Deckel genauso; zenOS sperrt aber, statt auszuschalten
  (`docs/module/m13.md`).
- **Neustart von zenos-idle nur gesperrt:** Ein Neustart beginnt die Leerlaufzeit von vorn. Ungesperrt schöbe er die
  Sperre hinaus, das verbietet die Leitplanke.
- **Zustände setzen nichts davon:** Ein Zustand wie «Sitzung» oder «Fokus» darf die Energie-Schlüssel nicht ändern
  (`GESPERRT`). Was die Sperre betrifft, ist Sicherheit, keine Stimmung.

## Leitplanken (Code, nicht abschaltbar)

- Die automatische Sperre bleibt 1–15 Min., nichts hier verzögert sie. Ein Idle-Hemmer hält sie höchstens 60 Min.
  ohne Eingabe auf.
- Dunkel heisst gesperrt: `zenos-bildschirm aus` sperrt immer zuerst und schaltet nur bei bestätigter Sperre ab. Der
  Bildschirm geht 1–10 Min. nach der Sperre aus, nie davor; ungesperrt bleibt die Sperre hell, auch wenn ein Helfer
  «aus» meldet.
- Die Wecktaste landet nie im Passwortfeld, und es wird nie mehr als eine Taste verworfen.
- Ausschalten frühestens 30 Min. nach der Sperre, nie ohne 60 s sichtbare Vorwarnung, nur mit
  `systemctl poweroff --check-inhibitors=yes`, nie neu starten, nie `-i` oder `--force`.
- Zuklappen sperrt immer. Bei 3 % Akku schaltet zenOS immer kontrolliert aus.
- Keine Shell: Alle Helfer und Aufrufe aus der Oberfläche nutzen Argumentlisten. Einzige Ausnahme ist swayidle, das
  seine Befehle über `sh -c` ausführt: zenos-idle gibt dort nur feste, per Muster geprüfte Pfade mit festen Wörtern
  weiter (`sperrbefehl`, `bildschirmbefehl`). IPC und Helfer nehmen nur feste Wörter an.
- Grenzen doppelt (QML und Shell) mit Abgleichstest: `zustandslogik.js` ↔ `zenos-idle`, `zenos-energie`,
  `zen energie` und `zenos-argon`.

## Ehrlich nicht möglich

- **Bereitschaft (Suspend-to-RAM, s2idle):** Der Ubuntu-Kernel `linux-raspi` (7.0) ist ohne `CONFIG_SUSPEND` gebaut,
  `CONFIG_PM_SLEEP` fehlt; `/sys/power/state` ist leer, logind meldet `CanSuspend=na`. Raspberry Pi baut ebenfalls
  ohne. Die Arbeit daran (raspberrypi/linux PR #7514) ist offen, nur mit Test-Firmware und noch ohne NVMe. Ein
  eigener Kernel widerspricht dem Manifest. Die Seite «Energie», `zen energie` und `zen doctor` lesen
  `/sys/power/state` zur Laufzeit und sagen es offen. Gebaut wird Bereitschaft erst, wenn Ubuntu einen Kernel mit
  `CONFIG_SUSPEND` liefert und sie am Gerät funktioniert.
- **Ruhezustand (Hibernate):** `CONFIG_HIBERNATION` fehlt, und es gibt keinen Weg zum Fortsetzen.
- **Aufwachen per Taste aus dem Aus:** Nach dem Ausschalten startet nur die Ein/Aus-Taste neu, ein Kaltstart (rund
  18 s ab Kernel bis zum Login, dazu die Firmware). Offene Fenster sind dann weg.
- **Halten der Ein/Aus-Taste** schaltet immer hart ab (PMIC).
- **Dimmen:** Es gibt keine Backlight-Klasse. Helligkeit ginge nur über DDC/CI mit einem eigenen Helfer, das ist ein
  eigenes Thema. Deshalb kein Dimmen vor dem Abschalten.
- **Verbrauch in Watt:** Der Strom-Rohwert des Messchips ist nicht kalibriert; wie viel «Bildschirm aus» spart, kann
  zenOS nicht anzeigen.
- **Den Bildschirm ohne Sperre ausschalten** bietet zenOS bewusst nicht an (Manifest 1).

## Tests

- **Einheitentests** (in `pruefen.sh einheiten`):
  - `test/einheiten/energie.test.mjs` (node): Grenzen und Standards, ungültige Typen, eingefrorene `LEITPLANKEN`,
    Akkubetrieb nur bei sicherer Messung, Zeitleiste, Zustandsautomat der Vorwarnung (Ablauf, Abbruch durch eine
    Eingabe, Blockade und neuer Versuch nach 5 Min.), Wecktaste (genau eine Taste), Ein/Aus-Taste gesperrt, Abgleich
    mit `Einstellungen.qml`, `Leitplanken.qml` und dem Schema, neutrales Beispiel.
    `test/einheiten/zustaende.test.mjs`: Zustände können die vier Schlüssel nicht setzen.
  - `test/einheiten/idle.test.py` (21 Tests): Reihenfolge und Sekunden der swayidle-Argumente, `resume`, «an» beim
    Start, Neustart nur bei geänderter Sperr- oder Bildschirmzeit, Weitergabe von SIGUSR1, unverändertes `pruefen`,
    Hemmer nur ausser bei `ausschalten` und kein verwaister Prozess nach Wechsel und SIGKILL, neuer Stand erst
    gesperrt und hell, kein unsicherer Pfad in der Shell von swayidle, Abgleich der Grenzen mit `energie.js` und dem
    Schema.
  - `test/einheiten/bildschirm.test.py` (17 Tests): ohne bestätigte Sperre nie `wlopm --off`, wlopm-Fehler trotz
    Exit 0, `status`, kein `sh -c`.
  - `test/einheiten/energie.test.py` (27 Tests): jeder Wächter einzeln, nicht Prüfbares gilt als blockiert, Marker
    fehlt, zu jung, zu alt, fremd oder Verweis, `poweroff` nur mit genau `--no-ask-password poweroff
    --check-inhibitors=yes`, Ein/Aus-Taste gesperrt und ungesperrt, Mitteilung nur nach einem neuen Start.
  - `test/einheiten/zen-energie.test.py` (11 Tests): `zen energie status` und `aus` (mit und ohne zenos-idle, ohne
    Sperre bleibt es hell), Höchstdauer trotz Hemmer wie die Leitplanke, Super+Shift+L ruft `zen energie aus`.
  - `test/einheiten/raster.test.py`: Super+Shift+L und `XF86PowerOff` ohne Shell, Programme vorhanden.
  - Deckel und leerer Akku: `argon.test.py` und `geraet.test.mjs` (`docs/module/m13.md`).
- **Start-Test** (`pruefen.sh start`): Rundgang mit `einstellungen oeffnen energie`, `energie status`,
  `sperre bildschirm aus → an` und `sperre bildschirm an → an` (ungesperrt bleibt es hell), `energie vorwarnung →
  nicht gesperrt` und `sperre taste → offen`.
- **Im Container** (`zenos-test:installiert`, Sitzung wie auf dem Pi, Oktober 2026):
  - Sperre 1 Min., Bildschirm 1 Min.: nach 70 s gesperrt und hell, nach 130 s gesperrt und dunkel. Shift weckt,
    die Sitzung bleibt gesperrt.
  - Ausschalten nach langer Sperre bis zum Aufruf von `systemctl` (dort ersetzt, kein echtes Aus).
  - `install.sh` zweimal hintereinander ohne Fehler, der zweite Lauf mit 0 Änderungen.
- **Nicht prüfbar im Container:** ein echtes Panel und sein Hintergrundlicht, die echte Ein/Aus-Taste, der Deckel,
  ein echtes Ausschalten und ob das Gerät danach stromlos ist.

## Am Gerät prüfen

1. **wlopm am eingebauten Bildschirm:** `zen energie aus` macht das Panel wirklich dunkel (auch das
   Hintergrundlicht), ohne Flackern oder Moduswechsel. Eine Eingabe bringt es zurück, die Fenster bleiben am Platz.
2. **Wecken:** Shift, eine Buchstabentaste und das Touchpad wecken. Die Sperre bleibt, kein Zeichen landet im
   Passwortfeld, das erste Passwort klappt.
3. **Video in Chrome und Firefox:** Halten sie einen Idle-Hemmer (ungesperrt: keine Sperre, nicht dunkel)? Lassen sie
   ihn im Hintergrund-Tab oder minimiert los? Gesperrt geht der Bildschirm nach B trotzdem aus. Nach 60 Min. ohne
   Eingabe sperrt zenOS auch mit laufendem Video.
4. **swayidle in der echten Sitzung:** `journalctl --user -u zenos-idle` ohne «Failed to parse get BlockInhibited
   property» und ohne «Failed to find session».
5. **Ein/Aus-Taste:** `systemd-inhibit --list` zeigt «zenOS» mit handle-power-key. Ein kurzer Druck sperrt und
   schaltet den Bildschirm aus, aber nicht das Gerät. Am Login-Bildschirm schaltet ein kurzer Druck weiter aus,
   Halten schaltet hart aus. Kommt `XF86PowerOff` nicht in labwc an, melden (dann Rückfrage zu
   `HandlePowerKey=lock` in `logind.conf`).
6. **Tastatur:** Sendet eine Taste `KEY_POWER` oder `KEY_SLEEP` (logind würde ausschalten bzw. vergeblich in
   Bereitschaft gehen)? Prüfen mit `sudo evtest` auf «System Control».
7. **Ausschalten:** «Immer, 30 Min.» einstellen, sperren, 30 Min. warten. Dann geht der Bildschirm an, die Zeile der
   Vorwarnung steht da, eine Taste bricht ab. Mit offener SSH-Sitzung, mit tmux und während `zen update` schaltet es
   nicht aus; der Grund steht in `journalctl -t zenos-energie` und auf der Seite «Energie» («Zurzeit nicht: …»).
8. **Nach dem Ausschalten im Akkubetrieb:** Ist das Gerät wirklich stromlos (LEDs aus, Akkustand am nächsten Morgen
   fast gleich)? Lesend prüfen: `sudo rpi-eeprom-config | grep POWER_OFF_ON_HALT`.
9. **Kaltstart nach dem automatischen Aus:** Zeit bis zum Login; die Mitteilung «zenOS hat ausgeschaltet» erscheint
   bei der nächsten Anmeldung genau einmal.
10. **Bereitschaft:** Die Seite «Energie» zeigt «nicht verfügbar», `zen doctor` meldet einen Hinweis und keinen
    Fehler.
11. **Deckel und leerer Akku:** wie in `docs/module/m13.md`, «Am Gerät prüfen», Punkte 8–10.
12. **Hell und dunkel:** Seite «Energie», Eintrag im System-Menü, Vorwarnung auf der Sperre, alles flüssig auf dem
    Pi.
13. **Update:** `install.sh` zweimal hintereinander ohne Fehler. Nach `zen update` in einer gesperrten Sitzung läuft
    die neue Leerlauf-Logik ohne neues Anmelden (`journalctl --user -u zenos-idle`: neu gestartet); ungesperrt erst
    nach der nächsten Sperre.

## Offen

- **Login-Bildschirm:** Dort geht der Bildschirm noch nicht von selbst aus (geplant: nach 1 Min. ohne Eingabe, mit
  verworfener Wecktaste). Das Ausschalten bei leerem Akku gilt dort schon.
- **Bereitschaft beobachten:** raspberrypi/linux PR #7514 und `linux-raspi` mit `CONFIG_SUSPEND`.
