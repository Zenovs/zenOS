# scripts

| Pfad | Zweck |
|---|---|
| `install.sh` | installiert zenOS, idempotent, darf beliebig oft laufen |
| `lib/gemeinsam.sh` | Hilfsfunktionen für install.sh, Module und zen (API im Kopf der Datei) |
| `lib/firewall.sh` | gemeinsame Teile der Firewall für `zen firewall`, `zen doctor` und `bin/zenos-firewall` |
| `lib/aufraeumen.sh` | gemeinsame Teile für `module/22-aufraeumen.sh` und `zen doctor` (snapd, landscape-common) |
| `lib/sensible-pfade` | Pfade, die `release-signieren.sh` gesondert zeigt: Rückfrage-Pfade (Firewall, Netz, Boot), Anmeldung, Vertrauen |
| `module/NN-name.sh` | Installationsschritte, laufen in Namensreihenfolge |
| `pakete/<modul>.txt` | apt-Pakete je Modul (ein Paket pro Zeile, `#` Kommentar) |
| `zen` | Werkzeug `zen`, `/usr/local/bin/zen` verweist darauf |
| `zen.d/<befehl>.sh` | je ein Unterbefehl von zen |
| `doctor.d/NN-name.sh` | Prüfungen für `zen doctor` |
| `bin/zenos-*` | Hilfsprogramme (bash oder python3, ausführbar) |
| `pruefen.sh` | Selbsttest des Repos (Linux, nicht auf dem Mac) |
| `release-signieren.sh` | signiert ein Release oder einen Tag `vertrauen/NNNN` mit 1Password (Mac, bash 3.2) |
| `bin/zenos-kanal` | signierter Kanal auf dem Gerät: holen (ohne Rechte), prüfen und bereitstellen (root, ohne Netz), installieren mit Gesundheitsprüfung und Rückweg, nachstart, Status, Anker, Zeitpunkt, `jetzt` und `zustimmen` für die Einstellungen; Kern von `zen update` und `zen rollback` |
| `bin/zenos-kanal-bedienen` | Updates aus den Einstellungen (root über pkexec, polkit `org.zenos.kanal.*`): `pruefen`, `installieren`, `zustimmen OBJEKT` starten die Units des Kanals, `zeitpunkt …` setzt den Zeitpunkt; nur feste Wörter, Journal `-t zenos-kanal-bedienen` |

## install.sh

```
./scripts/install.sh [--image] [--nur-benutzer] [--nur-code] [--ruhig]
```

- Läuft als normaler Benutzer und holt sich Root-Rechte mit `sudo` für die Systemteile. Mit
  `sudo ./scripts/install.sh` aufgerufen, läuft es als der aufrufende Benutzer weiter. Als root ohne
  sudo (chroot) gibt es keine Benutzerteile.
- `--image`: für den Image-Bau im chroot. Keine Benutzerteile, kein Zugriff auf `~`, Dienste werden nur
  aktiviert, nie gestartet. `ZENOS_KANAL=<kanal>` legt den Kanal beim ersten Mal fest (`stabil`, `vorschau` oder
  `dev`, `main` gilt als `stabil`; der Image-Bau setzt `dev`, solange es keine signierten Releases gibt).
- `--nur-benutzer`: nur die Benutzerteile, ohne sudo. Läuft auch beim Sitzungsstart (mit `--ruhig`). Ohne
  `--ruhig` (`zen update`, `zen benutzer`) startet es die Oberfläche neu, wenn sich QML geändert hat.
- `--nur-code`: nur als root, nur Modul 10-code (Code nach `/opt/zenos`), ohne Netz. Für
  `zenos-kanal-nachstart.service` nach einem Abbruch.
- `ZENOS_KANAL_LAUF=1` setzt zenos-kanal, wenn es install.sh aus einer Bereitstellung startet. Ohne die Variable
  gilt ein Lauf als «von Hand»: install.sh wartet über sudo auf die Kanal-Sperre und trägt darunter seine PID in
  `/run/zenos-sperre/hand` ein (nur root; solange der Prozess läuft, installiert der Kanal nichts; am Ende entfernt
  es den Vermerk). Aus einem anderen Checkout markiert 10-code den Stand als angehalten; jeder Lauf von Hand erledigt
  eine unterbrochene Kanal-Installation (`laeuft.json`).
- Sperre: Läufe als root (Kanal, `--nur-code`) nehmen `/run/zenos-sperre/install.lock` (Ordner nur für root, 0700),
  Läufe als Benutzer und das Image `/run/lock/zenos-install.lock`. Wird sie in 15 Minuten nicht frei, endet install.sh
  mit Exit 75, ohne etwas begonnen zu haben (zenos-kanal zählt den Versuch dann nicht).
- `--ruhig`: im Terminal nur Warnungen und Fehler, alles andere ins Log.
- Log: `/var/log/zenos/install.log` (gehört dem Benutzer, Gruppe `adm`, 0640). Kann `--nur-benutzer`
  dort nicht schreiben (frisches Image), landet das Log in `~/.local/state/zenos/install.log`. Jeder
  Lauf endet im Log mit einer Zeile `== Ende <datum> · <modus> · ok|abbruch · N Änderungen · N Warnungen`;
  auch ein Abbruch durch ein Signal (HUP, INT, PIPE, TERM) steht dort als `abbruch (Exit 128+N)`. Fehlt nach
  `== Beginn` die Ende-Zeile (SIGKILL, Stromausfall), meldet `zen doctor` das.
- Ohne `HOME` (etwa in einem systemd-Dienst ohne `User=`) läuft install.sh als root ebenso durch.
- Am Ende: `zenOS <version> installiert · N Änderungen`. Der zweite Lauf meldet `0 Änderungen`.
- Zwei Durchgänge: erst alle `modul_system`, dann alle `modul_benutzer`. Danach `systemctl daemon-reload`,
  falls sich Units geändert haben.
- Fehler brechen sofort ab, mit Modul, Datei, Zeile und Befehl. Es läuft nie mehr als ein install.sh
  gleichzeitig (Sperre `/run/lock/zenos-install.lock`).
- `/opt/zenos` (Modul `10-code`): Läuft install.sh aus einem anderen Checkout, bekommt `/opt/zenos` genau
  dessen Arbeitsstand (Commit, Branch, Tags, origin, nicht committete und neue Dateien, gelöschte weg).
  Läuft es aus `/opt/zenos` selbst (`zen update`), wird nichts synchronisiert. Eine Umgebungsvariable
  `ZENOS_CODE` beeinflusst install.sh nicht.

## Module

```bash
#!/usr/bin/env bash
# NN-name: <eine Zeile, was das Modul installiert>
# shellcheck shell=bash

modul_system() {    # optional; mit Root-Rechten über $SUDO bzw. als root
  pakete_sicherstellen paket1 paket2
  datei_installieren "$ZENOS_CODE/system/x/datei" /etc/xdg/zenos/datei
}

modul_benutzer() {  # optional; als Benutzer, ohne sudo, nie im --image-Modus
  verknuepfen "$ZENOS_CODE/system/x/datei" "$ZENOS_HOME/.config/x/datei"
}
```

- install.sh sourct jede Datei, ruft die Funktion auf und entfernt danach alle Funktionen der Datei.
  Weitere Funktionen nur mit Präfix `_<name>_` (für `25-quickshell.sh` also `_quickshell_*`), sonst
  gibt es eine Warnung.
- Jede echte Änderung läuft über die Hilfsfunktionen oder ruft `aenderung TEXT`, sonst stimmt der Zähler
  nicht. Die Zähler sind subshell-fest (auch `printf … | datei_schreiben …` zählt).
- Root-Funktionen sind nur in `modul_system` erlaubt, Benutzerfunktionen nur in `modul_benutzer`; ein
  Verstoss bricht mit Meldung ab.
- Pakete: `pakete_sicherstellen` installiert nur Fehlendes, macht höchstens einmal pro Lauf
  `apt-get update` und verhindert mit einem temporären `/usr/sbin/policy-rc.d`, dass Pakete ihre Dienste
  sofort starten (greetd!). Aktiviert werden sie trotzdem. Erlaubt bleibt nur, den laufenden System-Bus
  neu zu laden (`invoke-rc.d dbus reload`, etwa im postinst von polkitd). Die Richtlinie gilt nur, solange
  das eigene apt-get die dpkg-Sperre hält (apt setzt sie über `DPkg::Pre-Invoke` ein), nie für ein
  gleichzeitig laufendes unattended-upgrade. Wer einen Dienst sofort braucht, ruft
  `dienst_neustarten_falls` (nur mit laufendem systemd, nie im Image-Modus, nur nach einer Änderung im
  selben Modul). Nach neuen Paketquellen `apt_quellen_geaendert` aufrufen.
- Läuft gerade ein anderer Paketvorgang (apt-daily, unattended-upgrades, apt in einem anderen Terminal),
  wartet `pakete_sicherstellen` darauf, höchstens 20 Minuten, mit einer Meldung. Eigene apt-Aufrufe
  ausserhalb von `pakete_sicherstellen` laufen über `apt_ausfuehren ARG…` (wartet, wiederholt nach einer
  fremden Sperre); `apt_warten` wartet nur.
- Die ganze API mit allen Parametern steht im Kopf von `lib/gemeinsam.sh`.

## zen

| Befehl | Modul | Was es tut |
|---|---|---|
| `zen update` | M1 | über den Kanal holen, prüfen, bei Bedarf «ja», installieren, Gesundheit prüfen, sonst zurück |
| `zen rollback <tag>` | M1 | über den Kanal zu einem Tag zurück (signiert, sonst nur mit «ja») |
| `zen kanal [status\|pruefen\|anker\|zeitpunkt]` | Kanal | signierter Kanal: Stand mit Fingerabdrücken, letzte Installation; `sudo zen kanal pruefen` holt und prüft (installiert nichts); `sudo zen kanal anker ORDNER` setzt den Anker von Hand; `zen kanal zeitpunkt` zeigt, `sudo zen kanal zeitpunkt sperre\|fenster VON BIS\|jederzeit\|hand` setzt, wann geprüfte Updates automatisch kommen (dasselbe in Einstellungen › System › Updates) |
| `zen doctor [--kurz]` | M1 | Prüfbericht ohne Geheimnisse, Exit 1 bei Fehlern |
| `zen version` | M1 | zenOS-Version, Basis (Ubuntu), Kanal, Commit, letzte Installation über den Kanal, Quickshell, labwc, Architektur |
| `zen benutzer [--ruhig]` | M1 | nur die Benutzerteile einrichten (`install.sh --nur-benutzer`) |
| `zen hilfe [befehl]` | M1 | Übersicht oder Hilfe zu einem Befehl |
| `zen lock` | M7 | Sitzung sperren, auch per SSH (Notfall-Sperre, falls die Oberfläche nicht antwortet) |
| `zen thema [hell\|dunkel\|tageszeit\|wechseln]` | M3 | Erscheinungsbild setzen oder anzeigen |
| `zen firewall [status\|aktivieren]` | M11 | ufw anzeigen; `aktivieren` erst nach Prüfung der SSH-Regeln und der Eingabe «aktivieren» |
| `zen apps [installieren\|aktualisieren\|status] [app …]` | M12 | Chrome, VS Code, 1Password, CLI, coremail aus offiziellen Quellen, mit Rückfrage |
| `zen bootsplash [status\|aktivieren\|deaktivieren]` | Bootsplash | Plymouth-Stand anzeigen; `aktivieren` schaltet nach der Eingabe «aktivieren» ein, `deaktivieren` nimmt es zurück (`docs/module/bootsplash.md`) |
| `zen netzwerk [status\|umstellen\|zurueck]` | Netz | Netz auf NetworkManager umstellen (WLAN-Menü) nach Plan und Eingabe «umstellen», wirksam nach dem Neustart; `zurueck` stellt die Sicherung wieder her (`docs/module/netzwerk.md`) |
| `zen akku [status\|freigeben\|sperren]` | M13 | Akku des Argon ONE UP anzeigen; `freigeben` erlaubt zenos-argon nach der Eingabe «freigeben», Argons Akkuprofil in den Messchip zu schreiben, `sperren` nimmt es zurück |
| `zen luefter [status\|auto\|1\|2\|3\|4]` | M13 | Lüfter anzeigen (ohne sudo) oder einstellen: automatisch oder Mindeststufe, mit sudo über `bin/zenos-luefter`; dasselbe im System-Menü |

- `zen <befehl>` sourct `zen.d/<befehl>.sh` und ruft `befehl_<befehl>` auf (Bindestriche werden zu
  Unterstrichen). Unbekannter Befehl: Hilfe und Exit 2.
- Jede `zen.d`-Datei beginnt mit `# hilfe: <befehl> [argumente] – <kurz>`; weitere Kommentarzeilen direkt
  darunter erscheinen bei `zen hilfe <befehl>`.
- Den Unterbefehlen stehen `lib/gemeinsam.sh` sowie `zen_git` (lesend in /opt/zenos), `zen_git_root`
  (schreibend als root), `zen_fehler`, `zen_warnung`, `zen_hinweis`, `$SUDO` und `$ZENOS_CODE` (immer
  `/opt/zenos`) zur Verfügung.
- `zen update` und `zen rollback <tag>` starten `sudo /usr/local/libexec/zenos/zenos-kanal update` bzw. `rollback
  <tag>`. Das schreibt einen Wunsch, startet `zenos-kanal-holen` und `zenos-kanal-pruefen`, fragt bei Bedarf nach «ja»
  (gebunden an die gezeigte Commit- bzw. Objekt-ID), startet dann `zenos-kanal-installieren` und zeigt dessen Journal,
  danach prüft es den Stand neu. Eine eigene Sperre (`/run/zenos-sperre/bedienung.lock`, nur root) verhindert zwei
  gleichzeitige Aufrufe. Nach einer Installation oder einem Rückweg richtet zen die Benutzerteile ein (`install.sh
  --nur-benutzer`). Exit: 0 installiert oder aktuell, 3 abgelehnt, 4 gescheitert und zurück, 5 kaputt, 10 wartet
  (Zustimmung, Platz, Netz), 75 läuft schon (auch ein `install.sh` von Hand). Fehlt zenos-kanal, verweist zen auf den
  Notweg (ANLEITUNG F).

## zen doctor

Jede Datei `doctor.d/NN-name.sh` definiert `pruefe_<name>` und berichtet mit `abschnitt TITEL`, `ok TEXT`,
`hinweis TEXT`, `warnung TEXT` und `fehler TEXT`. Jede Datei läuft in einer eigenen Subshell ohne
`set -e`/`set -u`; ein Absturz erscheint als Fehler und stoppt die anderen Prüfungen nicht. Am Ende steht
`N Fehler · N Warnungen · N Hinweise`, Exit 1 bei Fehlern. `zen doctor --kurz` zeigt nur diese Zeile.

Nie ausgeben: Umgebungsvariablen, Tokens, Schlüssel, Passwörter, IP-/MAC-Adressen, Hostnamen, SSIDs,
Benutzernamen, Inhalte aus `~/.config/zenos` (nur Anzahl und Gültigkeit). Das Home erscheint als `~`.
Bekannte offene Punkte sind Hinweise, keine Fehler.

## release-signieren.sh

```
scripts/release-signieren.sh vX.Y.Z[-rcN]
scripts/release-signieren.sh --vertrauen
```

Läuft auf dem Mac (bash 3.2) in einem eigenen Terminal-Tab ohne Claude Code und signiert über `op-ssh-sign` von
1Password mit Touch ID; der öffentliche Schlüssel kommt aus `system/vertrauen` des signierten Stands. Prüft sauberen
Baum, HEAD auf origin, Tag neu und höher, CI per `gh` und den Anker, zeigt Commits und sensible Pfade
(`lib/sensible-pfade`), signiert nach «ja», prüft den Tag mit `git verify-tag` gegen den Anker und pusht nach einem
zweiten «ja» nur den Tag. `--vertrauen` signiert die Serie aus `system/vertrauen/serie` als `vertrauen/NNNN` mit dem
Wurzel-Schlüssel. Ablauf und Regeln: `docs/image-und-releases.md`, «Signierte Releases». Nur für Tests:
`ZENOS_TEST_SIGNIERPROGRAMM` (z. B. `ssh-keygen` mit einem Wegwerf-Schlüssel im ssh-agent) statt op-ssh-sign.

## zenos-kanal

`bin/zenos-kanal` (Python 3, nur Standardbibliothek, `python3 -I`) läuft als root-eigene Kopie
`/usr/local/libexec/zenos/zenos-kanal` (Modul `14-kanal`): `holen-intern` in `zenos-kanal-holen.service`
(DynamicUser, Sandbox, nur Netz), `pruefen` in `zenos-kanal-pruefen.service` (root, PrivateNetwork), `status` und
`anker` für alle, `installieren` in `zenos-kanal-installieren.service`, `nachstart` vor greetd, `selbsttest` als Teil
der Gesundheitsprüfung (mit Probelauf in einem Wegwerf-Zustand). Die vorige Fassung bleibt als `zenos-kanal.vorher`.
Prozesse nur mit Argumentlisten, jedes git mit leerer Umgebung und gehärteten Einstellungen. Den Anker legt
`12-vertrauen` an; mit Schlüsseln füllt es ihn nur im Image, sonst `sudo zen kanal anker ORDNER`. Regeln, Zustände und
Exit-Codes: `docs/image-und-releases.md`, «Auf dem Gerät: zenos-kanal». Tests: `test/einheiten/kanal.test.py`,
`test/einheiten/kanal-installieren.test.py`, Ende-zu-Ende `test/container/kanal-e2e.sh`.

## pruefen.sh

```
./scripts/pruefen.sh [--ausfuehrlich] [shellcheck|python|json|hex|shc|namen|einheiten|qmllint|gitleaks|start …]
```

Läuft im Testcontainer, auf dem Pi oder in CI (braucht shellcheck, python3-jsonschema, gitleaks und
optional qmllint aus `qt6-declarative-dev-tools`, nodejs und fish für die Einheitentests). Die Regeln und
Namenskonventionen für JSON-Schemas stehen im Kopf der Datei. Exit 1, wenn ein Teil Fehler findet.

- `einheiten`: Tests unter `test/einheiten/`: `*.test.mjs` mit `node --test`, `*.test.py` mit python3,
  `*.test.fish` mit fish. Fehlt node oder fish, werden deren Tests mit Hinweis übersprungen.
- `qmllint`: Ohne Quickshell-Module (`/usr/local/lib/qt6/qml/Quickshell`, etwa in CI) zählen nur echte
  Syntaxfehler; alle anderen Befunde sind dort Folgefehler der unbekannten Quickshell-Typen und nur
  Warnungen. Doppelte ids sind immer Warnungen (echte Doppelungen findet der Teil `start`).
- `start`: startet die Oberfläche in einer abgeschotteten Testsitzung (nur mit labwc und Quickshell).
