# Architektur

zenOS ist eine Sitzung auf Ubuntu Server: ein Fenstermanager (labwc), eine selbst gebaute Oberfläche (Quickshell)
und ein Installer, der beides einrichtet. Diese Seite beschreibt den Stand von Version 0.1. Einzelheiten und
Entscheidungen jedes Bausteins stehen in `docs/module/m1.md` bis `docs/module/m14.md`.

## Schichten

```
┌───────────────────────────────────────────────────────────────┐
│ Apps: Chrome, VS Code, 1Password, coremail, kitty + fish,     │
│ Web-Apps (proprietäre Apps nur nach Zustimmung, nie im Image) │
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
   - `zenos-idle.service`: swayidle über `zenos-idle` (automatische Sperre), `Restart=always`.
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
- **Oberflächen:** `leiste/`, `heute/`, `befehlsfeld/`, `mitteilungen/`, `sperre/`, `freigabe/`, `modi/`
  (Modus- und Zustand-Wahl), `einstellungen/`, `einrichtung/`, dazu `komponenten/Hinweise.qml` (Toast) und
  `greeter.qml` mit `greeter/` für den Login.
- **Apps aus der Oberfläche** starten über `zenos-oeffnen` in eigenen Einheiten
  (`app-zenos-<name>-<zeit>.scope` in `app.slice`). Ein Neustart von `zenos-shell.service` beendet sie nicht.
- **WLAN** (`leiste/WlanQuelle.qml`, kein Dienst unter `dienste/`): spricht NetworkManager über
  `Quickshell.Networking` (D-Bus) und entsteht erst, wenn NetworkManager läuft (siehe «Netz» unten).

**Dienste** (`qs.dienste`, Singletons ohne Oberfläche):

| Dienst | Aufgabe |
|---|---|
| `Pfade` | Orte: `~/.config/zenos`, `~/.local/state/zenos`, `$XDG_RUNTIME_DIR/zenos`, `/opt/zenos`, `scripts/bin` |
| `Einstellungen` | `einstellungen.json` lesen und schreiben (behält fremde Schlüssel, sichert eine ungültige Datei) |
| `Erscheinung` | hell, dunkel oder nach Tageszeit, Akzent; überträgt beides mit `zenos-thema` nach aussen |
| `Oberflaeche` | Zustand der Oberfläche (was offen ist, `gesperrt`), Hinweise, Sperr-Anforderung |
| `Aktionen` | Prozessstarts mit Argumentlisten: Apps, Terminal, Dateien, Werkzeuge, Abmelden, Neustart, Ausschalten |
| `System` | Temperatur, Netz, Ton (PipeWire), 1Password |
| `Geraet` | Akku und Lüfter aus `/run/zenos/geraet.json` (`zenos-argon`), Mitteilung bei niedrigem Akku |
| `Mitteilungen` | Mitteilungsdienst (`NotificationServer`), Bündelung, Zentrale |
| `Konfig` | Modi, Zustände, Raster, Bildschirme, Web-Apps lesen; schreiben über `zenos-konfig` |
| `Modi` | aktiver Modus, Wechsel (Akzent, Raster, Apps, Chrome-Profil) |
| `Zustaende` | aktiver Zustand, Auslöser, Timer, Rückkehr, wirksamer Zustand |
| `Freigabe` | Bildschirmfreigabe (Marker und IPC) |
| `Leitplanken` | feste Regeln, siehe unten |
| `Raster` | aktives Raster, Bildschirm-Profile, Aufruf von `zenos-labwc` (auch nach geändertem Scroll-Tempo) und `zenos-kanshi` |

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
| `sperre` | `sperren`, `status` (`gesperrt`/`offen`) |
| `thema` | `wechseln`, `setzen(hell\|dunkel\|tageszeit)`, `status` |
| `modus` | `waehlen`, `wechseln(id)`, `aktiv` |
| `zustand` | `waehlen`, `starten(id)`, `beenden`, `aktiv` |
| `freigabe` | `gewaehlt(ausgang)`, `gestartet`, `beendet`, `status` |
| `mitteilungen` | `zentrale`, `oeffnen`, `schliessen`, `zustellen`, `verwerfen(nummer)`, `alleVerwerfen`, `aktion(nummer, kennung)`, `status` |
| `einstellungen` | `oeffnen(seite)`, `schliessen` |
| `raster` | `setzen(id)`, `aktiv` |
| `hinweis` | `zeigen(text)`, `warnen(text)` |
| `einrichtung` | `oeffnen`, `apps`, `schliessen`, `status` |
| `leiste` | `menue(system\|raster\|wlan)` (`wlan`: System-Menü mit aufgeklappter WLAN-Liste), `schliessen` |

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
| `zenos-idle`, `zenos-1password-sperren` | automatische Sperre, 1Password mitsperren |
| `zenos-oeffnen` | Datei, Ordner oder Programm in eigener Einheit öffnen |
| `zenos-bildschirmfoto`, `zenos-pipette` | Werkzeuge des Befehlsfelds |
| `zenos-chrome`, `zenos-webapp` | Chrome im Profil des Modus, Web-Apps |
| `zenos-apps` | proprietäre Apps installieren (`zen apps`) |
| `zenos-argon` | Argon ONE: Lüfter und Power-Button (V3), Akku-Messchip (ONE UP), Werte für die Leiste |
| `zenos-netzwerk` | Netz von netplan/systemd-networkd auf NetworkManager umstellen und zurück (`zen netzwerk`) |

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
  `loginctl lock-session`.
- Marker `$XDG_RUNTIME_DIR/zenos/gesperrt`: Stürzt die Oberfläche ab, hält labwc den Bildschirm gesperrt, systemd
  startet Quickshell neu, und der Marker sperrt sofort wieder.
- `zen lock` (auch per SSH): IPC, sonst Neustart von `zenos-shell.service`, sonst **Notfall-Sperre** mit swaylock
  als eigene Einheit (Farben aus den Tokens, keine Inhalte). So fällt die Sperre nie aus.
- 1Password sperrt sich mit (`zenos-1password-sperren`), sobald es installiert ist.

### Leitplanken im Code

Die Regeln aus dem Manifest stehen im Code, nicht in der Konfiguration, und lassen sich nicht abschalten:

- `Leitplanken` (`shell/dienste/Leitplanken.qml`, Werte aus `shell/modi/zustandslogik.js`): Mitteilungsinhalte bei
  Freigabe verborgen, Sperre ohne Inhalte, Sperre nicht abschaltbar, Sperrzeit 1–15 Minuten. `anwenden(zustand)`
  setzt diese Regeln zuletzt in jedem wirksamen Zustand durch.
- Bei Freigabe erzeugen Karten und Zentrale die Inhalte gar nicht erst; «Heute» blendet Name und Zusammenfassung
  aus, das Befehlsfeld zeigt keine Dateinamen.
- Der Sperrbildschirm zeigt nur die Anzahl der Mitteilungen. `zenos-idle` begrenzt die Sperrzeit selbst auf 1–15
  Minuten und läuft mit `Restart=always`.
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
- **Argon ONE:** `zenos-argon.service` (Systemdienst, gehärtet) erkennt das Gerät am Gerätebaum. Am Raspberry Pi 5
  mit Argon ONE V3 regelt er den Lüfter über I2C und wertet den Power-Button aus; ein systemd-shutdown-Hook sendet
  beim Ausschalten das Abschaltsignal an die Platine. Am Compute Module 5 im Argon ONE UP liest er den
  Akku-Messchip CW2217 (lädt bei Bedarf Argons Akkuprofil hinein, erst nach `zen akku freigeben`, siehe
  `docs/sicherheit.md`) und zeigt Lüfter
  und Temperatur des Kernels an. Beide schreiben `/run/zenos/geraet.json`; die Oberfläche (`Geraet`) zeigt Akku
  und Lüfter in Leiste und System-Menü und meldet niedrigen Akku. Einzelheiten in `docs/module/m13.md`.

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
| Kanal für `zen update` | `/etc/xdg/zenos/kanal` (`dev` oder `main`) | nein, vom Installer |
| Lüfterkurve (optional) | `/etc/xdg/zenos/argon.json` | nie |
| Freigabe Akkuprofil (ONE UP) | `/etc/xdg/zenos/argon-akkuprofil` (`zen akku freigeben`) | nie |
| Gerätewerte (Akku, Lüfter) | `/run/zenos/geraet.json` (flüchtig, Ordner gehört `zenos-argon`) | nie |
| Quickshell | `/usr/local/bin/quickshell`, Stempel `/usr/local/share/zenos/quickshell.version` | nein, Quellbau |
| Schriften | `/usr/local/share/fonts/zenos/` | ja (`assets/fonts/`) |
| App-Icon `zenos` | `~/.local/share/icons/hicolor/<n>x<n>/apps/zenos.png` | ja (`assets/zeichen/png/`) |
| Bootsplash-Theme | `/usr/share/plymouth/themes/zenos/` (eingeschaltet erst mit `zen bootsplash aktivieren`) | ja (`system/plymouth/zenos/`) |
| Benutzereinheiten | `/etc/systemd/user/` (`zenos-sitzung.target`, `zenos-shell`, `zenos-idle`, `zenos-kanshi`, Drop-in für `xdg-desktop-portal-wlr`) | ja (Kopien) |
| Systemeinheiten | `/etc/systemd/system/zenos-argon.service`, `/usr/lib/systemd/system-shutdown/zenos-argon` | ja (Kopien) |
| Netz-Einheiten | `/etc/systemd/system/zenos-wlan-land.service`, `zenos-netzwerk-erststart.service`, Drop-in `systemd-networkd-wait-online.service.d/zenos-netzwerk.conf` | ja (Kopien) |
| Netz nach dem Umstieg | `/etc/netplan/90-zenos-netzwerk.yaml`, WLAN-Profile `/etc/netplan/90-NM-<uuid>.yaml` (0600 root, Passwörter wie bisher in netplan) | nie |
| Netz: Sicherung, Land, Treiber | `/var/lib/zenos/netplan-vorher/<zeit>/` (0700), `/etc/xdg/zenos/wlan-land`, `/etc/modprobe.d/zenos-brcmfmac.conf`, `/etc/cloud/cloud.cfg.d/99-zenos-netzwerk.cfg` | nie (Vorlagen: `system/modprobe/`, `system/cloud/`) |
| Login, Portale | `/etc/greetd/config.toml`, `/etc/xdg/xdg-desktop-portal/labwc-portals.conf`, `/etc/xdg/xdg-desktop-portal-wlr/config` | ja (Kopien) |
| Richtlinien | `/etc/opt/chrome/policies/managed/zenos.json`, `/etc/vscode/policy.json`, `/etc/apt/apt.conf.d/52zenos-unattended` | ja (Kopien) |
| Install-Log | `/var/log/zenos/install.log`, Rückfall `~/.local/state/zenos/install.log` | nie |
| Einstellungen | `~/.config/zenos/einstellungen.json` | nie |
| Modi | `~/.config/zenos/modi/*.json` | nie |
| Zustände | `~/.config/zenos/zustaende/*.json` | nie (Vorlagen: `config/vorlagen/`) |
| Raster | `~/.config/zenos/raster/*.json` | nie (Vorlagen: `config/vorlagen/`) |
| Bildschirm-Profile | `~/.config/zenos/bildschirme.json` | nie |
| Web-Apps | `~/.config/zenos/webapps.json`, Starter `~/.local/share/applications/zenos-webapp-<id>.desktop` | nie |
| Laufzeitzustand | `~/.local/state/zenos/laufzeit.json` (`modus`, `zustand`, `raster`, `profil`) | nie |
| Weiterer Zustand | `~/.local/state/zenos/` (`thema.json`: zuletzt übertragener Akzent; Merker für die Vorlagen) | nie |
| Nutzungsstatistik | `~/.local/share/zenos/befehlsfeld.json` (nur Desktop-IDs und Zähler) | nie |
| Flüchtige Marker | `$XDG_RUNTIME_DIR/zenos/` (`gesperrt`, `freigabe`, `freigabe.neu`, `freigabe-wahl`, `freigabe-eintraege`, `freigabe-ende`, Sperrdateien) | nie |
| Bildschirmfotos | `~/Bilder/Screenshots/` | nie |
| Geheimnisse | 1Password | nie |

Die Schlüssel der persönlichen Dateien stehen in `docs/konfiguration.md`.

## Installer

`scripts/install.sh [--image] [--nur-benutzer] [--ruhig]` läuft als normaler Benutzer und holt sich Root-Rechte
mit sudo. Die Module unter `scripts/module/` laufen in Namensreihenfolge, in zwei Durchgängen: erst alle
Systemteile, dann alle Benutzerteile.

| Modul | Aufgabe |
|---|---|
| `00-vorbereitung` | System prüfen (Ubuntu 26.04, arm64/amd64, Platz), Werkzeuge des Installers |
| `10-code` | `/opt/zenos` auf den Stand der Quelle bringen (atomar), Kanal festlegen |
| `20-pakete` | alle Paketlisten aus `scripts/pakete/` in einem apt-Lauf |
| `25-quickshell` | Quickshell bauen, nur wenn der Stempel fehlt oder abweicht |
| `30-schriften` | Geist, Geist Mono, Instrument Serif |
| `35-netzwerk` | NetworkManager fürs WLAN-Menü bereitlegen (umgestellt wird mit `zen netzwerk umstellen`), WLAN-Land, wait-online |
| `40-sitzung` | greetd mit Greeter, Benutzereinheiten, Portale |
| `42-bootsplash` | Bootsplash-Theme ablegen, nicht einschalten |
| `45-thema` | Erscheinungsbild auf GTK, Qt, kitty, labwc und VS Code, App-Icon `zenos` |
| `50-raster` | Raster, Tastenkürzel, Bildschirm-Profile |
| `55-zustaende` | Freigabe-Portal, Vorlagen der Zustände |
| `60-terminal` | kitty, fish, tldr-Seiten |
| `65-oberflaeche` | automatische Sperre, Notfall-Sperre, Hilfsprogramme |
| `70-sicherheit` | Sicherheitsupdates, Richtlinien, Ubuntu-Nachrichten aus, Firewall vorbereiten, gitleaks-Hook |
| `75-apps` | Werkzeuge für `zen apps`, Starter für Chrome und Web-Apps |
| `80-argon` | Argon-Dienst (V3 und ONE UP) und Shutdown-Hook |
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
Mac (Claude Code, Tests im Container) ── push ──▶ GitHub dev ──▶ Pi: zen update
                                                    │
                                                    └─ Tag v* ──▶ Image-Workflow (-rc: nur Artefakt, sonst Release)
                                                                  und Bürorechner (nur getestete Stände)
```

- **`zen update`:** `git fetch --tags --prune`, dann `reset --hard` auf `origin/<kanal>` und `clean`, danach
  `install.sh`. Zeigt alt → neu. Der Kanal steht in `/etc/xdg/zenos/kanal`: `dev` auf dem Pi und im Image, bis
  `main` Releases trägt. Lokale Änderungen in `/opt/zenos` gehen verloren.
- **`zen rollback <tag>`:** `/opt/zenos` losgelöst auf den Tag, dann `install.sh`. Das nächste `zen update` kehrt
  auf den Kanal zurück.
- **`zen doctor`:** Prüfbericht ohne Geheimnisse und ohne Persönliches, Exit 1 bei Fehlern. `zen version` zeigt
  zenOS-, Quickshell-, labwc- und Ubuntu-Version.
- Systemänderungen laufen immer über `install.sh`. Das Skript darf beliebig oft laufen.

## Plattformen

- **Raspberry Pi 5 (arm64):** Hauptziel und Messlatte. Gebaut und getestet wurde 0.1 in Docker-Containern mit
  Ubuntu 26.04 arm64 (`test/container/`); die Abnahme auf dem Pi steht aus. Zenos Gerät ist ein Argon ONE UP:
  ein Laptop mit Compute Module 5 Lite (gleicher Chip BCM2712 wie der Pi 5), eingebauter Tastatur und Akku.
- **x86-Bürorechner (amd64):** später. Gleiche Oberfläche, eigene Hardware-Teile, zum Beispiel ohne Argon-Dienst
  (`zenos-argon.service` startet dort nicht). Dort ist GNOME als Rückfall-Sitzung beim Login vorgesehen.
