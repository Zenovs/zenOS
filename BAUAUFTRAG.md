# Bauauftrag: zenOS 1.0, Vorschau auf der SSD des Argon

Erteilt von Zeno am 08.11.2026 («ja, lege los, auf diesem Mac»; die Entscheide in `docs/neubau.md` sind für ihn so in
Ordnung). Der Bauauftrag für 0.1 ist abgeschlossen; er steht im Branch `dev`.

## Ziel

Erweitert am 10.11.2026 auf Zenos Wunsch («die ssd kann gelöscht werden, darauf komplett das neue zenOS
installieren … nach dem einbau, können nur noch update über das terminal online gezogen und installiert werden»):

Ein Image, das Zeno selbst auf die SSD des Argon ONE UP (Compute Module 5 Lite) schreibt. Nach dem Einbau muss alles
funktionieren, bis zur Oberfläche und den Apps; die SSD kommt danach nicht mehr heraus. Neue Stände kommen nur noch
online über das Terminal (`zen update`), signiert mit Zenos Schlüssel, A/B mit Probestart. Der Argon wird danach Zenos
Gerät für Zahlungen und Trading. Das umfasst Vorschau 1 und die Updates aus Vorschau 2 (`docs/neubau.md`, Abschnitt 6).

Auf dem Gerät ist nur, was gebraucht wird. Keine überflüssige Software, und als Browser der sicherste, der sich auf
diesem Gerät pflegen lässt (Chromium aus Debian, gehärtet über Richtlinien).

## Rahmen

- Gebaut wird auf Zenos Mac: Docker über Colima, mkosi in einem Debian-Container, Tests in QEMU. Branch `neubau`.
- `MANIFEST.md` und `CLAUDE.md` gelten. Bei einem Widerspruch gewinnt das Manifest.
- Arbeite selbstständig durch. Frag Zeno nur bei den Punkten unter «Nur nach Rückfrage» oder bei einem echten Blocker.
- Halte den Fortschritt in `docs/baufortschritt.md` (Abschnitt «zenOS 1.0») fest. Endet eine Sitzung, muss eine neue
  dort nahtlos weitermachen können.
- Committe thematisch auf `neubau` und pushe danach.

## Freigegeben

- Die Colima-VM auf mehr Kerne und RAM stellen und dafür neu starten.
- Container und Images bauen, Pakete im Container installieren, Caches unter `mkosi/` anlegen (nicht im Repo).
- Pushen auf `neubau`.

## Nur nach Rückfrage bei Zeno

- Alles, was auf einen physischen Datenträger, das EEPROM oder das OTP schreibt. Das macht Zeno selbst.
- Software auf dem Mac ausserhalb von Docker installieren.
- Tags, Releases, GitHub-Einstellungen und Secrets.
- Änderungen am Branch `dev`.
- Signaturschlüssel: Claude erzeugt, sieht und benutzt nie welche.

## Umfang Vorschau 1

- Debian 13 arm64 als Image mit mkosi, aus einem eingefrorenen Paketstand von `snapshot.debian.org`.
- Kernel und Firmware von Raspberry Pi, Bootpartition für das CM5 (mit dem USB-Overlay für Tastatur und Touchpad).
- `/` schreibgeschützt mit dm-verity. `/var` und `/home` auf LUKS2 mit Argon2id, beim ersten Start eingerichtet. Platz
  für die B-Hälfte.
- Kein SSH, kein sudo und su, kein apt, keine Compiler. nftables verwirft Eingehendes, chrony mit NTS, resolved ohne
  mDNS und LLMNR, NetworkManager.
- Kernel-Härtung über sysctl und Befehlszeile.
- Chromium mit Richtlinien, udev-Regeln für Trezor und Ledger.
- Oberfläche: Login, Leiste, Apps starten, Sperre, WLAN.
- Angriffstests in QEMU.
- Updates: `zen update` lädt den neuen Stand (systemd-sysupdate, GitHub), prüft die Signatur von Zenos Schlüssel und
  alle Prüfsummen, schreibt in die freie Hälfte (System, Prüfsummen, Startpartition) und startet ihn einmal zur Probe
  (tryboot, autoboot.txt). Läuft er, wird er fest; sonst startet wieder der alte.

## Nicht im Umfang

Signierter Start und eigener Kernel (1.0), alle übrigen Funktionen von 0.1 (Einstellungen, Modi, Bluetooth, Akku …).

## Fertig heisst

- Das Image baut, die Angriffstests in QEMU sind grün (auch Oberfläche und Update), gitleaks ist sauber.
- Zenos öffentlicher Schlüssel ist im Image; ohne ihn baut das Image für den Argon nicht.
- `docs/baufortschritt.md` ist nachgeführt, `mkosi/README.md` erklärt Bau, Schreiben auf die SSD und Updates,
  `docs/signieren.md` das Signieren.
- Zeno bekommt einen kurzen Schlussbericht und den ersten Befehl, um das Image auf die SSD zu schreiben.
