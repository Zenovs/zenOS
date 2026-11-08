# zenOS 1.0: Bau des Images

Hier entsteht zenOS 1.0 als unveränderliches Image aus Debian 13 «trixie» (Konzept: `docs/neubau.md`). Stand:
**Vorschau 1** – startet, ist sicher gebaut, hat aber noch keine Updates. Nicht für Banking und Krypto, bis Vorschau 2
signierte Updates bringt.

## Was hier liegt

| Pfad | Inhalt |
|---|---|
| `mkosi.conf` | gemeinsame Einstellungen, Paketliste mit Gründen, Härtung der Kernel-Befehlszeile |
| `mkosi.sandbox/` | Paketquellen: ein fester Stand von snapshot.debian.org (auch die Sicherheitsupdates) |
| `mkosi.profiles/argon/` | Argon ONE UP (CM5) und Pi 5: Kernel und Firmware von Raspberry Pi, Bootpartition |
| `mkosi.profiles/qemu/` | virtuelle Maschine für die Tests: Kernel von Debian, Start über UEFI mit UKI |
| `repart/gemeinsam/` | Partitionen: System (erofs, dm-verity), Prüfsummen, leere B-Hälfte für Updates |
| `mkosi.extra/` | Dateien im System: Firewall, Zeit über NTS, Netz, Härtung, Chromium-Richtlinien, erster Start |
| `mkosi.postinst` | löscht Dateien von Paketen, die nur als Abhängigkeit kommen (Xwayland, man-db, initramfs-tools …) |
| `mkosi.finalize` | /var vorbereiten, setuid prüfen, Verbotenes prüfen; bricht den Bau bei einem Fund ab |
| `mkosi.postoutput` | schreibt Kernel, initrd, Gerätebäume, `config.txt` und `cmdline.txt` auf die Bootpartition (argon) |
| `start/config.txt` | Start auf dem CM5 und dem Pi 5 |
| `umgebung/` | Bauumgebung: Debian-Container mit mkosi und QEMU |
| `test/` | Angriffs- und Starttests in QEMU |

## Bauen

Auf dem Mac, mit Docker über Colima. Die Bauumgebung läuft in einer eigenen Colima-VM «zenos», damit andere Projekte
nicht gestört werden (einmalig: `colima start zenos --cpu 6 --memory 6 --disk 80 --vm-type vz`, danach den Kontext
mit `docker context use colima` zurückstellen).

```
mkosi/bauen.sh argon     # Image für das Argon ONE UP → mkosi/ausgabe/argon/zenos_<version>.raw
mkosi/bauen.sh qemu      # Image für die Tests        → mkosi/ausgabe/qemu/zenos_<version>.raw
mkosi/test/starten.sh    # erster und zweiter Start in QEMU mit Prüfungen
```

## Erster Start

1. Tastaturbelegung wählen (sie gilt ab dann immer, auch für das Passwort beim Start).
2. Passwort für die verschlüsselten Daten setzen: lang, zum Beispiel sechs zufällige Wörter.
3. Den Wiederherstellungsschlüssel auf Papier schreiben und getrennt vom Laptop aufbewahren.
4. Das Passwort eingeben, um die Daten zu öffnen.
5. Ein Konto anlegen (Name und Passwort).
6. Anmelden. Vorschau 1 zeigt den Text-Login von greetd und startet danach labwc.

## Was Vorschau 1 noch nicht kann

- **Keine Updates.** Ein neuer Stand heisst: neu auf den Stick schreiben. Darum nicht für Banking und Krypto.
- **Kein signierter Start.** Wer root hat, könnte die Bootpartition ändern. Das schliesst 1.0 (OTP).
- **Oberfläche:** noch nicht die von zenOS (Quickshell), sondern labwc pur mit Terminal (kitty) und Chromium.
- Ton, Bluetooth, Akku-Anzeige und Deckel des Argon sind noch nicht eingerichtet und nicht getestet.
