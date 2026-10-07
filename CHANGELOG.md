# Changelog

Was sich an zenOS ändert, pro Version. Das Format lehnt sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/)
an; eine Version entspricht einem Tag `v…` im Repo.

## 0.1.0-rc4 – 2026-10-07

Alles seit `v0.1.0-rc3`: der signierte Update-Kanal mit Automatik, Energie (Bildschirm aus, Ausschalten bei leerem
Akku), die Fensterübersicht mit `Super + Tab`, `Super + H` und Wischen mit drei Fingern, der Bildschirm geht auch am
Login-Bildschirm aus, und die Behebungen aus dem Lückencheck vor `v0.1.0`. `v0.1.0-rc4` ist der erste mit dem
Release-Schlüssel signierte Tag und der erste mit einer Release-Seite, dort als Vorabversion (Pre-release): zum Testen,
nicht für den Alltag. Name und Marke werden vor `v0.1.0` geklärt (Entscheid vom 07.10.2026).

### Neu

- **Bildschirm aus am Login-Bildschirm:** Nach 1 Minute ohne Eingabe geht der Bildschirm am Login aus, am Netzteil wie
  am Akku (`wlopm` in der Login-Sitzung, ausfallsicher: scheitert etwas, bleibt er an). Die erste Taste, der erste
  Klick oder die erste Berührung weckt ihn nur und wird verworfen; sie landet nie im Passwortfeld und löst keinen
  Knopf aus. Hält man die Wecktaste fest, verwirft das Formular auch ihre Wiederholungen, bis sie losgelassen ist (sonst
  kämen sie ins Passwortfeld, ein gehaltenes Return hätte mit dem halben Passwort angemeldet). Deckel auf, Vorwarnung
  oder ein neu angesteckter Bildschirm wecken ohne verworfene Taste, danach bleibt er mindestens 1 Minute an. Der
  Anmeldeablauf über greetd und PAM ist unverändert. Seite «Energie» und `zen doctor` nennen den Login-Bildschirm,
  Ende-zu-Ende-Test `test/container/login-e2e.sh`. Am Gerät zu prüfen: ANLEITUNG E.
- **Fensterübersicht, Schreibtisch und Wischen mit drei Fingern:** `Super + Tab` öffnet eine Übersicht aller offenen
  Fenster als Karten mit App-Symbol, App-Name und Titel, ohne Vorschaubilder (labwc 0.9.3 gibt einzelne Fenster nicht
  heraus). Sie bleibt offen, ohne dass eine Taste gehalten wird, und das vorige Fenster ist vorgewählt (`Super + Tab`,
  dann `Enter` führt zurück wie Alt+Tab). Tippen filtert wie im Befehlsfeld, Pfeile, Tab, Pos1 und Ende wählen, ein
  Klick wechselt, auch zu einem minimierten Fenster und über ein Vollbild-Fenster; Klick daneben oder `Esc` schliesst
  (ein Klick in die Filterzeile nicht). Hintergrund ist der neue Token `zudecken` (`grund` zu 92 %, hell und dunkel,
  ohne Weichzeichnen). Bei mehreren Bildschirmen stehen die Karten auf dem des aktiven Fensters, die anderen sind nur
  zugedeckt; wird ein Bildschirm ab- oder angesteckt, geht die Übersicht zu (ohne ihren Bildschirm bliebe sie sonst
  ohne Tastatur offen). `Super + Komma` schliesst sie und holt die Einstellungen nach vorn, auch wenn sie schon offen
  sind. `Super + H` minimiert alle sichtbaren App-Fenster, ein zweites `Super + H` holt genau diese zurück, auch nach
  einem Neuladen der Oberfläche beim Entsperren (vorher von Hand minimierte bleiben unten); solange zeigt «Heute» die
  Tastenkappe «Super H · Fenster zurück». Beides steht auch im Befehlsfeld («Fensterübersicht», «Schreibtisch zeigen»
  bzw. «Fenster zurück»). Drei Finger nach oben auf dem Touchpad öffnen die Übersicht, nach unten schliessen sie: Der
  neue Systemdienst `zenos-gesten` (Modul `82-gesten`) liest dafür als
  eigener Benutzer nur reine Touchpads und nur lesend (udev-Regel `72-zenos-gesten.rules`, gehärtete Einheit, ohne
  Touchpad läuft er nie). Er prüft jeden Knoten zusätzlich selbst beim Kernel (keine Tasten) und gibt die Gesten nur
  dem Benutzer an seat0. Die Sitzung bekommt keine Rechte an `/dev/input`, niemand kommt in die Gruppe `input`, kein
  neues Paket. Notschalter `/etc/xdg/zenos/gesten-aus` nimmt alles zurück. Nichts davon wirkt während Sperre und
  Einrichtung, und solange polkit nach dem Passwort fragt, öffnet die Übersicht nicht; während einer Freigabe sind die
  Titel verborgen. Die App-Leiste erscheint bei offener Übersicht nicht, Mitteilungskarten treten zurück. IPC
  `zenos-ipc uebersicht`, `schreibtisch` und `gesten`, `zen doctor` mit dem Abschnitt «Gesten», Ende-zu-Ende-Test
  `test/container/gesten-e2e.sh` (Testbild mit python3-libevdev, python3-yaml und libinput-tools). Aussehen in
  `docs/design.md`, Entscheidungen in `docs/module/m9.md`, Rechte und Restrisiko in `docs/sicherheit.md`, «Gesten»;
  am Gerät zu prüfen: ANLEITUNG E, «Fensterübersicht, Schreibtisch und Wischen».
- **`sudo zen kanal wechseln stabil|vorschau|dev`:** setzt den Kanal in `/etc/xdg/zenos/kanal`, statt ihn von Hand zu
  schreiben (ohne sudo scheiterte das, ein Tippfehler blockierte den Kanal). `zenos-kanal wechseln` schreibt atomar
  unter der Kanal-Sperre (root, 0644, nur diese drei Wörter, Eintrag im Journal), installiert nichts und sagt, was
  danach gilt: «Anker fehlt», oder ein «ja» für einen Rückschritt, wenn der installierte Stand neuer ist. Installiert
  wird danach mit `zen update`. ANLEITUNG E, F und G nennen den Schritt, etwa den Pi nach dem ersten signierten `-rc`
  auf `vorschau` und ein Gerät aus einem `-rc`-Image nach `v0.1.0` auf `stabil`.
- **Images nur aus signierten Tags, mit Kanal und Anker:** `image.yml` prüft vor dem Bau im Job «Tag und Signatur»
  mit dem neuen `image/tag-pruefen.sh`, ob der Tag ein Release-Tag `vX.Y.Z` oder `vX.Y.Z-rcN` ist und mit dem
  Release-Schlüssel des Ankers `system/vertrauen` in seinem Stand gültig signiert (gehärtetes `git verify-tag` und
  unabhängig `ssh-keygen -Y verify`, ab Serie 2 mit passendem `vertrauen/NNNN`); sonst wird nichts gebaut.
  `image/bauen.sh` prüft dasselbe noch einmal, der Kanal folgt dem Tag (`vX.Y.Z` → stabil, `-rcN` → vorschau, statt
  bisher dev), der Anker kommt aus `system/vertrauen`, und `zenos-kanal image <tag>` prüft im chroot ein drittes Mal
  und legt den Zustand ab Werk an (`gut.json`, `hoechste`, `gesehen.json` aus dem Tag). Ein Release gibt es nur, wenn
  `scripts/pruefen.sh` im selben Lauf grün ist (`pruefen.yml` als aufgerufener Workflow); `pruefen.yml` läuft auch für
  jeden Tag `v*`. Der Anker im Stand muss der sein, den ein Gerät über das Netz hätte: Wurzel und Release-Schlüssel
  von Serie 1 stehen fest in `tag-pruefen.sh`, jede spätere Serie braucht die ganze Kette `vertrauen/0002…NNNN`.
  Lokale Testbauten ohne Signatur nur mit `--testbau-ohne-signatur` (Version `-testbau`) oder `--nur-mechanik`, beide
  in GitHub Actions verweigert; `bauen.sh --nur-pruefen` prüft ohne root und ohne Bau. ANLEITUNG G: GitHub-Rulesets für
  `v*` und `vertrauen/*`, kein Force-Push auf `dev` und `main`, Immutable Releases, Release signieren mit
  `scripts/release-signieren.sh` (`image/README.md`, «Signatur des Tags»; `docs/image-und-releases.md`,
  «Vom Tag zum Image»).
- **Automatische Updates über den signierten Kanal:** `zenos-kanal.timer` holt und prüft 10–20 Min. nach dem Start
  und danach alle 6 h. Installiert wird nur auf stabil und vorschau (nie auf dev), nur gültig signiert und ohne
  Änderung an Firewall, Netz oder Boot (sonst «wartet auf Zustimmung»), nach der Wartezeit (stabil 24 h ab dem ersten
  Sehen, vorschau sofort) und zum eingestellten Zeitpunkt: «Bei Sperre» heisst, jede Sitzung am Gerät ist seit
  5 Min. gesperrt (die Oberfläche bestätigt es) oder der Login-Bildschirm wartet seit 5 Min., nie während einer
  SSH-Sitzung oder mit offener Textkonsole; dazu Zeitfenster (auch über Mitternacht, auch während der Arbeit),
  Jederzeit und Von Hand (nie, nur «Update bereit»). Bei jeder Wahl nur am Netzteil oder ab 50 % Akku und nie über
  einen Stand von Hand («angehalten», bis `zen update`). `zenos-kanal-gelegenheit.timer` schaut dafür alle 15 Min.
  ohne Holen. «Erstmals gesehen» entsteht nur mit synchronisierter Uhr, und im selben Start zählt die Zeit seit dem
  Start: Ein Sprung der Uhr verkürzt die Wartezeit nicht. Nach `zen rollback` bringt die Automatik die verlassene
  Version nicht wieder. Ein automatisch installierter Stand gilt erst als gut, wenn nach einem Neustart der Login
  kommt (Login-Bildschirm oder grafische Sitzung, `zenos-kanal-bestaetigen.timer`); fehlt er bei zwei Starts, geht es
  zurück auf den guten Stand, und die Version ist gesperrt. Scheitert der Weg zurück, ist das «kaputt», und der
  nächste Start versucht es noch einmal. Notschalter: `sudo zen kanal automatik an|aus`
  (`/etc/xdg/zenos/kanal-automatik-aus`, install.sh hält sich daran); `zen kanal automatik` zeigt den Stand. Das
  Ausschalten nach langer Sperre wartet, solange eine Unit des Kanals läuft. Einstellungen › System › Updates zeigen
  Notschalter, Bestätigung und Rückstellung (`docs/image-und-releases.md`, «Automatik»; GitHub als automatische
  Verbindung in `docs/sicherheit.md`).
- **Updates in den Einstellungen:** Einstellungen › System › Updates zeigt den signierten Kanal: Zustand mit
  Erklärung, Kanal, installierte und bereite Version, letzte Prüfung, Kontakt mit origin und den Anker mit kurzen
  Fingerabdrücken. «Jetzt prüfen» und «Jetzt installieren» gehen ohne Passwort, aber nur in der aktiven Sitzung am
  Gerät und nur für genau den angezeigten, gültig signierten, schon geprüften Stand; ändert er Firewall, Netz oder Boot,
  erscheint «Zustimmen …» mit Passwort, gebunden an das gezeigte Tag-Objekt. Der Zeitpunkt automatischer Updates ist
  wählbar («Bei Sperre» als Standard, Zeitfenster von–bis, Jederzeit, Von Hand) und gilt für das ganze Gerät
  (`/etc/xdg/zenos/kanal-zeitpunkt`, auch `sudo zen kanal zeitpunkt`). Der Satz «zenOS aktualisiert sich nicht von
  selbst» ist weg. Mitteilungen, jede nur einmal je Zustand: installiert (still), zurück, kaputt und blockiert
  (dringend), Anker fehlt, abgelehnt, wartet auf Zustimmung, 14 Tage ohne Kontakt und beim Zeitpunkt «Von Hand»
  «Update bereit». Im System-Menü steht bei Neustart und Ausschalten «Update läuft», solange install.sh aus dem Kanal
  läuft. Neu: `scripts/bin/zenos-kanal-bedienen` (pkexec), `system/polkit/org.zenos.kanal.policy`,
  `zenos-kanal-jetzt@.service`, `zenos-kanal-zustimmen@.service`, `zenos-kanal jetzt|zustimmen|zeitpunkt`, IPC
  `zenos-ipc kanal status|zeitpunkt|laeuft|uebernahme` (`docs/image-und-releases.md`, «In der Oberfläche»).
- **Energie:** Neue Seite «Energie» in den Einstellungen. Der Bildschirm geht 1–10 Min. nach der Sperre aus
  (Standard 1 Min.), nie vorher: Dunkel heisst immer gesperrt. Eine Taste oder das Touchpad weckt ihn, die Taste
  landet nicht im Passwortfeld. «Bildschirm aus» im System-Menü, im Befehlsfeld und mit Super+Shift+L sperrt und
  schaltet sofort ab. zenOS schaltet aus, wenn das Gerät lange gesperrt war: Standard im Akkubetrieb nach 60 Min.,
  einstellbar «Nie», «Im Akkubetrieb» oder «Immer» und 30–240 Min. Vorher steht 60 s lang die Uhrzeit auf dem
  Sperrbildschirm, eine Taste bricht ab, und nie während einer SSH-Sitzung, mit tmux oder während eines Updates. Am
  Login-Bildschirm schaltet zenOS im Akkubetrieb nach 30 Min. ohne Eingabe aus, ebenfalls mit Vorwarnung. Ein
  Video hält die automatische Sperre höchstens 60 Min. ohne Eingabe auf, dann sperrt zenOS trotzdem (Leitplanke).
  Die Ein/Aus-Taste sperrt in der Sitzung und macht dunkel (oder öffnet das System-Menü), statt sofort auszuschalten;
  gedrückt halten schaltet weiter aus. Beim Argon ONE UP sperrt Zuklappen sofort, und bei 3 % Akku schaltet zenOS
  nach 60 s Vorwarnung kontrolliert aus (nur das Netzteil bricht ab; laufen nach den 60 s `install.sh`, `dpkg` oder ein
  Update über den Kanal, wartet es höchstens 5 Min. länger); offene Terminals, auch per SSH, bekommen eine Meldung, und
  der Login-Bildschirm zeigt die Uhrzeit. Bereitschaft gibt es auf diesem Gerät nicht: Der Kernel bietet keinen
  Schlafzustand an, die Seite sagt das offen. Neues Paket: wlopm. `zen energie [status|aus]`, `zen doctor` (Abschnitt
  «Energie»), IPC `zenos-ipc energie aus|status|vorwarnung` und `sperre bildschirm|taste` (`docs/module/energie.md`).
- **Kanal gehärtet nach der Prüfung von Schritt 4:** Das Hauptbuch vergleicht Commits statt Objekt-IDs: Eine ohne
  Schlüssel neu umbrochene Signatur löst keinen ALARM mehr aus, der jedes Gerät blockierte. Sperren liegen in
  `/run/zenos-sperre` (nur root) statt in `/run/lock`, wo jeder Benutzer den Kanal abschneiden und über die belegte
  Sperre von install.sh ein «kaputt» mit gesperrter Version erzwingen konnte; ein `install.sh` von Hand vermerkt sich
  dort, und scheitert install.sh nur an seiner Sperre, zählt der Versuch nicht. Viele Tags auf origin blockieren nicht
  mehr (Prüfungen begrenzt, die bekannten zuerst), der Holer holt nur `dev` und `v*` und räumt seinen Spiegel auf. In
  die Bereitstellung und nach `/opt/zenos` kommen nur geprüfte Tags, eine alte Bereitstellung ohne Tag wird ersetzt.
  Die Gesundheitsprüfung wertet greetd und Quickshell nur, wenn das Update sie verschlechtert, prüft alle Shell-Skripte
  mit `bash -n`, und der Selbsttest macht einen Probelauf von status, update, rollback, installieren und nachstart;
  die vorige Fassung bleibt als `zenos-kanal.vorher`. Zurückgebliebene git-Sperren in `/opt/zenos` räumt der Kanal
  weg, der Anker wird in einer Reihenfolge geschrieben, die jeden Abbruch übersteht, `zen kanal status` merkt nach
  einer Installation, dass der Stand veraltet ist, und `zen update` prüft danach neu. Den Anker füllt ein ungeprüfter
  Stand nie mehr von selbst: `sudo zen kanal anker ORDNER` mit den Fingerabdrücken aus 1Password (abtippen vom
  Bildschirm geht nicht). Der Notweg in ANLEITUNG F prüft einen Tag gegen den Anker und nimmt `dev` nur ohne Anker.
  Exit 75 bei belegter Prüfung, «wartet» ohne Netz, Wunsch und Auftrag überstehen einen Uhrsprung, «gescheitert»
  bleibt in `zen doctor` sichtbar.
- **zen update und zen rollback über den Kanal:** `/opt/zenos` wird nie mehr direkt umgestellt. `zen update` holt
  ohne Rechte, prüft und stellt ohne Netz bereit (`/var/lib/zenos/kanal/bereit/<commit>`) und installiert als Dienst
  `zenos-kanal-installieren.service` (root, Block-Inhibitor fürs Ausschalten, `KillMode=mixed`; ein SSH-Abbruch
  schadet nicht). Auf `stabil` und `vorschau` nur gültig signierte Tags; auf `dev` ohne Frage nur, wenn jeder neue
  Commit gültig signiert ist, sonst (auch solange der Anker leer ist) nach einem getippten «ja» für genau diesen
  Commit. Ein «ja» braucht es auch für Firewall, Netz und Boot (Rückfrage-Pfade fest im Code), für einen gesperrten
  Stand und einen Rückschritt. Danach Gesundheitsprüfung (Log, Commit, `zen version`, Quickshell, greetd, Selbsttest
  des neuen zenos-kanal); scheitert sie, kommt die Version nach `gesperrt/` und der Stand davor zurück. Ein Abbruch
  (Strom, kill) wird beim Start vor greetd im Code vollendet (`zenos-kanal-nachstart.service`, `install.sh
  --nur-code`) und vom nächsten `zen update` fortgesetzt; nach zwei Abbrüchen geht es zurück. `zen rollback <tag>`
  nimmt signierte Tags ohne Frage, unsignierte nach «ja» für genau das Tag-Objekt. `zen version` zeigt die letzte
  Installation, `zen doctor` und `zen kanal status` dazu Unterbrechungen, gesperrte Stände und «angehalten» (ein
  `install.sh` von Hand aus `~/zenOS`, das jetzt auf den Kanal wartet). Kanäle in `/etc/xdg/zenos/kanal`: `stabil`,
  `vorschau`, `dev`; `main` wird `stabil`. Ende-zu-Ende-Test: `test/container/kanal-e2e.sh`. Das erste `zen update`
  mit diesem Stand läuft noch über den alten Weg und bringt den Kanal. `scripts/lib/wechsel.sh` entfällt.
- **Signierter Kanal auf dem Gerät, nur prüfend:** `sudo zen kanal pruefen` holt Tags und Branches von GitHub als
  flüchtiger Systembenutzer ohne Rechte in einer Sandbox und prüft sie als root ohne Netz gegen den Vertrauensanker
  `/etc/zenos/vertrauen`: annotiert, Name gleich dem Feld im Tag, genau eine SSH-Signatur, `git verify-tag` gegen
  Release-Schlüssel und Widerrufe, Hauptbuch gegen verschobene Tags (ein gültig signierter, verschobener Tag blockiert
  den Kanal), kein Downgrade (`hoechste`), Tags `vertrauen/NNNN` nur mit der Wurzel und steigender Serie. Das Ergebnis
  steht in `/var/lib/zenos/kanal/stand.json`, `zen kanal status` zeigt es mit den Fingerabdrücken. Installiert wird
  nichts, `zen update` bleibt der Weg von Hand. Solange `system/vertrauen/` keine Schlüssel hat, meldet der Kanal
  «Anker fehlt». Neu: `scripts/bin/zenos-kanal`, Module `12-vertrauen` (Anker nur anlegen, wenn er fehlt oder leer
  ist) und `14-kanal`, `zen kanal`, Abschnitt «Signierter Kanal» in `zen doctor`.
- **Signierte Releases vorbereitet:** `scripts/release-signieren.sh vX.Y.Z[-rcN]` signiert ein Release auf dem Mac
  mit dem Schlüssel «zenOS Release» aus 1Password (Touch ID, kein privater Schlüssel in einer Datei). Vorher prüft
  es sauberen Baum, HEAD auf origin, Tag neu und höher, CI und Anker und zeigt die Commits seit dem letzten Release
  sowie gesondert die sensiblen Pfade (Firewall, Netz, Boot, Anmeldung, Vertrauen). Signiert wird erst, wenn
  `pruefen.yml` für den Stand grün ist: Läuft die Prüfung noch oder ist noch kein Lauf zu sehen, wartet es höchstens
  25 Min.; ist sie rot oder danach nicht fertig, bricht es ab. Ist die CI nicht prüfbar (gh fehlt, kein Zugriff), geht
  es nur mit getipptem «ohne Prüfung» weiter, denn einen gepushten Tag nehmen Geräte auf `vorschau` sofort. Danach prüft
  es den Tag mit `git verify-tag` gegen den Anker und pusht nur nach Rückfrage. `--vertrauen` signiert mit dem Schlüssel
  «zenOS Wurzel» einen Tag `vertrauen/NNNN`, der den Anker ändert (neuer Release-Schlüssel, Widerruf). Der Anker
  `system/vertrauen/` hat Serie 1 mit den öffentlichen Schlüsseln «zenOS Release» und «zenOS Wurzel». Manifest 0 erlaubt
  jetzt ausdrücklich die öffentlichen Prüfschlüssel.

### Geändert

- **Release-Seite auch für Release-Kandidaten:** Ein gültig signierter Tag `vX.Y.Z-rcN` bekommt jetzt ebenfalls eine
  Release-Seite auf GitHub, als Vorabversion (Pre-release, nie «Latest»), mit Image, Manifest für den Imager, Quellcode
  und Herkunftsbestätigung; `vX.Y.Z` wird «Latest». Bis `v0.1.0-rc3` gab es für `-rc` nur ein Workflow-Artefakt, der
  Job «Release» lief so vor `v0.1.0` nie. Die Versionshinweise eines `-rc` sagen oben «Release-Kandidat zum Testen,
  nicht für den Alltag» und dass ein Gerät daraus im Kanal `vorschau` bleibt (zurück mit
  `sudo zen kanal wechseln stabil`). Die README verweist für den Download auf das Release mit der Marke «Latest». Ein
  Neustart des Laufs legt einen Entwurf neu an und lässt ein veröffentlichtes Release unverändert.
- **Leerer Akku (Argon ONE UP):** Bei 3 % schaltet zenOS kontrolliert aus (siehe «Energie»); bis `v0.1.0-rc3` fuhr es
  nicht selbst herunter.

### Behoben

- **Hinweise zum Anker:** `zen kanal status` versprach bei leerem Anker «kommt mit install.sh, sobald system/vertrauen
  Schlüssel hat». Die Schlüssel sind seit Serie 1 im Repo, aber `install.sh` übernimmt sie ausserhalb des Images bewusst
  nie; jetzt nennt es den Weg von Hand (`sudo zen kanal anker /opt/zenos/system/vertrauen`). Die Meldungen von
  `zen kanal anker`, `12-vertrauen` und `zen kanal` verweisen nicht mehr nur auf 1Password, sondern auf eine
  vertrauenswürdige Quelle: 1Password beim Besitzer der Schlüssel, sonst die veröffentlichten Fingerabdrücke in
  `docs/image-und-releases.md`. README und Doku sagen, was die Installation per Skript bedeutet: Kanal `dev`, ein «ja»
  je Update, kein Anker; das Image ist der empfohlene Weg.
- **Lizenzhinweise:** `RECHTLICHES` nennt jetzt auch die Schriften Geist, Geist Mono und Instrument Serif (SIL Open Font
  License 1.1, Lizenztexte unter `/usr/local/share/fonts/zenos`). `QUELLEN` und der copyright-Text von Quickshell
  nennen den Weg zu den Quellen auch für einen Release-Kandidaten: bis `v0.1.0-rc3` die Workflow-Artefakte des Laufs
  «Image», ab `v0.1.0-rc4` seine Release-Seite (siehe «Release-Seite auch für Release-Kandidaten»). Dazu der richtige
  Name `zenos-<version>-QUELLEN.txt`.
- **Prüfung der Automatik und der Updates-Seite (Teil B):**
  - Die Automatik installiert nicht mehr über einen Stand von Hand («angehalten»), auch nicht, wenn ein `install.sh`
    von Hand genau zwischen Prüfen und Installieren fertig wird.
  - Am Login-Bildschirm erst nach 5 Minuten (nicht gleich beim Start, wenn der Timer einen Lauf nachholt), nie während
    einer SSH-Sitzung, nie neben einer offenen Textkonsole; die Sperre zählt erst ab dem ersten Abgleich der Uhr.
  - Nur am Netzteil oder ab 50 % Akku, auch fürs Fortsetzen.
  - Den Zeitpunkt liest die Automatik vor dem Installieren neu («von Hand» bremst einen laufenden Lauf).
  - Eine unterbrochene Installation von Hand (etwa auf dev mit «ja») setzt nur `zen update` fort, nie die Automatik.
  - Bestätigung nach dem Start: Eine Anmeldung auf der Textkonsole zählt nicht als Login; die Bestätigung wartet auf
    eine laufende Automatik, statt bis zum nächsten Start zu verfallen; die Automatik installiert nichts Neues, solange
    ein Stand aus einem früheren Start auf sie wartet. Der Weg zurück nimmt keinen Rückweg auf den Stand ohne Login
    mehr und sperrt den guten Stand nicht; scheitert er, «kaputt», und der nächste Start versucht es noch einmal.
  - `zen update` und «Jetzt installieren» zielen nicht mehr auf eine gesperrte höhere Version; der Knopf gilt nur dem
    angezeigten, schon geprüften Stand (ohne neues Holen).
  - Updates in einer offenen Sitzung: Während der Übernahme lädt die Oberfläche nicht Datei für Datei nach, die Sperre
    lädt nicht mitten hinein neu; danach richtet die Oberfläche die Benutzerteile ein und startet neu, wenn sich QML
    geändert hat. Der Login-Bildschirm zeigt «zenOS wird aktualisiert».
  - Die Seite zeigt «Update kaputt», «Update unterbrochen», «Update läuft», «Letztes Update» und «Von Hand» auch nach
    der Prüfung danach; «Bereit» sagt je Zeitpunkt, wann es kommt; ehrliche Sätze zum Zeitpunkt; «Datei ungültig» in
    der Warnfarbe, und «Bei Sperre» repariert sie; «Wird installiert …»; die Zeilen bauen sich nur neu auf, wenn sich
    etwas ändert.
  - Mitteilungen: gescheitert und zurück auch nach mehr als 24 h genau einmal; «Seit N Tagen kein Kontakt zu origin»;
    Verweise auf «Einstellungen › System › Updates»; eine Änderung des Zeitpunkts, die nicht aus den Einstellungen
    kam, meldet sich mit dem Weg (pkexec oder sudo, uid).
  - `image/tag-pruefen.sh` nimmt keinen fremden oder ohne neue Serie gewachsenen Anker mehr an; `--nur-mechanik` gibt
    es in GitHub Actions nicht.
  - `install.sh` startet `zenos-kanal-bestaetigen.timer` nicht mehr im laufenden Betrieb (nur aktivieren): Er feuerte
    sonst nach jedem install.sh sofort und hielt kurz die Sperre der Bedienung (im Ende-zu-Ende-Test endete die
    Automatik so mit 75).
- **`zen update` bricht nicht mehr an einem verschobenen Tag ab:** Wurde ein Tag auf GitHub auf einen anderen Commit
  gesetzt (so bei `v0.1.0-rc1`), scheiterte `zen update` mit «git fetch ist fehlgeschlagen», ohne Grund. Jetzt holt
  es den Branch ohne Tags und die Tags getrennt, ohne `--force`: Ein verschobener Tag bleibt beim Stand, den das
  Gerät kennt, und erscheint nur als Warnung mit Grund. Wer noch einen Stand bis `v0.1.0-rc3` hat, kommt über den
  Notweg in `ANLEITUNG.md` (Abschnitt F) einmal darüber.
- **`zen update` und `zen rollback` robuster:** eigene Sperre (`/run/lock/zenos-kanal.lock`), damit nie zwei Wechsel
  gleichzeitig `/opt/zenos` umschreiben; der Wechsel wartet, bis ein laufendes `install.sh` fertig ist; `git fetch`
  hat 180 s Zeit und fragt nie nach Zugangsdaten; mit weniger als 1 GB frei bricht der Wechsel ab, bevor er etwas
  ändert (bei voller Platte schrieb `git checkout` Dateien nur halb).
- **`install.sh`:** läuft als root auch ohne `HOME` durch (etwa aus einem systemd-Dienst). Ein Abbruch durch SIGHUP
  (SSH weg, ohne tmux) oder SIGPIPE steht im Log als «abbruch» statt «ok».
- **`zen doctor`:** meldet eine Installation, die nach «== Beginn» nie ans Ende kam (Stromausfall, SIGKILL), und einen
  mittendrin unterbrochenen dpkg-Lauf (Reste in `/var/lib/dpkg/updates`), nach dem apt und unattended-upgrades
  nichts mehr installieren, mit dem Rat `sudo dpkg --configure -a`. Scheitert apt in `install.sh` daran, nennt die
  Meldung denselben Rat statt «Netz kurz weg». Ein Pi 5 ohne Argon-Gehäuse ergibt Hinweise statt Warnungen: Das Gehäuse
  ist optional, `zenos-argon` endet dann absichtlich mit Erfolg und «Kein Argon ONE … hat nichts zu tun», und der
  ruhende Dienst und keine Antwort an 0x1a bzw. 0x64 sind nur ein Hinweis (bisher «läuft nicht, der Argon-Lüfter wird
  nicht geregelt» und «Keine Antwort an 0x1a» als Warnungen). Nach einem Fehlschlag oder mit anderer Meldung bleibt es
  bei Warnung bzw. Fehler. Ist kein Bildschirm aktiv (Deckel zu, kein Monitor oder alle Ausgänge aus), gibt es einen
  Hinweis statt der Warnung «wlopm erreicht die Bildschirme der Sitzung nicht»; `zenos-bildschirm status` meldet dann
  «keiner», `zen energie` «kein Bildschirm aktiv».
- **Doku:** Ziel eines Rollbacks ist die letzte gültig signierte Version aus `zen kanal status`, nicht mehr `v0.1.0-rc3`
  (ANLEITUNG F, Beispiel in `zenos-kanal`): Auf `vorschau` und `stabil` brächte ein Stand ohne Kanal den alten
  `zen update` zurück, der nur Branches kennt und abbricht, und `zen kanal` fehlte; die Doku nennt die Grenze und den
  Weg ohne `zen` (`zenos-kanal update`). ROADMAP, README, ANLEITUNG A und `docs/baufortschritt.md` nannten noch
  `v0.1.0-rc2` als Stand; jetzt: rc3 gebaut, als Nächstes der signierte rc4, die Firewall seit rc3 an (auch
  `docs/funktionen.md`). `scripts/README.md`, m1 und m14 nennen für das Image den Kanal des Tags statt `dev` und
  `user`/`user` statt `ubuntu`/`ubuntu`. ANLEITUNG G sammelt die offenen Entscheidungen und Schritte vor `v0.1.0-rc4`
  und `v0.1.0`: Name und Marke (die IPR-Policy von Canonical steht jetzt vollständig zitiert in
  `docs/image-und-releases.md`), ein CHANGELOG-Abschnitt je Tag, das Warten auf die grüne Prüfung,
  `gh ruleset list --repo`, der Anker für Installationen aus `main` und die sudo-Regel von cloud-init.

### Sicherheit

- **Gesundheitsprüfung des Kanals ohne install.log:** `/var/log/zenos/install.log` gehört nach einem Lauf von Hand dem
  Benutzer (adm, 0640). Ein Prozess mit Benutzerrechten konnte es während eines Kanal-Laufs kürzen oder ein «== Beginn»
  anhängen: Die gültige Version galt dann als nicht gesund, wurde gesperrt, und das Gerät ging zurück. Jetzt schreibt
  `install.sh` im Lauf des Kanals Beginn und Ende zusätzlich nach `/var/lib/zenos/kanal/install-ergebnis` (root-eigen),
  und `zenos-kanal` liest für die Gesundheit und für die Frage, ob `install.sh` nur an seiner Sperre scheiterte, nur
  noch diese Datei. Ältere Stände ohne dieses Ergebnis prüft es weiter über das install.log.
- **sudo ohne Passwort:** `zen doctor` warnt «sudo geht ohne Passwort …», wenn eine Regel sudo ohne Passwort erlaubt,
  etwa `/etc/sudoers.d/90-cloud-init-users`: Die schreibt cloud-init, wenn der Raspberry Pi Imager bis 2.0.10 oder mit
  «sudo ohne Passwort» (`passwordlessSudo`) den Benutzer anlegt, und dann schützt keine Passwortabfrage über sudo, etwa
  bei `sudo zen firewall deaktivieren`. Bisher prüfte doctor nur die temporäre Regel aus dem Bau und zeigte ✓. Es fragt
  nur `sudo -n -k true` und ändert nichts, als root ohne Aussage. «sudo fragt immer nach dem Passwort» (seit
  `v0.1.0-rc3`) gilt nur für das Konto `user`, für einen Benutzer aus den Imager-Einstellungen nur mit einem Imager ab
  2.0.11 und ohne «sudo ohne Passwort». README, Versionshinweise und Doku sagen das jetzt; zenOS ändert die Regel von
  cloud-init nicht (offene Entscheidung in ANLEITUNG C4 und G1).
- **Manifest in Prüfsummen und Herkunftsbestätigung:** Über das Manifest lädt der Raspberry Pi Imager das Image und
  prüft es gegen die Prüfsummen darin; das Manifest selbst entstand aber erst nach der Herkunftsbestätigung und stand
  nicht in `SHA256SUMS`. Jetzt schreibt der Workflow es vorher, nimmt es in `SHA256SUMS` auf, und GitHub bestätigt die
  Herkunft von Image, Paketliste und Manifest. README und Versionshinweise prüfen mit
  `sha256sum -c --ignore-missing SHA256SUMS` (ohne die Paketliste endete der Befehl bisher mit Exit 1, obwohl alles
  stimmte) und mit `gh attestation verify` auch das Manifest, nennen den Raspberry Pi Imager ab 2.0.11 und empfehlen
  `image/tag-pruefen.sh` statt eines blossen `git verify-tag`, das den Namen des Tags nicht prüft.

## 0.1.0-rc3 – 2026-10-05

Alles seit `v0.1.0-rc2`: zenOS als eigenständige Distribution «basiert auf Ubuntu» (Systemkennung, ohne snapd und
landscape-common, Image mit Standardkonto `user`, Quellcode und Herkunft), Akku, Lüfter und WLAN-Menü für den
Argon ONE UP, die Ablage mit Thunar, die Firewall standardmässig an, App-Übersicht und App-Leiste.

**Nur als unsignierter Tag gebaut:** Das Image entstand als Workflow-Artefakt, ein Release wurde nicht
veröffentlicht. Geräte auf den Kanälen `stabil` und `vorschau` installieren `v0.1.0-rc3` nicht, denn dort gelten
nur gültig signierte Tags (`v0.1.0-rc1` bis `rc3` sind unsigniert). Den signierten Kanal hat rc3 selbst noch nicht;
ein `zen rollback` dorthin ist auf `stabil` und `vorschau` eine Sackgasse (ANLEITUNG F).

### Neu

- **Systemkennung zenOS:** Das System weist sich als zenOS aus (`ID=zenos`, `ID_LIKE="ubuntu debian"`), wie Pop!_OS,
  Mint und elementary: an der Textkonsole («zenOS 0.1.0-… <rechner> tty1»), bei `hostnamectl` und `lsb_release`, mit
  eigenem Logo (`LOGO=zenos`) und einer ruhigen Begrüssung bei der Anmeldung («zenOS … · Basis Ubuntu 26.04.1 LTS ·
  Kernel …») ohne die Hinweise und die Werbung von Ubuntu. «Basiert auf Ubuntu» bleibt überall sachlich stehen, alle
  Lizenz- und Urheberhinweise ebenso. Umgestellt wird nur, wenn unattended-upgrades die Ubuntu-Sicherheitsquelle
  auch mit der neuen Kennung nachweislich zulässt; sonst bleibt (oder wird) die Kennung Ubuntu, mit Warnung. Nach
  jedem apt-Lauf übernimmt die Kennung den Stand von Ubuntu (neue Punktversion, Codename). Kein Ubuntu-Paket wird
  geändert, nur umgelenkt (`dpkg-divert`, `dpkg-statoverride`). Zurück zu Ubuntu, und dabei bleiben:
  `sudo zenos-kennung ubuntu`; wieder zenOS: `sudo zenos-kennung einrichten`. `zen doctor` hat einen Abschnitt
  «Systemkennung», das Image wird ohne nachgewiesene Sicherheitsquelle nicht gebaut. Vor einem Release-Upgrade:
  `sudo zenos-kennung ubuntu`, danach `sudo zenos-kennung einrichten` (`docs/module/kennung.md`).
- **App-Übersicht:** Ein Klick auf das Zeichen oben links öffnet das Befehlsfeld mit allen installierten Apps
  (Web-Apps eingeschlossen) als Raster aus Kacheln, alphabetisch. Die Karte gleitet vom Zeichen her auf, die
  Kacheln blenden diagonal ein, alles in 200 ms. Pfeiltasten wählen, Enter oder ein Klick startet, Tippen sucht wie
  gewohnt; ein zweiter Klick auf das Zeichen schliesst. Ohne Apps steht dort «Apps installieren». Neu per IPC:
  `zenos-ipc befehlsfeld apps` und `befehlsfeld ansicht`.
- **Akku und Lüfter (Argon ONE UP):** Auf dem Laptop Argon ONE UP mit Compute Module 5 zeigt die Leiste oben rechts
  den Akku mit Prozent, beim Laden mit Blitz; bei höchstens 10 % im Akkubetrieb ruhig in der Warnfarbe. Das
  System-Menü zeigt Akku, Lüfter («aus» oder «Stufe 2 von 4 · 3120 U/min») und CPU-Temperatur. Bei 10 % kommt eine
  ruhige Mitteilung, bei 5 % ersetzt sie eine dringende Karte, die sofort erscheint (ohne Ton); am Netzteil
  verschwindet sie. zenOS fährt nicht selbst herunter. Der Dienst `zenos-argon` erkennt das Gerät und liest den
  Akku-Messchip (Cellwise CW2217). Schläft der Chip, weckt er ihn und lädt Argons Akkuprofil, aber erst nach
  `zen akku freigeben` und nur wenn nötig; danach misst er alle 15 s. Den Lüfter regelt weiter der Kernel.
  `zen akku status`, `zenos-argon --pruefen` und `zen doctor` zeigen den Akku.
- **Lüfter einstellen:** Im System-Menü klappt die Zeile «Lüfter» eine ruhige Wahl «Auto · 1 · 2 · 3 · 4» auf; ohne
  Passwort, nur am Gerät. «Auto» ist der Standard wie bisher, eine Stufe ist das Minimum: Bei Wärme läuft der Lüfter
  schneller, nie leiser als automatisch, ab 80 °C voll. Ein «aus» gibt es nicht. Die Zeile zeigt Stufe und Wunsch
  («Stufe 2 · mind. 2», «aus · Auto»). Am Argon ONE UP stellt `zenos-argon` dafür den Regler der Thermal-Zone auf
  `user_space` und gibt ihn bei «Auto», beim Beenden und nach Fehlern an den Kernel zurück (dazu eine Sicherung in der
  Unit für einen Absturz und ein Watchdog, falls der Dienst hängt); am Argon ONE V3 hebt die Stufe die eigene Kurve
  an. Der Wunsch bleibt über Neustarts (`/var/lib/zenos/luefter`). `zen luefter [status|auto|1|2|3|4]`, `zen doctor`
  und `zenos-argon --pruefen` zeigen und setzen ihn. Neu per IPC: `zenos-ipc leiste menue luefter`.
- **WLAN-Menü oben rechts:** Das System-Menü zeigt «WLAN» mit Schalter, das verbundene Netz und aufklappbar die
  Netze in Reichweite mit Signal und Schloss. Ein Klick verbindet ein bekanntes Netz, bei einem neuen erscheint ein
  Passwortfeld (Enter verbindet, Esc bricht ab); gespeicherte Netze lassen sich vergessen. Es ist nur eine
  Oberfläche für den NetworkManager von Ubuntu; Passwörter gehen nur über D-Bus an ihn. Netznamen stehen als reiner
  Text da, offene Netze verbinden sich später nur auf Klick. Während einer Bildschirmfreigabe stehen keine
  Netznamen da. Neu per IPC: `zenos-ipc leiste menue wlan`.
- **`zen netzwerk`:** `zen netzwerk umstellen` stellt das Netz einmal von netplan mit systemd-networkd auf
  NetworkManager um: jedes WLAN wird ein eigenes Profil, die alten Dateien werden gesichert, wirksam nach dem
  Neustart (kein `netplan apply`). Auf dem Raspberry Pi schaltet es dabei WPA3 im WLAN-Treiber ab, weil der Chip
  es nicht kann; Mischnetze verbinden über WPA2. `zen netzwerk zurueck` geht ohne Netz zurück, `zen netzwerk
  status` zeigt den Stand, `zen doctor` hat einen Abschnitt «Netz». Ein neues Image stellt beim ersten Start
  selbst um.
- **Scroll-Tempo einstellbar:** Einstellungen → Allgemein → «Scroll-Tempo für Touchpad und Maus» mit «Langsam»,
  «Normal», «Schnell» und «Sehr schnell» (Faktor 0.5, 1, 1.5, 2 für labwc). Die Wahl gilt sofort, ohne Abmelden.
  Gespeichert als `scrollTempo` in `einstellungen.json` (von Hand 0.25 bis 3); ohne Eintrag bleibt alles wie bisher.
- **Ablage:** `~/Ablage` ist der eine Ordner für deine Dateien, ohne vorgegebene Struktur. Ein Knopf mit
  Ordner-Symbol rechts neben dem Raster («4er») und die Aktion «Ablage» im Befehlsfeld öffnen ihn im Dateimanager.
  Downloads, Dokumente, Bilder, Musik und Videos landen dort (`~/.config/user-dirs.dirs`); Ordner wie Downloads oder
  Dokumente legt zenOS nicht an.
- **Vorgabe-Ordner von xdg-user-dirs aufgeräumt:** Hat Ubuntus xdg-user-dirs bei der ersten Anmeldung Desktop,
  Downloads, Documents … angelegt, richtet zenOS die Benutzerordner trotzdem auf die Ablage und entfernt die leeren
  davon; Ordner mit Dateien bleiben.
- **Bildschirmfotos in `~/Ablage/Screenshots`** (vorher `~/Bilder/Screenshots`). Ein leerer alter Ordner
  verschwindet, einer mit Bildern bleibt, und `install.sh` sagt, wie man sie holt.
- **Dateimanager Thunar** (von Ubuntu, im Image): öffnet Ordner aus dem Befehlsfeld und die Ablage, folgt hell und
  dunkel, ohne Indexer im Hintergrund. Vorher öffneten Ordner in kitty. «Terminal hier öffnen» im Rechtsklick
  startet kitty im Ordner. `zen doctor` prüft Ablage und Dateimanager.
- **Firewall standardmässig an:** `install.sh` (auch `zen update`) schaltet ufw ein: eingehend gesperrt, ausgehend
  offen, SSH nur aus lokalen Netzen. Vorher prüft es, ob jede laufende SSH-Verbindung erlaubt bleibt; sonst bleibt
  die Firewall aus und es warnt. Neue Images starten mit eingeschalteter Firewall.
- **Schalter «Firewall»** in Einstellungen → System. Einschalten geht sofort, Ausschalten nur mit dem Passwort, jedes
  Mal. Wer sie bewusst ausschaltet, behält das: `zen update` lässt sie dann aus (`/var/lib/zenos/firewall`). Solange
  sie aus ist, steht «Firewall · aus» im System-Menü, und `zen doctor` warnt.
- **Passwortdialog für Administratorrechte (polkit-Agent):** Verlangt ein Programm Rechte, die polkit nur nach einer
  Anmeldung gibt, fragt ein ruhiger Dialog nach dem Passwort und zeigt, wofür. Das Passwort geht nur an polkit.
  Während der Sperre gibt es keine Dialoge. Neu per IPC: `zenos-ipc polkit status|agent|abbrechen`.
- **`zen firewall deaktivieren`** schaltet nach der Eingabe «deaktivieren» aus und merkt sich das.
- **App-Leiste am rechten Rand:** Mit der Maus rechts in der Mitte an den Rand fahren und kurz ruhen (300 ms), dann
  gleitet eine schmale Karte mit einem Symbol pro offener App herein, auch über einem Vollbild-Fenster. Ein Klick
  holt die App nach vorne (minimierte kommen zurück), bei der aktiven App mit mehreren Fenstern das nächste. Die
  aktive App trägt einen Punkt im Akzent, mehrere Fenster eine kleine Zahl, beim Zeigen steht der Name daneben.
  Sonst ist am Rand nichts zu sehen; oben und unten und beim Vorbeifahren passiert nichts. Nie während Sperre und
  Einrichtung. Neu per IPC: `zenos-ipc appleiste zeigen|verbergen|status|apps`.

### Geändert

- **Image: Standardkonto und erster Start:** Ohne Einstellungen aus dem Raspberry Pi Imager heisst der Benutzer
  `user` («Default User») mit dem Passwort `user`, das bei der ersten Anmeldung geändert werden muss, und der Rechner
  `zenos` (bisher `ubuntu`/`ubuntu`). sudo fragt immer nach dem Passwort; bisher bekam der Standardbenutzer sudo ohne
  Passwort, womit etwa die Passwortsperre der Firewall wirkungslos war. SSH nimmt weiter nur Schlüssel an. Auf der
  Startpartition liegt ein README von zenOS, und `config.txt` hat einen Abschnitt `[cm5]` mit USB-2 im Host-Modus:
  Am Argon ONE UP gehen Tastatur, Touchpad und USB damit gleich beim ersten Start.
- **Releases mit Quellcode, Manifest und Herkunft:** Jedes Release enthält neben dem Image die Paketliste, den
  Quellcode aller enthaltenen Pakete in genau den ausgelieferten Versionen (`image/quellen.sh`, in Teilen unter
  2 GiB, mit Übersicht) und von Quickshell, ein Manifest für den Raspberry Pi Imager 2.x (nur damit wirken dort die
  Einstellungen für Benutzer, SSH und WLAN) und eine Herkunftsbestätigung von GitHub (`gh attestation verify`).
  Ohne vollständige Quellen gibt es kein Release. Die Versionshinweise sind zweisprachig und nennen die Basis
  Ubuntu und die Markenhinweise.
- **Lizenzhinweise im System:** `/usr/local/share/doc/zenos/` mit `copyright`, `RECHTLICHES` (Lizenzen, Marken) und
  `QUELLEN` (wo der Quellcode liegt), im Image dazu `pakete.txt`; `/usr/local/share/doc/quickshell/` mit Herkunft,
  Commit, Bauoptionen und den Lizenztexten (LGPL 3). `/etc/legal` verweist darauf.
- **`zen version`** zeigt statt «System …» eine Zeile «Basis Ubuntu 26.04.1 LTS» (aus der os-release von Ubuntu);
  Einstellungen → System ebenso.
- **motd-news ohne Eingriff ins Conffile:** Statt `ENABLED=0` in `/etc/default/motd-news` maskiert zenOS
  `motd-news.timer` und `motd-news.service` und legt `50-motd-news` per `dpkg-statoverride` still. Ein geändertes
  Conffile hielte unattended-upgrades bei einem Update des Pakets an. Ein schon gesetztes `ENABLED=0` bleibt stehen.
- **README:** zenOS heisst dort «eigenständige Linux®-Distribution, basiert auf Ubuntu 26.04 LTS», dazu ehrlich, dass
  Programme aus «universe» verlässliche Sicherheitsfixes nur mit Ubuntu Pro bekommen, und die Markenhinweise von
  Canonical, der Linux Foundation und Raspberry Pi. `docs/image-und-releases.md` («Name und Marke») behauptete, das
  Image trage kein Ubuntu-Logo; das stimmte nicht und ist korrigiert.
- **Manifest:** «kein eigenes WLAN-Menü» heisst jetzt «kein eigener Netzwerk-Stack»; das WLAN-Menü oben rechts
  bedient nur den NetworkManager von Ubuntu.
- **Netzsymbol in der Leiste** mit Signalstufe: ein bis drei Bögen, die fehlenden blass.
- **`zen update` installiert NetworkManager** (ohne Empfehlungen, also ohne Ubuntus Konnektivitätsprüfung) und lässt
  ihn aus, bis `zen netzwerk umstellen` läuft.
- **Gerätewerte für die Leiste:** `zenos-argon` schreibt `/run/zenos/geraet.json` (Version 1, mit Akku) statt
  `/run/zenos/argon.json`. Der Lüfter steht im System-Menü in einer eigenen Zeile, die CPU-Temperatur ebenso.
- **Natürliches Scrollen** wie auf dem Mac, für Touchpad und Maus (labwc, `rc.xml`).
- **Fenstergrösse leichter ziehen:** Ränder wirken mindestens 16 px breit (vorher 8), Ecken greifen auf 40 px
  entlang jeder Kante (vorher 17).
- **SSH-Regeln der Firewall mit Begrenzung** (`limit` statt `allow`): Je Adresse lässt sie in 30 s fünf neue
  Verbindungen zu und weist die sechste ab. `zen firewall aktivieren` schaltet über denselben Helfer ein wie der
  Schalter (`scripts/bin/zenos-firewall`) und merkt sich «an».
- **Neue Pakete:** `pkexec` (für den Schalter) und `iproute2` (`ss`, für die Prüfung der SSH-Verbindungen; bei Ubuntu
  Server schon dabei).
- **Passwortfelder leeren gründlicher:** Nach dem Weiterreichen bleibt das Getippte auch nicht im
  Rückgängig-Verlauf des Feldes stehen (Login, polkit-Dialog).
- **Alt+Tab grösser und mit App-Symbolen:** Der Fensterwechsler ist so breit wie das Befehlsfeld (720 statt 600 px),
  jede Zeile beginnt mit dem App-Symbol in 40 px (vorher so gross wie die Schrift), Name und Titel in 16 px, mehr
  Abstand. Der Titel fehlt, wenn er nur die App-Kennung wiederholt. Das Verhalten bleibt.
- **Ubuntu-Sicherheitsupdates hängen nicht mehr am Namen des Systems:** `/etc/apt/apt.conf.d/51zenos-ubuntu-quellen`
  erlaubt unattended-upgrades die Ubuntu-Quellen mit festem Origin «Ubuntu». Bisher kam das nur über `${distro_id}`
  aus `/etc/os-release`; eine andere Kennung dort hätte alle Sicherheitsupdates still abgeschnitten. Heute ändert sich
  dadurch nichts, es ist die Vorbereitung für eine eigene Systemkennung. `zen doctor` prüft mit der Logik von
  unattended-upgrades selbst, ob Ubuntu-Sicherheitsupdates erlaubt sind (neu: `zenos-sicherheitsquelle`).
- **zenOS-Pakete als manuell installiert markiert:** Was Ubuntu schon über ein Metapaket mitgebracht hatte (ufw,
  unattended-upgrades, jq, polkitd …), entfernt `apt autoremove` nicht mehr, wenn das Metapaket wegfällt.
  `zen doctor` warnt, wenn ufw oder unattended-upgrades wieder als automatisch installiert gelten.

### Entfernt

- **snapd und landscape-common:** snapd ist Store-Software, die von selbst ins Netz geht; landscape-common trägt nur
  die Marke Landscape. `zen update` entfernt beide mit `apt-get purge` (neues Modul `22-aufraeumen`), aber nur, wenn
  apt sie als automatisch installiert führt und ein Probelauf zeigt, dass nichts anderes mitginge (kein
  ubuntu-*-Metapaket, kein zenOS-Paket). Sind eigene Snaps installiert, bleibt snapd mit einer Warnung samt Weg;
  `~/snap` bleibt immer unberührt. `/etc/apt/preferences.d/zenos-ohne-snapd` hält snapd danach fern, auch als
  Empfehlung von ubuntu-server. Kein `autoremove`: Die früheren Abhängigkeiten von landscape-common (bc,
  python3-twisted …) bleiben, bis man selbst `sudo apt autoremove` aufruft. `zen doctor` prüft beides und den Pin.
  Rückweg: Pin löschen, `sudo apt install snapd landscape-common` (dann bleiben sie).

### Behoben

- **Login:** Er zeigte «Anmelden als Ubuntu»: cloud-init gibt dem ersten Benutzer eines Ubuntu-Images den Anzeigenamen
  «Ubuntu», auch wenn der Raspberry Pi Imager einen eigenen Login setzt. Steht im GECOS-Feld «Ubuntu», zeigt der Login
  jetzt den Login-Namen.

## 0.1.0-rc2 – 2026-09-28

Alles seit `v0.1.0-rc1`: die neue Bildmarke, ein vorbereiteter Bootsplash und die Behebungen aus der Abnahme in einer
VM mit Ubuntu 26.04 arm64 und Chrome 154.

### Neu

- **Bildmarke «Zwei Steine»:** ein Kiesel, diagonal geteilt; der untere Stein trägt den Akzent des aktiven Modus.
  Alle Varianten (einfarbig, farbig, Pixel-Variante für 16 px, Schriftzug, App-Icon, Favicon, GitHub-Avatar,
  Vorschaubild) liegen in `assets/zeichen/`, erzeugt von `erzeugen.py`. Regeln in `docs/bildmarke.md`.
- **`ZenZeichen`** zeigt die Marke in Leiste, Login, Sperrbildschirm, Befehlsfeld (ohne Treffer), Erstem Start und
  Notfall-Login. Bei einem Moduswechsel blendet nur der untere Stein über, hell/dunkel wechselt beide im selben Bild.
  Dazu das App-Icon `zenos` im hicolor-Thema des Benutzers.
- **Bootsplash (Plymouth), vorbereitet, nicht aktiv:** Die Steine gleiten zusammen, der untere blendet zum Akzent,
  danach atmet der Spalt; das Passwortfeld sieht aus wie in Sperre und Login. `zen bootsplash` zeigt den Stand,
  `zen bootsplash aktivieren` schaltet nach Rückfrage ein, `zen bootsplash deaktivieren` nimmt es zurück.

### Behoben

- **Bildschirmfreigabe mit Chrome (Leitplanke):** Beim Klick auf «Teilen» schliesst Chrome die Freigabe seiner
  Vorschau und öffnet sofort eine zweite, ohne Bildschirmwahl. Dazwischen war die Leitplanke 0,6 bis 1,8 s aus, und
  Mitteilungsinhalte konnten ins geteilte Bild gelangen. Jetzt endet eine Freigabe erst nach einem Nachlauf (3 s in
  `zenos-freigabe`, dann 2 s in der Oberfläche), und nur für Freigaben, die vor dem Ende begannen; die Reihenfolge
  entscheidet der Aufrufzeitpunkt. «Sitzung» endet so rund 5 s nach dem Ende der Freigabe, erst dann kommt
  Zurückgehaltenes.
- **Portal beendet:** Die Freigabe wird auch nach `systemctl --user kill` am Portal zurückgesetzt (zusätzlich
  `ExecStartPre` im Drop-in). Vorher blieben Rahmen, Sitzung und Zurückhalten stehen.
- **«Beim Wechsel öffnen: Chrome»** öffnet Chrome im Profil des neuen Modus auch dann, wenn Chrome schon offen ist
  (ein neues Fenster; keins, wenn in diesem Profil schon eines offen ist).
- **Hell/Dunkel:** Hell setzt `color-scheme` jetzt auf `prefer-light` statt `default`. Ein laufendes Chrome wechselt
  so auch von dunkel zurück auf hell (vorher blieb es dunkel). Bestehende Installationen stellen beim nächsten
  Wechsel oder Sitzungsstart selbst um.
- **Mitteilungen:** Dringende Karten lagen über dem System-Menü und fingen dessen Klicks ab. Solange ein Menü der
  Leiste offen ist, treten die Karten auf diesem Bildschirm zurück und kommen danach wieder.
- **Einstellungen:** Eine Änderung während eines laufenden Speicherns (etwa zwei schnelle Klicks auf Farben) ging
  bei Modi, Zuständen, Rastern und Bildschirmen still verloren. Jetzt wird sie danach gespeichert.
- **Erster Start:** Befehlsfeld, Modus- und Zustand-Wahl und Einstellungen öffneten unsichtbar hinter der
  Einrichtung; jetzt bleiben sie zu, bis sie fertig ist. In der Zustimmung liegt der Fokus auf «Installieren», Enter
  genügt. Das Terminal dazu ist höher (bis 64 Zeilen, nie über den Bildschirmrand), und passt die Übersicht nicht,
  zeigt ein Hinweis vor der Frage, wie man zurückblättert (vorher waren die Angaben zu Chrome schon hinausgescrollt).
- **Apps:** Den zweiten, kaputten Starter, den coremail beim ersten Start anlegt, entfernt zenOS (das Befehlsfeld
  zeigte coremail doppelt, der zweite Eintrag startete nichts). Chrome wird Standardbrowser, sofern du nichts anderes
  gewählt hast. Das Befehlsfeld bietet «Apps installieren» nur noch an, wenn die gesuchte App fehlt, sonst «Apps
  verwalten». Fehlt das Programm eines Starters (auch hinter `env NAME=WERT …`), erscheint «Programm nicht gefunden»
  statt still nichts.
- **`zen doctor`** erkennt die temporäre sudo-Regel auch, wenn cloud-init `/etc/sudoers.d` auf 0750 gesetzt hat, und
  meldet den echten letzten Lauf von unattended-upgrades (vorher «✓», auch ohne einen Lauf). Neu warnt es, wenn der
  Login in diesem Boot im Notfall-Modus lief (mit Grund) oder coremail wieder einen kaputten Starter angelegt hat,
  und zeigt, ob Chrome Standardbrowser ist.
- **Installer:** Bricht apt an einem Download ab, steht darunter, dass ein neuer Lauf genügt.
- **Login:** Die Ausgaben des Greeters stehen im Journal (`journalctl -b -t zenos-greeter`), der Grund eines
  Notfall-Logins geht nicht mehr verloren.
- **Terminal:** `?` wählt das Beispiel passend zu den Optionen: `? tar -xzf` zeigt Entpacken statt `tar cf`.
- **Doku:** volle Pfade für `zenos-ipc` und `zenos-thema` (nicht im `PATH`), sicheres DNS in Chrome (von den
  Richtlinien abgeschaltet) und coremail noch ohne `mailto:` beschrieben.

### Bekannte Grenzen

- Beginnt eine Freigabe ohne Bildschirmwahl und ohne eine andere Freigabe in den Sekunden davor (gespeicherte
  Freigabe einer anderen App), können die ersten Bilder weiter Inhalte zeigen. Mit Chrome kam das nicht vor: Dort
  beginnt jede Freigabe mit der Wahl.
- Symbole neu installierter Apps erscheinen im Befehlsfeld erst nach dem nächsten Anmelden.
- Chrome zeichnet seinen eigenen Rahmen, ohne zenOS-Titelzeile und Akzentrand; eingerastet ragt sein Schatten in
  die Lücke. Umstellbar in Chrome, die Entscheidung steht in `ANLEITUNG.md` unter G.

### Entfernt

- Die Platzhalter-Marke «Offene Stelle» (`assets/zeichen-platzhalter.svg`, `Zeichen.qml`), die grossen
  Bogen-Wasserzeichen in Sperre, Login und Erstem Start und das Farb-Token `wasserzeichen`. Der Login zeigt unten nur
  noch das Zeichen, ohne den Text «zenOS».

## 0.1.0-rc1 – 2026-09-28

Erster vollständiger Stand von zenOS 0.1, gebaut nach `BAUAUFTRAG.md`. Getestet in Containern mit Ubuntu 26.04
arm64; die Abnahme auf dem Pi folgt mit `ANLEITUNG.md`. Noch kein Release: Der Tag baut das Image nur als
Workflow-Artefakt.

### Neu

- **M1 · Installer und `zen`:** `scripts/install.sh` richtet alles ein und darf beliebig oft laufen (zweiter Lauf
  «0 Änderungen»), Protokoll unter `/var/log/zenos/install.log`, wartet auf laufende Paketvorgänge. `zen update`,
  `zen rollback <tag>`, `zen doctor` (Prüfbericht ohne Geheimnisse), `zen version`, `zen hilfe`; nach einem Update
  startet die Oberfläche gezielt neu. `scripts/pruefen.sh` prüft das Repo bis zum Start der Oberfläche.
- **M2 · Basis und Sitzung:** labwc, kitty, fish, PipeWire und Portale; Quickshell v0.3.1 aus dem Quellcode (neu
  gebaut nur bei einem neuen Qt). Login über greetd mit einem Greeter im zenOS-Look, ohne Autologin, mit
  Notfall-Login und Hinweis bei abgelaufenem Passwort. Schriften Geist, Geist Mono und Instrument Serif.
- **M3 · Design-Tokens und Theme:** `shell/theme/tokens.json` ist die einzige Quelle für Farben, Schrift, Radien und
  Bewegung. Hell und dunkel (auch nach Tageszeit) mit einem Schalter für Oberfläche, GTK, Qt, kitty, labwc, Chrome
  und VS Code; `zen thema`. Ruhiger Textcursor, der nicht blinkt.
- **M4 · Leiste und «Heute»:** Leiste nach Entwurf 2 mit Modus, Zustand, Raster, Uhrzeit, Mitteilungen,
  Hell/Dunkel und System-Menü (Netz, Ton, 1Password, Temperatur und Lüfter, Sperren, Abmelden, Neustart,
  Ausschalten). Hintergrund «Heute» mit Datum, Gruss und Zusammenfassung.
- **M5 · Befehlsfeld:** `Super + Leertaste` für Apps, Web-Apps, Rechnen, Dateien, Modi, Zustände und Aktionen.
  Werkzeuge Bildschirmfoto (Zwischenablage und `~/Bilder/Screenshots`) und Farbpipette.
- **M6 · Mitteilungen:** Quickshell ist der einzige Mitteilungsdienst. Gesammelt nach Zustand (ohne Zustand zur
  vollen Stunde), Dringendes sofort, Zentrale mit «Jetzt zustellen».
- **M7 · Sperrbildschirm:** ext-session-lock mit PAM; `Super + L`, `zen lock` (auch per SSH), automatisch bei
  Inaktivität und Standby. Bleibt nach einem Absturz gesperrt, Notfall-Sperre mit swaylock; 1Password sperrt mit.
- **M8 · Modi und Zustände:** eigene Modi (Akzent, Chrome-Profil, Apps beim Wechsel, Raster) und Zustände mit den
  Vorlagen Fokus und Sitzung, pro Modus anpassbar. Umschalter mit `Super + M` und `Super + Z`, Einstellungen
  «Modi & Zustände». Die Sitzung startet bei Bildschirmfreigabe von selbst, mit Rahmen und Label.
- **M9 · Raster und Bildschirme:** labwc-Regionen aus `raster/*.json`, Vorlagen Voll, Hälften, 3 Spalten, 4er-Grid
  und Gross + 2. Tastenkürzel für Bereiche, Hälften, Maximieren und den anderen Bildschirm; Bildschirm-Profile mit
  kanshi.
- **M10 · Terminal:** kitty mit schlauem `Ctrl + C`, `Ctrl + V` und Super-Kürzeln; fish mit Eingabezeile und
  Statuszeile pro Befehl. `?` erklärt Befehle offline, gefährliche Befehle brauchen eine Bestätigung. Dazu eza, bat,
  zoxide, fzf und tealdeer.
- **M11 · Sicherheit:** automatische Sicherheitsupdates, Chrome- und VS-Code-Richtlinien, Ubuntu-Nachrichten aus,
  gitleaks als Pre-Commit-Hook und in GitHub Actions. Die Firewall ist vorbereitet, `zen firewall` zeigt und
  schaltet sie ein.
- **M12 · Erster Start:** Einrichtung mit Name, Ort, Erscheinungsbild und erstem Modus. Nach Zustimmung installiert
  `zen apps` Chrome, VS Code, 1Password mit SSH-Agent, die 1Password-CLI und coremail aus den Quellen der
  Hersteller. Web-Apps in den Einstellungen.
- **M13 · Argon ONE:** `zenos-argon` regelt den Lüfter (55, 60, 65 °C) und wertet den Power-Button aus (Doppeltipp
  Neustart, Halten Ausschalten); beim Ausschalten bekommt die Platine das Abschaltsignal. Temperatur und Lüfter in
  der Leiste.
- **M14 · Image:** `image/bauen.sh` und ein Workflow für Tags `v*`: Ubuntu-26.04-Image mit geprüfter Signatur,
  `install.sh --image`, `SHA256SUMS`. Tags mit `-rc` nur als Artefakt, andere als Release.

### Bekannte Grenzen

- **Raster pro Bildschirm:** labwc 0.9 kennt Regionen nur global. Pro Bildschirm-Profil gilt ein Raster für alle
  Bildschirme, auch wenn `bildschirme.json` eines pro Ausgang speichert. Fenster sind nur oben abgerundet.
- **Nubix:** kein ARM-Build bis v4.4.4. `zen apps` bietet es an, sobald es einen gibt.
- **«Danach»:** Kalender und Termine (Leiste, rechte Spalte von «Heute», Auslöser `kalender`), Aufgaben, Wetter und
  Dev-Server fehlen noch. Die Zustandswerte `fenster` und `widgets` werden gespeichert, wirken aber noch nicht.
- **Passwortwechsel** geht nicht im Login (greetd 0.10 kennt kein `pam_chauthtok`), sondern an der Textkonsole.
- **Bildschirmfreigabe ohne Bildschirmwahl** (gespeichertes Token): Dann kündigt nichts die Freigabe vor dem ersten
  Bild an.
- **Am Pi zu prüfen:** Grafik mit GPU und 60 fps, greetd auf dem VT, echte Tastatur, Argon ONE (I2C, GPIO),
  Bildschirmfreigabe mit Chrome. Getestet ist bisher nur im Container, die Punkte stehen in `ANLEITUNG.md` und
  `docs/module/`.
- **Voraussetzung:** Ubuntu 26.04 braucht auf dem Pi 5 einen Bootloader vom 11.02.2025 oder neuer.

### Sicherheit

- **Leitplanken im Code**, nicht abschaltbar: Bei Bildschirmfreigabe bleiben Mitteilungsinhalte verborgen, der
  Sperrbildschirm zeigt nie Inhalte, die automatische Sperre gilt immer (1 bis 15 Minuten).
- Sperre und Login nur über PAM; zenOS fasst kein Passwort an. Prozesse starten mit Argumentlisten, nie über
  `sh -c`.
- **Keine Telemetrie:** 13 Chrome-Richtlinien (darunter 5 Abschaltungen von Telemetrie, nur die 1Password-Erweiterung
  erlaubt), VS Code mit `TelemetryLevel` `off`, motd-news und apt-news aus.
- Proprietäre Apps nur nach Zustimmung, aus den Quellen der Hersteller mit geprüften Schlüsseln, Signaturen und
  Prüfsummen, nie im Image.
- gitleaks prüft jeden Commit und in GitHub Actions den ganzen Verlauf. Die Firewall erlaubt SSH nur aus lokalen
  Netzen und bleibt bis zur Entscheidung aus.
