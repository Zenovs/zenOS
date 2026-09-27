# Anleitung: zenOS bauen, installieren und testen

Vom Mac bis zum getesteten zenOS auf dem Pi. Führe die Befehle einzeln aus und schau nach jedem, ob er ohne Fehler durchlief.

**Voraussetzungen:**
- Raspberry Pi 5 mit mindestens 4 GB RAM (Claude Code braucht 4 GB)
- SD-Karte oder NVMe mit mindestens 32 GB
- Bildschirm und Tastatur am Pi
- Netzwerkkabel, empfohlen für den Bau
- Claude-Abo mit Claude Code

---

## A · Repo auf GitHub bringen (Mac)

**A1.** `zenos-repo.zip` aus dem Chat herunterladen.

**A2.** Den versehentlich angelegten Ordner wieder entfernen. Das klappt nur, wenn er leer ist; es kann also nichts verloren gehen:

```
rmdir ~/Dokumente/github/zenOS ~/Dokumente/github ~/Dokumente
```

**A3.** Den richtigen Zielordner anlegen. Der Finder zeigt `~/Documents` als «Dokumente» an:

```
mkdir -p ~/Documents/github/zenOS
```

**A4.** Das ZIP entpacken:

```
unzip ~/Downloads/zenos-repo.zip -d /tmp/zenos-import
```

Hat Safari das ZIP schon selbst entpackt, liegt in Downloads ein Ordner `zenos`. Dann überspringe A4 und nimm in A5 `~/Downloads/zenos/.` als Quelle.

**A5.** Den Inhalt in den Zielordner kopieren, inklusive der versteckten Dateien:

```
cp -Rn /tmp/zenos-import/zenos/. ~/Documents/github/zenOS/
```

**A6.** Auf github.com ein neues Repository `zenOS` anlegen: öffentlich, ohne README und ohne Lizenz, beides ist schon da. Danach unter Settings die Issues ausschalten.

**A7.** In den Ordner wechseln:

```
cd ~/Documents/github/zenOS
```

**A8.**

```
git init -b main
```

**A9.**

```
git add .
```

**A10.**

```
git commit -m "start: Manifest, Doku und Bauauftrag"
```

**A11.**

```
git remote add origin git@github.com:Zenovs/zenOS.git
```

**A12.**

```
git push -u origin main
```

**A13.**

```
git switch -c dev
```

**A14.**

```
git push -u origin dev
```

---

## B · Pi vorbereiten

**B1.** Mit dem Raspberry Pi Imager auf dem Mac installieren:

- **Gerät:** Raspberry Pi 5
- **System:** Other general-purpose OS → Ubuntu → **Ubuntu Server 26.04 LTS (64-bit)**
- **Einstellungen**, falls der Imager sie anbietet:
  - Hostname `zenos-pi`
  - Benutzer und Passwort
  - SSH mit deinem öffentlichen Schlüssel
  - WLAN, falls kein Kabel

Bietet der Imager keine Einstellungen an, meldest du dich beim ersten Start am Pi mit `ubuntu` / `ubuntu` an und vergibst ein neues Passwort.

**B2.** Pi starten, zwei Minuten warten. Die IP-Adresse steht im Router, oder am Pi mit `hostname -I`.

**B3.** Vom Mac aus verbinden, dein Benutzername statt `<benutzer>`:

```
ssh <benutzer>@zenos-pi.local
```

Klappt `zenos-pi.local` nicht, nimm die IP-Adresse.

**B4.**

```
sudo apt update
```

**B5.**

```
sudo apt full-upgrade -y
```

**B6.** Neu starten, danach wie in B3 wieder verbinden:

```
sudo reboot
```

**B7.**

```
sudo apt install -y git gh tmux curl
```

**B8.** Bei GitHub anmelden. Wähle GitHub.com, HTTPS und die Anmeldung im Browser; den Code gibst du auf dem Mac ein:

```
gh auth login
```

**B9.**

```
git clone https://github.com/Zenovs/zenOS.git ~/zenOS
```

**B10.**

```
cd ~/zenOS
```

**B11.**

```
git switch dev
```

**B12.** Eine temporäre sudo-Regel anlegen. Claude Code kann keine Passwörter eintippen und braucht sie für den Bau. **Sie wird in G1 wieder gelöscht.**

```
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/zenos-bau
```

**B13.**

```
sudo chmod 0440 /etc/sudoers.d/zenos-bau
```

**B14.** Prüfen, ob die sudo-Konfiguration gültig ist. Erwartet wird «parsed OK»:

```
sudo visudo -c
```

**B15.** Claude Code mit dem offiziellen Installer installieren:

```
curl -fsSL https://claude.ai/install.sh | bash
```

**B16.** Prüfen:

```
claude --version
```

Wird `claude` nicht gefunden, zuerst `exec bash -l` ausführen und B16 wiederholen.

---

## C · Bau starten (Pi, per SSH)

**C1.** Eine Sitzung starten, die weiterläuft, auch wenn die SSH-Verbindung abbricht:

```
tmux new -s zenos
```

**C2.** Claude Code starten und anmelden:

```
claude
```

**C3.** Diesen Auftrag einfügen:

```
Lies CLAUDE.md und BAUAUFTRAG.md. Führe den Bauauftrag vollständig aus.
Arbeite selbstständig, halte docs/baufortschritt.md aktuell, committe und
pushe pro Modul. Frag mich nur bei den Punkten unter «Nur nach Rückfrage»
oder bei echten Blockern.
```

**Während des Baus:**

- Claude Code fragt vor manchen Befehlen nach Erlaubnis. Bei harmlosen, wiederkehrenden Befehlen kannst du das dauerhaft erlauben.
- Der Bau dauert mehrere Stunden. Du kannst die Verbindung trennen. Wieder verbinden mit `ssh …`, dann:

```
tmux attach -t zenos
```

- Endet eine Claude-Sitzung vor dem Ende, starte `claude` neu und schreib: «Lies docs/baufortschritt.md und mach beim nächsten offenen Modul weiter.»

---

## D · Installieren

Wenn Claude Code den Schlussbericht meldet:

**D1.** Neu starten:

```
sudo reboot
```

Am Bildschirm erscheint der zenOS-Login.

---

## E · Testen (am Pi)

Hake ab, was funktioniert. Notiere, was nicht geht.

**Login und Einrichtung**
- [ ] Nach dem Neustart erscheint der zenOS-Login, kein automatisches Anmelden.
- [ ] Die Einrichtung fragt nach Name, Ort (optional), Erscheinungsbild und erstem Modus.
- [ ] Nach deiner Zustimmung werden Chrome, VS Code und 1Password installiert.

**Leiste und Design**
- [ ] Die Leiste zeigt Modus, Zeit und den System-Knopf und sieht aus wie Entwurf 2.
- [ ] Der Hell/Dunkel-Schalter ändert alles: Leiste, Fenster, kitty, Chrome.

**Befehlsfeld**
- [ ] `Super + Leertaste` öffnet es, `Esc` schliesst es.
- [ ] `1440 / 16` ergibt `90`.
- [ ] Apps starten und Dateien finden funktioniert.
- [ ] Ein Bereichs-Screenshot landet in der Zwischenablage und in `~/Bilder/Screenshots`.
- [ ] Die Pipette kopiert einen Farbwert.

**Mitteilungen**
- [ ] `notify-send "Test" "Hallo"` im Terminal erscheint so, wie es der aktive Zustand vorsieht.

**Sperrbildschirm**
- [ ] `Super + L` sperrt. Es sind keine Inhalte sichtbar, entsperren geht mit dem Passwort.
- [ ] Nach Inaktivität sperrt zenOS automatisch.
- [ ] Absturztest: Per SSH im gesperrten Zustand `pkill quickshell` ausführen. Der Bildschirm bleibt gesperrt. Danach `zen lock` per SSH ausführen, um den Sperrbildschirm zurückzuholen.

**Modi und Zustände**
- [ ] Einen zweiten Modus mit anderer Akzentfarbe anlegen. Der Wechsel ändert Akzent und Chrome-Profil.
- [ ] Fokus starten: Mitteilungen warten, der Timer läuft.
- [ ] Sitzung: In Chrome den Bildschirm teilen. Sitzung startet von selbst, Mitteilungen erscheinen ohne Inhalt, und mit dem Ende der Freigabe endet auch Sitzung.

**Raster**
- [ ] `Super + 1` bis `4` setzt Fenster in die Viertel.
- [ ] `Super + Pfeil` setzt Fenster in die Hälften.
- [ ] `Super + Enter` schaltet Vollbild ein und aus.
- [ ] Mit zweitem Bildschirm: `Super + Shift + Pfeil` schiebt Fenster hinüber.

**Terminal**
- [ ] Text markieren, dann `Ctrl + C`: Der Text ist kopiert.
- [ ] Ohne Markierung bricht `Ctrl + C` einen laufenden `sleep 100` ab.
- [ ] `Ctrl + V` fügt ein.
- [ ] `? rsync` erklärt den Befehl.
- [ ] Ein Tippfehler im Befehl wird rot.
- [ ] Bei `sudo rm -rf /var/log/test` kommt die Warnung, «Abbrechen» ist vorausgewählt.

**System**
- [ ] `zen doctor` meldet keine Fehler, ausser den bekannten offenen Punkten.
- [ ] `zen update` holt den neuen Stand, `zen rollback v0.1.0-rc1` geht zurück.
- [ ] Die Temperatur erscheint in der Leiste, und der Lüfter reagiert auf Last.
- [ ] In Chrome zeigt `chrome://policy` die zenOS-Richtlinien.
- [ ] `ssh -T git@github.com` meldet sich über den 1Password-Agent an.
- [ ] Befehlsfeld und Fensterwechsel laufen flüssig, ohne Ruckeln.

---

## F · Wenn etwas nicht geht

**F1.** Per SSH den Prüfbericht erstellen:

```
zen doctor > ~/doctor.txt
```

**F2.** In der tmux-Sitzung Claude Code starten und schreiben: «Lies ~/doctor.txt und meine Notizen aus dem Test, und behebe die Fehler.» Danach wiederholst du D und E.

**Notfall:** Mit `zen rollback v0.1.0-rc1` kommst du zum letzten guten Stand zurück. Die Textkonsole erreichst du mit `Ctrl + Alt + F2`.

---

## G · Abschluss

**G1.** Die temporäre sudo-Regel löschen:

```
sudo rm /etc/sudoers.d/zenos-bau
```

**G2.** Final taggen, auf dem Pi in `~/zenOS`. Das startet den Image-Bau auf GitHub:

```
git tag v0.1.0
```

**G3.**

```
git push --tags
```

Nach dem Bau liegt `zenos-0.1.0-pi5-arm64.img.xz` unter Releases auf GitHub.
