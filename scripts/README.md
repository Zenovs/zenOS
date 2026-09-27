# scripts

| Pfad | Zweck |
|---|---|
| `install.sh` | installiert zenOS, idempotent, darf beliebig oft laufen |
| `lib/gemeinsam.sh` | Hilfsfunktionen für install.sh, Module und zen (API im Kopf der Datei) |
| `module/NN-name.sh` | Installationsschritte, laufen in Namensreihenfolge |
| `pakete/<modul>.txt` | apt-Pakete je Modul (ein Paket pro Zeile, `#` Kommentar) |
| `zen` | Werkzeug `zen`, `/usr/local/bin/zen` verweist darauf |
| `zen.d/<befehl>.sh` | je ein Unterbefehl von zen |
| `doctor.d/NN-name.sh` | Prüfungen für `zen doctor` |
| `bin/zenos-*` | Hilfsprogramme (bash oder python3, ausführbar) |
| `pruefen.sh` | Selbsttest des Repos (Linux, nicht auf dem Mac) |

## install.sh

```
./scripts/install.sh [--image] [--nur-benutzer] [--ruhig]
```

- Läuft als normaler Benutzer und holt sich Root-Rechte mit `sudo` für die Systemteile. Mit
  `sudo ./scripts/install.sh` aufgerufen, läuft es als der aufrufende Benutzer weiter. Als root ohne
  sudo (chroot) gibt es keine Benutzerteile.
- `--image`: für den Image-Bau im chroot. Keine Benutzerteile, kein Zugriff auf `~`, Dienste werden nur
  aktiviert, nie gestartet. Mit `ZENOS_KANAL=main` bekommt ein frisches Image den Kanal `main`.
- `--nur-benutzer`: nur die Benutzerteile, ohne sudo. Läuft auch beim Sitzungsstart (mit `--ruhig`).
- `--ruhig`: im Terminal nur Warnungen und Fehler, alles andere ins Log.
- Log: `/var/log/zenos/install.log` (gehört dem Benutzer, Gruppe `adm`, 0640). Kann `--nur-benutzer`
  dort nicht schreiben (frisches Image), landet das Log in `~/.local/state/zenos/install.log`. Jeder
  Lauf endet im Log mit einer Zeile `== Ende <datum> · <modus> · ok|abbruch · N Änderungen · N Warnungen`.
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
  sofort starten (greetd!). Aktiviert werden sie trotzdem. Wer einen Dienst sofort braucht, ruft
  `dienst_neustarten_falls` (nur mit laufendem systemd, nie im Image-Modus, nur nach einer Änderung im
  selben Modul). Nach neuen Paketquellen `apt_quellen_geaendert` aufrufen.
- Die ganze API mit allen Parametern steht im Kopf von `lib/gemeinsam.sh`.

## zen

```
zen update | rollback <tag> | doctor [--kurz] | version | benutzer [--ruhig] | hilfe [befehl] | …
```

- `zen <befehl>` sourct `zen.d/<befehl>.sh` und ruft `befehl_<befehl>` auf (Bindestriche werden zu
  Unterstrichen). Unbekannter Befehl: Hilfe und Exit 2.
- Jede `zen.d`-Datei beginnt mit `# hilfe: <befehl> [argumente] – <kurz>`; weitere Kommentarzeilen direkt
  darunter erscheinen bei `zen hilfe <befehl>`.
- Den Unterbefehlen stehen `lib/gemeinsam.sh` sowie `zen_git` (lesend in /opt/zenos), `zen_git_root`
  (schreibend als root), `zen_fehler`, `zen_hinweis`, `$SUDO` und `$ZENOS_CODE` (immer `/opt/zenos`) zur
  Verfügung.
- `zen update`: `git fetch --tags --prune` in /opt/zenos, Checkout hart auf `origin/<kanal>` (Kanal aus
  `/etc/xdg/zenos/kanal`, Standard `dev`), `clean -fd`, dann install.sh. Zeigt alt → neu.
- `zen rollback <tag>`: Tags holen, `checkout --detach <tag>`, install.sh. Das nächste `zen update` kehrt
  auf den Kanal zurück.

## zen doctor

Jede Datei `doctor.d/NN-name.sh` definiert `pruefe_<name>` und berichtet mit `abschnitt TITEL`, `ok TEXT`,
`hinweis TEXT`, `warnung TEXT` und `fehler TEXT`. Jede Datei läuft in einer eigenen Subshell ohne
`set -e`/`set -u`; ein Absturz erscheint als Fehler und stoppt die anderen Prüfungen nicht. Am Ende steht
`N Fehler · N Warnungen · N Hinweise`, Exit 1 bei Fehlern. `zen doctor --kurz` zeigt nur diese Zeile.

Nie ausgeben: Umgebungsvariablen, Tokens, Schlüssel, Passwörter, IP-/MAC-Adressen, Hostnamen, SSIDs,
Benutzernamen, Inhalte aus `~/.config/zenos` (nur Anzahl und Gültigkeit). Das Home erscheint als `~`.
Bekannte offene Punkte sind Hinweise, keine Fehler.

## pruefen.sh

```
./scripts/pruefen.sh [--ausfuehrlich] [shellcheck|python|json|hex|shc|namen|qmllint|gitleaks …]
```

Läuft im Testcontainer, auf dem Pi oder in CI (braucht shellcheck, python3-jsonschema, gitleaks und
optional qmllint aus `qt6-declarative-dev-tools`). Die Regeln und Namenskonventionen für JSON-Schemas
stehen im Kopf der Datei. Exit 1, wenn ein Teil Fehler findet.
