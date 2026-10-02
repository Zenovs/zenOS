# Ablage · ein Ordner und der Dateimanager

Wunsch: ein Ordner, in dem eigene Dateien liegen, ohne vorgegebene Struktur, und oben in der Leiste neben dem
Raster («4er») ein Knopf, der ihn im Dateimanager öffnet. Das Manifest sagt «kein eigener Dateimanager»: zenOS baut
keinen, sondern nimmt einen aus Ubuntu (Thunar).

## Was gebaut ist

- **`~/Ablage`** (Modul `scripts/module/48-ablage.sh`, Benutzerteil): legt den Ordner an, wenn er fehlt, mit 0700.
  Keine Unterordner. Danach bleibt er, wie er ist: nie löschen, nie verschieben, Rechte nicht zurücksetzen. Ein
  Verweis auf einen Ordner ist erlaubt; liegt dort eine Datei, bleibt sie mit einer Warnung liegen.
- **Benutzerordner** `~/.config/user-dirs.dirs`: Schreibtisch, Downloads, Dokumente, Bilder, Musik und Videos
  zeigen auf `"$HOME/Ablage"`, Vorlagen und Öffentlich auf `"$HOME/"` (abgeschaltet). Dazu
  `~/.config/user-dirs.conf` mit `enabled=False`. Beide schreibt zenOS nur, wenn sie fehlen oder ihre erste Zeile
  die zenOS-Marke ist; sonst steht ein Hinweis im Log. Einzelheiten in `docs/konfiguration.md`.
- **Thunar** (`scripts/pakete/ablage.txt`, kommt ins Image) und **Standard für Ordner**:
  `system/xdg/labwc-mimeapps.list` → `/etc/xdg/labwc-mimeapps.list` mit `inode/directory=thunar.desktop`.
- **«Terminal hier öffnen» in Thunar:** `system/thunar/uca.xml` → `~/.config/Thunar/uca.xml` (Benutzerteil), eine
  Aktion mit `kitty --directory %f`. Sie ersetzt die Beispiel-Aktion aus `/etc/xdg/Thunar/uca.xml`
  (`exo-open --launch TerminalEmulator`): Die braucht `xfce4-mime-helper` aus xfce4-settings (fast 1 MB, Einstellungs-
  Apps und xfsettingsd), ohne das Paket zeigt Thunar nur einen Fehler. Wie bei `user-dirs.dirs` schreibt zenOS die
  Datei nur, wenn sie fehlt oder die erste Zeile die zenOS-Marke ist. Legst du in Thunar eigene Aktionen an,
  schreibt Thunar die Datei selbst neu, und zenOS lässt sie danach ohne Hinweis in Ruhe. Startet Thunar, bevor
  zenOS die Datei angelegt hat, kopiert Thunar die Beispiel-Aktion selbst dorthin (im Container gesehen); auf dem Pi
  kommt die Datei mit demselben `install.sh`-Lauf wie Thunar. `zen doctor` meldet den Fall. Abhilfe: ohne eigene
  Aktionen die Datei löschen und `zen benutzer`, sonst die Aktion in Thunar auf `kitty --directory %f` ändern.
- **Hilfsstarter ausgeblendet:** `system/applications/thunar-bulk-rename.desktop` und `thunar-settings.desktop` →
  `/usr/local/share/applications/` mit `Hidden=true`. Im Befehlsfeld und in der App-Übersicht steht nur noch
  «Thunar File Manager» (deutsch «Dateimanager Thunar»).
- **Leiste:** `LeistenKnopf` «Ablage öffnen» direkt rechts neben dem Raster-Knopf (`shell/leiste/LeistenInhalt.qml`),
  32 px breit, Symbol `ordner` 15 px, sichtbar wie der Raster-Knopf (nur bei Leiste `normal`).
- **Befehlsfeld:** Aktion «Ablage» (Symbol `ordner`; Wörter «ablage dateien ordner dokumente downloads explorer
  finder dateimanager thunar»).
- **Aktion** `Aktionen.ablageOeffnen()`: während Sperre und Einrichtung nichts, sonst `dateiOeffnen(Pfade.ablage)`,
  also `zenos-oeffnen -- ~/Ablage` (Argumentliste, eigene Einheit, `gio open`). Fehlt der Ordner, erscheint «Ablage
  nicht gefunden». `zenos-oeffnen` verhält sich wie bisher (nur die Kommentare sind neu): Ordner öffnet die
  Standard-App, ohne sie kitty.
- **`zen doctor`** (`scripts/doctor.d/48-ablage.sh`, Abschnitt «Ablage und Dateimanager»): Thunar, die Datei in
  `/etc/xdg`, Standard für Ordner in der labwc-Sitzung, ausgeblendete Starter, `~/Ablage`, Benutzerordner,
  «Terminal hier öffnen» in Thunar. Gibt keine absoluten Pfade aus (sie könnten den Benutzernamen enthalten).
- **Tests:** `test/einheiten/ablage.test.py` (19 Fälle: frisches Home, zweiter Lauf, vorhandene Ablage mit Inhalt
  und eigenen Rechten, Verweis, Datei statt Ordner, eigene und alte Fassungen, Verweis auf `user-dirs.dirs`,
  `xdg-user-dirs-update` mit fehlender Ablage, Vorlage und Fassungen von `uca.xml`, Doctor-Ausgaben).

## Dateimanager: Vergleich

Gemessen am 2.10.2026 im Container (Ubuntu 26.04 arm64, `apt-get install --no-install-recommends`, wie zenOS
installiert):

| | Nautilus | **Thunar** | PCManFM-Qt |
|---|---|---|---|
| Neue Pakete, Download, installiert | 125, 32,6 MB, 125 MB | **15, 2,4 MB, 14,7 MB** | 25, 2,2 MB, 17,8 MB |
| Hell/dunkel ohne Zutun | ja (libadwaita, `color-scheme`) | **ja, GTK3 über `gtk-theme` Adwaita/Adwaita-dark, das `zenos-thema` schon setzt (am Pi prüfen)** | nein: im Container blieb die Dateiansicht im Dunkeln hell, nur der Rahmen wechselte |
| Fensterrahmen unter labwc | eigene Kopfleiste (GTK4, clientseitig) | **Rahmen von labwc** (GTK3 ohne Kopfleiste fragt nach Server-Dekoration; am Pi prüfen) | Rahmen von labwc (im Container gesehen) |
| Hintergrunddienste | localsearch (Indexer über das Home), tinysparql, udisks2, gvfs | **keine; xfconfd beim ersten Start und `thunar.service` (`Thunar --daemon`) erst, wenn eine App über D-Bus «Im Ordner anzeigen» ruft; beide bleiben danach im Leerlauf** | keine |
| Deutsch | über Sprachpakete | **in `thunar-data` enthalten** | nur mit `pcmanfm-qt-l10n`, `libfm-qt6-l10n` |
| Netz | gvfs-backends, samba-libs | **nichts** | nichts |
| Sonstiges | bringt xdg-user-dirs mit (legt Desktop, Downloads … an) | Seitenleiste soll die Ablage als «Ablage» zeigen (Schreibtisch-Eintrag, am Pi prüfen) | im Container ohne Datei-Symbole; nennt `~/Ablage` «Desktop» |

**Wahl: Thunar.** Klein (rund 2,4 MB im Image), kein Indexer und kein Dienst im Hintergrund (Pi, Datenschutz),
folgt hell/dunkel über den Weg, den `zenos-thema` für GTK3 schon geht, Deutsch ist dabei, und labwc zeichnet den
Rahmen wie bei allen anderen Fenstern. Bilder lädt GTK über glycin in einer Sandbox, nicht im Prozess des
Dateimanagers. Nautilus fällt wegen Grösse, Indexer und eigener Kopfleiste weg, PCManFM-Qt wegen hell/dunkel und
fehlender Symbole.

## Entscheidungen

- **Standard für Ordner systemweit, nur in der zenOS-Sitzung:** `/etc/xdg/labwc-mimeapps.list` (GLib liest
  `<desktop>-mimeapps.list` nach `XDG_CURRENT_DESKTOP=labwc:wlroots`). Ohne diese Datei entscheidet die Reihenfolge
  im Cache: Im Container gewann mit PCManFM-Qt daneben PCManFM-Qt, und eine App wie VS Code (`code.desktop` meldet
  `inode/directory` an) hätte Ordner übernommen. Im Container geprüft: mit der Datei bleibt es Thunar, eine eigene
  Wahl in `~/.config/mimeapps.list` geht vor. Nicht im Benutzerteil, weil `~/.config/mimeapps.list` deine Wahl
  hält (und `zen apps` dort Chrome einträgt); eine Vorgabe von zenOS gehört eine Ebene darunter. Eine andere Sitzung
  (später GNOME auf dem Bürorechner) bleibt unberührt.
- **Hilfsstarter mit `Hidden=true` in `/usr/local/share/applications/`:** Nach der Desktop-Entry-Spezifikation
  heisst das «gelöscht» und überdeckt die Datei gleichen Namens in `/usr/share/applications/`, ohne das Paket
  anzufassen. Quickshell übernimmt das sofort (im Container geprüft). Umbenennen mehrerer Dateien und die
  Einstellungen bleiben in Thunar erreichbar.
- **0700 statt 0755:** Downloads und Dokumente sind persönlich, und ausser dir braucht kein Konto Zugriff (Ubuntu
  legt das Home schon mit 0750 an; 0700 schützt zusätzlich vor Systemkonten der eigenen Gruppe). Gleich wie
  `~/.config/zenos`. Nur beim Anlegen: Wer die Rechte selbst ändert, behält sie.
- **Vorlagen und Öffentlich zeigen nicht auf die Ablage** (Abweichung vom Auftrag «alle acht auf die Ablage»):
  Thunar liest den Vorlagen-Ordner bei jedem «Dokument erstellen» rekursiv ein (`thunar-action-manager.c`,
  `thunar_io_scan_directory(…, TRUE, …)`) und böte jede Datei der Ablage als Vorlage an. Zeigt der Eintrag aufs
  Home, nimmt Thunar `~/Templates`, findet nichts und zeigt «Keine Vorlagen» und «Leere Datei», ohne einen Ordner
  anzulegen. «Öffentlich» ist der Ordner, den Freigabe-Dienste ins Netz stellen; er zeigt nie auf deine Dateien.
  `"$HOME/"` ist bei xdg-user-dirs die übliche Art, einen Eintrag abzuschalten.
- **Kein Paket xdg-user-dirs:** Apps lesen `user-dirs.dirs` selbst (GLib, Qt, Chrome, Firefox). Ubuntu Server
  bringt das Paket nicht mit, Thunar empfiehlt es nur. Kommt es mit einer anderen App, startet es bei jeder
  Anmeldung `xdg-user-dirs-update` (Benutzereinheit vor `graphical-session-pre.target`). Im Container geprüft: ohne
  `user-dirs.dirs` legt es acht englische Ordner an (Desktop, Documents, Downloads …); mit der Datei von zenOS bleibt
  alles, solange die Ablage da ist; mit `enabled=False` bleibt es auch, wenn die Ablage gerade fehlt.
- **Marke statt Inhaltsvergleich:** zenOS erkennt seine Dateien an der ersten Zeile. So bleibt eine eigene Fassung
  (oder ein Verweis aus Dotfiles) unangetastet, und ein Update kann die eigene Fassung von zenOS erneuern.
- **Papierkorb ohne gvfs:** Entf verschiebt auch ohne gvfs in den Papierkorb (GLib, `~/.local/share/Trash`; im
  Container geprüft). Nur die Ansicht des Papierkorbs in Thunar fehlt. gvfs brächte 33 Pakete mit, darunter
  udisks2 als Systemdienst; deshalb vorerst nicht (offen).
- **Bildschirmfotos** bleiben in `~/Bilder/Screenshots` (`zenos-bildschirmfoto`, Vorgabe aus dem Bauauftrag).

## Im Container geprüft

- `install.sh`: erster Lauf installiert Thunar, legt `~/Ablage` (700), `user-dirs.dirs`, `user-dirs.conf`,
  `~/.config/Thunar/uca.xml`, `/etc/xdg/labwc-mimeapps.list` und die beiden Starter an; zweiter Lauf
  «0 Änderungen». Eine Fassung von `user-dirs.dirs` mit der Marke von zenOS wird beim nächsten Lauf erneuert.
- Beispiel-Aktion von Thunar: `exo-open --launch TerminalEmulator` findet kein `xfce4-mime-helper` und will einen
  Fehlerdialog zeigen, auch mit dem Paket xfce4-helpers (es bringt nur die Beschreibungen der Terminals mit).
  Deshalb die eigene Aktion mit kitty.
- Klick auf die Stelle des Knopfs, während die Einrichtung offen ist: Es startet nichts.
- `xdg-user-dir DOWNLOAD` (und DESKTOP, DOCUMENTS, PICTURES, MUSIC, VIDEOS) → `~/Ablage`; TEMPLATES und
  PUBLICSHARE → `~`.
- Sitzung wie auf dem Pi: Klick mit der Maus (wlrctl) auf den Knopf → `app-zenos-oeffnen-….scope`, darin
  `thunar ~/Ablage`. Befehlsfeld: «ablage» zeigt die Aktion «Ablage» zuoberst.
- Leiste, Befehlsfeld und App-Übersicht in hell und dunkel.
- **Grenze:** Thunar selbst lässt sich im Container nicht zeigen. gdk-pixbuf 2.44 lädt in Ubuntu 26.04 jedes Bild
  (auch PNG) über glycin in einer bwrap-Sandbox. Im Docker-Container scheitert bwrap am Loopback des eigenen
  Netz-Namespace («RTM_NEWADDR: Operation not permitted»), und GTK3 bricht beim ersten Symbol ab. Auf dem Pi ist
  das vorgesehen: Ubuntu bringt dafür AppArmor-Profile mit (`glycin.bwrap`, `glycin.loaders`,
  `bwrap-userns-restrict` im Paket apparmor). Fenster, hell/dunkel und Rahmen von Thunar deshalb erst am Pi.

## Am Pi prüfen

- Klick auf den Ordner rechts neben «4er»: Thunar öffnet `~/Ablage`, mit Symbolen, mit genau einer Titelzeile (von
  labwc). Ein zweiter Klick öffnet ein zweites Fenster.
- Hell/Dunkel umschalten: Thunar folgt, auch ein schon offenes Fenster.
- Befehlsfeld: «ablage», Enter öffnet die Ablage.
- Ein Download in Chrome landet in `~/Ablage` (neues Profil; ein Profil mit selbst gesetztem Download-Ordner
  behält ihn).
- Rechtsklick in der Ablage → «Dokument erstellen» zeigt «Keine Vorlagen» und «Leere Datei».
- Rechtsklick in der Ablage → «Terminal hier öffnen»: kitty startet in `~/Ablage`, ohne Fehlermeldung.
- Seitenleiste von Thunar: Der Eintrag für den Schreibtisch (er zeigt auf die Ablage) heisst «Ablage».
- Entf auf eine Testdatei: Sie landet in `~/.local/share/Trash/files`.
- Chrome «Im Ordner anzeigen» nach einem Download öffnet Thunar.
- Sprache: Thunar spricht Deutsch nur mit deutscher Locale (`locale` zeigt `LANG`); mit `C.UTF-8` ist es englisch.
- `zen doctor`, Abschnitt «Ablage und Dateimanager»: alles ok.
