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
| am Login-Bildschirm nach 1 Min. (fest), am Netzteil wie am Akku | Bildschirm aus, die erste Eingabe weckt nur | `shell/greeter/Bildschirm.qml` |
| am Login-Bildschirm nach 30 Min. (fest), nur sicher im Akkubetrieb | 60 s Vorwarnung, dann aus | `shell/greeter/Leerlauf.qml` und `zenos-energie` |

Mit den Standardwerten im Akkubetrieb: gesperrt nach 5, dunkel nach 6, aus nach 65 Minuten. Gezählt wird ab der
Sperre (auch nach Super+L), nicht ab dem Zeitpunkt, an dem der Bildschirm ausging. Dazu kommen drei Auslöser, die
nicht warten:

- **Sofort:** «Bildschirm aus» im System-Menü und im Befehlsfeld, Super+Shift+L, `zen energie aus` und IPC
  `energie aus` sperren und schalten den Bildschirm aus. Eine Eingabe weckt ihn, die Sperre bleibt.
- **Zuklappen** (Argon ONE UP): sperrt sofort und schaltet den Bildschirm aus, Aufklappen schaltet ihn an
  (`docs/module/m13.md`).
- **Leerer Akku** (Argon ONE UP): Bei 3 % im Akkubetrieb schaltet `zenos-argon` nach 60 s Vorwarnung kontrolliert
  aus, unabhängig von `ausschalten` und auch am Login-Bildschirm (`docs/module/m13.md`). Die Zeile mit der Uhrzeit
  steht auf der Sperre und am Login-Bildschirm, `wall` meldet es allen offenen Terminals (auch per SSH).

## Was gebaut ist

- **Leitplanken und Logik:** `shell/modi/zustandslogik.js` hält die Grenzen eingefroren in `LEITPLANKEN`
  (`sperreTrotzHemmerMinuten` 60, `bildschirmNurGesperrt`, `bildschirmAusNachSperre…` 1–10 / 1,
  `ausschaltenMinuten…` 30–240 / 60, `vorwarnungSekunden` 60, `akkuAusschaltenProzent` 3). Die vier neuen Schlüssel
  stehen in `GESPERRT`: Ein Zustand kann sie nicht setzen, sie gelten nur aus `einstellungen.json`.
  `shell/dienste/energie.js` rechnet die wirksamen Werte, die Zeitleiste, die Vorwarnung als Zustandsautomat
  (`aus`, `laeuft`, `warten`, `abgelehnt`; die 60 s zählen in Takten zu 1 s, nie nach der Uhr) und die Wecktaste. `Leitplanken.qml` reicht die Werte an die Oberfläche weiter.
  Schlüssel in `Einstellungen.qml`, im Schema und im neutralen Beispiel `config/beispiele/einstellungen.energie.json`.
- **`scripts/bin/zenos-bildschirm aus|an|status`:** schaltet alle Bildschirme mit `wlopm --off|--on '*'` (Paket
  wlopm, Protokoll wlr-output-power-management, bietet labwc 0.9 an). `aus` ruft immer zuerst `zen lock` auf und
  schaltet nur ab, wenn die Sperre bestätigt ist; sonst bleibt der Bildschirm an, und der Grund steht im Journal
  (`journalctl -t zenos-bildschirm`). wlopm endet auch bei Fehlern mit 0, deshalb wertet der Helfer die
  JSON-Ausgabe aus. Vor dem Abschalten muss die Sperre der Oberfläche `sperre bildschirm aus` mit «aus» quittieren
  (letzter Sperr-Check, und sie verwirft dann die Wecktaste); antwortet sie anders, bleibt der Bildschirm an. Nur ohne
  erreichbare Oberfläche (Notfall-Sperre) schaltet er ohne Quittung ab, mit Eintrag im Journal. `an` ist erledigt,
  sobald alle Bildschirme an sind, auch wenn swayidle und die Sperre gleichzeitig einschalten.
- **`scripts/bin/zenos-idle`** startet swayidle mit
  `timeout (S+B)·60 "<bin>/zenos-bildschirm aus" resume "<bin>/zenos-bildschirm an"`, dann `before-sleep` und `lock`,
  zuletzt `timeout S·60 "zen lock"`. zenos-idle schaltet den Bildschirm beim Start an (nach SIGKILL oder einem Absturz
  bliebe er sonst dunkel), ausser es ist gesperrt und dunkel. swayidle startet es nur neu, wenn sich Sperr- oder
  Bildschirmzeit ändern, und nie, solange es gesperrt und dunkel ist (beim Beenden schaltete swayidle den Bildschirm
  über `resume` an). Ausschalten und Ein/Aus-Taste starten es nie neu. SIGUSR1 reicht es nicht mehr an swayidle
  weiter (Abschnitt «Sofort-Aktion»). Als Rückfallebene ohne Oberfläche sperrt es bei einem neuen Wechsel des Deckels
  zu «zu» (`/run/zenos/geraet.json`), wenn `zenos-shell.service` nicht läuft. Neu: `zenos-idle energie` (alle
  wirksamen Werte, je Zeile `<name> <wert> <art>`); `zenos-idle pruefen` behält sein Format.
- **Sperre** (`shell/sperre/Sperre.qml`): Ein IdleMonitor ab der Sperre (ohne Rücksicht auf Idle-Hemmer) schaltet
  den Bildschirm B Min. nach der Sperre aus, auch nach Super+L und hinter einem Video. Jede Eingabe weckt ihn. Die
  Sperre verwirft die Taste, die weckt (`Eingabe.vorTaste`): genau eine Taste, solange es dunkel ist oder bis 300 ms
  nach dem Wecken, nie mehr (sonst könnte ein hängender Zustand die Passworteingabe blockieren). Hält man sie fest,
  verwirft das Passwortfeld auch ihre Wiederholungen, bis sie losgelassen wird (Abschnitt «Gehaltene Wecktaste in der
  Sperre»). Weckt die Maus, das Touchpad, die Ein/Aus-Taste oder das Aufklappen, kommt ein Passwort danach ganz an.
  Startet die Oberfläche neu, während es gesperrt und dunkel ist, fragt die Sperre `zenos-bildschirm status` und
  weiss dann, dass es dunkel ist (Eingaben wecken); Entsperren schaltet den Bildschirm immer an. Während der
  Vorwarnung zeigt sie eine ruhige Zeile mit der Uhrzeit (Abschnitt «Ausschalten nach langer Sperre»). IPC
  `sperre bildschirm aus|an` und `sperre taste`.
- **Dienst `shell/dienste/Energie.qml`:** `aus()` (Sofort-Aktion über `zen energie aus`), `bildschirm(aus|an)` mit
  Argumentliste (immer nur ein Aufruf, der letzte Wunsch gilt), die Höchstdauer der Sperre trotz Idle-Hemmer, das
  Ausschalten nach langer Sperre, der Deckel und die Mitteilung nach einem automatischen Aus. IPC `energie aus`,
  `energie status` (Zeitleiste) und `energie vorwarnung` (Probe, schaltet nie aus, nur gesperrt).
- **`scripts/bin/zenos-energie`** (als Benutzer, nie als root): `darf-ausschalten` («ja» oder «nein: Grund», mit
  Journal; bei «ja» legt es den Marker an), `status` (dasselbe ohne Journal und Marker), `ausschalten` (Exit 4: noch
  keine 60 s, Exit 3: logind hat abgelehnt), `darf-ausschalten-login` und `ausschalten-login` (Login-Bildschirm),
  `taste` (Ein/Aus-Taste) und `meldung` (Mitteilung nach dem nächsten Start).
- **Login-Bildschirm** (`shell/greeter/Leerlauf.qml`, Benutzer `_greetd`): liest `/run/zenos/geraet.json` selbst
  (`dienste/geraet.js`) und zeigt die Zeile der Vorwarnung wie die Sperre, auch bei leerem Akku. Im Akkubetrieb
  schaltet es nach 30 Min. ohne Eingabe aus (Abschnitt «Ausschalten am Login-Bildschirm»). Nach 1 Min. ohne Eingabe
  geht dort der Bildschirm aus (`shell/greeter/Bildschirm.qml`, Abschnitt «Bildschirm aus am Login-Bildschirm»).
- **Sofort-Aktion:** System-Menü «Bildschirm aus» unter «Sperren» (ohne Rückfrage), Befehlsfeld «Bildschirm aus»
  und «Energie» (öffnet die Seite), Super+Shift+L (`system/labwc/rc.xml.in`), `zen energie aus`, die Ein/Aus-Taste und
  das Zuklappen. Immer über `zen lock` und `zenos-bildschirm aus`; geweckt wird über die Sperre (jede Eingabe, ohne
  Rücksicht auf Idle-Hemmer). Früher lief sie über SIGUSR1 an swayidle: Dessen Timeouts beachten Idle-Hemmer, mit
  einem Video blieb der Bildschirm an, und die Timeouts blieben auf 0 (nach dem Entsperren sofort wieder gesperrt).
  Zwischen Sperre und Abschalten wartet `zen energie aus` 1 s, sonst weckt das Loslassen von Super+Shift+L den
  Bildschirm gleich wieder.
- **Einstellungen → «Energie»** (`shell/einstellungen/SeiteEnergie.qml`, zwischen «Allgemein» und «System»):
  Zeitleiste, «Bildschirm aus», «Ausschalten, wenn gesperrt», «Ein/Aus-Taste», «Zuklappen», «Bereitschaft» und der
  Leitplankenhinweis. Unter «Allgemein» → «Automatische Sperre nach» führt ein Verweis dorthin. Aussehen:
  `docs/design.md`, «Einstellungen».
- **`zen energie [status|aus]`** (`scripts/zen.d/energie.sh`, ohne sudo): `status` zeigt die wirksamen Zeiten mit
  Herkunft (Standard, Einstellung, begrenzt, ungültig), was das Ausschalten gerade aufhält, die Ein/Aus-Taste, den
  Bildschirm in der laufenden Sitzung und ob der Kernel Bereitschaft anbietet. `aus` sperrt und schaltet ab, auch
  per SSH.
- **`zen doctor`**, Abschnitt «Energie» (`scripts/doctor.d/66-energie.sh`, nur lesend): wlopm und
  `zenos-bildschirm`, wirksame Zeiten, Bildschirm in der Sitzung erreichbar (ohne aktiven Bildschirm, etwa bei
  geschlossenem Deckel, nur ein Hinweis: `zenos-bildschirm status` meldet dann «keiner»), Stand von zenos-idle,
  Ausschalten (Einstellung und was im Weg ist), Hemmer und Tastenkürzel der Ein/Aus-Taste, Bereitschaft (nur Hinweis).
- **Installation:** wlopm steht in `scripts/pakete/sperre.txt`. `65-oberflaeche` startet zenos-idle nach einem
  Update nur neu, wenn die Sitzung gesperrt und der Bildschirm an ist: Ein Neustart beginnt die Leerlaufzeit von vorn
  und schöbe die Sperre sonst hinaus, und gesperrt und dunkel machte das `resume` von swayidle die Sperre bis S + B
  hell. Sonst übernimmt zenos-idle den neuen Stand selbst, sobald gesperrt und der Bildschirm an ist. Ein laufendes
  zenos-idle von vor der Bildschirm-Abschaltung kennt diese Prüfung nicht: Es übernimmt den neuen Stand erst nach
  dem nächsten Anmelden.

### Ausschalten nach langer Sperre

1. `Energie.qml` zählt ab der Sperre ohne Eingabe (IdleMonitor ohne Rücksicht auf Hemmer). Bei `akku` nur sicher im
   Akkubetrieb: Messwert «ok» und sicher «lädt nicht». Ein unbekannter Akku gilt als Netzteil.
2. Ist die Zeit um, fragt es `zenos-energie darf-ausschalten`. Die Wächter, der erste Grund gilt:
   - Einstellung und Akkubetrieb,
   - keine Fern-Sitzung (logind `Remote=yes`) und keine SSH-Verbindung (`sshd-session`),
   - kein tmux- und kein screen-Server,
   - keine Installation (Sperre `/run/lock/zenos-install.lock` von `install.sh`, nur lesend und kurz geteilt
     gesperrt; `zen update`, `zen rollback`; keine laufende Unit `zenos-kanal-*` oder `zenos-basis-*` laut
     `systemctl list-units`: Kanal und Basis-Updates arbeiten als root in Units, ihre Sperren in `/run/zenos-sperre`
     sieht kein Benutzer, und der Block-Hemmer gilt nur während apt bzw. `install.sh`, nicht beim Bereitstellen, bei
     der Gesundheitsprüfung oder beim Rückweg),
   - kein apt, apt-get, aptitude oder dpkg, kein laufendes `unattended-upgrade` (nicht der ständige
     `-shutdown`-Prozess), kein aktives `apt-daily(-upgrade).service`,
   - kein logind-Hemmer «shutdown» im Modus block (`busctl … ListInhibitors`),
   - logind erlaubt das Ausschalten ohne Passwort (`CanPowerOff` «yes»; «challenge» etwa bei einer zweiten Sitzung).

   Was sich nicht prüfen lässt, gilt als blockiert. Ist etwas im Weg, bleibt es dunkel, und der Dienst versucht es
   alle 5 Minuten erneut.
3. **Vorwarnung:** Bei «ja» legt der Helfer den Marker `$XDG_RUNTIME_DIR/zenos/vorwarnung` an (Start-ID und Sekunden
   seit dem Start aus `/proc/uptime`, nicht die Uhrzeit). Der Bildschirm geht an, die Sperre zeigt «zenOS schaltet um
   22:41 aus · Eine Taste bricht ab» (ohne Sekunden). Jede Eingabe, das Entsperren und bei `akku` das Netzteil brechen
   ab und löschen den Marker. Das Passwortfeld ist zu sehen: Wer tippt, tippt ins Feld, kein Zeichen geht verloren.
4. Nach 60 Takten zu 1 s (ein Sprung der Uhr verkürzt die Vorwarnung nie) prüft `zenos-energie ausschalten` alles
   erneut, dazu: Marker vorhanden, eigene Datei, aus diesem Start, 60 s bis 5 Min. alt nach Laufzeit; die Sitzung ist
   gesperrt. Massgebend für die 60 s ist die Laufzeit: Ein QML-Timer feuert etwas zu früh (im Container 30 Takte in
   29,8 s). Ist der Marker noch keine 60 s alt, antwortet der Helfer mit Exit 4, lässt ihn liegen, und die Oberfläche
   fragt im nächsten Takt erneut. Erst danach verbraucht es den Marker: Hat die Oberfläche ihn inzwischen gelöscht (eine Eingabe bis
   zuletzt), schaltet nichts aus. Dann schreibt es `~/.local/state/zenos/energie.json` und ruft nur
   `systemctl --no-ask-password poweroff --check-inhibitors=yes` auf. Lehnt logind ab (Exit 3), zeigt die Sperre bis
   zur nächsten Eingabe keine neue Vorwarnung (sonst ginge der Bildschirm die ganze Nacht alle 5 Min. für 60 s an).
   Jeder Entscheid steht mit Grund im Journal (`journalctl -t zenos-energie`).
5. Beim nächsten Start zeigt die Sitzung einmal die ruhige Mitteilung «zenOS hat ausgeschaltet · Am 5.10. um 22:41,
   nach 60 Min. gesperrt im Akkubetrieb.» und löscht die Datei.

### Ausschalten am Login-Bildschirm

Zenos Entscheid (Antwort b) gilt auch dort: Liegt das Gerät im Akkubetrieb am Login-Bildschirm (nach einem Neustart
oder dem Abmelden), schaltet zenOS nach 30 Min. ohne Eingabe aus. Fest im Code (`LEITPLANKEN.loginAusschaltenMinuten`),
ohne Einstellung: Die Einstellungen der Sitzung sind für `_greetd` nicht lesbar, und ohne offene Sitzung geht nichts
verloren.

1. `shell/greeter/Leerlauf.qml` zählt ohne Rücksicht auf Hemmer, nur sicher im Akkubetrieb.
2. Ist die Zeit um, fragt es `zenos-energie darf-ausschalten-login`: dieselben Wächter wie in der Sitzung (SSH, tmux,
   Updates, Hemmer, logind), dazu keine andere offene Sitzung (`loginctl`: nur `greeter` und die Benutzerdienste von
   systemd, Klasse `manager`). Eine Anmeldung an einer Textkonsole oder eine nach dem Abmelden weiterlaufende Sitzung
   hält es also auf.
3. Vorwarnung wie in der Sitzung: Die Zeile «zenOS schaltet um 22:41 aus · Eine Taste bricht ab» steht auf jedem
   Bildschirm des Logins, 60 Takte zu 1 s. Jede Eingabe und das Netzteil brechen ab.
4. `zenos-energie ausschalten-login` prüft alles erneut und schaltet aus wie in der Sitzung (ohne Mitteilung danach,
   es war niemand angemeldet). Im Journal mit «(Login-Bildschirm)».

### Bildschirm aus am Login-Bildschirm

Zenos Entscheid vom 06.10.2026: Am Login-Bildschirm (greetd mit dem zenOS-Greeter) geht der Bildschirm nach 1 Min.
ohne Eingabe aus, am Netzteil wie am Akku. Die erste Taste, der erste Klick oder die erste Berührung weckt ihn nur und
wird verworfen: Sie landet nie im Passwortfeld und löst nichts aus. Fest im Code
(`LEITPLANKEN.loginBildschirmAusMinuten`), ohne Einstellung: Die Einstellungen der Sitzung sind für `_greetd` nicht
lesbar.

- **Zählen:** `shell/greeter/Bildschirm.qml` misst mit einem IdleMonitor des Compositors (labwc,
  ext-idle-notify, ohne Rücksicht auf Idle-Hemmer). Jede Eingabe beginnt die Minute neu, auch Tippen im Passwortfeld.
  Ein Leerlauf-Zähler im Compositor statt eines eigenen Timers: Er sieht jede Eingabe (Tastatur, Maus, Touchpad,
  Berührung), auch solche, die nie bei der Oberfläche ankommen.
- **Aus und an:** `timeout 5 wlopm --json --off|--on '*'` als Argumentliste, direkt aus der Oberfläche des Logins
  (sie läuft als `_greetd` in ihrem eigenen labwc, `WAYLAND_DISPLAY` stimmt). Erfolg ist nur Exit 0 mit leerer
  Fehlerliste (wlopm endet auch bei Fehlern mit 0). Immer nur ein Aufruf, der letzte Wunsch gilt.
- **Wecktaste:** Schon bevor wlopm abschaltet, steht die Wecktaste aus. Solange hat ein unsichtbarer «Wecker» im
  Fenster mit dem Formular den Tastaturfokus, und ein Klickfang liegt über allem (auf jedem Bildschirm). Die erste
  Taste (auch Return, Escape, Tab, Shift) oder der erste Klick bzw. die erste Berührung geht dorthin, weckt und ist
  verworfen. Dann geht der Fokus dorthin zurück, wo er war (Passwortfeld, Namensfeld oder ein Knopf). Genau eine
  Eingabe, nie mehr: Der Wecker gibt den Fokus nach der ersten Taste in jedem Fall zurück, und er prüft dafür
  `focus`, nicht `activeFocus`. Weckt die Maus oder das Touchpad (Bewegung), gilt die Wecktaste noch 300 ms
  (`WECKEN_SCHONFRIST_MS`, wie in der Sperre), danach kommt alles an.
- **Gehaltene Wecktaste:** Wer die Taste festhält, bis der Bildschirm hell ist (ein HDMI-Monitor braucht dafür oft
  1–3 s), bekommt sie unter Wayland vom Client wiederholt (QtWayland, nach 600 ms 25 je Sekunde, labwc-Vorgabe).
  Die Wiederholungen gingen an das Feld, das den Fokus zurückbekam. Der Wecker merkt sich deshalb den Code der Taste
  (`nativeScanCode`), und das Formular verwirft im Namens- und Passwortfeld jede Wiederholung dieser Taste, bis sie
  losgelassen wird (`wecktasteGehalten` in `shell/dienste/energie.js`). Nie eine andere Taste: Ihr Loslassen, ein
  neuer Druck derselben Taste und die Wiederholung einer anderen beenden es, jede andere Taste kommt an (Abschnitt
  «Gehaltene Wecktaste in der Sperre», auch zu Shift, Ctrl, Alt, AltGr und Super). Ein gehaltenes Return meldet also
  nicht mit dem halben Passwort an, auch nicht mit Shift dazu, eine gehaltene Rücktaste oder Escape löscht nichts.
- **Zeichen im Feld:** Was schon im Passwortfeld stand, bleibt unverändert; die Wecktaste kommt nicht dazu. Das
  Passwort reicht weiterhin nur greetd an PAM weiter (`Ablauf.qml`), der Anmeldeablauf ist unverändert.
- **Vorwarnung vor dem Ausschalten** (30 Min. im Akkubetrieb, `Leerlauf.qml`): Sie schaltet den Bildschirm an und hält
  ihn an, ohne Wecktaste (wer tippt, tippt ins Feld und bricht ab). Endet sie ohne Eingabe (Netzteil, Wächter,
  logind lehnt ab), geht er eine Minute später wieder aus.
- **Deckel** (Argon ONE UP): Aufklappen schaltet den Bildschirm an (ohne Wecktaste), ohne Eingabe danach ist er eine
  Minute nach dem Aufklappen wieder aus, auch wenn es innerhalb der Minute nach der letzten Eingabe war. Für labwc
  ist das Aufklappen keine Eingabe (der Deckel kommt über GPIO27), sein Zähler liefe weiter. Deshalb gilt nach jedem
  Wecken ohne Eingabe (Deckel, Vorwarnung und ihr Ende, neuer Bildschirm) eine eigene Minute (`wach`, Timer
  `nachWecken`): Ein «idle» des Compositors in dieser Minute ändert nichts, danach geht er ohne Eingabe aus. Jede
  Eingabe beendet sie, dann zählt wieder der Compositor. Zuklappen ändert am Login-Bildschirm nichts (angemeldet ist
  niemand, gesperrt werden muss nichts); dunkel wird er nach der Minute.
- **Neuer Bildschirm** (angesteckt, oder nach dem Ausstecken wieder da, etwa über einen KVM-Umschalter oder einen
  Monitor, der im Standby die Verbindung trennt): labwc schaltet einen neuen Ausgang ein, `wlopm --off` erfasste nur
  die alten. `Bildschirm.qml` weckt dann wie beim Deckel: alle an, keine Wecktaste (sonst verwürfe das Formular auf
  einem hellen Bildschirm das erste Zeichen des Passworts), ohne Eingabe eine Minute später alle aus. Ausstecken
  ändert nichts.
- **Leerer Akku** (3 %, `zenos-argon`): unverändert. Die Zeile steht auch auf dem dunklen Login; wie auf der Sperre
  schaltet sie den Bildschirm nicht an.
- **Nach der Anmeldung:** Die Anmeldung braucht Eingaben, der Bildschirm ist dann an. Die Sitzung startet ihr eigenes
  labwc, das alle Bildschirme einschaltet, und `zenos-idle` schaltet beim Start an.
- **Ausfallsicher** (`shell/greeter/bildschirm.js`): Scheitert das Ausschalten (wlopm fehlt, das Protokoll fehlt,
  Fehler oder Zeitlimit), schaltet der Login sofort wieder ein und versucht es erst nach einer neuen Eingabe und einer
  neuen Minute ohne Eingabe erneut, nach drei Fehlschlägen in Folge nicht mehr. Scheitert das Einschalten, versucht
  er es nach 1 und 2 s erneut. War der Bildschirm sicher dunkel (wlopm hatte das Ausschalten bestätigt) und geht nach
  drei Versuchen nicht an, beendet sich der Login (Exit 1): greetd startet ihn neu, ein neues labwc schaltet alle
  Bildschirme an. Ohne bestätigtes Dunkel (wlopm fehlt oder antwortet unbrauchbar) gibt er auf, statt neu zu
  starten. Stürzt die Oberfläche des Logins ab, endet labwc (`-S`) und greetd startet beides neu, ebenfalls hell. Eine
  Taste oder ein Klick weckt über Wecker und Klickfang auch dann, wenn der IdleMonitor ausfiele. Jeder Fehlschlag steht
  im Journal (`journalctl -t zenos-greeter`).
- **Notfall-Login** (`shell/greeter/notfall/`): unverändert, ohne Ausschalten des Bildschirms (sichere Richtung).

### Gehaltene Wecktaste in der Sperre

Wer die Taste, die den dunklen Bildschirm weckt, festhält, bis er hell ist, bekommt sie unter Wayland vom Client
wiederholt (QtWayland, nach 600 ms 25 je Sekunde, labwc-Vorgabe). Früher verwarf die Sperre nur den ersten Druck: Die
Wiederholungen landeten im Passwortfeld, und ein gehaltenes Return prüfte das halbe Passwort (ein Fehlversuch bei
PAM, die Sperre blieb). Behoben wie am Login, mit derselben Logik:

- **Ein Weg für alles:** Die Sperre hat keinen eigenen Wecker, jede Taste geht durch das Passwortfeld. `Sperre.qml`
  reicht deshalb jedes Drücken (`Eingabe.vorTaste`) und jedes Loslassen (`Eingabe.vorLoslassen`) an
  `wecktasteSperre` in `shell/dienste/energie.js`. Die verbindet die Wecktaste (`wecktasteVerwerfen`, genau ein Druck,
  unverändert) mit dem Halten (`wecktasteGehalten`, wie im Login).
- **Gemerkt wird der Code der Taste** (`nativeScanCode`), nur wenn ihr Druck als Wecktaste verworfen wurde. Danach
  verwirft das Feld jede Wiederholung (`isAutoRepeat`) genau dieser Taste, bis sie losgelassen wird.
- **Nie eine andere Taste:** Verworfen werden nur Wiederholungen genau dieser Taste. Das echte Loslassen der
  gehaltenen Taste, ein neuer Druck derselben Taste und die Wiederholung einer anderen Taste beenden es. Eine andere
  Taste kommt immer an, ihr Drücken und Loslassen beenden es aber nicht: QtWayland wiederholt nur die zuletzt
  gedrückte Taste, die sich wiederholen darf (`xkb_keymap_key_repeats`). Eine Buchstabentaste, Return oder die
  Rücktaste übernimmt die Wiederholung, die gehaltene Taste wiederholt sich danach nicht mehr. Shift, Ctrl, Alt,
  AltGr, Super, Caps Lock, Num Lock und der Umschalter der Belegung wiederholen sich nicht (geprüft mit libxkbcommon,
  Belegungen ch und us): Ihr Druck lässt die gehaltene Taste weiter wiederholen, und diese Wiederholungen bleiben
  verworfen. Ein Loslassen allein ist nie die Wecktaste. Ohne gültigen Code bleibt es beim einen Druck, und ein
  Druck ohne gültigen Code beendet es.
- **Modifikatortasten** (behoben im Oktober 2026): Zuerst beendete jeder echte Druck einer anderen Taste das
  Verwerfen, auch der von Shift, Ctrl, Alt, AltGr oder Super. Wer die Wecktaste länger als 600 ms hielt und dazu
  eine davon drückte, bekam ab dann ihre Wiederholungen ins Feld: Mit Return prüfte PAM das halbe Passwort (ein
  Fehlversuch, «Das Passwort stimmt nicht.»), mit einer Buchstabentaste scheiterte das nächste Passwort. Am Login
  ebenso. Die Sperre war dadurch nicht schwächer, es gab keinen neuen Weg zu PAM.
- **Neu beginnen:** Sperren, Entsperren und eine von labwc beendete Sperre setzen den gemerkten Code zurück, zusammen
  mit dem Weckzustand.
- **Folgen:** Ein gehaltenes Return entsperrt nicht mit dem halben Passwort, auch nicht mit Shift dazu, eine
  gehaltene Rücktaste oder Escape löscht nichts. Ist der Bildschirm hell (ohne Wecken, nach der Schonfrist von 300 ms, während der Vorwarnung),
  wird nichts verworfen, auch keine Wiederholung. Der Weg zu PAM ist unverändert: Das Passwort geht nur über
  `PamContext` (Dienst `zenos-sperre`), zenOS prüft es nicht selbst.

### Ein/Aus-Taste

`einAusTaste`: `sperren` (Standard), `menue` oder `ausschalten`. Ausser bei `ausschalten` hält zenos-idle den
logind-Hemmer «handle-power-key»
(`systemd-inhibit --what=handle-power-key --mode=block --who=zenOS … tail --pid=<zenos-idle> -f /dev/null`). Er endet
mit zenos-idle, auch nach SIGKILL (`tail --pid`). labwc gibt `XF86PowerOff` (`allowWhenLocked`) an
`zenos-energie taste`:

- ungesperrt bei `sperren`: sperren und Bildschirm aus (wie Super+Shift+L), bei `menue`: das System-Menü,
- gesperrt: Bildschirm an, solange er dunkel ist oder bis 2 s nach dem Wecken, sonst aus,
- bei `ausschalten`: nichts, logind schaltet aus wie bisher.

Ohne zenos-idle gilt logind: Ein kurzer Druck schaltet sofort aus, ohne Vorwarnung und ohne Wächter. Das betrifft den
Login-Bildschirm, die ersten Sekunden nach dem Anmelden und die Pause zwischen zwei Läufen von zenos-idle (1 s,
`RestartSec`). Gedrückt halten schaltet immer hart aus (Hardware). Der Hemmer läuft im Benutzerdienst, also ausserhalb
einer Sitzung; logind zählt ihn dann vermutlich auch auf einer Textkonsole (Ctrl+Alt+F3), während die grafische
Sitzung im Hintergrund weiterläuft. Ein kurzer Druck bewirkt dort dann nichts. Das ist aus dem Quelltext von logind
hergeleitet und am Gerät zu prüfen («Am Gerät prüfen», Punkt 5).

### Dateien

| Was | Wo |
|---|---|
| Einstellungen | `~/.config/zenos/einstellungen.json` (`bildschirmAusNachSperre`, `ausschalten`, `ausschaltenNachMinuten`, `einAusTaste`) |
| Vorwarnung läuft | `$XDG_RUNTIME_DIR/zenos/vorwarnung` (Marker «zenos-vorwarnung 1 <Start-ID> <Sekunden seit dem Start>», gilt einmal; am Login-Bildschirm im Laufzeitordner von `_greetd`) |
| Nach einem automatischen Aus | `~/.local/state/zenos/energie.json` (Zeit, Start-ID, Minuten, Art; gelöscht nach der Mitteilung) |
| Deckel und leerer Akku | `/run/zenos/geraet.json` (`deckel`, `akku.ausschaltenUm`, von `zenos-argon`) |

## Entscheidungen

- **Zenos Entscheid zum Ausschalten (Antwort b):** Standard `ausschalten: akku` nach 60 Min. gesperrt, dazu das
  kontrollierte Ausschalten bei 3 % Akku. Immer 60 s Vorwarnung, nie während SSH, tmux oder Updates. Auch am
  Login-Bildschirm im Akkubetrieb nach 30 Min. Ohne Bereitschaft braucht ein gesperrter Laptop im Rucksack rund
  3,3 W, bis der Akku leer ist und hart abschaltet; ausgeschaltet laut Raspberry Pi rund 0,01 W (nicht selbst
  gemessen). «Nie» bleibt als Wahl.
- **Abweichung beim leeren Akku (von Zeno bestätigt am 08.10.2026):** Bei 3 % halten SSH und tmux das Ausschalten
  nicht auf, und auf dpkg oder `install.sh` wartet `zenos-argon` höchstens 5 Min. Der Wortlaut des Entscheids zum
  Ausschalten («nie während SSH, tmux oder Updates») sagt anderes. Grund: Bei leerem Akku käme sonst das harte Aus,
  mitten in dpkg ist das schlimmer als ein kontrolliertes. Damit niemand überrascht wird, meldet `wall` die
  Vorwarnung, eine Wartezeit und einen Abbruch allen offenen Terminals (auch SSH), und die Zeile steht auch am
  Login-Bildschirm. Zeno hat die Abweichung am 08.10.2026 bestätigt: kontrolliert ausschalten auch während SSH und
  tmux, auf Updates höchstens 5 Min. warten, mit der Warnung über `wall`.
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
- **Dunkel ohne Sperre nur am Login-Bildschirm** (Zenos Entscheid vom 06.10.2026): Dort ist niemand angemeldet, es
  gibt nichts zu sperren. Der Weg steht nur in der Oberfläche des Logins (`shell/greeter/`, Benutzer `_greetd`),
  nicht in `zenos-bildschirm`, IPC oder `zen energie`: In der Sitzung bleibt «dunkel heisst gesperrt» ohne Ausnahme.
- **wlopm direkt aus dem Login statt über `zenos-bildschirm`:** Der Helfer sperrt immer zuerst (`zen lock`) und
  verlangt die Quittung der Sperre; beides gibt es am Login nicht. Ein eigener Modus im Helfer wäre ein Weg, in der
  Sitzung ohne Sperre abzuschalten.
- **Neustart des Logins als letzter Ausweg:** Geht ein sicher dunkler Bildschirm nicht mehr an, ist ein neuer Login
  besser als ein dunkler; verloren geht nur, was im Feld stand. Ohne Bestätigung, dass es dunkel ist, kein Neustart
  (sonst liefe ein Login mit einer unbrauchbaren wlopm-Antwort jede Minute neu an).
- **Zwei Wege für «Bildschirm aus»:** Die Sperre zählt ab der Sperre und ohne Rücksicht auf Hemmer (ein Video hinter
  der Sperre sieht niemand) und kennt die Wecktaste. swayidle in zenos-idle schaltet zusätzlich nach S + B ab, als
  Rückfallebene ohne Oberfläche (dann zählt es ab der letzten Eingabe, wie die Sperre selbst).
- **Ausschalten frühestens 30 Min. nach der Sperre:** So liegt es immer nach Sperre und Bildschirm aus (zusammen
  höchstens 25 Min.), und eine kurze Pause endet nie mit offenen Fenstern im Aus.
- **Ausschalten in der Sitzung, nicht im Systemdienst:** Die Oberfläche kennt Sperre, Eingabe und Vorwarnung. Stürzt
  sie ab, schaltet nichts aus (sichere Richtung); Sperre und Bildschirm aus laufen über swayidle weiter. Ebenso hängen
  die Höchstdauer trotz Video (60 Min.) und das Sperren beim Zuklappen an der Oberfläche: Jeder Neustart der
  Oberfläche beginnt die 60 Min. von vorn, und ohne Oberfläche hält ein Video die Sperre unbegrenzt auf (swayidle
  beachtet Hemmer). Für den Deckel springt zenos-idle ein (sperrt bei einem neuen Wechsel zu «zu», wenn
  `zenos-shell.service` nicht läuft); für das Video gibt es keine Rückfallebene. polkit
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
  «aus» meldet. Einzige Ausnahme ist der Login-Bildschirm (niemand angemeldet): dort nach 1 Min. ohne Eingabe, fest.
- Die Wecktaste landet nie im Passwortfeld, und es wird nie mehr als eine Taste verworfen. Entsperrt ist der
  Bildschirm immer an. Am Login-Bildschirm gilt dasselbe für die erste Taste, den ersten Klick oder die erste
  Berührung; was dort scheitert, lässt den Bildschirm an.
- Ausschalten frühestens 30 Min. nach der Sperre (am Login-Bildschirm nach 30 Min. ohne Eingabe, nur im
  Akkubetrieb), nie ohne 60 s sichtbare Vorwarnung (nach der Laufzeit seit dem Start, nicht nach der Uhr), nur mit
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
    Akkubetrieb nur bei sicherer Messung (auch am Login-Bildschirm), Zeitleiste, Zustandsautomat der Vorwarnung
    (60 Takte, ein Sprung der Uhr verkürzt nichts, Abbruch durch eine Eingabe, Blockade und neuer Versuch nach 5 Min.,
    Ablehnung durch logind erst nach einer Eingabe), Zeile der Vorwarnung, Wecktaste (genau eine Taste, 300 ms; nach
    dem Wecken mit der Maus und während der Vorwarnung geht kein Zeichen verloren), gehaltene Wecktaste in der Sperre
    (`wecktasteSperre`: Wiederholungen verworfen bis zum Loslassen, auch Return; eine andere Taste kommt an und
    übernimmt die Wiederholung; Shift, Ctrl, Alt, AltGr, Super, Caps Lock, Num Lock und der Umschalter der Belegung
    während des Haltens kommen an und beenden es nicht; hell, nach der Schonfrist und ohne gültigen Code nie mehr als
    der eine Druck) und ihre Verdrahtung in
    `Sperre.qml` (Drücken und Loslassen, Neubeginn beim Sperren und Entsperren), Ein/Aus-Taste gesperrt, Abgleich
    mit `Einstellungen.qml`, `Leitplanken.qml` und dem Schema, neutrales Beispiel.
    `test/einheiten/zustaende.test.mjs`: Zustände können die vier Schlüssel nicht setzen.
  - `test/einheiten/idle.test.py` (25 Tests): Reihenfolge und Sekunden der swayidle-Argumente, `resume`, «an» beim
    Start (gesperrt und dunkel bleibt es dunkel), Neustart nur bei geänderter Sperr- oder Bildschirmzeit und nie
    gesperrt und dunkel, SIGUSR1 nur notiert, Deckel ohne Oberfläche, unverändertes `pruefen`, Hemmer nur ausser bei
    `ausschalten` und kein verwaister Prozess nach Wechsel und SIGKILL, neuer Stand erst gesperrt und hell, kein
    unsicherer Pfad in der Shell von swayidle, Abgleich der Grenzen mit `energie.js` und dem Schema.
  - `test/einheiten/bildschirm.test.py` (21 Tests): ohne bestätigte Sperre nie `wlopm --off`, ohne Quittung «aus» der
    erreichbaren Sperre ebenso nicht, ohne Oberfläche mit Eintrag im Journal, wlopm-Fehler trotz Exit 0, zweimal «an»
    zugleich ohne Fehler, `status`, kein `sh -c`.
  - `test/einheiten/energie.test.py` (37 Tests): jeder Wächter einzeln, `CanPowerOff`, nicht Prüfbares gilt als
    blockiert, Marker fehlt, zu jung, zu alt (nach Laufzeit, nicht nach der Uhr), aus einem anderen Start, fremd oder
    Verweis, Löschen bis zuletzt bricht ab, `poweroff` nur mit genau `--no-ask-password poweroff
    --check-inhibitors=yes` (abgelehnt: Exit 3), Login-Bildschirm (nur im Akkubetrieb, keine andere Sitzung, ohne
    Mitteilung), Ein/Aus-Taste gesperrt und ungesperrt, Mitteilung nur nach einem neuen Start.
  - `test/einheiten/zen-energie.test.py` (10 Tests): `zen energie status` und `aus` (immer direkt, nie über SIGUSR1,
    ohne Sperre bleibt es hell), Höchstdauer trotz Hemmer wie die Leitplanke, Super+Shift+L ruft `zen energie aus`.
  - `test/einheiten/energie-modul.test.py` (16 Tests): Neustart von zenos-idle nach einem Update nur gesperrt, mit
    neuerem Code und hellem Bildschirm, ein zweiter Lauf startet nichts neu; `zen doctor`, Abschnitt «Energie» (Zeiten,
    Ausschalten mit und ohne Akku, Login-Bildschirm, Stand von zenos-idle, Hemmer der Ein/Aus-Taste, nur lesend).
  - `test/einheiten/raster.test.py`: Super+Shift+L und `XF86PowerOff` ohne Shell, Programme vorhanden.
  - `test/einheiten/login-bildschirm.test.mjs` (15 Tests): Bildschirm am Login-Bildschirm (`greeter/bildschirm.js`):
    Ablauf aus und an, die Wecktaste steht schon vor dem Abschalten aus, genau eine Eingabe wird verworfen,
    Schonfrist, jede Eingabe beginnt die Minute neu (auch während des Ausschaltens), nach einem Wecken ohne Eingabe
    eine eigene Minute (Deckel 2 s vor dem Ende der alten Minute aufgeklappt: erst eine Minute später aus), neuer
    Bildschirm weckt ohne Wecktaste (auch während des Ausschaltens), gehaltene Wecktaste (Wiederholungen verworfen bis
    zum Loslassen, nie eine andere Taste, Modifikatortasten beenden es nicht), Fehlerfall bleibt an (Ausschalten gescheitert: sofort wieder an, nach drei
    Fehlschlägen nie mehr; wlopm unbrauchbar: aufgeben ohne Neustart; sicher dunkel und geht nicht an: Neustart des
    Logins), Vorwarnung und Deckel ohne Wecktaste, Antworten von wlopm, Argumentliste ohne Shell, Verdrahtung in
    `Bildschirm.qml` (Wachminute, neue Bildschirme), `Anmeldefenster.qml` (Wecker, Klickfang, Wiederholungen),
    `Formular.qml`, `Eingabe.qml` und `greeter.qml`, Notfall-Login ohne Ausschalten.
  - Deckel und leerer Akku: `argon.test.py` und `geraet.test.mjs` (`docs/module/m13.md`).
- **Start-Test** (`pruefen.sh start`): Rundgang mit `einstellungen oeffnen energie`, `energie status`,
  `sperre bildschirm aus → an` und `sperre bildschirm an → an` (ungesperrt bleibt es hell), `energie vorwarnung →
  nicht gesperrt` und `sperre taste → offen`.
- **Im Container** (`zenos-test:installiert`, Sitzung wie auf dem Pi, Oktober 2026):
  - Sperre 1 Min., Bildschirm 1 Min.: nach 70 s gesperrt und hell, nach 130 s gesperrt und dunkel. Shift weckt,
    die Sitzung bleibt gesperrt.
  - Ausschalten nach langer Sperre bis zum Aufruf von `systemctl` (dort ersetzt, kein echtes Aus).
  - Befunde der Prüfung (Oktober 2026), Abschnitt «Proben im Container» unten.
  - `install.sh` zweimal hintereinander ohne Fehler, der zweite Lauf mit 0 Änderungen.
  - Login-Bildschirm: `test/container/login-e2e.sh` (als tester, labwc ohne Bildschirm, Attrappe von greetd), Abschnitt
    «Login-Bildschirm im Container» unten.
  - Wecktaste der Sperre: `test/container/sperre-e2e.sh` (als tester, labwc ohne Bildschirm, echte Sperre und PAM),
    Abschnitt «Wecktaste der Sperre im Container» unten.
- **Nicht prüfbar im Container:** ein echtes Panel und sein Hintergrundlicht, die echte Ein/Aus-Taste, der Deckel,
  ein echtes Ausschalten und ob das Gerät danach stromlos ist.

## Am Gerät prüfen

1. **wlopm am eingebauten Bildschirm:** `zen energie aus` macht das Panel wirklich dunkel (auch das
   Hintergrundlicht), ohne Flackern oder Moduswechsel. Eine Eingabe bringt es zurück, die Fenster bleiben am Platz.
2. **Wecken:** Shift, eine Buchstabentaste und das Touchpad wecken. Die Sperre bleibt, kein Zeichen landet im
   Passwortfeld, das erste Passwort klappt. Gehalten: gesperrt drei Zeichen des Passworts tippen, dann den Bildschirm
   dunkel machen, ohne die Sperre neu zu beginnen: eine Minute warten (Standard «Bildschirm aus» nach 1 Min.), die
   Ein/Aus-Taste kurz drücken oder per SSH `zen energie aus`. Super+Shift+L wirkt in der Sperre nicht (kein
   `allowWhenLocked` in `rc.xml`), der Bildschirm bliebe hell. Dann eine Buchstabentaste 2 s halten, bis der
   Bildschirm hell ist, den Rest tippen und Enter: Es entsperrt beim ersten Versuch. Dasselbe mit gehaltenem Enter
   zum Wecken, und während Enter gehalten ist, kurz Shift drücken: Es bleibt gesperrt ohne «Das Passwort stimmt
   nicht.», der Rest und Enter entsperren. `journalctl -b | grep 'zenos-sperre:auth'` zeigt dabei keine Zeile
   «authentication failure».
3. **Video in Chrome und Firefox:** Halten sie einen Idle-Hemmer (ungesperrt: keine Sperre, nicht dunkel)? Lassen sie
   ihn im Hintergrund-Tab oder minimiert los? Gesperrt geht der Bildschirm nach B trotzdem aus. Nach 60 Min. ohne
   Eingabe sperrt zenOS auch mit laufendem Video.
4. **swayidle in der echten Sitzung:** `journalctl --user -u zenos-idle` ohne «Failed to parse get BlockInhibited
   property» und ohne «Failed to find session».
5. **Ein/Aus-Taste:** `systemd-inhibit --list` zeigt «zenOS» mit handle-power-key. Ein kurzer Druck sperrt und
   schaltet den Bildschirm aus, aber nicht das Gerät. Am Login-Bildschirm schaltet ein kurzer Druck weiter aus,
   Halten schaltet hart aus. Kommt `XF86PowerOff` nicht in labwc an, melden (dann Rückfrage zu
   `HandlePowerKey=lock` in `logind.conf`). Dazu: Sitzung offen, mit Ctrl+Alt+F3 auf eine Textkonsole, dort kurz
   drücken. Schaltet es aus oder bewirkt der Druck nichts? `systemd-inhibit --list` notieren und die Doku hier und in
   `docs/sicherheit.md` danach richtigstellen.
6. **Tastatur:** Sendet eine Taste `KEY_POWER` oder `KEY_SLEEP` (logind würde ausschalten bzw. vergeblich in
   Bereitschaft gehen)? Prüfen mit `sudo evtest` auf «System Control».
7. **Ausschalten:** «Immer, 30 Min.» einstellen, sperren, 30 Min. warten. Dann geht der Bildschirm an, die Zeile der
   Vorwarnung steht da, eine Taste bricht ab. Mit offener SSH-Sitzung, mit tmux und während `zen update` schaltet es
   nicht aus; der Grund steht in `journalctl -t zenos-energie` und auf der Seite «Energie» («Zurzeit nicht: …»).
8. **Nach dem Ausschalten im Akkubetrieb:** Ist das Gerät wirklich stromlos (LEDs aus, Akkustand am nächsten Morgen
   fast gleich)? Lesend prüfen: `sudo rpi-eeprom-config | grep POWER_OFF_ON_HALT`.
9. **Bildschirm am Login-Bildschirm:** Abmelden, eine Minute nichts tun: dunkel (auch das Hintergrundlicht). Je einmal
   mit einer Buchstabentaste, einem Mausklick auf «Anmelden», einem Tipp auf dem Touchpad und (falls vorhanden) einer
   Berührung des Bildschirms wecken: Er geht an, im Passwortfeld steht kein Punkt, nichts wird ausgelöst. Vorher drei
   Zeichen tippen, dunkel werden lassen, mit einer Taste wecken, den Rest tippen: Die Anmeldung klappt beim ersten
   Versuch. Tippen in Abständen unter einer Minute hält ihn an. Am Netzteil und am Akku gleich. Deckel zu, eine
   Minute warten, aufklappen: hell, das erste Zeichen landet im Feld. Deckel kurz nach einer Eingabe zu und gegen Ende
   der Minute auf: Er bleibt danach eine Minute hell. Drei Zeichen tippen, dunkel werden lassen, eine Buchstabentaste
   2 s halten, bis er hell ist, den Rest tippen: Die Anmeldung klappt beim ersten Versuch; ebenso mit gehaltenem
   Return (es meldet nicht an). Am dunklen Login den Monitor aus- und wieder anstecken: Er wird hell, das erste
   Zeichen landet im Feld, eine Minute ohne Eingabe später ist er wieder dunkel. `journalctl -b -t zenos-greeter`
   zeigt «Bildschirm aus» und «Wecktaste verworfen», keine Zeile «gescheitert».
10. **Login-Bildschirm im Akkubetrieb:** Abmelden, Netzteil ab, 30 Min. nichts tun. Die Zeile «zenOS schaltet um …
   aus» steht da, eine Taste bricht ab; ohne Eingabe schaltet es nach 60 s aus. Mit SSH, tmux oder einer Anmeldung auf
   einer Textkonsole schaltet es nicht aus (`journalctl -t zenos-energie`: «(Login-Bildschirm)»).
11. **Leerer Akku und SSH:** Bei der Vorwarnung erscheint in einer offenen SSH-Sitzung die Meldung von `wall`
    («zenOS: Akku fast leer …»), ebenso beim Abbruch. Am Login-Bildschirm steht die Zeile mit der Uhrzeit.
12. **Kaltstart nach dem automatischen Aus:** Zeit bis zum Login; die Mitteilung «zenOS hat ausgeschaltet» erscheint
   bei der nächsten Anmeldung genau einmal.
13. **Bereitschaft:** Die Seite «Energie» zeigt «nicht verfügbar», `zen doctor` meldet einen Hinweis und keinen
    Fehler.
14. **Deckel und leerer Akku:** wie in `docs/module/m13.md`, «Am Gerät prüfen», Punkte 8–10.
15. **Hell und dunkel:** Seite «Energie», Eintrag im System-Menü, Vorwarnung auf der Sperre und am Login-Bildschirm,
    alles flüssig auf dem Pi.
16. **Update:** `install.sh` zweimal hintereinander ohne Fehler. Nach `zen update` in einer gesperrten Sitzung läuft
    die neue Leerlauf-Logik ohne neues Anmelden (`journalctl --user -u zenos-idle`: neu gestartet); ungesperrt erst
    nach der nächsten Sperre.

## Proben im Container (Befunde der Prüfung)

`zenos-test:installiert` mit wlopm und wtype, Oktober 2026. Sitzung wie auf dem Pi (`oberflaeche.sh start
--sitzung`, Sperre 15 Min., Bildschirm 1 Min.):

- Gesperrt und dunkel, dann Quickshell mit `kill -9` beendet: Die neu gestartete Sperre meldet «Bildschirm beim
  Start schon aus», 8 s ohne Eingabe bleibt es dunkel, Shift weckt, die Sitzung bleibt gesperrt. Ebenso blind
  «Xtester» und Return getippt: entsperrt und hell (vorher: entsperrt und dunkel).
- `zen energie aus` mit einem Fenster, das den Leerlauf hemmt (Quickshell-`IdleInhibitor`): nach 5 s gesperrt und
  dunkel, Shift weckt, entsperrt; 15 s nach dem Ende des Hemmers weiter entsperrt (vorher: sofort wieder gesperrt).
- Gesperrt, Probe der Vorwarnung (`zenos-ipc energie vorwarnung`), dann «tester» und Return: entsperrt beim ersten
  Versuch (vorher: «Das Passwort stimmt nicht»).
- Gesperrt und dunkel, neuer Stand von zenos-idle, `install.sh`: «gesperrt und dunkel, zenos-idle übernimmt den neuen
  Stand, sobald der Bildschirm wieder an ist», 30 s lang dunkel (vorher: hell bis S + B). Nach Shift startet zenos-idle
  selbst neu («Neuer Stand von zenos-idle, starte neu (gesperrt)»).
- Login-Bildschirm (Kopie mit 10 s statt 30 Min., `zenos-energie` als Attrappe, `geraet.json` im Akkubetrieb): Nach
  10 s ohne Eingabe `darf-ausschalten-login`, die Zeile «zenOS schaltet um 13:01 aus · Eine Taste bricht ab» steht
  da, 60 Takte später `ausschalten-login`. Antwortet der Helfer mit Exit 4, fragt der Login einen Takt später erneut.
  Shift während der Vorwarnung bricht ab und löscht den Marker; am Netzteil beginnt keine neue. Mit
  `akku.ausschaltenUm` steht «Akku fast leer: zenOS schaltet um … aus · Netzteil anschliessen bricht ab» mit dem
  Akku-Symbol in `warnung`.
- QML-Timer: 30 Takte zu 1 s dauerten 29,8 s. Deshalb entscheidet über die 60 s die Laufzeit im Helfer (Exit 4).

## Login-Bildschirm im Container

`test/container/login-e2e.sh` in `zenos-test:installiert` mit wlopm, wtype und wlrctl, Oktober 2026: labwc ohne
Bildschirm mit `system/greeter/labwc`, `shell/greeter.qml`, dazu eine Attrappe von greetd
(`test/container/login/greetd_attrappe.py`), die jede Anfrage des Formulars protokolliert.

- **minute:** nach 40 s an; ein Zeichen im Passwortfeld nach 40 s, nach 80 s noch an; aus 60 s nach dieser Eingabe
  (Protokoll «1 Min. ohne Eingabe, Bildschirm aus»). Die Maus weckt.
- **taste:** «tes» getippt, nach 60 s aus. «q» weckt, greetd hat nichts bekommen. «ter» und Return: greetd bekommt
  genau «tester», danach `start_session`, der Bildschirm ist an. Protokoll «Wecktaste verworfen (Taste)».
- **halten:** «tes», dunkel, «q» 1,5 s gehalten (`wtype -P q -s 1500 -p q`): greetd hat nichts bekommen, nach «ter»
  und Return genau «tester». Dann «tes», dunkel, Return 1,5 s gehalten: greetd hat nichts bekommen, «ter» und Return
  melden mit «tester» an. Gegenprobe auf dem Stand vor der Behebung: greetd bekommt «tes», 20 Mal «q» und «ter»;
  mit gehaltenem Return meldet es mit «tes» an (Fehlversuch, dann `cancel_session`).
- **modifikator:** «tes», dunkel, Return gehalten und nach 900 ms Shift dazu: greetd hat nichts bekommen, «ter» und
  Return melden mit «tester» an. Dann «tes», dunkel, «q» gehalten und nacheinander Alt, AltGr und Super dazu: greetd
  bekommt genau «tester». Gegenprobe mit `energie.js` von `8af6728`: Mit Return und Shift meldet es mit «tes» an
  (dann `cancel_session`), mit «q» bekommt greetd «tes», 35 Mal «q» und «ter».
- **klick:** «tester» getippt, Zeiger auf «Anmelden», nach 60 s aus. Der erste Klick weckt, greetd hat nichts
  bekommen; der zweite meldet an.
- **fehler:** wlopm (Attrappe) schaltet ab, meldet aber einen Fehler: gleich wieder an, 20 s später weiter an, kein
  zweiter Versuch ohne Eingabe, Protokoll «wlopm --off gescheitert … der Bildschirm bleibt an».
- **neustart:** über `scripts/bin/zenos-greeter` (labwc `-S`), wlopm schaltet nicht mehr an (Attrappe): nach 63 s
  aus, «q» weckt nicht, nach drei Versuchen beendet sich der Login samt labwc, im Journal «Bildschirm geht nicht mehr
  an, starte den Login neu», kein Notfall-Login. Unter greetd folgt ein neuer Login mit allen Bildschirmen an.
- **Gegenprobe:** Ohne Wecker und Klickfang (nur in der Kopie im Container) scheitern «taste» (greetd bekommt
  «tesqter») und «klick» (der erste Klick meldet an).
- **Deckel innerhalb der Minute** (Probe von Hand, nicht in `login-e2e.sh`: `/run/zenos/geraet.json` als root wie
  `zenos-argon` geschrieben): letzte Eingabe bei 0 s, Deckel zu bei 5 s, auf bei 50 s. Danach an bei 56, 64, 75, 95
  und 105 s, aus bei 111 s. Gegenprobe auf dem Stand vor der Behebung: bei 56 s an, bei 64 s schon aus (am Ende der
  alten Minute, rund 10 s nach dem Aufklappen).
- **Neuer Bildschirm** (Probe von Hand): am dunklen Login den einzigen Ausgang mit `wlr-randr --output HEADLESS-1
  --off` und `--on` ab- und wieder angesteckt. Hell, 60 s später ohne Eingabe wieder dunkel. Nochmals angesteckt,
  dann ein Klick ins Passwortfeld, «tester» und Return: greetd bekommt genau «tester», keine Zeile «Wecktaste
  verworfen». Ohne Ausgang legt Qt einen Platzhalter-Bildschirm an; deshalb steht «Bildschirm an (Bildschirm neu)»
  je Anstecken zweimal im Protokoll (harmlos). Die Tastatur erreicht den Login im Container nach dem Wiederanstecken
  erst nach einem Klick, auch auf dem Stand vor der Behebung (dort kam nach dem Anstecken gar keine Eingabe an).
  `wlopm --json --on '*'` und `--off '*'` ohne Ausgang enden mit 0 und leerer Fehlerliste: Das Wecken in der Lücke
  zählt nicht als Fehlschlag und führt nie zum Neustart des Logins.
- Nicht prüfbar im Container: Touchpad, Berührung, der echte Deckel (GPIO27), ein zweiter, neu angesteckter
  Bildschirm (labwc ohne Bildschirm legt zur Laufzeit keinen neuen Ausgang an), ein echtes Panel und ein echter greetd
  mit PAM.

## Wecktaste der Sperre im Container

`test/container/sperre-e2e.sh` in `zenos-test:installiert` mit wlopm und wtype, Oktober 2026: labwc ohne Bildschirm
mit der Oberfläche aus `~/zenOS` (`oberflaeche.sh start`), die echte Sperre (ext-session-lock) und PAM (Dienst
`zenos-sperre`, Passwort `tester`). Dunkel über `scripts/bin/zenos-bildschirm aus` (Quittung der Sperre, dann wlopm;
so macht es gesperrt auch `zen energie aus`). Jeden Fehlversuch meldet pam_unix im Journal
(«pam_unix(zenos-sperre:auth): authentication failure»); der Test zählt diese Zeilen.

- **taste:** gesperrt, «tes», dunkel. «q» weckt, die Sperre bleibt; «ter» und Return entsperren beim ersten Versuch,
  kein Fehlversuch.
- **halten:** gesperrt, «tes», dunkel, «q» 1,5 s gehalten (`wtype -P q -s 1500 -p q`): hell, weiter gesperrt, kein
  Fehlversuch; «ter» und Return entsperren beim ersten Versuch. Dann gesperrt, «tes», dunkel, Return 1,5 s gehalten:
  hell, nach 3 s weiter gesperrt, PAM hat nichts geprüft; «ter» und Return entsperren beim ersten Versuch.
- **andere:** gesperrt, «tes», dunkel, «q» gehalten und nach 800 ms (schon wiederholt) «t» gedrückt
  (`wtype -P q -s 800 -k t -s 700 -p q`): «t» kommt an, «er» und Return entsperren beim ersten Versuch.
- **modifikator:** gesperrt, «tes», dunkel, Return gehalten und nach 900 ms Shift dazu
  (`wtype -P Return -s 900 -P Shift_L -s 600 -p Shift_L -s 100 -p Return`): hell, nach 3 s weiter gesperrt, PAM hat
  nichts geprüft; «ter» und Return entsperren beim ersten Versuch. Dann «q» gehalten und nacheinander Alt, AltGr
  (`ISO_Level3_Shift`) und Super je 300 ms dazu: «ter» und Return entsperren beim ersten Versuch. In der Keymap von
  wtype übernehmen Shift, Alt, AltGr und Super die Wiederholung nicht, Ctrl schon (anders als in den Belegungen ch
  und us): Mit Ctrl prüft der Container nichts, ihn decken die Einheitentests ab.
- **hell:** gesperrt und hell, «x» 1,5 s gehalten und Return: genau ein Fehlversuch (die Wiederholungen kamen an,
  ohne Wecken wird nichts verworfen); «tester» und Return entsperren.
- **Gegenprobe** auf dem Stand vor der Behebung (`Sperre.qml` von `37306f4` im Container): «taste» gelingt; «halten»
  scheitert (mit gehaltenem «q» entsperrt «ter» nicht, ein Fehlversuch; mit gehaltenem Return prüft PAM das halbe
  Passwort, danach entsperrt «ter» nicht); «andere» scheitert ebenso. «modifikator» auf dem Stand vor der Behebung
  der Modifikatortasten (`energie.js` von `8af6728`): Mit Return und Shift prüft PAM «tes» (ein Fehlversuch), danach
  entsperrt «ter» nicht; mit «q» und Alt, AltGr und Super entsperrt «ter» nicht (ein Fehlversuch). Einzeln geprobt
  («q» gehalten, eine Taste dazu) scheitert es dort mit Shift_L, Shift_R, Alt_L, ISO_Level3_Shift und Super_L, nicht
  mit Control_L und Control_R.
- Nicht prüfbar im Container: eine echte Tastatur und ein Monitor, der erst nach 1–3 s hell ist («Am Gerät prüfen»,
  Punkt 2). Die Wiederholung macht auch dort der Client, mit der Vorgabe von labwc (600 ms, 25 je Sekunde; zenOS
  stellt sie in `rc.xml` nicht um).

## Offen

- **Ein/Aus-Taste am dunklen Login-Bildschirm:** Dort gilt weiter logind, ein kurzer Druck schaltet sofort aus. Wer
  einen dunklen Login mit der Ein/Aus-Taste wecken will, schaltet aus (verloren geht nichts, angemeldet ist niemand,
  aber es folgt ein Kaltstart). Ein Hemmer «handle-power-key» im Greeter hielte das auf; das berührt logind und polkit
  für `_greetd` und ist nicht gebaut (Rückfrage an Zeno).
- **Ein/Aus-Taste während Updates:** Ohne zenos-idle schaltet ein kurzer Druck sofort aus, auch während `zen update`
  per SSH. Ein Hemmer «shutdown» um `install.sh` (`systemd-inhibit --what=shutdown --mode=block`, braucht sudo) hielte
  logind davon ab; das wäre ein Eingriff in den Ablauf von `install.sh` und ist nicht gebaut.
- **Höchstdauer trotz Video ohne Oberfläche:** keine Rückfallebene (Abschnitt «Entscheidungen»).
- **Bereitschaft beobachten:** raspberrypi/linux PR #7514 und `linux-raspi` mit `CONFIG_SUSPEND`.
