# Updates signieren (Zeno)

Der Argon ONE UP installiert nur Updates, deren Prüfsummenliste `SHA256SUMS` mit einem von Zenos zwei FIDO2-Schlüsseln
signiert ist, mit PIN und Berührung. Leitplanke aus `MANIFEST.md`: «Ein Gerät installiert nur, was zenOS signiert hat.
Der geheime Signaturschlüssel existiert nur auf Zenos Hardware-Schlüsseln und verlässt sie nie. Signiert wird nur von
Zeno selbst, in seinem Terminal, mit PIN und Berührung des Schlüssels; eine KI löst nie eine Signatur aus.»

Signiert wird mit OpenSSH: `ssh-keygen -Y sign` am Mac, `ssh-keygen -Y verify` auf dem Argon. Die zwei «Security Key C
NFC» (Firmware 5.8) können kein OpenPGP, aber FIDO2, und OpenSSH legt darauf Signaturschlüssel vom Typ `ed25519-sk` an.

- Jeder Key erzeugt seinen eigenen Schlüssel direkt auf dem Gerät. Der geheime Teil verlässt den Key nie.
- Am Mac liegt nur eine Verweisdatei. Ohne den Key ist sie wertlos.
- Jede Signatur braucht die FIDO-PIN und eine Berührung des Keys. Die Berührung ist der eigentliche Schutz: Wer den Mac
  übernimmt, kann nicht auf den Key tippen. Der Argon prüft beides in der Signatur (unten).
- Key A ist der Alltags-Key, Key B das Backup an einem anderen Ort. Beide öffentlichen Schlüssel kommen ins Image.
- Signiert wird `SHA256SUMS`, die Liste mit den Prüfsummen aller Dateien eines Stands: eine Berührung pro Update.
- Claude erzeugt, sieht und benutzt die Schlüssel nie und startet nie `ssh-keygen -Y sign`. Claude prüft nur.

Steck während der Einrichtung immer nur einen Key ein, sonst ist unklar, welchen `ykman` und `ssh-keygen` ansprechen.

## 1. Voraussetzungen (einmal, am Mac)

`ykman` ist installiert. Es fehlt ein OpenSSH, das FIDO-Keys ansprechen kann; das von macOS kann es nicht zuverlässig.

1. OpenSSH aus Homebrew: `brew install openssh`
2. Neues Terminal-Fenster öffnen und prüfen: `which ssh-keygen` muss `/opt/homebrew/bin/ssh-keygen` zeigen. Steht dort
   `/usr/bin/ssh-keygen`, überall `/opt/homebrew/bin/ssh-keygen` mit vollem Pfad aufrufen.
3. Version (mindestens 8.2): `ssh -V`
4. Nur Key A einstecken, FIDO-Status: `ykman fido info`. Bei PIN steht «Not set» oder die Zahl der verbleibenden
   Versuche.
5. FIDO-PIN setzen oder ändern (mindestens 6 Zeichen): `ykman fido access change-pin`

Dasselbe (4 und 5) mit Key B, mit einer eigenen PIN. Nach 8 falschen PINs ist der FIDO-Teil gesperrt und muss
zurückgesetzt werden; dabei gehen alle Passkeys auf diesem Key verloren, auch die Einträge für den Start und die
Anmeldung des Argon.

**PIN und Bauauftrag 4:** Dieselben Keys öffnen auf dem Argon die Daten und die Anmeldung. Diese Wege fragen nicht nach
der PIN, nur nach der Berührung. Mit gesetzter PIN geht das nur, wenn der Key neue Einträge ohne PIN erlaubt
(`makeCredUvNotRqd`, Firmware 5.8 sollte das). Claude prüft das nach dem Setzen der PIN einmal lesend; vorher wird
das Image nicht gebaut.

## 2. Schlüssel erzeugen

Nur Key A eingesteckt. Ein Befehl erzeugt den Schlüssel auf dem Key:

```
ssh-keygen -t ed25519-sk -O resident -O verify-required -O application=ssh:argon-update -C "Argon Update Key A" -f ~/.ssh/argon_update_a
```

| Option | Wirkung |
|---|---|
| `-t ed25519-sk` | Schlüssel liegt auf dem FIDO-Key, nicht am Mac |
| `-O resident` | Der Key speichert den Eintrag selbst; die Verweisdatei lässt sich auf jedem Rechner neu holen |
| `-O verify-required` | Jede Signatur verlangt die FIDO-PIN |
| `-O application=ssh:argon-update` | eigener Name, getrennt von anderen SSH-Schlüsseln |
| `-f ~/.ssh/argon_update_a` | Name der Verweisdatei am Mac |

PIN eingeben, Key berühren, wenn er blinkt. Die Frage nach einer Passphrase für die Datei mit Enter leer lassen; die
Datei allein nützt niemandem. Danach liegen `~/.ssh/argon_update_a` (Verweis, bleibt am Mac) und
`~/.ssh/argon_update_a.pub` (öffentlich) da.

Key A abziehen, Key B einstecken, derselbe Befehl mit B:

```
ssh-keygen -t ed25519-sk -O resident -O verify-required -O application=ssh:argon-update -C "Argon Update Key B" -f ~/.ssh/argon_update_b
```

Kontrolle: `cat ~/.ssh/argon_update_a.pub ~/.ssh/argon_update_b.pub` zeigt zwei verschiedene Zeilen, beide beginnen
mit `sk-ssh-ed25519@openssh.com`.

## 3. Öffentliche Schlüssel ins Repo

Der Argon prüft gegen `/usr/lib/zenos/update-signierer`; der Bau nimmt sie aus `mkosi/schluessel/argon-allowed-signers`
(eine Zeile pro Key, nicht geheim). Im Ordner des Repos:

1. `printf 'argon-update namespaces="argon-update" %s\n' "$(cat ~/.ssh/argon_update_a.pub)" > mkosi/schluessel/argon-allowed-signers`
2. `printf 'argon-update namespaces="argon-update" %s\n' "$(cat ~/.ssh/argon_update_b.pub)" >> mkosi/schluessel/argon-allowed-signers`
3. Kontrolle, genau zwei Zeilen: `cat mkosi/schluessel/argon-allowed-signers`
4. Fingerabdrücke: `ssh-keygen -lf ~/.ssh/argon_update_a.pub` und `ssh-keygen -lf ~/.ssh/argon_update_b.pub`. Auf
   Papier notieren; sie kommen auch in `MANIFEST.md`. So fällt auf, wenn jemand die Datei austauscht. Der Bau zeigt
   sie jedes Mal («Updates nur mit Zenos FIDO2-Schlüsseln»).

`namespaces="argon-update"` sorgt dafür, dass diese Keys auf dem Argon nur für Updates gelten. Eine Signatur, die für
etwas anderes gemacht wurde (etwa ein Git-Commit), lehnt er ab. Der Bau nimmt in dieser Datei nur FIDO2-Schlüssel
(`sk-ssh-ed25519`) an; ohne die Datei baut das Image für den Argon nicht.

## 4. Testen, vor dem ersten Bau

Einmal pro Key, nur dieser Key eingesteckt. Claude legt eine Probe an (`mkosi/ausgabe/signatur-probe/SHA256SUMS`).

1. Signieren, PIN, dann den Key berühren:
   `ssh-keygen -Y sign -f ~/.ssh/argon_update_a -n argon-update mkosi/ausgabe/signatur-probe/SHA256SUMS`
2. Claude prüft mit dem Code des Argon: `mkosi/signatur-pruefen.sh probe` muss «Berührung und PIN: ja» melden.
3. Dasselbe mit Key B (`~/.ssh/argon_update_b`); vorher `SHA256SUMS.sig` der Probe löschen.

Erst wenn beide Keys bestanden haben, baut Claude das Image für den Argon und du schreibst die SSD.

## 5. Jedes Update

1. Claude baut den Stand und bereitet ihn vor (`mkosi/bauen.sh argon`, `mkosi/veroeffentlichen.sh`). Am Ende steht der
   Befehl zum Signieren.
2. Du signierst in deinem Terminal, PIN und Berührung:
   `ssh-keygen -Y sign -f ~/.ssh/argon_update_a -n argon-update mkosi/ausgabe/veroeffentlichung/argon/<version>/SHA256SUMS`
3. Claude prüft wie der Argon (`mkosi/signatur-pruefen.sh <version>`: Signatur, Berührung und PIN, Liste, alle
   Prüfsummen) und veröffentlicht nach deinem Ja das Release `zenos-<version>` mit den Dateien, `SHA256SUMS` und
   `SHA256SUMS.sig` (nie mit einem Tag `v…`, die gehören zu 0.1).
4. Auf dem Argon: `zen update`.

Blinkt der Key, ohne dass du gerade selbst signierst: nicht berühren, abziehen.

## Was der Argon prüft

`/usr/lib/zenos/update` lädt `SHA256SUMS` und `SHA256SUMS.sig` und prüft, bevor irgendetwas geschrieben wird:

1. `ssh-keygen -Y verify` gegen `/usr/lib/zenos/update-signierer` (im schreibgeschützten System unter dm-verity),
   Prinzipal und Namespace `argon-update`.
2. Die Flags der Signatur: Bit «berührt» und Bit «PIN geprüft» müssen gesetzt sein. Sie sind mitsigniert, aber
   `ssh-keygen -Y verify` prüft sie bei FIDO-Schlüsseln nicht selbst; zenOS liest sie aus der Signatur.
3. Erst dann `SHA256SUMS` selbst: nur die Dateinamen eines Stands, eine Version, neuer als die laufende.
4. Jede Datei des Updates gegen ihre Prüfsumme. Erst diese geprüfte Kopie schreibt systemd-sysupdate in die freie
   Hälfte; sysupdate lädt selbst nichts aus dem Netz.

## Aufbewahrung, Verlust, Regeln

Key A bleibt bei dir (am Schlüsselbund). Key B liegt an einem anderen Ort, etwa in einem Safe. Die PINs auf Papier oder
im Passwortmanager, nie als Datei auf dem Mac.

**Neuer Mac oder Verweisdatei weg:** Key einstecken, in `~/.ssh` wechseln, `ssh-keygen -K` (PIN nötig) holt die
Verweisdatei vom Key zurück.

**Ein Key verloren oder gestohlen:**

1. In `mkosi/schluessel/argon-allowed-signers` die Zeile des verlorenen Keys löschen.
2. Claude baut ein Update; die Datei kommt mit dem neuen System auf den Argon. Du signierst es mit dem verbliebenen Key.
   Der Argon nimmt es an, weil er diesen Key kennt; danach lehnt er den verlorenen ab.
3. Einen Ersatz-Key kaufen, nach Abschnitt 1 und 2 einrichten und mit dem nächsten Update in die Datei aufnehmen.

Sind beide Keys weg, nimmt der Argon kein Update mehr an. Dann muss die SSD einmal heraus und neu beschrieben werden
(die Daten vorher sichern).

**Regeln:**

- Der geheime Schlüssel existiert nur auf den beiden Keys.
- Signiert wird nur von dir, in deinem Terminal, mit PIN und Berührung.
- Keine KI startet `ssh-keygen -Y sign` oder einen anderen Signaturbefehl. (Einzige Ausnahme: der Wegwerf-Schlüssel
  des QEMU-Tests unter `mkosi/ausgabe/test-schluessel/`, dem nur das Test-Image traut.)
- Du berührst den Key nur, wenn du die Signatur gerade selbst gestartet hast.
- Nur der Key eingesteckt, mit dem du gerade arbeitest.
