# Bauauftrag: zenOS 0.1

## Ziel

Baue zenOS Version 0.1 vollständig, in einem Durchgang. Am Ende soll Zeno auf einem frisch installierten Ubuntu Server 26.04 LTS auf dem Raspberry Pi 5 mit diesen Schritten ein laufendes zenOS bekommen:

```
git clone https://github.com/Zenovs/zenOS.git ~/zenOS
cd ~/zenOS && ./scripts/install.sh
sudo reboot
```

Danach testet er es mit der Testliste in `ANLEITUNG.md`.

## Rahmen

- Du arbeitest direkt auf dem Test-Pi (Ubuntu Server 26.04 LTS, arm64), im Repo `~/zenOS`, auf dem Branch `dev`.
- `MANIFEST.md` und `CLAUDE.md` gelten weiter. Dieser Auftrag ergänzt sie. Bei einem Widerspruch gewinnt das Manifest.
- Arbeite selbstständig durch. Frag Zeno nur bei den Punkten unter «Nur nach Rückfrage» oder bei einem echten Blocker.
- Halte den Fortschritt in `docs/baufortschritt.md` fest. Endet eine Sitzung, muss eine neue Sitzung dort nahtlos weitermachen können.
- Committe pro Modul auf `dev` und pushe nach jedem Modul. Die Claude-Attribution in den Commits bleibt drin.

## Freigegeben auf dem Test-Pi

- Pakete aus den Ubuntu-Paketquellen installieren.
- Dateien schreiben unter `/opt/zenos`, `/etc/xdg`, `/etc/greetd`, `/etc/opt/chrome/policies/managed`, `/usr/local/bin`, `/usr/local/share/fonts`, `/var/log/zenos`, `~/.config` und `~/.local`.
- systemd-Dienste von zenOS anlegen, starten und neu starten.
- `scripts/install.sh` beliebig oft ausführen.

## Nur nach Rückfrage bei Zeno

- SSH-Konfiguration, Firewall aktivieren, Netzwerk umstellen (zum Beispiel von netplan auf NetworkManager).
- Benutzer, Passwörter, sudo-Regeln.
- Bootloader, Firmware, Festplattenverschlüsselung.
- Neustart des Pi.

Solange SSH läuft, ist alles reparierbar. Tu nichts, was die SSH-Verbindung trennen kann.

## Umfang Version 0.1

Baue die Module in dieser Reihenfolge. Die Details stehen in `docs/`.

**M1 · Installer und zen-Werkzeug**
- `scripts/install.sh` ist idempotent und in Module aufgeteilt (`scripts/module/*.sh`). Das Log landet unter `/var/log/zenos/install.log`.
- Der Schalter `--image` baut ohne proprietäre Apps und ohne Benutzerdaten, für den Image-Bau.
- Der Code liegt als Checkout unter `/opt/zenos`. `~/.config/quickshell` verweist auf `/opt/zenos/shell`.
- `zen` unter `/usr/local/bin` mit den Befehlen `update`, `rollback <tag>`, `doctor`, `version` und `lock`. `zen doctor` erstellt einen Prüfbericht ohne Geheimnisse.

**M2 · Basis und Sitzung**
- Pakete: labwc, Quickshell, kitty, fish, greetd, PipeWire mit WirePlumber, xdg-desktop-portal-wlr, grim, slurp, wl-clipboard, swayidle, kanshi.
- Quickshell kommt aus den Paketquellen. Fehlt es dort oder ist es zu alt, baust du es aus dem Quellcode, mit einer fest eingetragenen Version.
- Die Schriften Geist, Geist Mono und Instrument Serif kommen aus den offiziellen Quellen, mit dem OFL-Lizenztext unter `assets/fonts/`.
- Der Login läuft über greetd mit einem Quickshell-Greeter im zenOS-Look. Kein Autologin.

**M3 · Design-Tokens und Theme**
- `shell/theme/tokens.json` wird zum QML-Singleton `Theme`. Ausserhalb davon stehen keine Hex-Werte im QML.
- Hell und dunkel wechseln mit einem Schalter. Quickshell, GTK (`color-scheme`), Qt, kitty, Chrome und VS Code folgen.

**M4 · Leiste** nach `docs/design.md` und dem Screen «Heute» aus Entwurf 2.

**M5 · Befehlsfeld**
- Apps aus den `.desktop`-Dateien starten, rechnen, Dateien im Home-Ordner suchen, Modus und Zustand wechseln.
- Werkzeuge: Screenshot eines Bereichs (in die Zwischenablage und nach `~/Bilder/Screenshots`) und Farbpipette.

**M6 · Mitteilungen**
- Quickshell ist der Benachrichtigungsdienst.
- Die Bündelung richtet sich nach dem aktiven Zustand. Die nächste Zustellung steht in der Leiste.

**M7 · Sperrbildschirm**
- `ext-session-lock` mit PAM.
- Sperre bei Inaktivität, bei Standby und mit `Super+L`.
- 1Password sperrt sich mit, sobald es installiert ist.

**M8 · Modi und Zustände**
- Modell nach `docs/konfiguration.md`.
- Umschalter in Leiste und Befehlsfeld, Editor «Modi & Zustände» in den Einstellungen.
- Vorlagen Fokus und Sitzung. Sitzung startet automatisch bei Bildschirmfreigabe (Screencast über xdg-desktop-portal erkennen).
- Die Leitplanken stehen im Code, nicht in der Konfiguration.

**M9 · Raster und Bildschirme**
- labwc-Regionen werden aus `raster/*.json` erzeugt.
- Tastenkürzel nach `docs/funktionen.md`, Bildschirm-Profile mit kanshi.

**M10 · Terminal**
- kitty: Ctrl+C mit `copy_and_clear_or_interrupt`, Ctrl+V fügt ein, dazu die Super-Kürzel, Theme aus den Tokens.
- fish mit Eingabezeile und Statuszeile pro Befehl.
- `?` erklärt Befehle über lokale tldr-Seiten. Bei gefährlichen Befehlen erscheint eine Warnung mit «Abbrechen» als Vorauswahl.
- eza, bat, zoxide und fzf sind installiert.

**M11 · Sicherheit**
- unattended-upgrades, Chrome-Richtlinien nach `docs/sicherheit.md`, gitleaks als Pre-Commit-Hook.
- ufw wird vorbereitet, aber erst nach Rückfrage aktiviert. SSH aus dem lokalen Netz muss vorher erlaubt sein.

**M12 · Erster Start**
- Einrichtung nach dem Screen «Erster Start».
- Danach, mit ausdrücklicher Zustimmung: Chrome (arm64-Paket), VS Code (Paketquelle von Microsoft) und 1Password (arm64-Archiv, SSH-Agent aktivieren) installieren.
- coremail und Nubix installieren, falls es ARM-Builds gibt. Sonst als offenen Punkt melden.
- Web-Apps legt Zeno selbst in den Einstellungen an. Sie stehen nicht im Repo.

**M13 · Argon ONE**
- Lüfterkurve und Power-Button als Dienst, orientiert am offiziellen Argon-Skript für den Pi 5.
- Die Temperatur erscheint in der Leiste.

**M14 · Image-Workflow**
- `.github/workflows/image.yml` nach `docs/image-und-releases.md`. Er läuft nur bei Tags `v*`.

**M15 · Abschluss**
- Doku aktualisieren und die Testliste in `ANLEITUNG.md` an den echten Stand anpassen.
- `CHANGELOG.md` anlegen.
- Tag `v0.1.0-rc1` setzen und pushen. Noch kein Release.

## Nicht im Umfang

Alles unter «Danach» und «Später» in `ROADMAP.md`.

## Selbsttests nach jedem Modul

- `shellcheck` für alle Skripte, `qmllint` für QML (falls verfügbar), JSON-Dateien gegen ihr Schema prüfen.
- `scripts/install.sh` zweimal hintereinander ausführen. Der zweite Lauf ändert nichts und meldet keine Fehler.
- Oberfläche prüfen:
  - Läuft eine grafische Sitzung, einen Screenshot mit `grim` aufnehmen, mit `XDG_RUNTIME_DIR` und `WAYLAND_DISPLAY` der Sitzung, und mit `docs/design.md` vergleichen.
  - Sonst labwc ohne Bildschirm starten (`WLR_BACKENDS=headless`), Quickshell darin, und dort den Screenshot machen.
  - Geht beides nicht, notieren, was Zeno am Bildschirm prüfen muss.
- `gitleaks detect` muss sauber sein.

Was ein Selbsttest findet, wird behoben, bevor das nächste Modul beginnt.

## Sonderfälle

- **sudo:** Während des Baus gibt es die temporäre Regel `/etc/sudoers.d/zenos-bau`. Ändere sie nie. `zen doctor` warnt, solange sie existiert.
- **Fehlende arm64-Pakete:** nicht blockieren. Ersatz wählen oder als offenen Punkt notieren und weiterbauen.
- **Unklare Designdetails:** Entwurf 2 und `docs/design.md` sind massgeblich. Wo beides nichts sagt, entscheide nach dem Manifest und notiere die Entscheidung.

## Fertig heisst

- Alle Module in `docs/baufortschritt.md` sind abgehakt oder als offener Punkt mit Grund markiert.
- Auf dem Test-Pi läuft `scripts/install.sh` fehlerfrei, und `zen doctor` meldet keine Fehler.
- Tag `v0.1.0-rc1` ist gesetzt und gepusht.
- Zeno bekommt einen kurzen Schlussbericht:
  - was fertig ist
  - was offen ist
  - dass er jetzt neu starten und mit der Testliste beginnen kann
  - dass er die sudo-Regel nach der Testphase löschen soll
