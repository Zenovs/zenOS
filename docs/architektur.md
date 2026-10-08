# Architektur

zenOS ist eine Sitzung auf Ubuntu Server: ein Fenstermanager (labwc), eine selbst gebaute Oberfläche (Quickshell)
und ein Installer, der beides einrichtet. Diese Seite beschreibt den Stand von Version 0.1. Einzelheiten und
Entscheidungen jedes Bausteins stehen in `docs/module/m1.md` bis `docs/module/m14.md`, dazu `bootsplash.md`,
`ablage.md`, `netzwerk.md` und `kennung.md`. Das System weist sich als zenOS aus (`ID=zenos`, `ID_LIKE="ubuntu debian"`)
und bleibt dabei ein Ubuntu mit dessen Paketen und Sicherheitsupdates (`docs/module/kennung.md`). Die übrigen
Paket-Updates innerhalb von Ubuntu 26.04 LTS bringt `zen update` als zweiten Schritt («Update-Fluss»); ein Wechsel der
Ubuntu-Hauptversion ist gesperrt und kommt nur als neue zenOS-Hauptversion mit neuem Image.

## Schichten

```
┌───────────────────────────────────────────────────────────────┐
│ Apps: Chrome, VS Code, 1Password, coremail, kitty + fish,     │
│ Web-Apps (proprietäre Apps nur nach Zustimmung, nie im Image) │
│ Dateimanager Thunar (von Ubuntu)                              │
├───────────────────────────────────────────────────────────────┤
│ zenOS-Oberfläche: Quickshell v0.3.1 (QML, Qt 6.10)            │
│ Leiste · «Heute» · Befehlsfeld · Mitteilungen · Sperre        │
│ Umschalter · Einstellungen · Einrichtung · Login (Greeter)    │
├───────────────────────────────────────────────────────────────┤
│ Sitzung: systemd-Benutzer-Target zenos-sitzung                │
│ labwc 0.9 (Wayland) · Portale · PipeWire · kanshi · swayidle  │
├───────────────────────────────────────────────────────────────┤
│ Ubuntu 26.04 LTS Server (arm64) · greetd · systemd · Kernel   │
└───────────────────────────────────────────────────────────────┘
```

## Anmeldung und Sitzung

1. **Login:** greetd (VT 7, Benutzer `_greetd`, kein Autologin) startet `scripts/bin/zenos-greeter`: ein eigenes
   labwc (`-C system/greeter/labwc`, ohne Vorgabe-Tasten, ohne Menü) mit Quickshell und `shell/greeter.qml`. Der
   Greeter ist immer dunkel, meldet über `Quickshell.Services.Greetd` an und startet `zenos-sitzung`. Lädt die
   Oberfläche nicht (Fehler in einem Dienst), erscheint ein schlichter Notfall-Login ohne `qs.*`-Module
   (`shell/greeter/notfall/`). greetd 0.10 kann kein Passwort ändern (kein `pam_chauthtok`); ein abgelaufenes
   Passwort wird an der Textkonsole geändert, der Login nennt den Weg. Die Ausgaben des Greeters (labwc, Quickshell)
   stehen im Journal: `journalctl -b -t zenos-greeter` (Systemjournal, lesbar mit der Gruppe `adm` oder sudo).
2. **`zenos-sitzung`** setzt die Umgebung und die Tastaturbelegung aus `/etc/default/keyboard`, ruft
   `install.sh --nur-benutzer --ruhig` (Benutzerteile, höchstens 2 Minuten), beendet Reste einer abgestürzten
   Sitzung, löscht die Marker in `$XDG_RUNTIME_DIR/zenos` und startet labwc.
3. **labwc** liest `~/.config/labwc/environment`. `autostart` gibt die Umgebung an systemd und D-Bus weiter (auch
   `LABWC_PID` und `XDG_SESSION_ID`) und startet `zenos-sitzung.target`.
4. **`zenos-sitzung.target`** (`BindsTo=graphical-session.target`) zieht per `Wants=`:
   - `zenos-shell.service`: Quickshell mit `~/.config/quickshell` (Verweis auf `/opt/zenos/shell`), `Restart=always`.
   - `zenos-idle.service`: swayidle über `zenos-idle` (automatische Sperre, danach Bildschirm aus; Hemmer für die
     Ein/Aus-Taste), `Restart=always`.
   - `zenos-kanshi.service`: kanshi mit der Konfiguration aus `bildschirme.json`.

   Die Einheiten liegen in `/etc/systemd/user`. systemd 259 durchsucht `/etc/xdg/systemd/user` nur über
   `XDG_CONFIG_DIRS`; unter Ubuntu ist dieser Ordner ein Verweis auf `/etc/systemd/user`.
5. **Abmelden:** `zenos-abmelden` stoppt zuerst das Target und `graphical-session.target`, dann labwc. So endet
   kein Dienst als «failed». `~/.config/labwc/shutdown` räumt bei jedem anderen Ende auf.

Das System startet mit `graphical.target`. Die Installation aktiviert greetd, startet es aber nicht; der Login
erscheint erst nach dem Neustart, und eine SSH-Verbindung bleibt während der Installation bestehen.

## Komponenten

### Fenstermanager

- **labwc 0.9** verwaltet die Fenster. `zenos-labwc` erzeugt `~/.config/labwc/rc.xml` aus `system/labwc/rc.xml.in`,
  dem aktiven Raster, den Tokens (Regionen `r1 … rN`, Tastenkürzel, Titelzeile, Lücke) und dem Scroll-Tempo aus
  `einstellungen.json` und lädt labwc neu.
  Fenster rasten per Tastenkürzel oder beim Ziehen in die Regionen ein (`SnapToRegion`). Automatisches Kacheln gibt
  es bewusst nicht. Farben der Rahmen und Menüs kommen aus `~/.config/labwc/themerc-override` (`zenos-thema`).
- **kanshi** wählt beim An- und Abstecken ein Bildschirm-Profil und ruft `zenos-labwc --profil-hex …` auf.
  Profilnamen stehen nie in der kanshi-Befehlszeile, weil kanshi sie an `/bin/sh -c` gibt.

### Oberfläche (Quickshell)

- **Quickshell v0.3.1** fehlt in Ubuntu 26.04 und wird aus dem Quellcode gebaut: fester Commit `1a4716c…`, Ziel
  `/usr/local`, Stempel `/usr/local/share/zenos/quickshell.version` (Commit, Version, Qt-Version). Quickshell nutzt
  private Qt-Schnittstellen; weicht die Qt-Version ab, baut `install.sh` neu. Die Build-Abhängigkeiten bleiben
  dafür installiert.
- **`shell/shell.qml`** lädt jede Oberfläche einzeln über `LazyLoader { source }`, die Sperre zuerst und synchron.
  Ein Fehler in einer Oberfläche reisst die anderen nicht mit. Grenze: Qt lädt beim Import eines Moduls alle
  Singletons. Ein Syntaxfehler unter `shell/dienste/` oder in `Theme.qml` legt die ganze Oberfläche lahm, auch die
  Sperre. Deshalb prüft `scripts/pruefen.sh` jeden Einstieg mit einem Start-Test.
- **Theme** (`qs.theme`): liest `shell/theme/tokens.json` und ist die einzige Stelle mit Farbwerten
  (`docs/design.md`).
- **Komponenten** (`qs.komponenten`): gemeinsame Bausteine wie `Symbol`, `Chip`, `Knopf`, `Eingabe`, `Toast`.
- **Oberflächen:** `leiste/`, `heute/`, `befehlsfeld/`, `mitteilungen/`, `appleiste/` (App-Leiste am rechten
  Rand, Fenster über `ToplevelManager` aus Quickshell.Wayland, wlr-foreign-toplevel), `uebersicht/`
  (Fensterübersicht auf Super+Tab, Karten ohne Vorschaubilder, dieselbe Fensterliste), `sperre/`, `freigabe/`, `modi/`
  (Modus- und Zustand-Wahl), `einstellungen/`, `einrichtung/`, `polkit/` (Passwortdialog als polkit-Agent),
  `installer/` (zen Installer: Fenster für eine heruntergeladene .deb), dazu `komponenten/Hinweise.qml` (Toast) und
  `greeter.qml` mit `greeter/` für den Login.
- **Apps aus der Oberfläche** starten über `zenos-oeffnen` in eigenen Einheiten
  (`app-zenos-<name>-<zeit>.scope` in `app.slice`). Ein Neustart von `zenos-shell.service` beendet sie nicht.
- **WLAN** (`leiste/WlanQuelle.qml`, kein Dienst unter `dienste/`): spricht NetworkManager über
  `Quickshell.Networking` (D-Bus) und entsteht erst, wenn NetworkManager läuft (siehe «Netz» unten).
- **Ordner und Ablage:** Ordner öffnet Thunar, der Dateimanager von Ubuntu (Standard für `inode/directory` in
  `/etc/xdg/labwc-mimeapps.list`, nur in der zenOS-Sitzung). Der Knopf rechts neben dem Raster und die Aktion
  «Ablage» öffnen `~/Ablage`, den einen Ordner für eigene Dateien (`docs/module/ablage.md`).

**Dienste** (`qs.dienste`, Singletons ohne Oberfläche):

| Dienst | Aufgabe |
|---|---|
| `Pfade` | Orte: `~/.config/zenos`, `~/.local/state/zenos`, `~/Ablage`, `$XDG_RUNTIME_DIR/zenos`, `/opt/zenos`, `scripts/bin` |
| `Einstellungen` | `einstellungen.json` lesen und schreiben (behält fremde Schlüssel, sichert eine ungültige Datei) |
| `Erscheinung` | hell, dunkel oder nach Tageszeit, Akzent; überträgt beides mit `zenos-thema` nach aussen |
| `Oberflaeche` | Zustand der Oberfläche (was offen ist, `gesperrt`, `uebersichtOffen`: eine Fläche zur Zeit, nie während Sperre und Einrichtung), Hinweise, Sperr-Anforderung |
| `Schreibtisch` | Super+H: sichtbare App-Fenster über `ToplevelManager` minimieren, sich merken und genau diese zurückholen; `frei` nur aus der Lage der Fenster, der Merker übersteht ein Neuladen (`PersistentProperties`; Logik in `uebersicht/schreibtisch.mjs`) |
| `Gesten` | liest «oben» und «unten» vom Socket des Systemdienstes `zenos-gesten` (verbindet erst, wenn `/run/zenos-gesten/bereit` da ist, danach mit wachsender Pause neu), öffnet bzw. schliesst die Fensterübersicht; keine Rechte am Touchpad |
| `Aktionen` | Prozessstarts mit Argumentlisten: Apps, Terminal, Dateien, Ablage, Werkzeuge, Abmelden, Neustart, Ausschalten |
| `System` | Temperatur, Netz, Ton (PipeWire), 1Password |
| `Geraet` | Akku und Lüfter aus `/run/zenos/geraet.json` (`zenos-argon`) samt Lüfterwunsch, Mitteilung bei niedrigem Akku |
| `Luefter` | Lüfter einstellen («auto» oder Mindeststufe 1–4) über `pkexec zenos-luefter`, Bestätigung über `Geraet` |
| `Kanal` | Update-Kanal: Lage aus `/var/lib/zenos/kanal/stand.json` und `letzte.json`, Zeitpunkt aus `/etc/xdg/zenos/kanal-zeitpunkt`, «Update läuft» aus `/run/zenos-kanal/uebernahme` und `/run/zenos-basis/uebernahme`; prüfen, jetzt installieren, zustimmen und Zeitpunkt über `pkexec zenos-kanal-bedienen`; Mitteilungen je einmal (Logik in `kanal.js`) |
| `Basis` | Basis-Updates: Lage aus `/var/lib/zenos/basis/stand.json`, `letzte.json` und `automatik.json`, Notschalter `/etc/xdg/zenos/kanal-automatik-aus`, «Neustart nötig» aus `/run/reboot-required(.pkgs)` (Hinweis in Leiste und System-Menü, Leitplanke in `basis.js`); prüfen, jetzt installieren und mit Passwort installieren über `pkexec zenos-kanal-bedienen basis-…`; Mitteilungen je einmal (Logik in `basis.js`) |
| `Mitteilungen` | Mitteilungsdienst (`NotificationServer`), Bündelung, Zentrale |
| `Konfig` | Modi, Zustände, Raster, Bildschirme, Web-Apps lesen; schreiben über `zenos-konfig` |
| `Modi` | aktiver Modus, Wechsel (Akzent, Raster, Apps, Chrome-Profil) |
| `Zustaende` | aktiver Zustand, Auslöser, Timer, Rückkehr, wirksamer Zustand |
| `Freigabe` | Bildschirmfreigabe (Marker und IPC) |
| `Leitplanken` | feste Regeln, siehe unten |
| `Raster` | aktives Raster, Bildschirm-Profile, Aufruf von `zenos-labwc` (auch nach geändertem Scroll-Tempo) und `zenos-kanshi` |
| `Firewall` | Zustand der Firewall lesen (`/etc/ufw/ufw.conf`, `/var/lib/zenos/firewall`), ein- und ausschalten über `pkexec zenos-firewall` |
| `InstallerListe` | was über den zen Installer kam (`zenos-installer liste --json` ohne Rechte, neu bei Änderungen an `/var/lib/zenos/installer/installiert.json`), «Entfernen …» in Einstellungen › Apps über `pkexec zenos-installer-bedienen entfernen PAKET` (jedes Mal mit Passwort), Rückmeldung als Hinweis (Logik in `installer/installer.js`) |

Dienste importieren nie `qs.theme`. Im Greeter (Benutzer `_greetd`, ohne `~/.config/zenos`) schreiben und starten
sie nichts.

### IPC

Alle Aufrufe in die laufende Oberfläche gehen über `scripts/bin/zenos-ipc <ziel> <funktion> [argumente…]`. Das
kapselt `quickshell ipc call` und findet die Oberfläche auch ohne Sitzungsvariablen, etwa aus einer SSH-Sitzung.
Exit 0 ok (Rückgabewert auf stdout), 1 abgelehnt, 2 keine Oberfläche, 64 falscher Aufruf. `quickshell ipc call`
selbst endet in v0.3.1 auch bei Fehlern mit 0; `zenos-ipc` wertet die Ausgabe aus.

| Ziel | Funktionen |
|---|---|
| `befehlsfeld` | `umschalten`, `oeffnen`, `schliessen`, `werkzeuge`, `apps` (App-Übersicht), `status` (`offen`/`zu`), `ansicht` (`apps`/`suche`) |
| `sperre` | `sperren`, `status` (`gesperrt`/`offen`), `bildschirm(aus\|an)` (Meldung von `zenos-bildschirm`; ungesperrt bleibt es hell), `taste` (Ein/Aus-Taste, gesperrt: Bildschirm an oder aus) |
| `energie` | `aus` (sperren und Bildschirm aus), `status` (Zeitleiste), `vorwarnung` (Probe der Vorwarnung, schaltet nie aus, nur gesperrt) |
| `kanal` | `status` (Zustand der letzten Prüfung oder `ungeprueft`), `zeitpunkt` (`sperre`, `jederzeit`, `hand` oder `fenster 02:00-05:00`), `laeuft` (`ja`, solange install.sh aus dem Kanal oder ein Basis-Update läuft), `uebernahme(beginn\|ende)` (von zenos-kanal und zenos-basis) |
| `basis` | `status` (Ergebnis der letzten Prüfung der Ubuntu-Basis: `aktuell`, `bereit`, `zustimmung`, `gesperrt`, `fehler` oder `ungeprueft`), `neustart` (`ja`, solange `/run/reboot-required` besteht), `hinweis` (`ja`, wenn Leiste und System-Menü «Neustart nötig» zeigen), `pruefen` (wie «Jetzt prüfen»: pkexec, `apt-get update` über die Unit; `gestartet` oder `nicht jetzt`) |
| `thema` | `wechseln`, `setzen(hell\|dunkel\|tageszeit)`, `status` |
| `modus` | `waehlen`, `wechseln(id)`, `aktiv` |
| `zustand` | `waehlen`, `starten(id)`, `beenden`, `aktiv` |
| `freigabe` | `gewaehlt(ausgang)`, `gestartet`, `beendet`, `status` |
| `mitteilungen` | `zentrale`, `oeffnen`, `schliessen`, `zustellen`, `verwerfen(nummer)`, `alleVerwerfen`, `aktion(nummer, kennung)`, `status` |
| `einstellungen` | `oeffnen(seite)`, `schliessen` |
| `raster` | `setzen(id)`, `aktiv` |
| `hinweis` | `zeigen(text)`, `warnen(text)` |
| `einrichtung` | `oeffnen`, `apps`, `schliessen`, `status` |
| `leiste` | `menue(system\|raster\|wlan\|luefter)` (`wlan`: System-Menü mit aufgeklappter WLAN-Liste, `luefter`: mit Wahl des Lüfters), `schliessen`, `status` (`system`/`raster`/`zu`) |
| `polkit` | `status` (`offen`/`zu`), `agent` (`angemeldet`/`nicht angemeldet`), `abbrechen` |
| `appleiste` | `zeigen` (auf dem Bildschirm des aktiven Fensters, nur wenn sie erscheinen darf), `verbergen`, `status` (`offen`/`zu`), `apps` (eine Zeile pro App: appId, Anzahl Fenster, `aktiv`) |
| `uebersicht` | `umschalten`, `oeffnen`, `schliessen` (Fensterübersicht; öffnet nie während Sperre, Einrichtung und polkit-Dialog), `status` (`offen`/`zu`, `zu` erst nach dem Ausblenden), `fenster` (eine Zeile je Kachel: Index, appId, «Titel» bzw. bei Freigabe «Titel verborgen», dazu `aktiv`, `minimiert`, `vollbild`, `gewaehlt`) |
| `schreibtisch` | `umschalten` (Schreibtisch zeigen bzw. die gemerkten Fenster zurück; nicht während Sperre und Einrichtung), `status` (`frei`/`normal`) |
| `gesten` | `status` (`verbunden`/`getrennt`: liest die Oberfläche den Dienst `zenos-gesten`?) |
| `installer` | `oeffnen(pfad)` (zen Installer für eine .deb, vom Starter `zenos-installer.desktop` über `zenos-installer oeffnen`: `offen`, `laeuft` (eine Installation läuft, das Fenster zeigt sie), `gesperrt`, `einrichtung` oder `ungueltig`), `status` (`zu`, `ansehen`, `bereit`, `installiert`, `abgelehnt`, `fehler`, `laeuft`, `fertig`, `gescheitert`), `schliessen`, `liste` (was Einstellungen › Apps unter «Über den zen Installer» zeigt: Paketnamen mit Leerzeichen oder `keine`; liest neu ein, das Ergebnis zählt erst für den nächsten Aufruf). Installieren nur über den Knopf im Fenster, Entfernen nur über den Knopf in den Einstellungen |

Die Tastenkürzel von labwc rufen dieselben Ziele auf (Liste in `docs/module/m9.md`).

### Hilfsprogramme (`scripts/bin/`)

| Programm | Aufgabe |
|---|---|
| `zenos-sitzung`, `zenos-greeter`, `zenos-abmelden` | Sitzung starten, Login, sauber abmelden |
| `zenos-ipc` | Aufruf in die Oberfläche |
| `zenos-konfig` | persönliche Konfiguration lesen, gegen das Schema prüfen, atomar schreiben |
| `zenos-thema` | Erscheinungsbild auf GTK, Qt, kitty, labwc und VS Code übertragen |
| `zenos-labwc`, `zenos-kanshi` | `rc.xml` und kanshi-Konfiguration erzeugen |
| `zenos-freigabe` | Bildschirmfreigabe erkennen (vom Portal aufgerufen) |
| `zenos-idle`, `zenos-1password-sperren` | automatische Sperre, Bildschirm aus nach der Sperre (swayidle), Hemmer für die Ein/Aus-Taste, 1Password mitsperren |
| `zenos-bildschirm`, `zenos-energie` | Bildschirm aus/an (wlopm, sperrt immer zuerst); Ausschalten nach langer Sperre mit Wächtern (SSH, tmux, Updates, Hemmer) und Ein/Aus-Taste |
| `zenos-oeffnen` | Datei, Ordner oder Programm in eigener Einheit öffnen (Ordner in Thunar, ohne Dateimanager in kitty) |
| `zenos-bildschirmfoto`, `zenos-pipette` | Werkzeuge des Befehlsfelds |
| `zenos-chrome`, `zenos-webapp` | Chrome im Profil des Modus, Web-Apps |
| `zenos-apps` | proprietäre Apps installieren (`zen apps`) |
| `zenos-argon` | Argon ONE: Lüfter und Power-Button (V3), Akku-Messchip, Deckel und kontrolliertes Ausschalten bei 3 % (ONE UP), Mindeststufe für den Lüfter, Werte für die Leiste |
| `zenos-gesten` | Wischen mit drei Fingern: Systemdienst `zenos-gesten.service` (eigener Benutzer, liest reine Touchpads nur lesend über libinput, meldet «oben» und «unten» auf `/run/zenos-gesten/gesten.sock`); dazu `--messen` (Schwelle einmessen) und `--pruefen` (für `zen doctor`) |
| `zenos-luefter` | Lüfterwunsch schreiben («auto» oder Mindeststufe 1–4; root: über pkexec oder sudo, `zen luefter`) |
| `zenos-kanal-bedienen` | Updates aus den Einstellungen (root über pkexec): prüfen, jetzt installieren und zustimmen starten Units des Kanals, Zeitpunkt setzen über `zenos-kanal zeitpunkt`; für die Ubuntu-Basis `basis-pruefen` (Unit), `basis-installieren HASH` und `basis-installieren-zustimmen HASH` (über `zenos-basis jetzt` bzw. `zustimmen`) |
| `zenos-basis` | Paket-Updates der Ubuntu-Basis (root, ausgeführt wird die Kopie unter `/usr/local/libexec/zenos`): `pruefen` (ein unterbrochenes dpkg nachholen, apt-get update, Auswertung von `apt-get -s full-upgrade`), `installieren` (genau die geprüfte Liste, mit Inhibitor, danach `install.sh` und Gesundheitsprüfung), `update [--ja]` (Schritt 2 von `zen update`), `jetzt` und `zustimmen` (Einstellungen), `automatik lauf\|gelegenheit` (Timer), `status` (ohne root) |
| `zenos-netzwerk` | Netz von netplan/systemd-networkd auf NetworkManager umstellen und zurück (`zen netzwerk`) |
| `zenos-firewall` | Firewall ein- und ausschalten (root: über pkexec, sudo oder `install.sh`), bewussten Zustand merken |
| `zenos-sicherheitsquelle` | prüft mit unattended-upgrades selbst, ob die Ubuntu-Sicherheitsquelle erlaubt ist (nur lesend, für `zen doctor` und die Vorab-Prüfung von `72-kennung`) |
| `zenos-kennung` | Systemkennung zenOS: os-release, Konsole, `/etc/legal` und Begrüssung per dpkg-divert und dpkg-statoverride einrichten, nachziehen (apt-Hook), prüfen und zurück zu Ubuntu (root; ausgeführt wird die Kopie unter `/usr/local/sbin`) |
| `zenos-installer` | zen Installer für .deb: `ansehen` (ohne Rechte: Metadaten, Inhalt, Symbol, Simulation mit `apt-get -s install`, Hinweise, Ablehnungen, Plan), `oeffnen` (Starter für .deb, gibt den geprüften Pfad an die Oberfläche), `liste`, `status`; als root (ausgeführt wird die Kopie unter `/usr/local/libexec/zenos`) `auftrag-installieren`, `auftrag-entfernen` und in den Units `installieren SHA256`, `entfernen PAKET` (`docs/module/installer.md`) |
| `zenos-installer-bedienen` | zen Installer mit Rechten (root über pkexec, jedes Mal mit Passwort, oder sudo aus `zen install`): `installieren PFAD SHA256 PLAN` (genau die angezeigte Datei und der angezeigte Plan), `entfernen PAKET` (nur aus der Liste des Installers); startet die Units, arbeitet nicht selbst |

### Portale und Bildschirmfreigabe

- `xdg-desktop-portal` mit `/etc/xdg/xdg-desktop-portal/labwc-portals.conf`: `default=gtk` (liefert `color-scheme`
  an Chrome, Qt und Electron), ScreenCast und Screenshot über `wlr`.
- `xdg-desktop-portal-wlr` mit `/etc/xdg/xdg-desktop-portal-wlr/config`: Die Bildschirmwahl
  (`zenos-freigabe waehlen`, mit slurp) meldet die Freigabe per IPC, bevor das Portal den Stream anlegt, damit schon
  das erste Bild keine Inhalte zeigt. `exec_before`/`exec_after` rufen `zenos-freigabe start|ende` (Marker
  `$XDG_RUNTIME_DIR/zenos/freigabe`, IPC).
- **Nachlauf:** Chrome schliesst beim Klick auf «Teilen» die Freigabe seiner Vorschau und öffnet sofort eine zweite,
  ohne Bildschirmwahl. Das Portal ruft dazwischen `ende` und `start` auf, ohne auf sie zu warten. `zenos-freigabe
  ende` löscht den Marker deshalb erst nach 3 s und nur für Freigaben, die vor ihm begannen. Was vorher kam,
  entscheidet der Aufrufzeitpunkt (Startzeit des Prozesses, den das Portal gestartet hat), nicht die Reihenfolge, in
  der die Aufrufe die Sperrdatei bekommen. Die Oberfläche (`Freigabe`) hält «aktiv» danach noch 2 s. So ist die Leitplanke zwischen zwei
  Freigaben nie aus, und «Sitzung» endet rund 5 s nach dem Ende der Freigabe; erst dann kommt Zurückgehaltenes.
- Endet das Portal ohne `exec_after` (Absturz, `kill`), setzt das Drop-in
  `xdg-desktop-portal-wlr.service.d/zenos.conf` die Freigabe zurück: nach jedem Ende (`ExecStopPost`) und vor jedem
  Start (`ExecStartPre`), denn nach `systemctl --user kill` beendet systemd 259 auch `ExecStopPost` sofort.
- Qt-Apps folgen dem Erscheinungsbild über `QT_QPA_PLATFORMTHEME=xdgdesktopportal`. Die Oberfläche selbst nutzt
  weder Plattform-Theme noch Portal-Dienste von Qt (Pragmas in `shell.qml`); ihr Start hängt nicht am Portal.

### Sperre

- `ext-session-lock` (`WlSessionLock`) mit PAM (`PamContext`, Dienst `zenos-sperre` aus `/opt/zenos/system/pam`,
  Rückfall `/etc/pam.d/login`). zenOS reicht das Passwort nur an PAM weiter und leert das Feld sofort.
- Auslöser: Super+L und `zen lock`, swayidle bei Inaktivität (1–15 Minuten), vor dem Standby und bei
  `loginctl lock-session`. Dazu Super+Shift+L, «Bildschirm aus» und die Ein/Aus-Taste (sperren und Bildschirm aus),
  das Zuklappen (Argon ONE UP) und nach höchstens 60 Minuten ohne Eingabe auch gegen einen Idle-Hemmer (Video,
  `shell/dienste/Energie.qml`).
- **Bildschirm aus** nur gesperrt, 1–10 Minuten nach der Sperre: `zenos-bildschirm` (wlopm) sperrt immer zuerst.
  Die Sperre zählt ab der Sperre und verwirft die Taste, die weckt; swayidle ist die Rückfallebene ohne Oberfläche.
  Auf Wunsch schaltet `Energie` nach 30–240 Minuten gesperrt aus, mit 60 s Vorwarnung und den Wächtern von
  `zenos-energie` (SSH, tmux, Updates, Hemmer). Einzelheiten in `docs/module/energie.md`.
- Marker `$XDG_RUNTIME_DIR/zenos/gesperrt`: Stürzt die Oberfläche ab, hält labwc den Bildschirm gesperrt, systemd
  startet Quickshell neu, und der Marker sperrt sofort wieder.
- `zen lock` (auch per SSH): IPC, sonst Neustart von `zenos-shell.service`, sonst **Notfall-Sperre** mit swaylock
  als eigene Einheit (Farben aus den Tokens, keine Inhalte). So fällt die Sperre nie aus.
- 1Password sperrt sich mit (`zenos-1password-sperren`), sobald es installiert ist.

### Rechte (polkit und pkexec)

- Die Oberfläche ist der polkit-Agent der Sitzung (`shell/polkit/Polkit.qml`, `PolkitAgent` aus
  `Quickshell.Services.Polkit`). Quickshell läuft in `user@.service`, nicht im Bereich der Sitzung; polkit ordnet
  den Agenten und die Programme der Oberfläche deshalb über die «Display»-Sitzung des Benutzers zu (die Sitzung von
  greetd, Typ wayland, Sitz `seat0`, lokal und aktiv).
- Der Dialog zeigt Nachricht und Kennung der Aktion und das Konto, reicht das Passwort nur an polkit weiter
  (`AuthFlow.submit`) und leert das Feld sofort. polkit prüft es über PAM in `polkit-agent-helper-1`. Während der
  Sperre gibt es keine Dialoge (Begründung in `docs/sicherheit.md`).
- Programme mit Rootrechten aus der Oberfläche: nur über `pkexec` mit einer eigenen polkit-Aktion, deren
  `exec.path` genau ein Programm unter `/opt/zenos` nennt und `exec.argv1` das erste Argument. Ausserhalb der aktiven
  Sitzung am Gerät erlaubt polkit keine davon. Heute vier Dateien in `system/polkit/`:
  - `org.zenos.firewall.policy`: `zenos-firewall ein` ohne Passwort, `aus` nur mit Passwort, jedes Mal.
  - `org.zenos.luefter.policy`: `zenos-luefter` ohne Passwort (eine Aktion für den Helfer).
  - `org.zenos.kanal.policy`: `zenos-kanal-bedienen` für Einstellungen › System › Updates. Ohne Passwort `pruefen`,
    `installieren`, `zeitpunkt`, `basis-pruefen` und `basis-installieren`; nur mit Passwort, jedes Mal, `zustimmen`
    (Kanal: Firewall, Netz oder Boot) und `basis-installieren-zustimmen` (Basis: Kernel, Firmware, Bootloader oder
    Entfernungen). Einzelheiten in `docs/sicherheit.md`.
  - `org.zenos.installer.policy`: `zenos-installer-bedienen` für den zen Installer. `installieren` (Fenster «zen
    Installer») und `entfernen` (Einstellungen › Apps) nur mit Passwort, jedes Mal (`docs/sicherheit.md`, «zen
    Installer»).

### Leitplanken im Code

Die Regeln aus dem Manifest stehen im Code, nicht in der Konfiguration, und lassen sich nicht abschalten:

- `Leitplanken` (`shell/dienste/Leitplanken.qml`, Werte aus `shell/modi/zustandslogik.js`): Mitteilungsinhalte bei
  Freigabe verborgen, Sperre ohne Inhalte, Sperre nicht abschaltbar, Sperrzeit 1–15 Minuten, höchstens 60 Minuten
  Aufschub durch einen Idle-Hemmer, Bildschirm aus nur gesperrt (1–10 Minuten danach), Ausschalten frühestens
  30 Minuten gesperrt mit 60 s Vorwarnung, kontrolliertes Ausschalten bei 3 % Akku. `anwenden(zustand)` setzt diese
  Regeln zuletzt in jedem wirksamen Zustand durch; die Energie-Schlüssel kann kein Zustand setzen.
- Bei Freigabe erzeugen Karten und Zentrale die Inhalte gar nicht erst; «Heute» blendet Name und Zusammenfassung
  aus, das Befehlsfeld zeigt keine Dateinamen.
- Der Sperrbildschirm zeigt nur die Anzahl der Mitteilungen. `zenos-idle` begrenzt die Sperrzeit selbst auf 1–15
  Minuten und läuft mit `Restart=always`. `zenos-bildschirm` schaltet nur bei bestätigter Sperre ab,
  `zenos-energie` nur nach sichtbarer Vorwarnung und nur mit `--check-inhibitors=yes`.
- Prozesse starten mit Argumentlisten, nie über `sh -c`. `zenos-labwc` lehnt eine Vorlage ab, die eine Shell
  startet. `scripts/pruefen.sh` prüft beides.

### Netz

- **NetworkManager** von Ubuntu verwaltet das Netz, sobald Zeno einmal `zen netzwerk umstellen` und einen Neustart
  gemacht hat (ein neues Image stellt beim ersten Start selbst um). Vorher läuft es wie bei Ubuntu Server über
  netplan mit systemd-networkd, und das System-Menü zeigt nur den Zustand. zenOS hat keinen eigenen
  Netzwerk-Stack; das WLAN-Menü oben rechts ist nur eine Oberfläche für NetworkManager (`MANIFEST.md`).
- Der Umstieg übernimmt jedes WLAN aus netplan als eigenes Profil (`/etc/netplan/90-NM-<uuid>.yaml`), sichert
  die alten Dateien und ist mit `zen netzwerk zurueck` umkehrbar. Nichts wird live angewendet (kein
  `netplan apply`), eine SSH-Verbindung bleibt bis zum Neustart.
- Auf Raspberry Pis schaltet zenOS dabei WPA3 im WLAN-Treiber ab, weil der Chip es nicht zuverlässig kann;
  Mischnetze verbinden über WPA2. Einzelheiten, Rechte (polkit) und Dateien in `docs/module/netzwerk.md`.

### Terminal, Apps und Hardware

- **Terminal:** kitty (`system/kitty/kitty.conf`) mit fish (`system/fish/`). Farben schreibt `zenos-thema`.
- **Apps:** `zen apps installieren` holt Chrome, VS Code, 1Password mit CLI und coremail aus den Quellen der
  Hersteller, nur nach ausdrücklicher Zustimmung und nie im Image. Nubix folgt, sobald es einen arm64-Build gibt.
- **zen Installer** (heruntergeladene .deb): Der Starter `zenos-installer.desktop` ist in der zenOS-Sitzung Standard
  für .deb; ein Doppelklick ruft `zenos-installer oeffnen PFAD`, das den Pfad prüft und als Argument per IPC
  `installer oeffnen` an die Oberfläche gibt. Das Fenster (`shell/installer/`) sieht das Paket ohne Rechte an
  (`zenos-installer ansehen --json`: nichts wird entpackt oder ausgeführt, apt nur simuliert) und installiert erst
  nach «Installieren» und dem Passwort: `pkexec zenos-installer-bedienen installieren PFAD SHA256 PLAN` kopiert genau
  diese Datei in eine root-eigene Ablage und startet `zenos-installer-installieren@SHA256.service`, die unter der
  gemeinsamen Sperre mit Kanal und Basis noch einmal auswertet und nur bei gleichem Plan `apt-get install` ausführt.
  Was so kam, steht in `/var/lib/zenos/installer/installiert.json`; Einstellungen › Apps entfernt es wieder
  (`zenos-installer-entfernen@PAKET.service`, mit Passwort). Updates solcher Software kommen mit den Basis-Updates,
  wenn das Paket eine eigene Paketquelle einrichtet, sonst nur über eine neuere .deb («Aktualisieren»). Einzelheiten
  in `docs/module/installer.md`.
- **Argon ONE:** `zenos-argon.service` (Systemdienst, gehärtet) erkennt das Gerät am Gerätebaum. Am Raspberry Pi 5
  mit Argon ONE V3 regelt er den Lüfter über I2C und wertet den Power-Button aus; ein systemd-shutdown-Hook sendet
  beim Ausschalten das Abschaltsignal an die Platine. Am Compute Module 5 im Argon ONE UP liest er den
  Akku-Messchip CW2217 (lädt bei Bedarf Argons Akkuprofil hinein, erst nach `zen akku freigeben`, siehe
  `docs/sicherheit.md`) und zeigt Lüfter
  und Temperatur des Kernels an; er liest den Deckel (GPIO27, nur lesend) und schaltet bei 3 % Akku nach 60 s
  Vorwarnung kontrolliert aus. Beide schreiben `/run/zenos/geraet.json`; die Oberfläche (`Geraet`) zeigt Akku
  und Lüfter in Leiste und System-Menü, meldet niedrigen Akku und sperrt beim Zuklappen (`Energie`). Den Lüfter
  stellt Zeno im System-Menü oder mit `zen luefter` auf «auto» oder eine Mindeststufe 1–4: Der Helfer
  `zenos-luefter` (pkexec bzw. sudo) schreibt nur den Wunsch, `zenos-argon` setzt ihn um (beim ONE UP über den
  Regler `user_space` der Thermal-Zone, nie weniger als automatisch). Einzelheiten in `docs/module/m13.md`.
- **Touchpad-Gesten:** labwc 0.9.3 bindet keine Gesten an Aktionen und reicht sie nur an die Fläche unter dem
  Zeiger weiter. Für das Wischen mit drei Fingern (Fensterübersicht auf und zu) liest deshalb der Systemdienst
  `zenos-gesten.service` die Touchpads mit: als eigener Benutzer `zenos-gesten`, nur lesend und ohne sie zu greifen,
  über libinput aus Ubuntu (udev-Backend für seat0, ein neu erscheinendes Touchpad nimmt er von selbst auf). Eine
  udev-Regel gibt nur die Knoten reiner Touchpads (ohne Tasten) seiner Gruppe zum Lesen und startet ihn; ohne
  Touchpad läuft er nie. labwc öffnet die Geräte weiter über logind und bekommt jede Bewegung unverändert. Die
  Oberfläche (`Gesten`) liest nur die Wörter «oben» und «unten» von seinem Socket. Rechte, Härtung, Restrisiko und
  Rückweg in `docs/sicherheit.md`, «Gesten».

## Entscheidung: Logik für Modi und Zustände (C5)

Die Logik läuft in Quickshell selbst, ohne eigenen Hintergrunddienst.

- Zustände, Auslöser (manuell, Uhrzeit, Moduswechsel, Bildschirmfreigabe), Timer und die Rückkehr nach einer
  Sitzung stehen in den Diensten `Modi` und `Zustaende` und in `shell/modi/zustandslogik.js` (reines JavaScript,
  Einheitentests unter `test/einheiten/`). Die Bündelung der Mitteilungen macht der Dienst `Mitteilungen`, denn
  Quickshell ist zugleich der Mitteilungsdienst.
- Was ausserhalb der Oberfläche geschehen muss, erledigen kleine Programme: das Portal ruft `zenos-freigabe`,
  kanshi ruft `zenos-labwc`, swayidle ruft `zen lock`. Geschrieben wird nur über `zenos-konfig`.
- Gründe: ein Dienst weniger, Logik und Anzeige an einer Stelle, live nachladbar und ohne Oberfläche testbar.
- Was einen Neustart der Oberfläche überdauern muss, steht in `~/.local/state/zenos/laufzeit.json` (Modus, Zustand
  mit Ende und vorherigem Zustand, Raster, Profil) und im Marker `freigabe`. Die Oberfläche stellt es beim Start
  wieder her; ein inzwischen abgelaufener Timer endet dann.
- Grenzen: Ein Uhrzeit-Auslöser wirkt nur, wenn die Oberfläche in dieser Minute läuft, er wird nicht nachgeholt.
  Wartende Mitteilungen überstehen ein Neuladen der Oberfläche, aber keinen Neustart von Quickshell. Ihre Inhalte
  kommen bewusst nie auf die Platte.

## Datenorte

| Was | Wo | Im Repo? |
|---|---|---|
| zenOS-Code | `/opt/zenos` (Git-Checkout, gehört root) | ja |
| Oberfläche live | `~/.config/quickshell` verweist auf `/opt/zenos/shell` | ja |
| Verweise ins Repo | `~/.config/labwc/{autostart,environment,shutdown,menu.xml}`, `~/.config/kitty/kitty.conf`, `~/.config/fish/conf.d/zenos.fish` | ja |
| Erzeugte Konfiguration | `~/.config/labwc/rc.xml` und `themerc-override`, `~/.config/kanshi/config`, `~/.config/kitty/*-theme.auto.conf` | nein, erzeugt |
| `zen` | `/usr/local/bin/zen` verweist auf `/opt/zenos/scripts/zen` | ja |
| Kanal für `zen update` | `/etc/xdg/zenos/kanal` (`stabil`, `vorschau` oder `dev`; ein alter Wert `main` gilt als `stabil`). Der Installer legt ihn beim ersten Mal an (`main` → `stabil`, sonst `dev`; im Image der Kanal des Tags), wechseln: `sudo zen kanal wechseln` | nein, vom Installer |
| Zeitpunkt automatischer Updates | `/etc/xdg/zenos/kanal-zeitpunkt` (`zeitpunkt=sperre\|fenster\|jederzeit\|hand`, bei `fenster` `von=` und `bis=` als HH:MM, `seit=…`; root, 0644; fehlt = `sperre`), gilt für den Kanal und die Basis-Updates. Setzen: Einstellungen › System › Updates oder `sudo zen kanal zeitpunkt` | nie |
| Notschalter der Automatik | `/etc/xdg/zenos/kanal-automatik-aus` (root, 0644): Timer des Kanals und der Basis-Updates aus, `install.sh` lässt sie aus. Setzen und entfernen: `sudo zen kanal automatik aus\|an` | nie |
| Vertrauensanker | `/etc/zenos/vertrauen/{release,wurzel,widerrufen,serie}` (root, 0644). Mit Schlüsseln gefüllt nur im Image (aus `system/vertrauen/`) oder von Hand (`sudo zen kanal anker ORDNER`, Fingerabdrücke aus einer vertrauenswürdigen Quelle eintippen), danach nur über `vertrauen/NNNN` | im Image ja (`system/vertrauen/`), sonst nein |
| Signierter Kanal | Programm `/usr/local/libexec/zenos/zenos-kanal` (Kopie, root, 0755; die vorige Fassung als `zenos-kanal.vorher`), Units `zenos-kanal-holen`, `-pruefen`, `-installieren`, `-jetzt@`, `-zustimmen@`, `-automatik`, `-gelegenheit` und `-bestaetigen` (statisch) und `-nachstart` (aktiviert, vor greetd), Timer `zenos-kanal.timer` und `zenos-kanal-gelegenheit.timer` (aktiviert, ausser mit Notschalter) und `zenos-kanal-bestaetigen.timer` (aktiviert); Zustand `/var/lib/zenos/kanal/` (`stand.json`, `gesehen.json`, `hoechste`, `gesperrt/`, `wunsch.json`, `auftrag.json`, `laeuft.json`, `gut.json`, `unbestaetigt.json`, `zurueckgestellt.json`, `automatik-bereit`, `automatik.json`, `letzte.json`, `angehalten`, `bereit/<commit>`); Spiegel und Bundle des Holers `/var/lib/zenos-kanal-holen/`; Sperren und Vermerk eines `install.sh` von Hand `/run/zenos-sperre/` (nur root, 0700) | Programm und Units ja (Kopien), Zustand nie |
| Lüfterkurve (optional) | `/etc/xdg/zenos/argon.json` | nie |
| Freigabe Akkuprofil (ONE UP) | `/etc/xdg/zenos/argon-akkuprofil` (`zen akku freigeben`) | nie |
| Gerätewerte (Akku, Lüfter) | `/run/zenos/geraet.json` (flüchtig, Ordner gehört `zenos-argon`) | nie |
| Gesten | Socket `/run/zenos-gesten/gesten.sock` und Merker `bereit` (flüchtig, Ordner gehört `zenos-gesten`); Einheit `/etc/systemd/system/zenos-gesten.service`, udev-Regel `/etc/udev/rules.d/72-zenos-gesten.rules`, Benutzer `/etc/sysusers.d/zenos-gesten.conf`; Notschalter `/etc/xdg/zenos/gesten-aus` (root, `install.sh` nimmt dann alles zurück) | Einheit, Regel und Benutzer ja (Kopien), sonst nie |
| Lüfterwunsch | `/var/lib/zenos/luefter` (`modus=auto\|mindest`, `stufe=1…4`, `seit=…`; root, 0644; fehlt = auto) | nie |
| Firewall, bewusster Zustand | `/var/lib/zenos/firewall` (`zustand=an\|aus`, `seit=…`; root, 0644; fehlt = Standard an) | nie |
| polkit-Aktionen | `/usr/share/polkit-1/actions/org.zenos.firewall.policy`, `org.zenos.luefter.policy`, `org.zenos.kanal.policy`, `org.zenos.installer.policy` | ja (Kopie von `system/polkit/`) |
| Quickshell | `/usr/local/bin/quickshell`, Stempel `/usr/local/share/zenos/quickshell.version` | nein, Quellbau |
| Systemkennung | `/usr/lib/os-release`, `/etc/issue`, `/etc/legal` (umgelenkt, Ubuntu-Fassung jeweils als `<datei>.ubuntu`), `/etc/update-motd.d/00-zenos`, statoverrides für Ubuntus motd-Skripte, Verweise `zenos.info`/`zenos.mirrors`/`zenos.csv`, Version `/usr/local/share/zenos/version`, Merker `/var/lib/zenos/kennung` (nur nach `zenos-kennung ubuntu`) | nein, von `zenos-kennung` |
| `zenos-kennung` und Hook | `/usr/local/sbin/zenos-kennung` (Kopie, root, 0755), `/etc/apt/apt.conf.d/60zenos-kennung` | ja (Kopien) |
| Logo `zenos` | `/usr/local/share/icons/hicolor/scalable/apps/zenos.svg` | ja (`assets/zeichen/zenos-app-icon.svg`) |
| Schriften | `/usr/local/share/fonts/zenos/` | ja (`assets/fonts/`) |
| App-Icon `zenos` | `~/.local/share/icons/hicolor/<n>x<n>/apps/zenos.png` | ja (`assets/zeichen/png/`) |
| Bootsplash-Theme | `/usr/share/plymouth/themes/zenos/` (eingeschaltet erst mit `zen bootsplash aktivieren`) | ja (`system/plymouth/zenos/`) |
| Benutzereinheiten | `/etc/systemd/user/` (`zenos-sitzung.target`, `zenos-shell`, `zenos-idle`, `zenos-kanshi`, Drop-in für `xdg-desktop-portal-wlr`) | ja (Kopien) |
| Systemeinheiten | `/etc/systemd/system/zenos-argon.service`, `/usr/lib/systemd/system-shutdown/zenos-argon` | ja (Kopien) |
| Netz-Einheiten | `/etc/systemd/system/zenos-wlan-land.service`, `zenos-netzwerk-erststart.service`, Drop-in `systemd-networkd-wait-online.service.d/zenos-netzwerk.conf` | ja (Kopien) |
| Netz nach dem Umstieg | `/etc/netplan/90-zenos-netzwerk.yaml`, WLAN-Profile `/etc/netplan/90-NM-<uuid>.yaml` (0600 root, Passwörter wie bisher in netplan) | nie |
| Netz: Sicherung, Land, Treiber | `/var/lib/zenos/netplan-vorher/<zeit>/` (0700), `/etc/xdg/zenos/wlan-land`, `/etc/modprobe.d/zenos-brcmfmac.conf`, `/etc/cloud/cloud.cfg.d/99-zenos-netzwerk.cfg` | nie (Vorlagen: `system/modprobe/`, `system/cloud/`) |
| Login, Portale | `/etc/greetd/config.toml`, `/etc/xdg/xdg-desktop-portal/labwc-portals.conf`, `/etc/xdg/xdg-desktop-portal-wlr/config` | ja (Kopien) |
| Standard-Apps, Starter | `/etc/xdg/labwc-mimeapps.list` (Ordner: Thunar, .deb: zen Installer), `/usr/local/share/applications/thunar-{bulk-rename,settings}.desktop` (`Hidden=true`), `/usr/local/share/applications/zenos-installer.desktop` (`NoDisplay`, `MimeType` für .deb) | ja (Kopien) |
| Richtlinien | `/etc/opt/chrome/policies/managed/zenos.json`, `/etc/vscode/policy.json`, `/etc/apt/apt.conf.d/51zenos-ubuntu-quellen`, `52zenos-unattended` | ja (Kopien) |
| Kein Basiswechsel | `/etc/update-manager/release-upgrades.d/zenos.cfg` (`Prompt=never`, `71-basis`); die Ubuntu-Version eines Stands steht in `system/basis` (liest `zenos-kanal` aus dem geprüften Stand) | ja (Kopie von `system/update-manager/zenos.cfg`) |
| Basis-Updates | Programm `/usr/local/libexec/zenos/zenos-basis` (Kopie, root, 0755), Units `zenos-basis-pruefen`, `-installieren`, `-automatik` und `-gelegenheit` (statisch), `zenos-basis-automatik.timer` und `zenos-basis-gelegenheit.timer` (ab Werk an, gemeinsamer Notschalter `/etc/xdg/zenos/kanal-automatik-aus`); Zustand `/var/lib/zenos/basis/` (`stand.json`, `letzte.json`, `auftrag.json`, `install-ergebnis`, `automatik.json`, `automatik-bereit`; root, für alle lesbar); Übernahme-Marker `/run/zenos-basis/uebernahme` (Laufzeitordner der Unit); Log `/var/log/zenos/basis.log` (root, 0640, Paketstand vorher und Änderungen); Sperre gemeinsam mit dem Kanal (`/run/zenos-sperre/kanal.lock`) | Programm und Units ja (Kopien), Zustand nie |
| zen Installer | Programm `/usr/local/libexec/zenos/zenos-installer` (Kopie, root, 0755), Units `zenos-installer-installieren@.service` (Instanz: SHA-256 der Datei) und `zenos-installer-entfernen@.service` (Instanz: Paketname, maskiert; beide statisch); Zustand `/var/lib/zenos/installer/` (`installiert.json`: was über den zen Installer kam, `letzte.json`: letztes Ergebnis; root, 0644, für alle lesbar), darin `ablage/` (root, 0755; die Datei, solange eine Installation läuft, danach leer); was gerade läuft `/run/zenos-installer/laeuft-PID.json`; Log `/var/log/zenos/installer.log` (root, 0640, Gruppe adm); Symbol eines angesehenen Pakets `$XDG_RUNTIME_DIR/zenos-installer/` (0700, flüchtig); Sperre gemeinsam mit Kanal und Basis (`/run/zenos-sperre/kanal.lock`) | Programm, Units und Starter ja (Kopien), Zustand nie |
| Install-Log | `/var/log/zenos/install.log`, Rückfall `~/.local/state/zenos/install.log` | nie |
| Einstellungen | `~/.config/zenos/einstellungen.json` | nie |
| Modi | `~/.config/zenos/modi/*.json` | nie |
| Zustände | `~/.config/zenos/zustaende/*.json` | nie (Vorlagen: `config/vorlagen/`) |
| Raster | `~/.config/zenos/raster/*.json` | nie (Vorlagen: `config/vorlagen/`) |
| Bildschirm-Profile | `~/.config/zenos/bildschirme.json` | nie |
| Web-Apps | `~/.config/zenos/webapps.json`, Starter `~/.local/share/applications/zenos-webapp-<id>.desktop` | nie |
| Laufzeitzustand | `~/.local/state/zenos/laufzeit.json` (`modus`, `zustand`, `raster`, `profil`) | nie |
| Weiterer Zustand | `~/.local/state/zenos/` (`thema.json`: zuletzt übertragener Akzent; Merker für die Vorlagen; `kanal-meldungen.json` und `basis-meldungen.json`: welche Mitteilungen der Updates schon kamen) | nie |
| Nutzungsstatistik | `~/.local/share/zenos/befehlsfeld.json` (nur Desktop-IDs und Zähler) | nie |
| Flüchtige Marker | `$XDG_RUNTIME_DIR/zenos/` (`gesperrt`, `freigabe`, `freigabe.neu`, `freigabe-wahl`, `freigabe-eintraege`, `freigabe-ende`, Sperrdateien) | nie |
| Bildschirmfotos | `~/Ablage/Screenshots/` | nie |
| Ablage | `~/Ablage` (beim Anlegen 0700), dorthin zeigen Schreibtisch, Downloads, Dokumente, Bilder, Musik, Videos | nie |
| Benutzerordner | `~/.config/user-dirs.dirs`, `~/.config/user-dirs.conf` (zenOS schreibt sie nur, solange die erste Zeile die Marke von `48-ablage` trägt) | nein, erzeugt |
| Thunar-Aktionen | `~/.config/Thunar/uca.xml` aus `system/thunar/uca.xml` («Terminal hier öffnen» mit kitty, «Mit zen Installer öffnen» für .deb; nur mit der Marke von `48-ablage` in der ersten Zeile) | nein, erzeugt |
| Geheimnisse | 1Password | nie |

Die Schlüssel der persönlichen Dateien stehen in `docs/konfiguration.md`.

## Installer

`scripts/install.sh [--image] [--nur-benutzer] [--ruhig]` läuft als normaler Benutzer und holt sich Root-Rechte
mit sudo. Die Module unter `scripts/module/` laufen in Namensreihenfolge, in zwei Durchgängen: erst alle
Systemteile, dann alle Benutzerteile.

| Modul | Aufgabe |
|---|---|
| `00-vorbereitung` | System prüfen (Ubuntu 26.04 als Kennung oder als Basis von zenOS, arm64/amd64, Platz), Werkzeuge des Installers |
| `10-code` | `/opt/zenos` auf den Stand der Quelle bringen (atomar), Kanal festlegen |
| `12-vertrauen` | Vertrauensanker `/etc/zenos/vertrauen` anlegen; mit Schlüsseln aus `system/vertrauen/` nur im Image, sonst nur ein Hinweis auf `sudo zen kanal anker`; Besitz und Rechte |
| `14-kanal` | signierter Kanal: `zenos-kanal` als root-eigene Kopie (die vorige als `zenos-kanal.vorher`), die Units und Timer, `/var/lib/zenos/kanal`; aktiviert `zenos-kanal-nachstart.service`, `zenos-kanal-bestaetigen.timer` und die Timer der Automatik (ausser mit Notschalter, dann aus). Installiert selbst nichts |
| `20-pakete` | alle Paketlisten aus `scripts/pakete/` in einem apt-Lauf |
| `22-aufraeumen` | snapd und landscape-common entfernen (nur automatisch installierte, snapd nicht bei eigenen Snaps), snapd per apt-Pin fernhalten |
| `25-quickshell` | Quickshell bauen, nur wenn der Stempel fehlt oder abweicht |
| `30-schriften` | Geist, Geist Mono, Instrument Serif |
| `35-netzwerk` | NetworkManager fürs WLAN-Menü bereitlegen (umgestellt wird mit `zen netzwerk umstellen`), WLAN-Land, wait-online |
| `40-sitzung` | greetd mit Greeter, Benutzereinheiten, Portale |
| `42-bootsplash` | Bootsplash-Theme ablegen, nicht einschalten |
| `45-thema` | Erscheinungsbild auf GTK, Qt, kitty, labwc und VS Code, App-Icon `zenos` |
| `48-ablage` | Thunar als Standard für Ordner (dazu der zen Installer für .deb in derselben `labwc-mimeapps.list`), `~/Ablage`, Benutzerordner (`user-dirs.dirs`), «Terminal hier öffnen» und «Mit zen Installer öffnen» in Thunar |
| `50-raster` | Raster, Tastenkürzel, Bildschirm-Profile |
| `55-zustaende` | Freigabe-Portal, Vorlagen der Zustände |
| `60-terminal` | kitty, fish, tldr-Seiten |
| `65-oberflaeche` | automatische Sperre, Notfall-Sperre, Hilfsprogramme |
| `70-sicherheit` | Sicherheitsupdates, Richtlinien, Ubuntu-Nachrichten aus (motd-news maskiert und stillgelegt), Firewall (standardmässig an) und polkit-Aktionen, gitleaks-Hook |
| `71-basis` | Ubuntu-Basis: Paket-Updates über `zenos-basis` (root-eigene Kopie, Units `zenos-basis-pruefen` und `-installieren`, Timer der Automatik nach dem gemeinsamen Notschalter, `/var/lib/zenos/basis`; installiert selbst nichts), kein Wechsel der Hauptversion (`Prompt=never` per Drop-in in `/etc/update-manager/release-upgrades.d/`), keine Hinweise auf neue Ubuntu-Versionen |
| `72-kennung` | Systemkennung zenOS (`zenos-kennung`, apt-Hook, Version, Logo), nur nach der Vorab-Prüfung der Ubuntu-Sicherheitsquelle |
| `75-apps` | Werkzeuge für `zen apps`, Starter für Chrome und Web-Apps |
| `76-installer` | zen Installer: `zenos-installer` als root-eigene Kopie (nur, wenn der Weg dorthin nur für root schreibbar ist), Units `zenos-installer-installieren@` und `-entfernen@` (statisch), polkit-Aktionen, Starter `zenos-installer.desktop`, `/var/lib/zenos/installer` mit `ablage/`. Keine Pakete, läuft auch im Image |
| `80-argon` | Argon-Dienst (V3 und ONE UP) und Shutdown-Hook |
| `82-gesten` | Wischen mit drei Fingern: Dienstbenutzer `zenos-gesten` (systemd-sysusers), udev-Regel für reine Touchpads, `zenos-gesten.service` (startet ihn, wenn es ein Touchpad gibt; nach Änderungen neu); keine Pakete. Mit Notschalter `/etc/xdg/zenos/gesten-aus` nimmt es alles zurück |
| `90-benutzer` | Oberfläche verknüpfen, Ordner für persönliche Daten |
| `95-zen` | `/usr/local/bin/zen`, Log-Ordner |

- **Idempotent:** Jede Änderung läuft über die Hilfsfunktionen aus `scripts/lib/gemeinsam.sh` und wird gezählt. Der
  zweite Lauf meldet `0 Änderungen`. Nie zwei Läufe gleichzeitig (Sperrdatei). Log: `/var/log/zenos/install.log`.
- **Dienste bei apt:** Während des eigenen dpkg-Laufs verbietet eine `policy-rc.d` Dienststarts (nur ein Neuladen
  des System-Busses ist erlaubt). greetd wird so aktiviert, startet aber erst nach dem Neustart; SSH bleibt
  unberührt. Vorher wartet der Installer höchstens 20 Minuten auf laufende Paketvorgänge (apt-daily,
  unattended-upgrades).
- **`--image`:** für den Image-Bau im chroot. Keine Benutzerteile, kein Zugriff auf `~`, Dienste werden nur
  aktiviert. `ZENOS_KANAL=<kanal>` legt den Kanal beim ersten Mal fest.
- **`--nur-benutzer`:** nur die Benutzerteile, ohne sudo. `zenos-sitzung` ruft es bei jeder Anmeldung auf; so
  bekommt ein Image-System die Benutzerdateien beim ersten Login.
- **Oberfläche nach der Installation:** Haben sich QML-Dateien geändert, während die Oberfläche lief, startet ein
  normaler Lauf `zenos-shell.service` am Ende einmal neu. Ist die Sitzung gesperrt, lädt die Sperre nach dem
  Entsperren selbst neu.
- **Selbsttest:** `scripts/pruefen.sh` (shellcheck, JSON-Schemas, Hex- und sh-c-Regel, Einheitentests, qmllint,
  gitleaks, Start-Test der Oberfläche). Läuft auch in GitHub Actions.

## Update-Fluss

```
Mac (Claude Code, Tests im Container) ── push ──▶ GitHub dev ──▶ Pi: zen update, Schritt 1 (zenOS-Kanal)
                                                    │
                                                    └─ Tag v* ──▶ Image-Workflow (Release; -rc als Vorabversion)
                                                                  und Bürorechner (nur getestete Stände)

Ubuntu-Archiv und Herstellerquellen (Ubuntu 26.04 LTS) ──▶ Pi: zen update, Schritt 2 (Ubuntu-Basis)
                                                           unattended-upgrades (Sicherheit, täglich)
```

- **`zen update`** hat zwei Schritte, jeder meldet für sich, ob er gelungen ist: zuerst zenOS über den Kanal (unten),
  dann die Pakete der Ubuntu-Basis (`zenos-basis`, «Basis-Updates» unten; Zusammenfassung, ein getipptes «ja», mit
  `--ja` ohne Rückfrage). `--nur-zenos` und `--nur-basis` nehmen nur einen; Claude deployt mit `--nur-zenos`. Die
  Basis läuft auch, wenn der Kanal nichts Neues hatte, ein «ja» fehlte oder etwas lief, aber nicht über einen
  kaputten oder unterbrochenen Stand des Kanals. Exit 0 nur, wenn jeder gelaufene Schritt gelang, sonst der schwerere.
- **Schritt 1, der Kanal,** läuft über `scripts/bin/zenos-kanal` (root-eigene Kopie unter
  `/usr/local/libexec/zenos`). Die Arbeit machen systemd-Units, ein SSH-Abbruch schadet nicht:
  1. holen ohne Rechte (`zenos-kanal-holen.service`, DynamicUser, nur https) als Bundle;
  2. prüfen und bereitstellen als root ohne Netz (`zenos-kanal-pruefen.service`): Signatur gegen den Anker
     `/etc/zenos/vertrauen`, Ziel nach `/var/lib/zenos/kanal/bereit/<commit>` (eigenes Repo, ausgecheckt, geprüft);
  3. installieren als root mit Netz (`zenos-kanal-installieren.service`, Block-Inhibitor, `KillMode=mixed`):
     `install.sh` aus der Bereitstellung, 10-code übernimmt den Code Datei für Datei atomar nach `/opt/zenos`. Danach
     Gesundheitsprüfung; scheitert sie, kommt die Version nach `gesperrt/` und der Stand davor zurück.
  Der Kanal steht in `/etc/xdg/zenos/kanal`: `stabil` (nur `vX.Y.Z`), `vorschau` (auch `-rcN`), `dev` (Branch dev;
  ohne Frage nur, wenn jeder neue Commit gültig signiert ist, sonst nach «ja» für genau diesen Commit). Firewall,
  Netz und Boot fragen immer. Solange der Anker leer ist, geht nur dev von Hand. Zum Schluss (nach beiden Schritten)
  richtet `zen update` die Benutzerteile als Benutzer ein (`install.sh --nur-benutzer`).
- **`zen rollback <tag>`:** derselbe Weg mit einem Tag als Ziel, signiert ohne Frage, unsigniert nur nach «ja» für
  genau dieses Tag-Objekt. `hoechste` bleibt; das nächste `zen update` kehrt auf den Kanal zurück. Die Automatik
  bringt die verlassene Version nicht wieder (sie liegt nicht über `hoechste`). Eine gesperrte Version noch einmal
  versuchen geht nur so, mit «ja»; `zen update` lässt gesperrte Versionen aus.
- **Automatik:** `zenos-kanal.timer` holt und prüft alle 6 h, `zenos-kanal-gelegenheit.timer` schaut alle 15 Min.
  ohne Holen. Installiert wird über dieselben Units, nur auf `stabil` und `vorschau`, nur gültig signiert ohne
  Rückfrage-Pfade, nach der Wartezeit (stabil 24 h, mit synchronisierter Uhr) und zum Zeitpunkt des Geräts
  (`/etc/xdg/zenos/kanal-zeitpunkt`: seit 5 Min. gesperrt oder Login-Bildschirm seit 5 Min., ohne SSH-Sitzung;
  Zeitfenster; jederzeit; nie), nur am Netzteil oder ab 50 % Akku und nicht über einen Stand von Hand
  («angehalten»). Ein automatisch installierter Stand gilt erst als gut, wenn nach einem Neustart der Login kommt
  (`zenos-kanal-bestaetigen.timer`); sonst geht es nach zwei Starts zurück. Notschalter (gilt auch für die
  Basis-Updates): `sudo zen kanal automatik aus`.
- **Abbruch:** Strom weg oder hart beendet hinterlässt `/var/lib/zenos/kanal/laeuft.json`. Beim Start vollendet
  `zenos-kanal-nachstart.service` vor greetd die Übernahme des Codes (`install.sh --nur-code`, ohne Netz), damit der
  Login keinen Mischstand sieht; `zen update` setzt den Rest fort. Nach zwei unterbrochenen Versuchen wird die
  Version gesperrt und der Rückweg genommen.
- **Von Hand:** `install.sh` aus einem Arbeits-Checkout (etwa `~/zenOS`) oder aus `/opt/zenos` wartet über sudo
  auf die Kanal-Sperre und vermerkt sich in `/run/zenos-sperre/hand` (nur root); solange es läuft, installiert der
  Kanal nichts. Aus einem Arbeits-Checkout markiert es den Stand als «angehalten»; das nächste `zen update` kehrt zum
  Kanal zurück. Den Notweg ohne `zen` und ohne den neuen Code beschreibt `ANLEITUNG.md`, Abschnitt F.
- **Basis-Updates** (Pakete innerhalb von Ubuntu 26.04 LTS, wie `apt full-upgrade`): `scripts/bin/zenos-basis`,
  root-eigene Kopie unter `/usr/local/libexec/zenos`. `zenos-basis-pruefen.service` holt die Paketlisten und wertet
  `apt-get -s full-upgrade` aus (Anzahl, Sicherheit, Kernel/Firmware/Bootloader, Entfernungen, Neustart
  voraussichtlich, Hash der Liste); `zenos-basis-installieren.service` installiert genau diese Liste (ohne neues
  `apt-get update`) unter derselben Sperre wie der Kanal, mit Block-Inhibitor und Übernahme-Marker
  `/run/zenos-basis/uebernahme`. Dienste starten wie bei Ubuntu neu, nur greetd nicht (eigene `policy-rc.d` für
  diesen Lauf; eine neue greetd-Version heisst «Neustart nötig»). Danach `install.sh` aus `/opt/zenos` (baut
  Quickshell nach einem Qt-Update neu) und eine Gesundheitsprüfung, die nur wertet, was schlechter wurde; zurückgerollt
  wird nichts. Kernel, Firmware, Bootloader und Entfernungen nur mit Zustimmung, ein geschütztes Paket nie.
  Sicherheitsupdates bringt weiter unattended-upgrades. Von Hand: Schritt 2 von `zen update` und die Knöpfe in
  Einstellungen › System › Updates (`zenos-kanal-bedienen basis-…`; mit Kernel, Firmware, Bootloader oder
  Entfernungen nur mit Passwort). Automatisch: `zenos-basis-automatik.timer` (alle 6 h, versetzt zum Kanal) prüft
  und installiert, `zenos-basis-gelegenheit.timer` (alle 15 Min.) installiert eine bereite Liste, aber nie Kernel,
  Firmware, Bootloader oder Entfernungen, nur wenn `zenos-kanal automatik darf --ohne-ssh` ja sagt (dieselben Regeln
  wie der Kanal: Notschalter, Zeitpunkt, Akku; dazu bei jedem Zeitpunkt keine SSH-Sitzung), auch auf dev, nie ein
  Neustart. Einzelheiten: `docs/image-und-releases.md`, «Basis-Updates».
- **Basiswechsel** (etwa auf Ubuntu 28.04) ist kein Update, sondern eine neue zenOS-Hauptversion mit neuem Image:
  `Prompt=never` sperrt `do-release-upgrade` (`71-basis`), und `zenos-kanal` nimmt keinen Stand, dessen
  `system/basis` nicht zur Ubuntu-Version des Geräts passt. Persönliche Daten kommen per Backup von Hand mit
  (`docs/image-und-releases.md`, «Basiswechsel»).
- **`zen kanal`:** `zen kanal status` zeigt Kanal, Zustand, Fingerabdrücke, abgelehnte Tags, letzte Installation,
  guten und gesperrten Stand; `sudo zen kanal pruefen` holt und prüft, ohne zu installieren. Regeln, Zustände und
  Dateien: `docs/image-und-releases.md`, «Signierte Releases».
- **`zen doctor`:** Prüfbericht ohne Geheimnisse und ohne Persönliches, Exit 1 bei Fehlern. `zen version` zeigt
  zenOS-Version, die Basis (Ubuntu), Kanal, Commit, die letzte Installation über den Kanal, die ausstehenden
  Basis-Updates samt «Neustart nötig» (Zeile `Pakete`, ohne Netz), Quickshell und labwc.
- Systemänderungen laufen immer über `install.sh`. Das Skript darf beliebig oft laufen.

## Plattformen

- **Raspberry Pi 5 (arm64):** Hauptziel und Messlatte. Gebaut und getestet wurde 0.1 in Docker-Containern mit
  Ubuntu 26.04 arm64 (`test/container/`); die Abnahme auf dem Pi steht aus. Zenos Gerät ist ein Argon ONE UP:
  ein Laptop mit Compute Module 5 Lite (gleicher Chip BCM2712 wie der Pi 5), eingebauter Tastatur und Akku.
- **x86-Bürorechner (amd64):** später. Gleiche Oberfläche, eigene Hardware-Teile, zum Beispiel ohne Argon-Dienst
  (`zenos-argon.service` startet dort nicht). Dort ist GNOME als Rückfall-Sitzung beim Login vorgesehen.
