# Öffentlicher Bildschirm (Geräteprofil `anzeige`)

Ein Gerät, etwa ein x86-Bürorechner an der Wand oder ein Pi 5, zeigt nach dem Einschalten von selbst genau eine App im
Vollbild, ohne Sperre. Erste Ziel-App ist ein Kiosk-Dashboard als systemd-Benutzerdienst; zenOS bindet sich aber an
keine App, sie ist Konfiguration. Auftrag und Entscheid: Zeno, 15.10.2026 («ja baue das»).

## Grundsatz

Die Leitplanke «Die automatische Sperre lässt sich nicht abschalten» gilt für jedes persönliche Konto wörtlich weiter.
Der öffentliche Bildschirm ist deshalb kein Modus, kein Zustand und keine Einstellung, sondern ein **Geräteprofil**
(MANIFEST, Grundsatz 0 und Leitplanke «Ausnahme Anzeigegerät»):

- Nur root richtet es ein oder entfernt es, mit getippter Bestätigung (`sudo zen anzeige einrichten|entfernen`).
- Dazu kommt ein technisches **Anzeige-Konto**: Systemkonto ohne Rechte, ohne Passwort, ohne persönliche Daten. Es
  meldet sich beim Start von selbst an und braucht keine Sperre, weil es nichts zu schützen hat.
- Persönliche Konten melden sich auf so einem Gerät nie automatisch an und sperren wie immer.

Das steht als Code fest: Als Anzeige-Konto nimmt `zenos-anzeige` nur ein Systemkonto (UID unter 1000) mit Login-Shell
`nologin`, ohne Passwort, ohne Verwaltungsgruppen und ohne SSH-Schlüssel; ein persönliches Konto lehnt es ab.
`zenos-idle` und die Sperre persönlicher Konten ändern sich nicht.

## Was gebaut ist

| Teil | Datei | Aufgabe |
|---|---|---|
| Konfiguration | `/etc/zenos/anzeige.json` (root, 0644) | Konto, App, Ports, Bildschirmzeiten; Schema `config/schema/anzeige.schema.json`, neutrales Beispiel `config/beispiele/anzeige.beispiel.json` |
| Zustand | `/var/lib/zenos/anzeige.json` (root, 0644) | aktiv, Konto, ob zenOS es angelegt hat, seit |
| Programm | `scripts/bin/zenos-anzeige` (Python) | prüfen, einrichten, entfernen, neu starten, nachziehen; in der Sitzung App und Bildschirmzeiten |
| Befehl | `zen anzeige status\|einrichten\|entfernen\|neustart` (`scripts/zen.d/anzeige.sh`) | Plan zeigen, Wort eintippen, dann `zenos-anzeige … --ja` als root |
| Login | `/etc/greetd/config.toml` | nur bei aktivem Profil zusätzlich `[initial_session]` (Anzeige-Konto, `zenos-anzeige-sitzung`); erzeugt von `zenos-anzeige greetd-konfig`, geschrieben von `40-sitzung` und `zen anzeige` |
| Sitzung | `scripts/bin/zenos-anzeige-sitzung`, `system/anzeige/labwc/` | labwc mit eigener Konfiguration, ohne Oberfläche und Sperre |
| Einheiten | `system/systemd/user/zenos-anzeige*` → `/etc/systemd/user/` (nur bei aktivem Profil) | `zenos-anzeige.target` und vier Dienste, siehe unten |
| Ersatzbild | `shell/anzeige.qml` | Uhrzeit, «Anzeige startet …», Rechnername im zenOS-Look |
| Rechte | `/etc/polkit-1/rules.d/50-zenos-anzeige.rules` (erzeugt) | das Anzeige-Konto darf über polkit nur die Hemmer gegen Leerlauf, Standby und Deckel |
| Firewall | `zenos-firewall anzeige`, `scripts/lib/firewall.sh` | Ports nur aus den lokalen Netzen, wie SSH, Kommentar `zenos-anzeige` |
| install.sh | `scripts/module/77-anzeige.sh` | zieht ein aktives Profil nach; ohne Profil tut es nichts |
| doctor | `scripts/doctor.d/77-anzeige.sh` | Abschnitt «Öffentlicher Bildschirm» |
| Protokoll | `/var/log/zenos/anzeige.log` | jede Änderung mit Zeit und Aufrufer |

### Konfiguration

```json
{
  "version": 1,
  "konto": "anzeige",
  "app": { "einheit": "beispiel-anzeige.service" },
  "ports": [8080],
  "bildschirmzeiten": [ { "tage": ["mo", "di", "mi", "do", "fr"], "an": "07:00", "aus": "19:00" } ]
}
```

- `konto`: Standard `anzeige`; Name wie ein Linux-Konto, nie `root`, `_greetd`, `nobody` oder ein Dienstkonto von zenOS.
- `app`: genau eins von beidem.
  - `einheit`: eine systemd-Benutzereinheit des Anzeige-Kontos (`….service`). zenOS hängt sie über das Drop-in
    `/etc/systemd/user/zenos-anzeige.target.d/zenos-app.conf` an die Anzeige-Sitzung. Eine Einheit mit
    `WantedBy=graphical-session.target` startet ohnehin von selbst; die Angabe lässt `zen doctor` sie prüfen.
  - `befehl`: Programm mit absolutem Pfad und Argumente als Liste. `zenos-anzeige app` startet es mit `execv`, nie
    über eine Shell; `zenos-anzeige-app.service` startet es nach einem Absturz nach 5 s neu.
  - ohne `app`: nur das Ersatzbild, ausser eine Einheit startet von selbst.
- `ports`: TCP-Ports der App (höchstens 16, nie 22). Die Firewall gibt sie nur aus den lokalen Netzen frei.
- `bildschirmzeiten`: optional. zenOS schaltet die Bildschirme dann nach Wochentag und Uhrzeit an und aus, über
  `wlopm` wie am Login (über Mitternacht zählt der Tag von «an»). Ohne Bildschirmzeiten schaltet zenOS nie; das darf
  die App selbst, etwa mit `wlr-randr`.

Eine kaputte Konfiguration hält die Anzeige nicht an: Das Konto kommt dann aus dem Zustand, App und Ports entfallen,
`zen doctor` meldet den Fehler.

### Anzeige-Konto

- Angelegt mit `useradd --system --create-home --home-dir /home/<konto> --shell /usr/sbin/nologin --user-group`, dann
  `usermod --lock`. Keine weiteren Gruppen: labwc bekommt Bildschirm und Eingabe über logind (Sitz der Sitzung).
- **Login-Shell `nologin`:** greetd startet jede Sitzung über `/bin/sh -c` (Quelltext `greetd/src/session/worker.rs`),
  die Login-Shell spielt dort keine Rolle. Konsole und SSH lehnen das Konto ab, ohne dass zenOS die
  SSH-Konfiguration anfasst. Das gesperrte Passwort schliesst jede Anmeldung mit Passwort zusätzlich aus.
- Keine Benutzerteile von zenOS: kein `install.sh --nur-benutzer`, keine Einstellungen, Modi, Zustände, Web-Apps,
  kein 1Password, keine Einrichtung von Chrome oder VS Code. Die Anzeige-Sitzung startet nichts davon.
- polkit: Die Regel lehnt für dieses Konto alles ab, ausser `org.freedesktop.login1.inhibit-block-idle`,
  `inhibit-block-sleep` und `inhibit-handle-lid-switch`. Ausschalten, Neustart und Standby aus der Anzeige-Sitzung,
  auch durch eine ferngesteuerte App, gehen also nicht (Entscheid: alles gesperrt). Wartung per SSH mit dem
  persönlichen Konto.
- Ein vorhandenes Konto nimmt `einrichten` nur, wenn es genau so aussieht (dann bleibt es auch beim Entfernen).
- Linger: Eine App darf `loginctl enable-linger` für das Konto setzen (etwa für ihre Updates); `zen doctor` zeigt
  es, `entfernen` nimmt es zurück.

### Login

`[default_session]` bleibt der Login von zenOS. Nur bei aktivem Profil kommt dazu:

```toml
[initial_session]
command = "/opt/zenos/scripts/bin/zenos-anzeige-sitzung"
user = "anzeige"
```

greetd führt `[initial_session]` einmal beim eigenen Start aus. Endet die Anzeige-Sitzung, erscheint der Login von
zenOS; dort meldet sich Zeno mit seinem Passwort an, seine Sperre funktioniert wie immer. Zurück zur Anzeige:
`sudo zen anzeige neustart` (startet greetd neu; lehnt ab, solange am Gerät eine persönliche Sitzung läuft) oder ein
Neustart. Ohne Profil schreibt `40-sitzung` genau `system/greetd/config.toml`; `entfernen` stellt also Byte für Byte
den Zustand vor dem Profil her.

### Anzeige-Sitzung

- `zenos-anzeige-sitzung` setzt die Umgebung (Wayland, Tastatur aus `/etc/default/keyboard`) und startet
  `labwc --config-dir /opt/zenos/system/anzeige/labwc`.
- `rc.xml`: ein einziges Tastenkürzel, der **Ausweg** `Strg + Alt + Shift + Rücktaste` (Aktion `Exit`; vier Tasten,
  die man nicht zufällig zusammen drückt). Weil die Liste da ist, lädt labwc seine eigenen Vorgaben nicht: kein
  Terminal, kein Befehlsfeld, kein App-Start, kein Alt+Tab. Die Maus hat nur eine wirkungslose Bindung am Desktop
  (kein Menü, kein Verschieben). Jedes Fenster erscheint maximiert ohne Rahmen; ohne Leiste füllt es den Bildschirm.
  `menu.xml` hat leere Menüs.
- `autostart` gibt die Umgebung an systemd und D-Bus und startet `zenos-anzeige.target`. Es hat
  `BindsTo=graphical-session.target`; so starten Benutzerdienste mit `WantedBy=graphical-session.target` von selbst.
- `zenos-anzeige.target` will:
  - `zenos-anzeige-wach.service`: `systemd-inhibit --what=idle:sleep:handle-lid-switch --mode=block` – kein Standby,
    kein Leerlauf, der Deckel schickt nichts in den Ruhezustand.
  - `zenos-anzeige-ersatz.service`: Quickshell mit `shell/anzeige.qml` auf der Ebene Background.
  - `zenos-anzeige-app.service`: die App als Befehl (sonst übersprungen).
  - `zenos-anzeige-bildschirm.service`: die Bildschirmzeiten (sonst übersprungen).
- Kein `zenos-idle`, keine Leiste, kein Befehlsfeld, keine Mitteilungen, keine Oberfläche von zenOS.
- **Ersatzbild:** Es liegt immer unter der App. Läuft sie, sieht man es nicht; läuft sie nicht oder stürzt sie ab,
  steht dort ruhig die Uhrzeit (minutengenau), «Anzeige startet …» und der Rechnername, nie ein leerer Desktop. Fehlt
  die App, steht statt «Anzeige startet …», was fehlt: «App slatedesk.service ist nicht installiert», «App /pfad
  fehlt» oder «Keine App eingerichtet». Das liefert `zenos-anzeige hinweis` (alle 30 s neu, Argumentliste); der
  Hinweis verschwindet von selbst, sobald die App installiert ist.

### App installieren

zenOS installiert keine App; es startet nur die, die in der Konfiguration steht. Eine App als Einheit
(`app.einheit`) bringt ihr eigenes Setup als Benutzereinheit ins Anzeige-Konto (`~/.config/systemd/user` des Kontos,
mit `runuser -u <konto>`, denn das Konto hat keine Login-Shell) oder ins System (`/etc/systemd/user`). Gesucht wird
wie bei systemd: im Home des Kontos (`.config/systemd/user`, `.local/share/systemd/user`), dann in `/etc/systemd/user`,
`/etc/xdg/systemd/user`, `/usr/local/share/systemd/user`, `/usr/share/systemd/user`, `/usr/local/lib/systemd/user` und
`/usr/lib/systemd/user`, bei `name@instanz.service` auch die Vorlage `name@.service`. Fehlt sie, warnen der Plan von
`zen anzeige einrichten` und `zen anzeige status` (ohne abzubrechen), und das Ersatzbild sagt es. Der Ablauf für
SlateDesk steht in ANLEITUNG, Abschnitt I.

Eine geänderte Konfiguration gilt erst nach `sudo zen anzeige einrichten` (oder dem nächsten `zen update`), nicht
schon nach einem Neustart: Drop-in der App und Firewall-Regeln schreibt `zenos-anzeige`, nicht der Start.

### Firewall

`zenos-firewall anzeige` gleicht die Regeln an: Für jeden Port und jedes lokale Netz der SSH-Regel
(`_firewall_netze`) gibt es `allow proto tcp from NETZ to any port PORT` mit dem Kommentar `zenos-anzeige`. Fehlende
kommen dazu, überzählige gehen weg; Regeln ohne diesen Kommentar (etwa die eigene Regel einer App) bleiben, wie sie
sind. Ohne aktives Profil gehen alle Regeln der Anzeige weg. Die Firewall schaltet es nie ein oder aus: Ist sie
bewusst aus (`/var/lib/zenos/firewall`), liegen die Regeln bereit, und `zen doctor` warnt.

### Updates

Die Automatik von Kanal und Basis wartet beim Zeitpunkt «bei Sperre» auf ein gesperrtes Gerät. Die Anzeige-Sitzung
wird nie gesperrt; sie zählt deshalb als ruhig (`display_account` in `zenos-kanal`, aus dem Zustand von root). Meldet
sich jemand nach dem Ausweg selbst an, gilt wieder dessen Sperre. Kein Update startet die Anzeige neu.

### zen doctor

Abschnitt «Öffentlicher Bildschirm», nur bei aktivem Profil (ohne Profil nur dann, wenn greetd trotzdem jemanden
automatisch anmeldet: Fehler). Geprüft: Profil und Konfiguration, Konto (Systemkonto, nologin, Passwort gesperrt, keine
Verwaltungsgruppen, keine SSH-Schlüssel; Passwort und Schlüssel mit `sudo -n`), Linger, greetd passt Byte für Byte,
greetd ist der Anmeldedienst, Anzeige-Sitzung auf seat0, App aktiv (mit `sudo -n`), Firewall-Regeln und Zustand der
Firewall, das eigene Konto meldet sich nie automatisch an und sperrt nach 1–15 Min. Ausgegeben werden Kontoname,
Einheit und Ports, nie der Befehl der App, Inhalte oder Adressen.

## Entscheidungen

- **Geräteprofil statt Einstellung:** Eine Sperre, die eine Einstellung abschalten könnte, wäre keine Leitplanke
  mehr. Ein Profil, das nur root einrichtet, mit einem eigenen Konto ohne Rechte, lässt sie für jedes persönliche
  Konto unangetastet.
- **Ausschalten, Neustart, Standby gesperrt:** Eine ferngesteuerte App soll das Gerät nicht ausschalten können.
- **Ausweg `Strg + Alt + Shift + Rücktaste`:** vier Tasten, angelehnt an das alte «Zap» von X11; danach der Login. Die
  Anzeige kommt erst mit `sudo zen anzeige neustart` oder einem Neustart zurück (einfacher und vorhersehbar).
- **Updates automatisch:** Die Anzeige-Sitzung gilt als ruhig, sonst kämen auf einem Anzeigegerät nie Updates.
- **Bildschirmzeiten über `wlopm` statt `wlr-randr`:** `wlopm` schaltet nur die Anzeige aus (Energieverwaltung), die
  Anordnung der Bildschirme bleibt; zenOS nutzt es schon am Login, `wlr-randr` wäre ein neues Paket auf allen Geräten.
  Die App darf weiter selbst `wlr-randr` nehmen.
- **Fenster maximiert statt Vollbild-Regel:** labwc hat für Fensterregeln nur ein Umschalten des Vollbilds; ein App,
  die selbst ins Vollbild geht, fiele damit heraus. Maximiert ohne Rahmen und ohne Leiste füllt jedes Fenster den
  Bildschirm.
- **Einheiten nur bei aktivem Profil installiert:** Ohne Profil ändert sich auf bestehenden Geräten nichts.

## Grenzen

- Geprüft ist das Profil in Einheitentests (`test/einheiten/anzeige.test.py`: Konfiguration gegen dieselben Fälle wie das
  Schema, greetd, polkit-Regel in node, einrichten und entfernen in einer Testwurzel, persönliches Konto abgelehnt,
  Befehl als Argumentliste, Bildschirmzeiten, Regeln der Firewall) und in `test/container/anzeige-e2e.sh`. Der
  Container-Test ist geschrieben, aber bis zur Abnahme nicht gelaufen (auf dem Bau-Rechner fehlt Docker).
- Auf echter Hardware (EliteDesk, 15.10.2026) gesehen: Autologin nach dem Start und das Ersatzbild. Noch nicht
  abgenommen: 30 Minuten ohne Standby, Ausweg, Ports aus dem Büronetz, SlateDesk. Testliste in ANLEITUNG, Abschnitt
  «Öffentlicher Bildschirm».
- Eine App, die zusätzlich einen anderen Anmeldedienst einrichtet (etwa Autologin für gdm), gehört hier nicht dazu: Den
  Login macht greetd.
- Das Konto sieht man nicht im Login von zenOS (Systemkonto), wohl aber in `loginctl` und `zen doctor`.

## Am Gerät prüfen

Siehe ANLEITUNG, Abschnitt «Öffentlicher Bildschirm (Testliste)».
